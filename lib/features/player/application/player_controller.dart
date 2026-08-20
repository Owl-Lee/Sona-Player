import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:audio_service/audio_service.dart' as system_audio;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart' hide Track;

import '../../../core/utils/latest_request_gate.dart';
import '../../library/domain/track.dart';
import '../../library/application/library_controller.dart';
import 'sona_audio_handler.dart';
import 'video_playback_request.dart';

final playerControllerProvider =
    StateNotifierProvider<PlayerController, PlaybackState>((ref) {
      final audioHandler = ref.read(sonaAudioHandlerProvider);
      final controller = PlayerController(
        onTrackSelected: (track) => ref
            .read(libraryControllerProvider.notifier)
            .markRecentlyPlayed(track),
        onValidPlay: (track, listened, duration) => ref
            .read(libraryControllerProvider.notifier)
            .recordPlay(
              track,
              listenedDuration: listened,
              mediaDuration: duration,
            ),
        onVideoTrackRequested: (track, queue, source) {
          ref
              .read(videoPlaybackRequestProvider.notifier)
              .state = VideoPlaybackRequest(
            track: track,
            queue: List<Track>.unmodifiable(queue),
            source: source,
          );
        },
      );
      audioHandler.attach(
        play: controller.play,
        pause: controller.pause,
        next: controller.next,
        previous: controller.previous,
        seek: controller.seek,
      );
      final removeSystemSync = controller.addListener(
        (state) => audioHandler.publish(
          currentTrack: state.currentTrack,
          tracks: controller.queue,
          playing: state.isPlaying,
          position: state.position,
          bufferedPosition: state.position,
          repeatMode: switch (state.playbackMode) {
            VaultPlaybackMode.one => system_audio.AudioServiceRepeatMode.one,
            VaultPlaybackMode.loop => system_audio.AudioServiceRepeatMode.all,
            VaultPlaybackMode.shuffle =>
              system_audio.AudioServiceRepeatMode.all,
          },
          shuffleMode: state.playbackMode == VaultPlaybackMode.shuffle
              ? system_audio.AudioServiceShuffleMode.all
              : system_audio.AudioServiceShuffleMode.none,
        ),
        fireImmediately: true,
      );
      ref.listen<LibraryState>(libraryControllerProvider, (previous, next) {
        if (!identical(previous?.tracks, next.tracks)) {
          unawaited(controller.reconcileLibraryTracks(next.tracks));
        }
      });
      ref.onDispose(removeSystemSync);
      ref.onDispose(controller.dispose);
      return controller;
    });

enum VaultPlaybackMode { loop, one, shuffle }

class PlaybackState {
  const PlaybackState({
    this.currentTrack,
    this.isPlaying = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.volume = 80,
    this.playbackMode = VaultPlaybackMode.loop,
    this.queueSource = '本地曲库',
    this.errorMessage = '',
    this.sleepTimerRemaining,
  });

  final Track? currentTrack;
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final double volume;
  final VaultPlaybackMode playbackMode;
  final String queueSource;
  final String errorMessage;
  final Duration? sleepTimerRemaining;

  PlaybackState copyWith({
    Track? currentTrack,
    bool? isPlaying,
    Duration? position,
    Duration? duration,
    double? volume,
    VaultPlaybackMode? playbackMode,
    String? queueSource,
    String? errorMessage,
    Duration? sleepTimerRemaining,
    bool clearCurrentTrack = false,
    bool clearSleepTimer = false,
  }) {
    return PlaybackState(
      currentTrack: clearCurrentTrack
          ? null
          : (currentTrack ?? this.currentTrack),
      isPlaying: isPlaying ?? this.isPlaying,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      volume: volume ?? this.volume,
      playbackMode: playbackMode ?? this.playbackMode,
      queueSource: queueSource ?? this.queueSource,
      errorMessage: errorMessage ?? this.errorMessage,
      sleepTimerRemaining: clearSleepTimer
          ? null
          : (sleepTimerRemaining ?? this.sleepTimerRemaining),
    );
  }
}

class PlayerController extends StateNotifier<PlaybackState> {
  PlayerController({
    required this._onTrackSelected,
    required this._onValidPlay,
    required this._onVideoTrackRequested,
  }) : _player = Player(
         configuration: const PlayerConfiguration(title: 'Sona'),
       ),
       super(const PlaybackState()) {
    _subscriptions.add(
      _player.stream.playing.listen((playing) {
        if (state.currentTrack == null) return;
        state = state.copyWith(isPlaying: playing);
      }),
    );
    _subscriptions.add(_player.stream.position.listen(_handlePosition));
    _subscriptions.add(
      _player.stream.duration.listen(
        // media_kit reports Duration.zero while it is opening a file (and for
        // a moment when a video switches streams).  Treating that transient
        // value as a real duration made the desktop seek bar clamp itself to
        // one millisecond, which looked like an immediate jump to the end.
        (duration) {
          if (state.currentTrack != null && duration > Duration.zero) {
            state = state.copyWith(duration: duration);
          }
        },
      ),
    );
    _subscriptions.add(
      _player.stream.volume.listen(
        (volume) => state = state.copyWith(volume: volume),
      ),
    );
    _subscriptions.add(
      _player.stream.completed.listen((completed) {
        if (completed && state.currentTrack != null) {
          unawaited(_playAfterCompletion());
        }
      }),
    );
    _subscriptions.add(
      _player.stream.error.listen(
        (error) => state = state.copyWith(errorMessage: error),
      ),
    );
    unawaited(_player.setVolume(state.volume));
  }

  final Player _player;
  final Future<void> Function(Track) _onTrackSelected;
  final Future<void> Function(Track, Duration, Duration) _onValidPlay;
  final void Function(Track, List<Track>, String) _onVideoTrackRequested;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  List<Track> _queue = const [];
  double _volumeBeforeMute = 80;
  int? _sessionTrackId;
  Duration? _lastObservedPosition;
  final Set<int> _heardSeconds = <int>{};
  var _validPlayRecorded = false;
  Timer? _sleepTimer;
  Timer? _sleepTicker;
  DateTime? _sleepDeadline;
  var _handlingCompletion = false;
  Duration? _pendingSeekPosition;
  DateTime? _pendingSeekRequestedAt;
  final _sourceRequests = LatestRequestGate();
  // media_kit's native open calls are not safe to overlap. A quick sequence
  // of next/previous taps therefore queues native work, while request ids make
  // every stale queued operation a no-op.
  Future<void> _nativeOpenTail = Future<void>.value();
  // The Player is shared by the mini player and the full-screen player. Keep
  // the file it already has open so presenting a new video texture never
  // mistakes a UI transition for a request to restart the media.
  String? _activeSourcePath;

  Player get player => _player;

  List<Track> get queue => List.unmodifiable(_queue);

  /// Makes a list the active playback context before a deferred media open.
  ///
  /// Video-only tracks mount a native surface before their file can be opened.
  /// Updating the queue here keeps the mini player and queue sheet in sync
  /// with the list the user just clicked, instead of briefly exposing the
  /// previous MV queue while that surface is being prepared.
  void selectQueue(Track track, List<Track> queue, {String source = '本地曲库'}) {
    // Cancel an earlier deferred open. The following playTrack call creates
    // its own request after the video surface is ready.
    _sourceRequests.begin();
    _replaceQueue(track, queue);
    state = state.copyWith(queueSource: source, errorMessage: '');
  }

  Future<void> playTrack(
    Track track,
    List<Track> queue, {
    String source = '本地曲库',
    bool videoSurfaceReady = false,
  }) async {
    if (track.isVideoOnly && !videoSurfaceReady) {
      selectQueue(track, queue, source: source);
      _onVideoTrackRequested(track, _queue, source);
      return;
    }
    final previousState = state;
    final request = _sourceRequests.begin();
    _replaceQueue(track, queue);
    state = state.copyWith(
      currentTrack: track,
      position: Duration.zero,
      duration: track.duration,
      queueSource: source,
      errorMessage: '',
    );
    final opened = await _openSingleTrack(track, play: true, request: request);
    if (!_sourceRequests.isCurrent(request)) return;
    if (!opened) {
      state = previousState.copyWith(
        errorMessage: '无法打开“${track.title}”。已保留上一首歌曲。',
      );
      return;
    }
    _startListeningSession(track, force: true);
    await _onTrackSelected(track);
    await _applyPlaybackMode(state.playbackMode);
  }

  Future<void> togglePlayPause() => _player.playOrPause();
  Future<void> play() => _player.play();
  Future<void> pause() => _player.pause();
  Future<void> next() => _moveInQueue(forward: true);
  Future<void> previous() => _moveInQueue(forward: false);
  Future<void> seek(Duration position) async {
    final duration = state.duration;
    // Seeking a stream whose duration is not known yet is undefined in the
    // native backend. Keep the seek bar disabled until that moment instead.
    if (duration <= Duration.zero) return;

    final target = position < Duration.zero
        ? Duration.zero
        : (position > duration ? duration : position);
    _pendingSeekPosition = target;
    _pendingSeekRequestedAt = DateTime.now();
    // Update immediately, then ignore the old position events that can arrive
    // just after a native seek. This makes dragging feel direct instead of
    // snapping back to 0:00.
    state = state.copyWith(position: target);
    await _player.seek(target);
  }

  Future<void> setVolume(double volume) async {
    if (volume > 0) _volumeBeforeMute = volume;
    await _player.setVolume(volume);
    state = state.copyWith(volume: volume);
  }

  Future<void> toggleMute() {
    return setVolume(state.volume <= 0 ? _volumeBeforeMute : 0);
  }

  void setSleepTimer(Duration? duration) {
    _sleepTimer?.cancel();
    _sleepTicker?.cancel();
    _sleepTimer = null;
    _sleepDeadline = null;
    if (duration == null || duration <= Duration.zero) {
      state = state.copyWith(clearSleepTimer: true);
      return;
    }
    _sleepDeadline = DateTime.now().add(duration);
    state = state.copyWith(sleepTimerRemaining: duration);
    _sleepTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      final deadline = _sleepDeadline;
      if (deadline == null) return;
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) return;
      state = state.copyWith(sleepTimerRemaining: remaining);
    });
    _sleepTimer = Timer(duration, () {
      unawaited(_player.pause());
      _sleepTicker?.cancel();
      _sleepTicker = null;
      _sleepDeadline = null;
      state = state.copyWith(clearSleepTimer: true);
    });
  }

  Future<void> switchTrackSource(Track track, String sourcePath) async {
    if (!await File(sourcePath).exists()) {
      state = state.copyWith(
        errorMessage: '找不到“${track.title}”的本地文件。它可能被移动或删除。',
      );
      return;
    }
    if (_isActiveSource(track, sourcePath)) {
      _replaceTrackInQueue(track);
      state = state.copyWith(currentTrack: track, errorMessage: '');
      return;
    }
    final previousState = state;
    final request = _sourceRequests.begin();
    final position = state.position;
    final wasPlaying = state.isPlaying;
    if (_queue.isEmpty) _queue = [track];
    var index = _queue.indexWhere((item) => item.id == track.id);
    if (index < 0) {
      _queue = [track];
      index = 0;
    } else {
      _queue[index] = track;
    }
    state = state.copyWith(currentTrack: track, errorMessage: '');
    final opened = await _openSingleTrack(
      track,
      path: sourcePath,
      // Open paused, restore the current position, then resume. Starting the
      // new source immediately causes a visible jump back to 0:00 whenever a
      // track switches between the MV and vinyl surfaces.
      play: false,
      request: request,
    );
    if (!_sourceRequests.isCurrent(request)) return;
    if (!opened) {
      state = previousState.copyWith(
        errorMessage: '无法打开“${track.title}”的本地文件。',
      );
      return;
    }
    if (position > Duration.zero) await _player.seek(position);
    if (!_sourceRequests.isCurrent(request)) return;
    if (wasPlaying) await _player.play();
  }

  Future<void> setPlaybackMode(VaultPlaybackMode mode) async {
    await _applyPlaybackMode(mode);
    state = state.copyWith(playbackMode: mode);
  }

  Future<void> _applyPlaybackMode(VaultPlaybackMode mode) async {
    // Sona owns queue navigation. Keeping media_kit on a one-item playlist
    // prevents delayed playlist-index events from a prior queue from changing
    // the visible current track (the IMG_5921 jump reported by users).
    await _player.setShuffle(false);
    await _player.setPlaylistMode(PlaylistMode.none);
  }

  Future<bool> _openSingleTrack(
    Track track, {
    String? path,
    required bool play,
    int? request,
  }) async {
    Future<bool> open() async {
      if (request != null && !_sourceRequests.isCurrent(request)) return false;
      final mediaPath = path ?? track.path;
      if (!await File(mediaPath).exists()) return false;
      if (request != null && !_sourceRequests.isCurrent(request)) return false;
      try {
        await _player.open(
          Media(
            mediaPath,
            extras: {
              'track_id': track.id,
              'title': track.title,
              'artist': track.artist,
            },
          ),
          play: play,
        );
      } catch (_) {
        return false;
      }
      if (request != null && !_sourceRequests.isCurrent(request)) return false;
      _activeSourcePath = mediaPath;
      unawaited(_hydrateDuration(track));
      return true;
    }

    final scheduled = _nativeOpenTail.then(
      (_) => open(),
      onError: (_) => open(),
    );
    _nativeOpenTail = scheduled.then<void>((_) {}, onError: (_) {});
    return scheduled;
  }

  bool _isActiveSource(Track track, String sourcePath) {
    return state.currentTrack?.id == track.id &&
        _activeSourcePath != null &&
        _normaliseSourcePath(_activeSourcePath!) ==
            _normaliseSourcePath(sourcePath);
  }

  String _normaliseSourcePath(String path) =>
      path.replaceAll('/', '\\').trim().toLowerCase();

  void _replaceTrackInQueue(Track track) {
    if (_queue.isEmpty) {
      _queue = [track];
      return;
    }
    final index = _queue.indexWhere((item) => item.id == track.id);
    if (index < 0) {
      _queue = [track];
    } else {
      _queue[index] = track;
    }
  }

  void _replaceQueue(Track track, List<Track> queue) {
    _queue = queue.isEmpty ? [track] : List<Track>.from(queue);
    if (_queue.every((item) => item.id != track.id)) {
      _queue.insert(0, track);
    }
  }

  Future<void> _hydrateDuration(Track track) async {
    if (state.currentTrack?.id != track.id) return;
    final currentDuration = _player.state.duration;
    if (currentDuration > Duration.zero) {
      state = state.copyWith(duration: currentDuration);
      return;
    }
    try {
      final discovered = await _player.stream.duration
          .firstWhere((duration) => duration > Duration.zero)
          .timeout(const Duration(seconds: 5));
      if (state.currentTrack?.id == track.id) {
        state = state.copyWith(duration: discovered);
      }
    } on TimeoutException {
      // Some malformed local files genuinely have no duration. The UI will
      // keep seeking disabled rather than pretending that 0:00 is seekable.
    }
  }

  Future<void> _moveInQueue({required bool forward}) async {
    final current = state.currentTrack;
    if (current == null || _queue.isEmpty) return;
    final currentIndex = _queue.indexWhere((item) => item.id == current.id);
    final safeIndex = currentIndex < 0 ? 0 : currentIndex;
    final nextIndex = _nextQueueIndex(safeIndex, forward: forward);
    final nextTrack = _queue[nextIndex];
    final previousState = state;
    final request = _sourceRequests.begin();
    state = state.copyWith(
      currentTrack: nextTrack,
      position: Duration.zero,
      duration: nextTrack.duration,
      errorMessage: '',
    );
    final opened = await _openSingleTrack(
      nextTrack,
      play: true,
      request: request,
    );
    if (!_sourceRequests.isCurrent(request)) return;
    if (!opened) {
      state = previousState.copyWith(
        errorMessage: '下一首“${nextTrack.title}”暂时无法打开，已保留当前歌曲。',
      );
      return;
    }
    _startListeningSession(nextTrack, force: true);
    await _onTrackSelected(nextTrack);
  }

  int _nextQueueIndex(int currentIndex, {required bool forward}) {
    if (_queue.length == 1 || state.playbackMode == VaultPlaybackMode.one) {
      return currentIndex;
    }
    if (state.playbackMode == VaultPlaybackMode.shuffle && forward) {
      final offset = Random().nextInt(_queue.length - 1) + 1;
      return (currentIndex + offset) % _queue.length;
    }
    final delta = forward ? 1 : -1;
    return (currentIndex + delta + _queue.length) % _queue.length;
  }

  Future<void> _playAfterCompletion() async {
    if (_handlingCompletion) return;
    _handlingCompletion = true;
    try {
      await _moveInQueue(forward: true);
    } finally {
      _handlingCompletion = false;
    }
  }

  void _startListeningSession(Track track, {bool force = false}) {
    if (!force && _sessionTrackId == track.id) return;
    _sessionTrackId = track.id;
    _lastObservedPosition = Duration.zero;
    _heardSeconds.clear();
    _validPlayRecorded = false;
    _pendingSeekPosition = null;
    _pendingSeekRequestedAt = null;
  }

  Future<void> reconcileLibraryTracks(Iterable<Track> libraryTracks) async {
    final availableById = <int, Track>{
      for (final track in libraryTracks)
        if (track.id != null) track.id!: track,
    };
    _queue = _queue
        .map((track) => track.id == null ? track : availableById[track.id])
        .whereType<Track>()
        .toList(growable: false);

    final current = state.currentTrack;
    if (current == null || current.id == null) return;
    final updated = availableById[current.id];
    if (updated == null) {
      await _clearCurrentTrack('当前歌曲已从本地曲库移除。');
      return;
    }
    if (!identical(current, updated)) {
      state = state.copyWith(currentTrack: updated);
    }
  }

  Future<void> _clearCurrentTrack(String message) async {
    _sourceRequests.begin();
    _sessionTrackId = null;
    _lastObservedPosition = null;
    _heardSeconds.clear();
    _validPlayRecorded = false;
    _pendingSeekPosition = null;
    _pendingSeekRequestedAt = null;
    _activeSourcePath = null;
    await _player.stop();
    state = state.copyWith(
      clearCurrentTrack: true,
      isPlaying: false,
      position: Duration.zero,
      duration: Duration.zero,
      errorMessage: message,
    );
  }

  void _handlePosition(Duration position) {
    final track = state.currentTrack;
    if (track == null) return;
    final pendingTarget = _pendingSeekPosition;
    if (pendingTarget != null) {
      final requestedAt = _pendingSeekRequestedAt;
      final isAtTarget =
          (position - pendingTarget).abs() < const Duration(milliseconds: 750);
      final hasSettled =
          requestedAt == null ||
          DateTime.now().difference(requestedAt) >= const Duration(seconds: 2);
      if (!isAtTarget && !hasSettled) return;
      _pendingSeekPosition = null;
      _pendingSeekRequestedAt = null;
    }
    final previous = _lastObservedPosition;
    if (state.isPlaying && previous != null && position > previous) {
      final delta = position - previous;
      // Normal media position updates are close together. A large jump is a
      // seek, so it must not make the skipped section count as listened.
      if (delta <= const Duration(seconds: 3)) {
        final startSecond = previous.inMilliseconds ~/ 1000;
        final endSecond = position.inMilliseconds ~/ 1000;
        for (var second = startSecond; second < endSecond; second++) {
          _heardSeconds.add(second);
        }
        _recordValidPlayIfNeeded(track);
      }
    }
    _lastObservedPosition = position;
    state = state.copyWith(position: position);
  }

  void _recordValidPlayIfNeeded(Track track) {
    if (_validPlayRecorded || track.id == null) return;
    final duration = state.duration > Duration.zero
        ? state.duration
        : track.duration;
    if (duration <= Duration.zero) return;
    final thresholdSeconds = validPlayThresholdSeconds(duration);
    if (_heardSeconds.length < thresholdSeconds) return;
    _validPlayRecorded = true;
    unawaited(
      _onValidPlay(track, Duration(seconds: _heardSeconds.length), duration),
    );
  }

  @override
  void dispose() {
    _sleepTimer?.cancel();
    _sleepTicker?.cancel();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(_player.dispose());
    super.dispose();
  }
}

int validPlayThresholdSeconds(Duration duration) {
  final total = duration.inSeconds;
  if (total <= 0) return 0;
  if (duration > const Duration(minutes: 10)) return 5 * 60;
  final seventyPercent = (total * 0.7).ceil();
  final minimum = total < 30 ? total : 30;
  return seventyPercent.clamp(minimum, total);
}
