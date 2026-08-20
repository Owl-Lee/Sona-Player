import '../../library/domain/track.dart';

/// Chooses the track represented by the full-screen player.
///
/// A newly opened pure-MV page has to reserve its video stage before the
/// player controller has switched away from the previous song. During that
/// short hand-off only, [requestedTrack] is the correct visual track. Once the
/// request settles, the controller is the sole source of truth so queue,
/// next/previous, and side-panel selections always update the whole page.
Track? resolveNowPlayingDisplayTrack({
  required Track? currentTrack,
  required Track? requestedTrack,
  required bool isInitialVideoRequestPending,
}) {
  if (isInitialVideoRequestPending && requestedTrack != null) {
    return requestedTrack;
  }
  return currentTrack;
}
