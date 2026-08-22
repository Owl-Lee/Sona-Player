import '../../library/domain/track.dart';
import 'playback_mode.dart';

bool samePlaybackTrack(Track first, Track second) {
  if (first.id != null && second.id != null) return first.id == second.id;
  return first.contentHash == second.contentHash;
}

List<Track> normalizedPlaybackQueue(Track selected, Iterable<Track> source) {
  final result = <Track>[];
  final ids = <int>{};
  final hashes = <String>{};

  for (final track in source) {
    final duplicateId = track.id != null && ids.contains(track.id);
    final duplicateHash =
        track.contentHash.isNotEmpty && hashes.contains(track.contentHash);
    if (duplicateId || duplicateHash) continue;
    result.add(track);
    if (track.id != null) ids.add(track.id!);
    if (track.contentHash.isNotEmpty) hashes.add(track.contentHash);
  }
  if (!result.any((track) => samePlaybackTrack(track, selected))) {
    result.insert(0, selected);
  }
  return result;
}

/// Rebinds a queue to the newest database rows after library mutations.
///
/// A queue item with an id is local-library state and is removed when that id
/// disappears. Id-less items are transient cloud candidates; retaining them
/// preserves the existing offline cloud queue behavior until their own request
/// is superseded. Returning the refreshed current track lets the player react
/// immediately when metadata or an associated MV is removed.
({List<Track> queue, Track? current}) reconcilePlaybackQueue({
  required Track? current,
  required Iterable<Track> queue,
  required Iterable<Track> available,
}) {
  final availableById = <int, Track>{
    for (final track in available)
      if (track.id != null) track.id!: track,
  };
  final refreshedQueue = queue
      .map((track) => track.id == null ? track : availableById[track.id])
      .whereType<Track>()
      .toList(growable: false);
  if (current == null || current.id == null) {
    return (queue: refreshedQueue, current: current);
  }
  return (queue: refreshedQueue, current: availableById[current.id]);
}

int nextPlaybackQueueIndex({
  required int length,
  required int currentIndex,
  required bool forward,
  required VaultPlaybackMode mode,
  int? shuffleOffset,
}) {
  if (length <= 0) return 0;
  final safeIndex = currentIndex.clamp(0, length - 1);
  if (length == 1 || mode == VaultPlaybackMode.one) return safeIndex;
  if (mode == VaultPlaybackMode.shuffle && forward) {
    final offset = (shuffleOffset ?? 1).clamp(1, length - 1);
    return (safeIndex + offset) % length;
  }
  final delta = forward ? 1 : -1;
  return (safeIndex + delta + length) % length;
}
