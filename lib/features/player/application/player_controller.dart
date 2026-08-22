import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:audio_service/audio_service.dart' as system_audio;
import 'package:audio_session/audio_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart' hide Track;

import '../../library/domain/track.dart';
import '../../library/application/library_controller.dart';
import 'sona_audio_handler.dart';
import 'notification_permission_service.dart';
import 'video_playback_request.dart';
import '../domain/playback_mode.dart';
import '../domain/media_transport_coordinator.dart';
import '../domain/playback_queue_policy.dart';
import '../domain/audio_interruption_policy.dart';

export '../domain/playback_mode.dart';

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
        onVideoTrackRequested: (track, queue, source, sourceArgs) {
          ref
              .read(videoPlaybackRequestProvider.notifier)
              .state = VideoPlaybackRequest(
            track: track,
            queue: List<Track>.unmodifiable(queue),
            source: source,
            sourceArgs: Map<String, String>.unmodifiable(sourceArgs),
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

class PlaybackState {
  const PlaybackState({
    this.currentTrack,
    this.isPlaying = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.volume = 80,
    this.playbackMode = VaultPlaybackMode.loop,
    this.queueSource = 'queue_source_local_library',
    this.queueSourceArgs = const {},
    this.errorMessage = '',
    this.errorMessageArgs = const {},
    this.sleepTimerRemaining,
  });

  final Track? currentTrack;
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final double volume;
  final VaultPlaybackMode playbackMode;

  /// Locale-neutral localization key for the active queue origin.
  final String queueSource;
  final Map<String, String> queueSourceArgs;
  final String errorMessage;
  final Map<String, String> errorMessageArgs;
  final Duration? sleepTimerRemaining;

  PlaybackState copyWith({
    Track? currentTrack,
    bool? isPlaying,
    Duration? position,
    Duration? duration,
    double? volume,
    VaultPlaybackMode? playbackMode,
    String? queueSource,
    Map<String, String>? queueSourceArgs,
    String? errorMessage,
    Map<String, String>? errorMessageArgs,
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
      queueSourceArgs:
          queueSourceArgs ??
          (queueSource != null ? const {} : this.queueSourceArgs),
      errorMessage: errorMessage ?? this.errorMessage,
      errorMessageArgs:
          errorMessageArgs ??
          (errorMessage != null ? const {} : this.errorMessageArgs),
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
          _queueCompletion();
        }
      }),
    );
    _subscriptions.add(
      _player.stream.error.listen(
        (error) => state = state.copyWith(errorMessage: 'player_error_engine'),
      ),
    );
    unawaited(_player.setVolume(state.volume));
    if (Platform.isAndroid) unawaited(_initializeAudioSession());
  }

  final Player _player;
  final Future<void> Function(Track) _onTrackSelected;
  final Future<void> Function(Track, Duration, Duration) _onValidPlay;
  final void Function(Track, List<Track>, String, Map<String, String>)
  _onVideoTrackRequested;
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
  // Every command which may replace or unload the native source uses this one
  // lane. Explicit selections invalidate older opens immediately; the lane
  // then disposes a stale native result before the next command can start.
  final _transport = MediaTransportCoordinator();
  // The Player is shared by the mini player and the full-screen player. Keep
  // the file it already has open so presenting a new video texture never
  // mistakes a UI transition for a request to restart the media.
  String? _activeSourcePath;
  AudioSession? _audioSession;
  StreamSubscription<AudioInterruptionEvent>? _interruptionSubscription;
  StreamSubscription<void>? _becomingNoisySubscription;
  bool _resumeAfterInterruption = false;
  bool _duckedBySystem = false;
  double? _volumeBeforeSystemDuck;
  Player get player => _player;

  List<Track> get queue => List.unmodifiable(_queue);

  /// Makes a list the active playback context before a deferred media open.
  ///
  /// Video-only tracks mount a native surface before their file can be opened.
  /// Updating the queue here keeps the mini player and queue sheet in sync
  /// with the list the user just clicked, instead of briefly exposing the
  /// previous MV queue while that surface is being prepared.
  void selectQueue(
    Track track,
    List<Track> queue, {
    String source = 'queue_source_local_library',
    Map<String, String> sourceArgs = const {},
  }) {
    // Cancel an earlier deferred open. The following playTrack call creates
    // its own request after the video surface is ready.
    _transport.beginSourceRequest();
    _replaceQueue(track, queue);
    state = state.copyWith(
      queueSource: source,
      queueSourceArgs: sourceArgs,
      errorMessage: '',
    );
  }

  Future<void> playTrack(
    Track track,
    List<Track> queue, {
    String source = 'queue_source_local_library',
    Map<String, String> sourceArgs = const {},
    bool videoSurfaceReady = false,
  }) {
    // Android 13+ hides media notifications until the user grants this. The
    // request is intentionally tied to an explicit playback gesture and never
    // blocks local playback when permission is denied.
    unawaited(requestPlaybackNotificationPermissionIfNeeded());
    if (track.isVideoOnly && !videoSurfaceReady) {
      selectQueue(track, queue, source: source, sourceArgs: sourceArgs);
      _onVideoTrackRequested(track, _queue, source, sourceArgs);
      return Future<void>.value();
    }
    final previousState = state;
    final request = _transport.beginSourceRequest();
    // Reflect an explicit selection immediately. Besides making the UI feel
    // direct, this lets a concurrent library refresh reconcile the selected
    // row instead of mistaking the previously playing row for the target.
    _replaceQueue(track, queue);
    state = state.copyWith(
      currentTrack: track,
      position: Duration.zero,
      duration: track.duration,
      queueSource: source,
      queueSourceArgs: sourceArgs,
      errorMessage: '',
    );
    return _enqueueTransport(
      () =>
          _playTrackNow(track, previousState: previousState, request: request),
    );
  }

  Future<void> _playTrackNow(
    Track track, {
    required PlaybackState previousState,
    required int request,
  }) async {
    if (!_transport.isCurrentSourceRequest(request)) return;
    final opened = await _openSingleTrack(track, play: true, request: request);
    if (!_transport.isCurrentSourceRequest(request)) return;
    if (!opened) {
      state = previousState.copyWith(
        errorMessage: 'player_error_open_track_preserved_previous',
        errorMessageArgs: {'title': track.title},
      );
      return;
    }
    _startListeningSession(track, force: true);
    await _onTrackSelected(track);
    if (!_transport.isCurrentSourceRequest(request)) return;
    await _applyPlaybackMode(state.playbackMode);
  }

  Future<void> togglePlayPause() {
    if (!state.isPlaying) {
      unawaited(requestPlaybackNotificationPermissionIfNeeded());
    }
    return _enqueueTransport(() async {
      // Read media_kit's state only when this queued command starts. Rapid taps
      // therefore alternate deterministically instead of all observing the same
      // slightly delayed Riverpod state and issuing duplicate play commands.
      if (_player.state.playing) {
        await _pauseForUser();
      } else {
        await _playForUser();
      }
    });
  }

  Future<void> play() => _enqueueTransport(_playForUser);

  Future<void> pause() => _enqueueTransport(_pauseForUser);

  Future<void> _playForUser() async {
    _resumeAfterInterruption = false;
    if (!await _activateAudioSession()) {
      state = state.copyWith(errorMessage: 'player_error_audio_focus_denied');
      return;
    }
    await _player.play();
  }

  Future<void> _pauseForUser() async {
    _resumeAfterInterruption = false;
    await _player.pause();
  }

  Future<void> _enqueueTransport(Future<void> Function() operation) {
    return _transport.run(operation);
  }

  Future<void> next() => _enqueueTransport(() => _moveInQueue(forward: true));
  Future<void> previous() =>
      _enqueueTransport(() => _moveInQueue(forward: false));
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

  Future<void> switchTrackSource(Track track, String sourcePath) {
    final request = _transport.beginSourceRequest();
    return _enqueueTransport(
      () => _switchTrackSourceNow(track, sourcePath, request: request),
    );
  }

  Future<void> _switchTrackSourceNow(
    Track track,
    String sourcePath, {
    required int request,
  }) async {
    if (!_transport.isCurrentSourceRequest(request)) return;
    if (!await File(sourcePath).exists()) {
      state = state.copyWith(
        errorMessage: 'player_error_local_file_missing',
        errorMessageArgs: {'title': track.title},
      );
      return;
    }
    if (!_transport.isCurrentSourceRequest(request)) return;
    if (_isActiveSource(track, sourcePath)) {
      _replaceTrackInQueue(track);
      state = state.copyWith(currentTrack: track, errorMessage: '');
      return;
    }
    final previousState = state;
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
    if (!_transport.isCurrentSourceRequest(request)) return;
    if (!opened) {
      state = previousState.copyWith(
        errorMessage: 'player_error_open_local_file',
        errorMessageArgs: {'title': track.title},
      );
      return;
    }
    if (position > Duration.zero) await _player.seek(position);
    if (!_transport.isCurrentSourceRequest(request)) return;
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
    final mediaPath = path ?? track.path;
    final sourceRequest = request ?? _transport.beginSourceRequest();
    if (!_transport.isCurrentSourceRequest(sourceRequest)) return false;
    if (play && !await _activateAudioSession()) return false;
    if (!await File(mediaPath).exists()) return false;
    if (!_transport.isCurrentSourceRequest(sourceRequest)) return false;
    try {
      return await _transport.openLatest(
        request: sourceRequest,
        open: () => _player.open(
          Media(
            mediaPath,
            extras: {
              'track_id': track.id,
              'title': track.title,
              'artist': track.artist,
            },
          ),
          play: play,
        ),
        discardStale: _discardStaleNativeSource,
        commit: () {
          _activeSourcePath = mediaPath;
          unawaited(_hydrateDuration(track));
        },
      );
    } catch (_) {
      return false;
    }
  }

  Future<void> _discardStaleNativeSource() async {
    try {
      await _player.stop();
    } finally {
      _activeSourcePath = null;
    }
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
    _queue = normalizedPlaybackQueue(track, queue);
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
    final request = _transport.beginSourceRequest();
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
    if (!_transport.isCurrentSourceRequest(request)) return;
    if (!opened) {
      state = previousState.copyWith(
        errorMessage: 'player_error_open_next_preserved_current',
        errorMessageArgs: {'title': nextTrack.title},
      );
      return;
    }
    _startListeningSession(nextTrack, force: true);
    await _onTrackSelected(nextTrack);
  }

  int _nextQueueIndex(int currentIndex, {required bool forward}) {
    final shuffleOffset =
        state.playbackMode == VaultPlaybackMode.shuffle &&
            forward &&
            _queue.length > 1
        ? Random().nextInt(_queue.length - 1) + 1
        : null;
    return nextPlaybackQueueIndex(
      length: _queue.length,
      currentIndex: currentIndex,
      forward: forward,
      mode: state.playbackMode,
      shuffleOffset: shuffleOffset,
    );
  }

  void _queueCompletion() {
    if (_handlingCompletion) return;
    _handlingCompletion = true;
    unawaited(
      _enqueueTransport(() async {
        try {
          await _moveInQueue(forward: true);
        } finally {
          _handlingCompletion = false;
        }
      }),
    );
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

  Future<void> reconcileLibraryTracks(Iterable<Track> libraryTracks) {
    final snapshot = List<Track>.unmodifiable(libraryTracks);
    final current = state.currentTrack;
    final preview = reconcilePlaybackQueue(
      current: current,
      queue: _queue,
      available: snapshot,
    );
    final willClearCurrent =
        current != null && current.id != null && preview.current == null;
    final willDetachActiveVideo =
        current?.hasVideo == true &&
        preview.current?.hasVideo == false &&
        current!.videoPath != null &&
        _isActiveSource(current, current.videoPath!);
    final request = willClearCurrent || willDetachActiveVideo
        ? _transport.beginSourceRequest()
        : null;
    return _enqueueTransport(
      () => _reconcileLibraryTracksNow(snapshot, request: request),
    );
  }

  Future<void> _reconcileLibraryTracksNow(
    Iterable<Track> libraryTracks, {
    required int? request,
  }) async {
    if (request != null && !_transport.isCurrentSourceRequest(request)) return;
    final current = state.currentTrack;
    final reconciled = reconcilePlaybackQueue(
      current: current,
      queue: _queue,
      available: libraryTracks,
    );
    _queue = reconciled.queue;
    if (current == null || current.id == null) return;
    final updated = reconciled.current;
    if (updated == null) {
      final clearRequest = request ?? _transport.beginSourceRequest();
      await _clearCurrentTrack(
        'player_error_current_removed_from_library',
        request: clearRequest,
      );
      return;
    }
    final detachedActiveVideo =
        current.hasVideo &&
        !updated.hasVideo &&
        _isActiveSource(current, current.videoPath!);
    if (detachedActiveVideo) {
      // A deleted paired MV must not leave the native player bound to a file
      // that no longer belongs to the refreshed track. Preserve position and
      // playback state while returning to the audio source.
      final switchRequest = request ?? _transport.beginSourceRequest();
      await _switchTrackSourceNow(
        updated,
        updated.path,
        request: switchRequest,
      );
      return;
    }
    if (!identical(current, updated)) {
      state = state.copyWith(currentTrack: updated);
    }
  }

  Future<void> _clearCurrentTrack(
    String message, {
    required int request,
  }) async {
    if (!_transport.isCurrentSourceRequest(request)) return;
    _sessionTrackId = null;
    _lastObservedPosition = null;
    _heardSeconds.clear();
    _validPlayRecorded = false;
    _pendingSeekPosition = null;
    _pendingSeekRequestedAt = null;
    _activeSourcePath = null;
    await _player.stop();
    await _audioSession?.setActive(false);
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

  Future<void> _initializeAudioSession() async {
    try {
      final session = await AudioSession.instance;
      if (!mounted) return;
      _audioSession = session;
      await _interruptionSubscription?.cancel();
      await _becomingNoisySubscription?.cancel();
      _interruptionSubscription = session.interruptionEventStream.listen(
        _handleAudioInterruption,
      );
      _becomingNoisySubscription = session.becomingNoisyEventStream.listen((_) {
        // Unplugging wired/Bluetooth headphones must never continue through
        // the phone speaker. A later reconnect remains an explicit user play.
        _resumeAfterInterruption = false;
        unawaited(_restoreSystemDuck());
        if (interruptionBeginAction(
              PlaybackInterruptionKind.becomingNoisy,
              isPlaying: state.isPlaying,
              isDucked: _duckedBySystem,
            ) ==
            PlaybackInterruptionAction.pause) {
          unawaited(_player.pause());
        }
      });
    } catch (_) {
      // Playback remains available on hosts without an audio-session backend.
    }
  }

  Future<bool> _activateAudioSession() async {
    if (!Platform.isAndroid) return true;
    var session = _audioSession;
    if (session == null) {
      try {
        session = await AudioSession.instance;
        _audioSession = session;
      } catch (_) {
        return true;
      }
    }
    try {
      return await session.setActive(true);
    } catch (_) {
      return false;
    }
  }

  void _handleAudioInterruption(AudioInterruptionEvent event) {
    switch (event.type) {
      case AudioInterruptionType.duck:
        if (event.begin) {
          final action = interruptionBeginAction(
            PlaybackInterruptionKind.duck,
            isPlaying: state.isPlaying,
            isDucked: _duckedBySystem,
          );
          if (action != PlaybackInterruptionAction.duck) return;
          _duckedBySystem = true;
          _volumeBeforeSystemDuck = state.volume;
          unawaited(
            _player.setVolume((state.volume * 0.25).clamp(0, 100).toDouble()),
          );
        } else {
          final action = interruptionEndAction(
            PlaybackInterruptionKind.duck,
            shouldResume: false,
            isDucked: _duckedBySystem,
          );
          if (action == PlaybackInterruptionAction.restoreVolume) {
            unawaited(_restoreSystemDuck());
          }
        }
        return;
      case AudioInterruptionType.pause:
        if (event.begin) {
          _resumeAfterInterruption = state.isPlaying;
          final action = interruptionBeginAction(
            PlaybackInterruptionKind.pause,
            isPlaying: state.isPlaying,
            isDucked: _duckedBySystem,
          );
          if (action == PlaybackInterruptionAction.pause) {
            unawaited(_player.pause());
          }
        } else {
          final action = interruptionEndAction(
            PlaybackInterruptionKind.pause,
            shouldResume: _resumeAfterInterruption,
            isDucked: _duckedBySystem,
          );
          _resumeAfterInterruption = false;
          if (action == PlaybackInterruptionAction.resume) unawaited(play());
        }
        return;
      case AudioInterruptionType.unknown:
        if (event.begin) {
          // Unknown interruptions can be indefinite. Pause safely but never
          // surprise the user by resuming after the source disappears.
          _resumeAfterInterruption = false;
          unawaited(_restoreSystemDuck());
          if (interruptionBeginAction(
                PlaybackInterruptionKind.unknown,
                isPlaying: state.isPlaying,
                isDucked: _duckedBySystem,
              ) ==
              PlaybackInterruptionAction.pause) {
            unawaited(_player.pause());
          }
        }
        return;
    }
  }

  Future<void> _restoreSystemDuck() async {
    if (!_duckedBySystem) return;
    final volume = _volumeBeforeSystemDuck ?? state.volume;
    _duckedBySystem = false;
    _volumeBeforeSystemDuck = null;
    await _player.setVolume(volume);
  }

  @override
  void dispose() {
    _sleepTimer?.cancel();
    _sleepTicker?.cancel();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(_interruptionSubscription?.cancel());
    unawaited(_becomingNoisySubscription?.cancel());
    unawaited(_audioSession?.setActive(false));
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
