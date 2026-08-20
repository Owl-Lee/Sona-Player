import 'package:flutter_test/flutter_test.dart';
import 'package:sonar_vault/features/library/domain/track.dart';

void main() {
  test('track survives a database map round trip', () {
    final importedAt = DateTime(2026, 8, 14, 12, 30);
    final track = Track(
      id: 7,
      path: r'C:\Music\Example.mp3',
      title: 'Example',
      artist: 'Artist',
      album: 'Album',
      duration: const Duration(minutes: 3, seconds: 40),
      fileSize: 123456,
      contentHash: 'abc123',
      importedAt: importedAt,
      isFavorite: true,
      playCount: 2,
      videoPath: r'C:\Music\Example.mp4',
      mediaType: 'video',
    );

    final map = track.toDatabaseMap()..['id'] = track.id;
    final restored = Track.fromDatabaseMap(map);

    expect(restored.id, 7);
    expect(restored.title, 'Example');
    expect(restored.duration, const Duration(minutes: 3, seconds: 40));
    expect(restored.isFavorite, isTrue);
    expect(restored.importedAt, importedAt);
    expect(restored.videoPath, r'C:\Music\Example.mp4');
    expect(restored.mediaType, 'video');
    expect(restored.isVideoOnly, isTrue);
  });

  test('copyWith can explicitly clear the recent-play timestamp', () {
    final track = Track(
      id: 8,
      path: r'C:\Music\Recent.mp3',
      title: 'Recent',
      artist: 'Artist',
      album: 'Album',
      duration: const Duration(minutes: 4),
      fileSize: 2048,
      contentHash: 'recent-hash',
      importedAt: DateTime(2026, 8, 16),
      lastPlayedAt: DateTime(2026, 8, 16, 12),
    );

    final cleared = track.copyWith(clearLastPlayedAt: true);

    expect(cleared.lastPlayedAt, isNull);
  });
}
