import 'track.dart';

class ParsedTrackName {
  const ParsedTrackName({
    required this.title,
    required this.artist,
    required this.album,
    required this.usedFileNameFallback,
  });

  final String title;
  final String artist;
  final String album;
  final bool usedFileNameFallback;
}

class TrackNameParser {
  const TrackNameParser._();

  /// Stable metadata sentinels are persisted independently of the UI locale.
  /// [SonaLocalizations.metadata] translates them only at presentation time.
  static const unknownArtist = 'Unknown artist';
  static const unknownAlbum = 'Unknown album';
  static const localVideoArtist = 'Local video';
  static const standaloneVideoAlbum = 'Standalone MV';

  // Keep accepting legacy localized sentinels written by earlier releases.
  static const _unknownArtists = {
    '',
    'unknown artist',
    'local video',
    '未知歌手',
    '本地视频',
  };

  static const _unknownAlbums = {
    '',
    'unknown album',
    'standalone mv',
    '未知专辑',
    '独立 mv',
  };

  static ParsedTrackName parse({
    required String fileName,
    String? taggedTitle,
    String? taggedArtist,
    String? taggedAlbum,
    required bool isVideo,
  }) {
    final baseName = fileName.replaceFirst(RegExp(r'\.[^.]+$'), '').trim();
    final titleReliable = isReliableTitle(taggedTitle, fileName: baseName);
    final parsedArtist = _artistFromFileName(baseName);
    final parsedTitle = _titleFromFileName(baseName);

    final normalizedArtist = taggedArtist?.trim() ?? '';
    final artist = !_unknownArtists.contains(normalizedArtist.toLowerCase())
        ? normalizedArtist
        : parsedArtist.isNotEmpty
        ? parsedArtist
        : isVideo
        ? localVideoArtist
        : unknownArtist;
    final normalizedAlbum = taggedAlbum?.trim() ?? '';
    final album = !_unknownAlbums.contains(normalizedAlbum.toLowerCase())
        ? normalizedAlbum
        : isVideo
        ? standaloneVideoAlbum
        : '';

    return ParsedTrackName(
      title: titleReliable ? taggedTitle!.trim() : parsedTitle,
      artist: artist,
      album: album,
      usedFileNameFallback: !titleReliable,
    );
  }

  static bool isReliableTitle(String? value, {required String fileName}) {
    final title = value?.trim() ?? '';
    if (title.isEmpty) return false;
    if (title.toLowerCase() == 'unknown title') return false;
    if (title == fileName) return false;
    if (title.length > 96) return false;
    if (RegExp(
      r'^(img|dsc|mv)[_-]?\d+$',
      caseSensitive: false,
    ).hasMatch(title)) {
      return false;
    }
    if (RegExp(r'BV[0-9A-Za-z]{8,}', caseSensitive: false).hasMatch(title)) {
      return false;
    }
    return true;
  }

  static String _artistFromFileName(String value) {
    for (final match in RegExp(r'【([^】]{1,30})】').allMatches(value)) {
      final candidate = match.group(1)!.trim();
      final lower = candidate.toLowerCase();
      if (candidate.contains('馆') ||
          candidate.contains('经典') ||
          candidate.contains('现场') ||
          lower.contains('fps') ||
          lower.contains('mv') ||
          lower.contains('k歌')) {
        continue;
      }
      return candidate;
    }
    return '';
  }

  static String _titleFromFileName(String value) {
    var title = value;
    title = title.replaceAll(
      RegExp(r'\s*[-_]?[0-9]{9,}$', caseSensitive: false),
      '',
    );
    title = title.replaceAll(
      RegExp(r'\s*\[BV[0-9A-Za-z]+(?:_p\d+)?\]', caseSensitive: false),
      '',
    );

    final partMatches = RegExp(
      r'(?:p\d+\s*)?(?:^|\s)\d{1,3}[.、]\s*([^\[\]【】]+)$',
      caseSensitive: false,
    ).allMatches(title).toList(growable: false);
    if (partMatches.isNotEmpty) {
      final part = _cleanTitle(partMatches.last.group(1)!);
      if (part.isNotEmpty) return part;
    }

    final bookTitles = RegExp(r'《([^》]{1,80})》')
        .allMatches(title)
        .map((match) => match.group(1)!.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    if (bookTitles.isNotEmpty) return bookTitles.last;

    title = title
        .replaceAll(RegExp(r'【[^】]*】'), ' ')
        .replaceAll(RegExp(r'\[[^\]]*\]'), ' ')
        .replaceFirst(RegExp(r'^\s*\d{1,3}\s*[-_.、]\s*'), '')
        .replaceAll(
          RegExp(
            r'\b(4k|8k|60fps|120fps|official\s*mv|mv|超清|高清)\b',
            caseSensitive: false,
          ),
          ' ',
        );
    final cleaned = _cleanTitle(title);
    return cleaned.isEmpty ? value.trim() : cleaned;
  }

  static String _cleanTitle(String value) => value
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'^[\s\-—_:：]+|[\s\-—_:：]+$'), '')
      .trim();
}

class TrackIdentificationCandidate {
  const TrackIdentificationCandidate({
    required this.title,
    required this.artist,
    required this.album,
    required this.confidence,
    required this.source,
    required this.explanation,
  });

  final String title;
  final String artist;
  final String album;
  final double confidence;
  final String source;
  final String explanation;
}

class TrackIdentificationResult {
  const TrackIdentificationResult({
    this.candidate,
    required this.message,
    this.fingerprintAttempted = false,
  });

  final TrackIdentificationCandidate? candidate;
  final String message;
  final bool fingerprintAttempted;

  bool get found => candidate != null;
}

/// Every persisted track is eligible for the explicit full-library scan.
///
/// This deliberately differs from [needsSmartOrganization], which is only a
/// lightweight import hint. A plausible-looking value such as `Hi-res` can
/// still be bad metadata and must not prevent an explicit user-requested scan.
List<Track> fullLibraryIdentificationTargets(Iterable<Track> tracks) =>
    tracks.where((track) => track.id != null).toList(growable: false);

/// Whether a track still resembles raw download metadata and should be
/// offered to the optional online/fingerprint organizer.
///
/// An empty album is intentionally not enough: many correctly tagged singles
/// have no album field, and batch organization should leave them alone.
bool needsSmartOrganization(Track track) {
  final title = track.title.trim();
  final artist = track.artist.trim().toLowerCase();
  final fileName = track.path.split(RegExp(r'[/\\]')).last;
  final unknownArtist =
      artist.isEmpty ||
      artist == 'unknown artist' ||
      artist == 'local video' ||
      artist == '未知歌手' ||
      artist == '本地视频';
  final suspiciousTitle =
      title.isEmpty ||
      title.length > 72 ||
      RegExp(r'BV[0-9A-Za-z]{8,}', caseSensitive: false).hasMatch(title) ||
      RegExp(r'^(img|dsc|mv)[_-]?\d+$', caseSensitive: false).hasMatch(title) ||
      RegExp(r'^\d{1,3}\s*[-_.、]').hasMatch(title) ||
      !TrackNameParser.isReliableTitle(title, fileName: fileName);
  return unknownArtist || suspiciousTitle;
}
