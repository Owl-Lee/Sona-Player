import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../library/domain/track.dart';

/// A video-only track has to open only after [VideoController] has attached
/// its native output. This request lets the shell present that stable surface
/// before [PlayerController] opens the media source.
class VideoPlaybackRequest {
  const VideoPlaybackRequest({
    required this.track,
    required this.queue,
    required this.source,
    this.sourceArgs = const {},
  });

  final Track track;
  final List<Track> queue;

  /// Locale-neutral localization key describing where this queue came from.
  final String source;
  final Map<String, String> sourceArgs;
}

final videoPlaybackRequestProvider = StateProvider<VideoPlaybackRequest?>(
  (ref) => null,
);
