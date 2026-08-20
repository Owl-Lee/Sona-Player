import 'dart:async';

import 'package:audio_service/audio_service.dart' as system_audio;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../library/domain/track.dart';

typedef VoidAudioAction = Future<void> Function();
typedef SeekAudioAction = Future<void> Function(Duration position);

final sonaAudioHandlerProvider = Provider<SonaAudioHandler>((ref) {
  throw StateError('SonaAudioHandler must be initialized before runApp.');
});

/// Bridges Sona's media_kit player to Android MediaSession/MediaStyle controls.
///
/// The player remains Sona's single source of truth. This handler only forwards
/// system actions to it and publishes the latest state to Android.
class SonaAudioHandler extends system_audio.BaseAudioHandler
    with system_audio.SeekHandler {
  VoidAudioAction? _play;
  VoidAudioAction? _pause;
  VoidAudioAction? _next;
  VoidAudioAction? _previous;
  SeekAudioAction? _seek;
  String? _lastQueueSignature;

  void attach({
    required VoidAudioAction play,
    required VoidAudioAction pause,
    required VoidAudioAction next,
    required VoidAudioAction previous,
    required SeekAudioAction seek,
  }) {
    _play = play;
    _pause = pause;
    _next = next;
    _previous = previous;
    _seek = seek;
  }

  void publish({
    required Track? currentTrack,
    required List<Track> tracks,
    required bool playing,
    required Duration position,
    required Duration bufferedPosition,
    required system_audio.AudioServiceRepeatMode repeatMode,
    required system_audio.AudioServiceShuffleMode shuffleMode,
  }) {
    final item = currentTrack == null ? null : _mediaItem(currentTrack);
    if (mediaItem.valueOrNull != item) mediaItem.add(item);

    final signature = tracks
        .map(
          (track) =>
              '${track.id}:${track.title}:${track.duration.inMilliseconds}',
        )
        .join('|');
    if (_lastQueueSignature != signature) {
      _lastQueueSignature = signature;
      queue.add(tracks.map(_mediaItem).toList(growable: false));
    }

    final currentIndex = currentTrack == null
        ? null
        : tracks.indexWhere((track) => track.id == currentTrack.id);
    playbackState.add(
      system_audio.PlaybackState(
        controls: currentTrack == null
            ? const []
            : [
                system_audio.MediaControl.skipToPrevious,
                playing
                    ? system_audio.MediaControl.pause
                    : system_audio.MediaControl.play,
                system_audio.MediaControl.skipToNext,
              ],
        systemActions: const {
          system_audio.MediaAction.seek,
          system_audio.MediaAction.seekForward,
          system_audio.MediaAction.seekBackward,
        },
        androidCompactActionIndices: currentTrack == null
            ? const []
            : const [0, 1, 2],
        processingState: currentTrack == null
            ? system_audio.AudioProcessingState.idle
            : system_audio.AudioProcessingState.ready,
        playing: playing,
        updatePosition: position,
        bufferedPosition: bufferedPosition,
        speed: 1,
        queueIndex: currentIndex != null && currentIndex >= 0
            ? currentIndex
            : null,
        repeatMode: repeatMode,
        shuffleMode: shuffleMode,
      ),
    );
  }

  system_audio.MediaItem _mediaItem(Track track) {
    return system_audio.MediaItem(
      id: track.path,
      title: track.title,
      artist: track.artist,
      album: track.album,
      duration: track.duration,
      extras: {'track_id': track.id, 'media_type': track.mediaType},
    );
  }

  @override
  Future<void> play() => _play?.call() ?? Future<void>.value();

  @override
  Future<void> pause() => _pause?.call() ?? Future<void>.value();

  @override
  Future<void> skipToNext() => _next?.call() ?? Future<void>.value();

  @override
  Future<void> skipToPrevious() => _previous?.call() ?? Future<void>.value();

  @override
  Future<void> seek(Duration position) =>
      _seek?.call(position) ?? Future<void>.value();

  @override
  Future<void> stop() async {
    await pause();
    await super.stop();
  }
}
