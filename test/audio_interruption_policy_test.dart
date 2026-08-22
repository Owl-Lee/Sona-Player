import 'package:flutter_test/flutter_test.dart';
import 'package:sonar_vault/features/player/domain/audio_interruption_policy.dart';

void main() {
  group('audio interruption policy', () {
    test('ducks only active playback and restores exactly once', () {
      expect(
        interruptionBeginAction(
          PlaybackInterruptionKind.duck,
          isPlaying: true,
          isDucked: false,
        ),
        PlaybackInterruptionAction.duck,
      );
      expect(
        interruptionBeginAction(
          PlaybackInterruptionKind.duck,
          isPlaying: true,
          isDucked: true,
        ),
        PlaybackInterruptionAction.none,
      );
      expect(
        interruptionEndAction(
          PlaybackInterruptionKind.duck,
          shouldResume: false,
          isDucked: true,
        ),
        PlaybackInterruptionAction.restoreVolume,
      );
      expect(
        interruptionEndAction(
          PlaybackInterruptionKind.duck,
          shouldResume: false,
          isDucked: false,
        ),
        PlaybackInterruptionAction.none,
      );
    });

    test('resumes after a call only when playback was active', () {
      expect(
        interruptionBeginAction(
          PlaybackInterruptionKind.pause,
          isPlaying: true,
          isDucked: false,
        ),
        PlaybackInterruptionAction.pause,
      );
      expect(
        interruptionEndAction(
          PlaybackInterruptionKind.pause,
          shouldResume: true,
          isDucked: false,
        ),
        PlaybackInterruptionAction.resume,
      );
      expect(
        interruptionEndAction(
          PlaybackInterruptionKind.pause,
          shouldResume: false,
          isDucked: false,
        ),
        PlaybackInterruptionAction.none,
      );
    });

    test('unknown interruptions and headphone removal never auto-resume', () {
      for (final kind in [
        PlaybackInterruptionKind.unknown,
        PlaybackInterruptionKind.becomingNoisy,
      ]) {
        expect(
          interruptionBeginAction(kind, isPlaying: true, isDucked: false),
          PlaybackInterruptionAction.pause,
        );
        expect(
          interruptionEndAction(kind, shouldResume: true, isDucked: false),
          PlaybackInterruptionAction.none,
        );
      }
    });
  });
}
