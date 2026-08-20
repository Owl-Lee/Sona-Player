class Track {
  const Track({
    this.id,
    required this.path,
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    required this.fileSize,
    required this.contentHash,
    required this.importedAt,
    this.isFavorite = false,
    this.playCount = 0,
    this.lastPlayedAt,
    this.videoPath,
    this.mediaType = 'audio',
  });

  final int? id;
  final String path;
  final String title;
  final String artist;
  final String album;
  final Duration duration;
  final int fileSize;
  final String contentHash;
  final DateTime importedAt;
  final bool isFavorite;
  final int playCount;
  final DateTime? lastPlayedAt;
  final String? videoPath;
  final String mediaType;

  bool get hasVideo => videoPath != null && videoPath!.isNotEmpty;
  bool get isVideoOnly => mediaType.trim().toLowerCase() == 'video';

  Track copyWith({
    int? id,
    String? path,
    String? title,
    String? artist,
    String? album,
    Duration? duration,
    int? fileSize,
    String? contentHash,
    DateTime? importedAt,
    bool? isFavorite,
    int? playCount,
    DateTime? lastPlayedAt,
    bool clearLastPlayedAt = false,
    String? videoPath,
    bool clearVideoPath = false,
    String? mediaType,
  }) {
    return Track(
      id: id ?? this.id,
      path: path ?? this.path,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      duration: duration ?? this.duration,
      fileSize: fileSize ?? this.fileSize,
      contentHash: contentHash ?? this.contentHash,
      importedAt: importedAt ?? this.importedAt,
      isFavorite: isFavorite ?? this.isFavorite,
      playCount: playCount ?? this.playCount,
      lastPlayedAt: clearLastPlayedAt
          ? null
          : lastPlayedAt ?? this.lastPlayedAt,
      videoPath: clearVideoPath ? null : videoPath ?? this.videoPath,
      mediaType: mediaType ?? this.mediaType,
    );
  }

  Map<String, Object?> toDatabaseMap() {
    return {
      'path': path,
      'title': title,
      'artist': artist,
      'album': album,
      'duration_ms': duration.inMilliseconds,
      'file_size': fileSize,
      'content_hash': contentHash,
      'imported_at': importedAt.toIso8601String(),
      'is_favorite': isFavorite ? 1 : 0,
      'play_count': playCount,
      'last_played_at': lastPlayedAt?.toIso8601String(),
      'video_path': videoPath,
      'media_type': mediaType,
    };
  }

  factory Track.fromDatabaseMap(Map<String, Object?> map) {
    return Track(
      id: map['id'] as int?,
      path: map['path']! as String,
      title: map['title']! as String,
      artist: map['artist']! as String,
      album: map['album']! as String,
      duration: Duration(milliseconds: map['duration_ms']! as int),
      fileSize: map['file_size']! as int,
      contentHash: map['content_hash']! as String,
      importedAt: DateTime.parse(map['imported_at']! as String),
      isFavorite: (map['is_favorite']! as int) == 1,
      playCount: map['play_count']! as int,
      lastPlayedAt: map['last_played_at'] == null
          ? null
          : DateTime.parse(map['last_played_at']! as String),
      videoPath: map['video_path'] as String?,
      mediaType: map['media_type'] as String? ?? 'audio',
    );
  }
}
