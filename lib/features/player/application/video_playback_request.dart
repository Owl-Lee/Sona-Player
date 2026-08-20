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
  });

  final Track track;
  final List<Track> queue;
  final String source;
}

final videoPlaybackRequestProvider =
    StateProvider<VideoPlaybackRequest?>((ref) => null);
