enum PlaybackInterruptionKind { duck, pause, unknown, becomingNoisy }

enum PlaybackInterruptionAction { none, duck, restoreVolume, pause, resume }

PlaybackInterruptionAction interruptionBeginAction(
  PlaybackInterruptionKind kind, {
  required bool isPlaying,
  required bool isDucked,
}) {
  return switch (kind) {
    PlaybackInterruptionKind.duck =>
      isPlaying && !isDucked
          ? PlaybackInterruptionAction.duck
          : PlaybackInterruptionAction.none,
    PlaybackInterruptionKind.pause =>
      isPlaying
          ? PlaybackInterruptionAction.pause
          : PlaybackInterruptionAction.none,
    PlaybackInterruptionKind.unknown ||
    PlaybackInterruptionKind.becomingNoisy => PlaybackInterruptionAction.pause,
  };
}

PlaybackInterruptionAction interruptionEndAction(
  PlaybackInterruptionKind kind, {
  required bool shouldResume,
  required bool isDucked,
}) {
  return switch (kind) {
    PlaybackInterruptionKind.duck =>
      isDucked
          ? PlaybackInterruptionAction.restoreVolume
          : PlaybackInterruptionAction.none,
    PlaybackInterruptionKind.pause =>
      shouldResume
          ? PlaybackInterruptionAction.resume
          : PlaybackInterruptionAction.none,
    PlaybackInterruptionKind.unknown ||
    PlaybackInterruptionKind.becomingNoisy => PlaybackInterruptionAction.none,
  };
}
