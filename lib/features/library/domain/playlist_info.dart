class PlaylistInfo {
  const PlaylistInfo({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.trackCount,
    this.description = '',
    this.coverPath,
    this.cloudId,
    this.updatedAt,
  });

  final int id;
  final String name;
  final DateTime createdAt;
  final int trackCount;
  final String description;
  final String? coverPath;
  final String? cloudId;
  final DateTime? updatedAt;

  PlaylistInfo copyWith({
    String? name,
    String? description,
    String? coverPath,
    String? cloudId,
    DateTime? updatedAt,
    bool clearCover = false,
    int? trackCount,
  }) {
    return PlaylistInfo(
      id: id,
      name: name ?? this.name,
      createdAt: createdAt,
      trackCount: trackCount ?? this.trackCount,
      description: description ?? this.description,
      coverPath: clearCover ? null : coverPath ?? this.coverPath,
      cloudId: cloudId ?? this.cloudId,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory PlaylistInfo.fromDatabaseMap(Map<String, Object?> map) {
    return PlaylistInfo(
      id: map['id']! as int,
      name: map['name']! as String,
      createdAt: DateTime.parse(map['created_at']! as String),
      trackCount: map['track_count']! as int,
      description: map['description'] as String? ?? '',
      coverPath: map['cover_path'] as String?,
      cloudId: map['cloud_id'] as String?,
      updatedAt: map['updated_at'] == null
          ? null
          : DateTime.tryParse(map['updated_at']! as String),
    );
  }
}
