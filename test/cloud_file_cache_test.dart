import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path_util;
import 'package:sonar_vault/features/cloud/domain/cloud_file_cache.dart';
import 'package:sonar_vault/features/cloud/domain/cloud_storage_delete_outbox.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('sona-cloud-cache-test-');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('validated stream becomes visible only at the final path', () async {
    final bytes = utf8.encode('verified cloud object');
    final destination = File(path_util.join(root.path, 'track.mp3'));
    final cache = AtomicCloudFileCache();

    await cache.ensure(
      destination: destination,
      expectedLength: bytes.length,
      expectedSha256: sha256.convert(bytes).toString(),
      openStream: () => Stream<List<int>>.fromIterable([
        bytes.sublist(0, 5),
        bytes.sublist(5),
      ]),
    );

    expect(await destination.readAsBytes(), bytes);
    expect(await File('${destination.path}.part').exists(), isFalse);
    expect(await File('${destination.path}.complete.json').exists(), isTrue);
  });

  test('truncated or corrupt cloud objects leave no cache hit', () async {
    final complete = utf8.encode('complete payload');
    final destination = File(path_util.join(root.path, 'track.mp3'));
    final cache = AtomicCloudFileCache();

    await expectLater(
      cache.ensure(
        destination: destination,
        expectedLength: complete.length,
        expectedSha256: sha256.convert(complete).toString(),
        openStream: () => Stream<List<int>>.value(complete.sublist(0, 4)),
      ),
      throwsA(isA<CloudFileIntegrityException>()),
    );
    expect(await destination.exists(), isFalse);
    expect(await File('${destination.path}.part').exists(), isFalse);
  });

  test('an invalid existing final file is replaced, never trusted', () async {
    final destination = File(path_util.join(root.path, 'track.mp3'));
    await destination.writeAsString('partial-but-final');
    final complete = utf8.encode('correct');
    var downloads = 0;
    final cache = AtomicCloudFileCache();

    await cache.ensure(
      destination: destination,
      expectedLength: complete.length,
      expectedSha256: sha256.convert(complete).toString(),
      openStream: () {
        downloads++;
        return Stream<List<int>>.value(complete);
      },
    );

    expect(downloads, 1);
    expect(await destination.readAsBytes(), complete);
  });

  test(
    'an unverified legacy final is downloaded once then reused with marker',
    () async {
      final destination = File(path_util.join(root.path, 'video.mp4'));
      await destination.writeAsString('legacy-partial');
      final complete = utf8.encode('complete video payload');
      var downloads = 0;
      final cache = AtomicCloudFileCache();

      Stream<List<int>> source() {
        downloads++;
        return Stream<List<int>>.value(complete);
      }

      await cache.ensure(destination: destination, openStream: source);
      await cache.ensure(destination: destination, openStream: source);

      expect(downloads, 1);
      expect(await destination.readAsBytes(), complete);
      expect(await File('${destination.path}.complete.json').exists(), isTrue);
    },
  );

  test('concurrent requests for one path share a single download', () async {
    final destination = File(path_util.join(root.path, 'track.mp3'));
    final complete = utf8.encode('one request');
    final release = Completer<void>();
    var downloads = 0;
    final cache = AtomicCloudFileCache();
    Stream<List<int>> source() async* {
      downloads++;
      await release.future;
      yield complete;
    }

    final first = cache.ensure(
      destination: destination,
      expectedLength: complete.length,
      openStream: source,
    );
    final second = cache.ensure(
      destination: destination,
      expectedLength: complete.length,
      openStream: source,
    );
    release.complete();
    await Future.wait([first, second]);

    expect(downloads, 1);
    expect(await destination.readAsBytes(), complete);
  });

  test(
    'startup cleanup removes stale partials without touching finals',
    () async {
      final nested = Directory(path_util.join(root.path, 'nested'));
      await nested.create(recursive: true);
      final partial = File(path_util.join(nested.path, 'song.mp3.part'));
      final finalFile = File(path_util.join(nested.path, 'song.mp3'));
      await partial.writeAsString('interrupted');
      await finalFile.writeAsString('complete');

      expect(await AtomicCloudFileCache.cleanupPartFiles(root), 1);
      expect(await partial.exists(), isFalse);
      expect(await finalFile.readAsString(), 'complete');
    },
  );

  test('storage cleanup outbox is deterministic and idempotent', () {
    final queued = const CloudStorageDeleteOutbox.empty().addAll([
      'space/tracks/b.mp3',
      'space/tracks/a.mp3',
      'space/tracks/b.mp3',
      '',
      null,
    ]);
    expect(
      queued.encode(),
      '{"version":1,"objects":["space/tracks/a.mp3","space/tracks/b.mp3"]}',
    );
    expect(CloudStorageDeleteOutbox.decode(queued.encode()).objects, {
      'space/tracks/a.mp3',
      'space/tracks/b.mp3',
    });
    expect(queued.removeAll(['space/tracks/a.mp3']).objects, {
      'space/tracks/b.mp3',
    });
    expect(CloudStorageDeleteOutbox.decode('{broken').isEmpty, isTrue);
    expect(
      CloudStorageDeleteOutbox.decode('{"version":1,"objects":"not-a-list"}')
          .isEmpty,
      isTrue,
    );
  });

  test('failed storage cleanup survives restart until an idempotent retry', () {
    final beforeFailure = const CloudStorageDeleteOutbox.empty().addAll([
      'space/tracks/song.mp3',
      'space/videos/song.mp4',
    ]);

    // A failed Storage request does not mutate persisted JSON. Constructing a
    // new instance from that JSON models the next application process.
    final afterRestart = CloudStorageDeleteOutbox.decode(
      beforeFailure.encode(),
    );
    expect(afterRestart.objects, beforeFailure.objects);

    final afterSuccessfulRetry = afterRestart.removeAll([
      'space/tracks/song.mp3',
      'space/videos/song.mp4',
      'space/videos/song.mp4',
    ]);
    expect(afterSuccessfulRetry.isEmpty, isTrue);
    expect(afterSuccessfulRetry.encode(), '{"version":1,"objects":[]}');
  });
}
