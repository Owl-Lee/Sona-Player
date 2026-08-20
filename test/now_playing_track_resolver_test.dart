import 'package:flutter_test/flutter_test.dart';
import 'package:sonar_vault/features/library/domain/track.dart';
import 'package:sonar_vault/features/player/presentation/now_playing_track_resolver.dart';

Track _track(int id, {required bool isVideo}) => Track(
  id: id,
  path: 'C:/test/$id.${isVideo ? 'mp4' : 'mp3'}',
  title: 'Track $id',
  artist: 'Artist',
  album: 'Album',
  duration: const Duration(minutes: 4),
  fileSize: 1,
  contentHash: 'track-$id',
  importedAt: DateTime(2026, 8, 18),
  mediaType: isVideo ? 'video' : 'audio',
);

void main() {
  group('resolveNowPlayingDisplayTrack', () {
    final previousAudio = _track(1, isVideo: false);
    final requestedMv = _track(2, isVideo: true);
    final nextMv = _track(3, isVideo: true);
    final nextAudio = _track(4, isVideo: false);

    test('uses the requested MV only while its initial surface is pending', () {
      expect(
        resolveNowPlayingDisplayTrack(
          currentTrack: previousAudio,
          requestedTrack: requestedMv,
          isInitialVideoRequestPending: true,
        ),
        requestedMv,
      );
    });

    test('uses the controller track after MV-to-MV queue navigation', () {
      expect(
        resolveNowPlayingDisplayTrack(
          currentTrack: nextMv,
          requestedTrack: requestedMv,
          isInitialVideoRequestPending: false,
        ),
        nextMv,
      );
    });

    test(
      'uses the controller audio after selecting audio from an MV queue',
      () {
        expect(
          resolveNowPlayingDisplayTrack(
            currentTrack: nextAudio,
            requestedTrack: requestedMv,
            isInitialVideoRequestPending: false,
          ),
          nextAudio,
        );
      },
    );
  });
}
