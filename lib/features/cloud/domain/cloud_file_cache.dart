import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path_util;

class CloudFileIntegrityException implements Exception {
  const CloudFileIntegrityException(this.message);

  final String message;

  @override
  String toString() => 'CloudFileIntegrityException: $message';
}

/// Writes cloud objects through a sibling `.part` file, validates them, and
/// only then atomically exposes the final cache path.
///
/// Requests for the same path share one operation. An interrupted process can
/// therefore leave at most a `.part` file, which is never treated as playable
/// and is removed by [cleanupPartFiles].
class AtomicCloudFileCache {
  final Map<String, Future<File>> _pending = <String, Future<File>>{};

  Future<File> ensure({
    required File destination,
    required Stream<List<int>> Function() openStream,
    int? expectedLength,
    String? expectedSha256,
  }) {
    final key = path_util.normalize(destination.absolute.path);
    final active = _pending[key];
    if (active != null) return active;
    late final Future<File> operation;
    operation =
        _ensure(
          destination: destination,
          openStream: openStream,
          expectedLength: expectedLength,
          expectedSha256: expectedSha256,
        ).whenComplete(() {
          if (identical(_pending[key], operation)) _pending.remove(key);
        });
    _pending[key] = operation;
    return operation;
  }

  Future<File> _ensure({
    required File destination,
    required Stream<List<int>> Function() openStream,
    required int? expectedLength,
    required String? expectedSha256,
  }) async {
    final normalizedHash = _normalizedHash(expectedSha256);
    final normalizedLength = expectedLength != null && expectedLength > 0
        ? expectedLength
        : null;
    if (await _isComplete(
      destination,
      expectedLength: normalizedLength,
      expectedSha256: normalizedHash,
    )) {
      return destination;
    }
    if (await destination.exists()) await destination.delete();
    final completion = File('${destination.path}.complete.json');
    if (await completion.exists()) await completion.delete();
    await destination.parent.create(recursive: true);

    final partial = File('${destination.path}.part');
    if (await partial.exists()) await partial.delete();
    RandomAccessFile? output;
    var exposedFinal = false;
    try {
      output = await partial.open(mode: FileMode.write);
      final digestSink = _DigestCollector();
      final hashSink = sha256.startChunkedConversion(digestSink);
      var written = 0;
      await for (final chunk in openStream()) {
        if (chunk.isEmpty) continue;
        written += chunk.length;
        if (normalizedLength != null && written > normalizedLength) {
          throw const CloudFileIntegrityException(
            'Cloud object is larger than its declared size.',
          );
        }
        hashSink.add(chunk);
        await output.writeFrom(chunk);
      }
      hashSink.close();
      await output.flush();
      await output.close();
      output = null;

      final digest = digestSink.value?.toString();
      if (written == 0 ||
          (normalizedLength != null && written != normalizedLength) ||
          digest == null ||
          (normalizedHash != null && digest != normalizedHash)) {
        throw const CloudFileIntegrityException(
          'Cloud object failed size or SHA-256 validation.',
        );
      }
      await partial.rename(destination.path);
      exposedFinal = true;
      await _writeCompletionMarker(
        completion,
        length: written,
        sha256Value: digest,
      );
      return destination;
    } catch (_) {
      await output?.close();
      if (await partial.exists()) await partial.delete();
      if (exposedFinal && await destination.exists()) {
        await destination.delete();
      }
      if (await completion.exists()) await completion.delete();
      rethrow;
    }
  }

  static Future<bool> _isComplete(
    File file, {
    required int? expectedLength,
    required String? expectedSha256,
  }) async {
    if (!await file.exists()) return false;
    final length = await file.length();
    if (length == 0 || (expectedLength != null && length != expectedLength)) {
      return false;
    }
    final digest = await sha256.bind(file.openRead()).first;
    if (expectedSha256 != null) return digest.toString() == expectedSha256;

    final marker = File('${file.path}.complete.json');
    if (!await marker.exists()) return false;
    try {
      final decoded = jsonDecode(await marker.readAsString());
      if (decoded is! Map || decoded['length'] != length) return false;
      final markerHash = decoded['sha256'];
      return markerHash is String &&
          RegExp(r'^[a-f0-9]{64}$').hasMatch(markerHash) &&
          digest.toString() == markerHash;
    } on Object {
      return false;
    }
  }

  static Future<void> _writeCompletionMarker(
    File marker, {
    required int length,
    required String sha256Value,
  }) async {
    final partial = File('${marker.path}.part');
    if (await partial.exists()) await partial.delete();
    await partial.writeAsString(
      jsonEncode(<String, Object?>{
        'version': 1,
        'length': length,
        'sha256': sha256Value,
      }),
      flush: true,
    );
    if (await marker.exists()) await marker.delete();
    await partial.rename(marker.path);
  }

  static String? _normalizedHash(String? value) {
    final normalized = value?.trim().toLowerCase();
    return normalized != null && RegExp(r'^[a-f0-9]{64}$').hasMatch(normalized)
        ? normalized
        : null;
  }

  static Future<int> cleanupPartFiles(
    Directory root, {
    int maximumEntries = 50000,
  }) async {
    if (!await root.exists()) return 0;
    var scanned = 0;
    var removed = 0;
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      scanned++;
      if (scanned > maximumEntries) break;
      if (entity is File && entity.path.endsWith('.part')) {
        try {
          await entity.delete();
          removed++;
        } on FileSystemException {
          // A locked partial remains non-playable and can be retried later.
        }
      }
    }
    return removed;
  }
}

class _DigestCollector implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
