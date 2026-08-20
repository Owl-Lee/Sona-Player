import 'package:flutter_test/flutter_test.dart';
import 'package:sonar_vault/features/library/domain/track.dart';
import 'package:sonar_vault/features/player/application/player_controller.dart';

void main() {
  test('playback state can clear a removed current track', () {
    final state =
        PlaybackState(
          currentTrack: Track(
            id: 1,
            path: 'C:/test/deleted.mp3',
            title: 'Deleted',
            artist: 'Artist',
            album: 'Album',
            duration: const Duration(minutes: 3),
            fileSize: 1,
            contentHash: 'deleted',
            importedAt: DateTime(2026, 8, 17),
          ),
          isPlaying: true,
          position: const Duration(seconds: 30),
          duration: const Duration(minutes: 3),
        ).copyWith(
          clearCurrentTrack: true,
          isPlaying: false,
          position: Duration.zero,
          duration: Duration.zero,
        );

    expect(state.currentTrack, isNull);
    expect(state.isPlaying, isFalse);
    expect(state.position, Duration.zero);
    expect(state.duration, Duration.zero);
  });

  group('validPlayThresholdSeconds', () {
    test('normal tracks require seventy percent of their duration', () {
      expect(validPlayThresholdSeconds(const Duration(minutes: 4)), 168);
    });

    test('very short tracks can still complete', () {
      expect(validPlayThresholdSeconds(const Duration(seconds: 20)), 20);
    });

    test('long media uses the five minute threshold', () {
      expect(validPlayThresholdSeconds(const Duration(minutes: 45)), 300);
    });
  });
}
