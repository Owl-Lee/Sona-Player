import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:path/path.dart' as path_util;

import '../../../core/utils/chinese_text.dart';
import '../domain/track.dart';
import '../domain/track_identification.dart';

class TrackIdentifier {
  TrackIdentifier({HttpClient? httpClient})
    : _httpClient = httpClient ?? HttpClient();

  final HttpClient _httpClient;
  Future<void> _acoustIdGate = Future.value();
  DateTime? _lastAcoustIdRequestAt;
  Future<void> _musicBrainzGate = Future.value();
  DateTime? _lastMusicBrainzRequestAt;

  static const _builtInAcoustIdClientKey = String.fromEnvironment(
    'ACOUSTID_API_KEY',
  );

  Future<TrackIdentificationResult> identify(
    Track track, {
    String? acoustIdClientKey,
  }) async {
    final file = File(track.path);
    if (!await file.exists()) {
      return const TrackIdentificationResult(message: '找不到本地文件，无法识别。');
    }

    final hints = _localHints(track);
    final key = (acoustIdClientKey ?? _builtInAcoustIdClientKey).trim();
    var fingerprintAttempted = false;

    if (key.isNotEmpty) {
      final fingerprint = await _fingerprint(track.path);
      if (fingerprint != null) {
        fingerprintAttempted = true;
        final match = await _lookupAcoustId(fingerprint, key);
        if (match != null && match.confidence >= 0.72) {
          return TrackIdentificationResult(
            candidate: match,
            message: '已通过音频声纹找到匹配结果。',
            fingerprintAttempted: true,
          );
        }
      }
    }

    final match = await _searchMusicBrainz(track, hints);
    if (match != null && match.confidence >= 0.68) {
      return TrackIdentificationResult(
        candidate: match,
        message: fingerprintAttempted
            ? '声纹没有可靠命中，已用公开曲库完成后备校准。'
            : '已用文件信息和公开曲库完成后备校准。',
        fingerprintAttempted: fingerprintAttempted,
      );
    }

    final localChanged =
        hints.title != track.title || hints.artist != track.artist;
    if (localChanged && hints.title.isNotEmpty) {
      return TrackIdentificationResult(
        candidate: TrackIdentificationCandidate(
          title: toSimplifiedChinese(hints.title),
          artist: toSimplifiedChinese(hints.artist),
          album: toSimplifiedChinese(hints.album),
          confidence: 0.52,
          source: '本地智能清洗',
          explanation: '公开曲库没有可靠结果，仅根据标签和文件名给出建议，请确认后再应用。',
        ),
        message: '没有查到可靠的联网结果，已生成本地清洗建议。',
        fingerprintAttempted: fingerprintAttempted,
      );
    }

    return TrackIdentificationResult(
      message: '没有找到可靠的识别结果，已保留原信息。',
      fingerprintAttempted: fingerprintAttempted,
    );
  }

  ParsedTrackName _localHints(Track track) {
    AudioMetadata? metadata;
    if (!track.isVideoOnly) {
      try {
        metadata = readMetadata(File(track.path), getImage: false);
      } catch (_) {
        metadata = null;
      }
    }
    return TrackNameParser.parse(
      fileName: path_util.basename(track.path),
      taggedTitle: metadata?.title ?? track.title,
      taggedArtist: metadata?.artist ?? track.artist,
      taggedAlbum: metadata?.album ?? track.album,
      isVideo: track.isVideoOnly,
    );
  }

  Future<_Fingerprint?> _fingerprint(String filePath) async {
    if (!Platform.isWindows) return null;
    final executable = _findFpcalc();
    if (executable == null) return null;
    try {
      final result = await Process.run(executable, [
        '-json',
        '-length',
        '120',
        filePath,
      ]).timeout(const Duration(seconds: 30));
      if (result.exitCode != 0) return null;
      final json = jsonDecode(result.stdout.toString()) as Map<String, dynamic>;
      final value = json['fingerprint']?.toString() ?? '';
      final duration = (json['duration'] as num?)?.round() ?? 0;
      if (value.isEmpty || duration <= 0) return null;
      return _Fingerprint(value: value, durationSeconds: duration);
    } catch (_) {
      return null;
    }
  }

  String? _findFpcalc() {
    final candidates = [
      path_util.join(
        path_util.dirname(Platform.resolvedExecutable),
        'fpcalc.exe',
      ),
      path_util.join(
        Directory.current.path,
        'windows',
        'third_party',
        'chromaprint',
        'fpcalc.exe',
      ),
    ];
    for (final candidate in candidates) {
      if (File(candidate).existsSync()) return candidate;
    }
    return null;
  }

  Future<TrackIdentificationCandidate?> _lookupAcoustId(
    _Fingerprint fingerprint,
    String clientKey,
  ) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        // AcoustID asks clients to stay below three requests per second. A
        // 400 ms gate is intentionally conservative and is shared by batch
        // and single-track identification.
        await _waitForAcoustIdSlot();
        final request = await _httpClient
            .postUrl(Uri.parse('https://api.acoustid.org/v2/lookup'))
            .timeout(const Duration(seconds: 8));
        request.headers.contentType = ContentType(
          'application',
          'x-www-form-urlencoded',
          charset: 'utf-8',
        );
        request.write(
          Uri(
            queryParameters: {
              'client': clientKey,
              'format': 'json',
              'duration': '${fingerprint.durationSeconds}',
              'fingerprint': fingerprint.value,
              'meta': 'recordings releasegroups compress',
            },
          ).query,
        );
        final response = await request.close().timeout(
          const Duration(seconds: 10),
        );
        if (response.statusCode == HttpStatus.tooManyRequests ||
            response.statusCode == HttpStatus.serviceUnavailable) {
          await response.drain<void>();
          if (attempt == 0) {
            await Future<void>.delayed(const Duration(milliseconds: 1200));
            continue;
          }
          return null;
        }
        if (response.statusCode != HttpStatus.ok) {
          await response.drain<void>();
          return null;
        }
        final body = await utf8.decoder.bind(response).join();
        final data = jsonDecode(body) as Map<String, dynamic>;
        final results = data['results'] as List<dynamic>? ?? const [];
        TrackIdentificationCandidate? best;
        for (final rawResult in results.whereType<Map<String, dynamic>>()) {
          final confidence = (rawResult['score'] as num?)?.toDouble() ?? 0;
          final recordings =
              rawResult['recordings'] as List<dynamic>? ?? const [];
          for (final rawRecording
              in recordings.whereType<Map<String, dynamic>>()) {
            final candidate = _candidateFromAcoustId(rawRecording, confidence);
            if (candidate != null &&
                (best == null || candidate.confidence > best.confidence)) {
              best = candidate;
            }
          }
        }
        return best;
      } catch (_) {
        if (attempt == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 700));
          continue;
        }
        return null;
      }
    }
    return null;
  }

  Future<void> _waitForAcoustIdSlot() async {
    final previous = _acoustIdGate;
    final completer = Completer<void>();
    _acoustIdGate = completer.future;
    await previous;
    try {
      final last = _lastAcoustIdRequestAt;
      if (last != null) {
        final remaining =
            const Duration(milliseconds: 400) - DateTime.now().difference(last);
        if (remaining > Duration.zero) await Future<void>.delayed(remaining);
      }
      _lastAcoustIdRequestAt = DateTime.now();
    } finally {
      completer.complete();
    }
  }

  TrackIdentificationCandidate? _candidateFromAcoustId(
    Map<String, dynamic> recording,
    double confidence,
  ) {
    final title = recording['title']?.toString().trim() ?? '';
    final artists = recording['artists'] as List<dynamic>? ?? const [];
    final artist = artists
        .whereType<Map<String, dynamic>>()
        .map((item) => item['name']?.toString().trim() ?? '')
        .where((item) => item.isNotEmpty)
        .join('、');
    final releaseGroups =
        recording['releasegroups'] as List<dynamic>? ?? const [];
    final album = releaseGroups
        .whereType<Map<String, dynamic>>()
        .map((item) => item['title']?.toString().trim() ?? '')
        .firstWhere((item) => item.isNotEmpty, orElse: () => '');
    if (title.isEmpty || artist.isEmpty) return null;
    return TrackIdentificationCandidate(
      title: toSimplifiedChinese(title),
      artist: toSimplifiedChinese(artist),
      album: toSimplifiedChinese(album),
      confidence: confidence.clamp(0, 1),
      source: 'AcoustID 音频声纹',
      explanation: '根据音频内容匹配，与文件名无关。',
    );
  }

  Future<TrackIdentificationCandidate?> _searchMusicBrainz(
    Track track,
    ParsedTrackName hints,
  ) async {
    final title = hints.title.trim();
    if (title.isEmpty) return null;
    final knownArtist = !_isUnknownArtist(hints.artist)
        ? hints.artist.trim()
        : '';
    final query = knownArtist.isEmpty
        ? 'recording:"${_escapeQuery(title)}"'
        : 'recording:"${_escapeQuery(title)}" AND artist:"${_escapeQuery(knownArtist)}"';
    final uri = Uri.https('musicbrainz.org', '/ws/2/recording/', {
      'query': query,
      'fmt': 'json',
      'limit': '8',
    });
    try {
      await _waitForMusicBrainzSlot();
      final request = await _httpClient
          .getUrl(uri)
          .timeout(const Duration(seconds: 8));
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'Sona/0.4.51 (https://github.com/Owl-Lee/Sona-Player)',
      );
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      if (response.statusCode != HttpStatus.ok) return null;
      final body = await utf8.decoder.bind(response).join();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final recordings = data['recordings'] as List<dynamic>? ?? const [];
      TrackIdentificationCandidate? best;
      for (final recording in recordings.whereType<Map<String, dynamic>>()) {
        final candidate = _candidateFromMusicBrainz(recording, track, hints);
        if (candidate != null &&
            (best == null || candidate.confidence > best.confidence)) {
          best = candidate;
        }
      }
      return best;
    } catch (_) {
      return null;
    }
  }

  Future<void> _waitForMusicBrainzSlot() async {
    final previous = _musicBrainzGate;
    final completer = Completer<void>();
    _musicBrainzGate = completer.future;
    await previous;
    try {
      final last = _lastMusicBrainzRequestAt;
      if (last != null) {
        final remaining =
            const Duration(milliseconds: 1100) -
            DateTime.now().difference(last);
        if (remaining > Duration.zero) await Future<void>.delayed(remaining);
      }
      _lastMusicBrainzRequestAt = DateTime.now();
    } finally {
      completer.complete();
    }
  }

  TrackIdentificationCandidate? _candidateFromMusicBrainz(
    Map<String, dynamic> recording,
    Track track,
    ParsedTrackName hints,
  ) {
    final title = recording['title']?.toString().trim() ?? '';
    final artistCredit =
        recording['artist-credit'] as List<dynamic>? ?? const [];
    final artist = artistCredit
        .whereType<Map<String, dynamic>>()
        .map((item) {
          final nested = item['artist'];
          if (nested is Map<String, dynamic>) {
            return nested['name']?.toString().trim() ?? '';
          }
          return item['name']?.toString().trim() ?? '';
        })
        .where((item) => item.isNotEmpty)
        .join('、');
    if (title.isEmpty || artist.isEmpty) return null;
    final releases = recording['releases'] as List<dynamic>? ?? const [];
    final album = releases
        .whereType<Map<String, dynamic>>()
        .map((item) => item['title']?.toString().trim() ?? '')
        .firstWhere((item) => item.isNotEmpty, orElse: () => '');
    final serverScore = ((recording['score'] as num?)?.toDouble() ?? 0) / 100;
    final titleSimilarity = _tokenSimilarity(title, hints.title);
    final artistSimilarity = _isUnknownArtist(hints.artist)
        ? 0.62
        : _tokenSimilarity(artist, hints.artist);
    var durationSimilarity = 0.65;
    final length = (recording['length'] as num?)?.round();
    if (length != null && length > 0 && track.duration > Duration.zero) {
      final delta = (length - track.duration.inMilliseconds).abs();
      durationSimilarity = (1 - delta / 30000).clamp(0, 1);
    }
    final confidence =
        serverScore * 0.42 +
        titleSimilarity * 0.30 +
        artistSimilarity * 0.18 +
        durationSimilarity * 0.10;
    return TrackIdentificationCandidate(
      title: toSimplifiedChinese(title),
      artist: toSimplifiedChinese(artist),
      album: toSimplifiedChinese(album),
      confidence: confidence.clamp(0, 1),
      source: 'MusicBrainz 公开曲库',
      explanation: '根据清洗后的曲名、歌手和时长进行联网校准，并非声纹命中。',
    );
  }

  static bool _isUnknownArtist(String value) {
    final normalized = value.trim().toLowerCase();
    return normalized.isEmpty ||
        normalized == '未知歌手' ||
        normalized == '本地视频' ||
        normalized == 'unknown artist';
  }

  static String _escapeQuery(String value) =>
      value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');

  static double _tokenSimilarity(String first, String second) {
    String normalize(String value) => value.toLowerCase().replaceAll(
      RegExp(r'[^\p{L}\p{N}]+', unicode: true),
      '',
    );
    final a = normalize(first);
    final b = normalize(second);
    if (a.isEmpty || b.isEmpty) return 0;
    if (a == b) return 1;
    if (a.contains(b) || b.contains(a)) {
      return (a.length < b.length ? a.length : b.length) /
          (a.length > b.length ? a.length : b.length);
    }
    final aChars = a.runes.toSet();
    final bChars = b.runes.toSet();
    final intersection = aChars.intersection(bChars).length;
    final union = aChars.union(bChars).length;
    return union == 0 ? 0 : intersection / union;
  }
}

class _Fingerprint {
  const _Fingerprint({required this.value, required this.durationSeconds});

  final String value;
  final int durationSeconds;
}
