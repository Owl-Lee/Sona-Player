class TrackMetadataValues {
  const TrackMetadataValues({
    required this.title,
    required this.artist,
    required this.album,
    this.artworkPath,
  });

  final String title;
  final String artist;
  final String album;
  final String? artworkPath;

  bool sameAs(TrackMetadataValues other) =>
      title == other.title &&
      artist == other.artist &&
      album == other.album &&
      artworkPath == other.artworkPath;
}

class TrackMetadataRevision {
  const TrackMetadataRevision({
    required this.id,
    required this.trackId,
    required this.kind,
    required this.source,
    required this.previous,
    required this.current,
    required this.createdAt,
    this.revertedAt,
  });

  final int id;
  final int trackId;
  final String kind;
  final String source;
  final TrackMetadataValues previous;
  final TrackMetadataValues current;
  final DateTime createdAt;
  final DateTime? revertedAt;

  bool get isReverted => revertedAt != null;

  factory TrackMetadataRevision.fromDatabaseMap(Map<String, Object?> map) {
    return TrackMetadataRevision(
      id: map['id']! as int,
      trackId: map['track_id']! as int,
      kind: map['change_kind']! as String,
      source: map['source']! as String,
      previous: TrackMetadataValues(
        title: map['previous_title']! as String,
        artist: map['previous_artist']! as String,
        album: map['previous_album']! as String,
        artworkPath: map['previous_artwork_path'] as String?,
      ),
      current: TrackMetadataValues(
        title: map['new_title']! as String,
        artist: map['new_artist']! as String,
        album: map['new_album']! as String,
        artworkPath: map['new_artwork_path'] as String?,
      ),
      createdAt: DateTime.parse(map['created_at']! as String),
      revertedAt: map['reverted_at'] == null
          ? null
          : DateTime.parse(map['reverted_at']! as String),
    );
  }
}
