import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/chinese_text.dart';
import '../data/library_database.dart';
import '../data/track_importer.dart';
import '../data/track_identifier.dart';
import '../domain/playlist_info.dart';
import '../domain/track.dart';
import '../domain/track_identification.dart';

final libraryControllerProvider =
    StateNotifierProvider<LibraryController, LibraryState>((ref) {
      final controller = LibraryController(ref.watch(libraryDatabaseProvider));
      Future<void>.microtask(controller.load);
      return controller;
    });

class LibraryState {
  const LibraryState({
    this.tracks = const [],
    this.playlists = const [],
    this.isLoading = true,
    this.isImporting = false,
    this.importProgress = 0,
    this.importTotal = 0,
    this.importingFile = '',
    this.databasePath = '',
    this.errorMessage = '',
  });

  final List<Track> tracks;
  final List<PlaylistInfo> playlists;
  final bool isLoading;
  final bool isImporting;
  final int importProgress;
  final int importTotal;
  final String importingFile;
  final String databasePath;
  final String errorMessage;

  int get totalBytes => tracks.fold(0, (sum, track) => sum + track.fileSize);
  Duration get totalDuration =>
      tracks.fold(Duration.zero, (sum, track) => sum + track.duration);
  List<Track> get recentlyPlayed {
    final result = tracks.where((track) => track.lastPlayedAt != null).toList();
    result.sort((a, b) => b.lastPlayedAt!.compareTo(a.lastPlayedAt!));
    return result.take(20).toList(growable: false);
  }

  LibraryState copyWith({
    List<Track>? tracks,
    List<PlaylistInfo>? playlists,
    bool? isLoading,
    bool? isImporting,
    int? importProgress,
    int? importTotal,
    String? importingFile,
    String? databasePath,
    String? errorMessage,
  }) {
    return LibraryState(
      tracks: tracks ?? this.tracks,
      playlists: playlists ?? this.playlists,
      isLoading: isLoading ?? this.isLoading,
      isImporting: isImporting ?? this.isImporting,
      importProgress: importProgress ?? this.importProgress,
      importTotal: importTotal ?? this.importTotal,
      importingFile: importingFile ?? this.importingFile,
      databasePath: databasePath ?? this.databasePath,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class ImportSummary {
  const ImportSummary({
    required this.added,
    required this.skipped,
    required this.failed,
    this.needsReview = 0,
  });

  final int added;
  final int skipped;
  final int failed;
  final int needsReview;

  String get message {
    final base = '导入 $added 首，跳过 $skipped 首，失败 $failed 首';
    return needsReview == 0 ? base : '$base · $needsReview 首可智能整理';
  }
}

class LibraryController extends StateNotifier<LibraryState> {
  LibraryController(this._database)
    : _importer = TrackImporter(),
      _identifier = TrackIdentifier(),
      super(const LibraryState());

  final LibraryDatabase _database;
  final TrackImporter _importer;
  final TrackIdentifier _identifier;
  final Set<int> _identifyingTrackIds = {};
  var _isBackfillingDurations = false;

  Future<void> load() async {
    try {
      final results = await Future.wait([
        _database.getTracks(),
        _database.getPlaylists(),
      ]);
      final repairedTracks = await _database.repairMovedTrackPaths(
        results[0] as List<Track>,
      );
      state = state.copyWith(
        tracks: repairedTracks,
        playlists: results[1] as List<PlaylistInfo>,
        isLoading: false,
        databasePath: _database.databasePath,
        errorMessage: '',
      );
      unawaited(_backfillVideoDurations());
    } catch (error) {
      state = state.copyWith(isLoading: false, errorMessage: '曲库读取失败：$error');
    }
  }

  Future<void> _backfillVideoDurations() async {
    if (_isBackfillingDurations) return;
    final missing = state.tracks
        .where(
          (track) =>
              track.id != null &&
              track.isVideoOnly &&
              track.duration <= Duration.zero,
        )
        .toList(growable: false);
    if (missing.isEmpty) return;
    _isBackfillingDurations = true;
    try {
      for (final track in missing) {
        final duration = await _importer.probeVideoDuration(track.path);
        if (duration <= Duration.zero || track.id == null) continue;
        await _database.setTrackDuration(track.id!, duration);
        state = state.copyWith(
          tracks: state.tracks
              .map(
                (item) => item.id == track.id
                    ? item.copyWith(duration: duration)
                    : item,
              )
              .toList(growable: false),
        );
      }
    } finally {
      _isBackfillingDurations = false;
    }
  }

  Future<ImportSummary?> importFiles() async {
    final paths = await _importer.pickAudioFiles();
    if (paths.isEmpty) return null;
    return _importPaths(paths);
  }

  Future<ImportSummary?> importDirectory() async {
    final paths = await _importer.pickAudioDirectory();
    if (paths.isEmpty) return null;
    return _importPaths(paths);
  }

  Future<ImportSummary> _importPaths(List<String> paths) async {
    var added = 0;
    var skipped = 0;
    var failed = 0;
    state = state.copyWith(
      isImporting: true,
      importProgress: 0,
      importTotal: paths.length,
      errorMessage: '',
    );

    for (var index = 0; index < paths.length; index++) {
      final filePath = paths[index];
      state = state.copyWith(
        importProgress: index,
        importingFile: filePath.split(RegExp(r'[/\\]')).last,
      );
      try {
        final track = await _importer.inspect(filePath);
        final inserted = await _database.insertTrack(track);
        if (inserted == null) {
          skipped++;
        } else {
          added++;
        }
      } catch (_) {
        failed++;
      }
    }

    state = state.copyWith(
      isImporting: false,
      importProgress: paths.length,
      importingFile: '',
    );
    await load();
    final importedPaths = paths.toSet();
    final needsReview = state.tracks
        .where(
          (track) =>
              importedPaths.contains(track.path) &&
              needsSmartOrganization(track),
        )
        .length;
    return ImportSummary(
      added: added,
      skipped: skipped,
      failed: failed,
      needsReview: needsReview,
    );
  }

  Future<void> toggleFavorite(Track track) async {
    if (track.id == null) return;
    await _database.setFavorite(track.id!, value: !track.isFavorite);
    final updated = state.tracks
        .map(
          (item) => item.id == track.id
              ? item.copyWith(isFavorite: !item.isFavorite)
              : item,
        )
        .toList(growable: false);
    state = state.copyWith(tracks: updated);
  }

  Future<void> setFavorites(
    Iterable<Track> tracks, {
    required bool value,
  }) async {
    final ids = tracks.map((track) => track.id).whereType<int>().toSet();
    if (ids.isEmpty) return;
    await _database.setFavorites(ids, value: value);
    state = state.copyWith(
      tracks: state.tracks
          .map(
            (track) => ids.contains(track.id)
                ? track.copyWith(isFavorite: value)
                : track,
          )
          .toList(growable: false),
    );
  }

  Future<void> recordPlay(
    Track track, {
    Duration listenedDuration = Duration.zero,
    Duration mediaDuration = Duration.zero,
  }) async {
    if (track.id == null) return;
    await _database.recordPlay(
      track.id!,
      listenedDuration: listenedDuration,
      mediaDuration: mediaDuration,
    );
    final updated = state.tracks
        .map(
          (item) => item.id == track.id
              ? item.copyWith(playCount: item.playCount + 1)
              : item,
        )
        .toList(growable: false);
    state = state.copyWith(tracks: updated);
  }

  Future<void> markRecentlyPlayed(Track track) async {
    if (track.id == null) return;
    final now = DateTime.now();
    state = state.copyWith(
      tracks: state.tracks
          .map(
            (item) =>
                item.id == track.id ? item.copyWith(lastPlayedAt: now) : item,
          )
          .toList(growable: false),
    );
    await _database.markRecentlyPlayed(track.id!);
  }

  Future<void> clearFromRecentlyPlayed(Track track) async {
    if (track.id == null) return;
    await _database.clearLastPlayed(track.id!);
    state = state.copyWith(
      tracks: state.tracks
          .map(
            (item) => item.id == track.id
                ? item.copyWith(clearLastPlayedAt: true)
                : item,
          )
          .toList(growable: false),
    );
  }

  Future<void> clearFromRankings(Track track) async {
    if (track.id == null) return;
    await _database.clearPlayHistory(track.id!);
    state = state.copyWith(
      tracks: state.tracks
          .map(
            (item) => item.id == track.id ? item.copyWith(playCount: 0) : item,
          )
          .toList(growable: false),
    );
  }

  Future<void> removeTrack(Track track) async {
    await removeTracks([track]);
  }

  Future<void> removeTracks(Iterable<Track> tracks) async {
    final ids = tracks.map((track) => track.id).whereType<int>().toSet();
    if (ids.isEmpty) return;
    await _database.removeTracks(ids);
    state = state.copyWith(
      tracks: state.tracks
          .where((item) => !ids.contains(item.id))
          .toList(growable: false),
    );
    await _refreshPlaylists();
  }

  Future<void> setVideoPath(Track track, String? videoPath) async {
    if (track.id == null) return;
    await _database.setTrackVideoPath(track.id!, videoPath);
    state = state.copyWith(
      tracks: state.tracks
          .map(
            (item) => item.id == track.id
                ? item.copyWith(
                    videoPath: videoPath,
                    clearVideoPath: videoPath == null,
                  )
                : item,
          )
          .toList(growable: false),
    );
  }

  Future<TrackIdentificationResult> identifyTrack(Track track) async {
    final id = track.id;
    if (id == null) {
      return const TrackIdentificationResult(message: '歌曲尚未写入曲库，无法识别。');
    }
    if (!_identifyingTrackIds.add(id)) {
      return const TrackIdentificationResult(message: '这首歌正在识别，请稍候。');
    }
    try {
      final clientKey = await _database.getSetting(
        'recognition.acoustid_client_key',
      );
      return await _identifier.identify(track, acoustIdClientKey: clientKey);
    } finally {
      _identifyingTrackIds.remove(id);
    }
  }

  Future<String> getAcoustIdClientKey() async =>
      (await _database.getSetting('recognition.acoustid_client_key') ?? '')
          .trim();

  Future<void> setAcoustIdClientKey(String value) =>
      _database.setSetting('recognition.acoustid_client_key', value.trim());

  Future<Track?> applyIdentification(
    Track track,
    TrackIdentificationCandidate candidate,
  ) async {
    final id = track.id;
    if (id == null) return null;
    final title = toSimplifiedChinese(candidate.title).trim();
    final artist = toSimplifiedChinese(candidate.artist).trim();
    final album = toSimplifiedChinese(candidate.album).trim();
    if (title.isEmpty || artist.isEmpty) return null;
    await _database.updateTrackMetadata(
      id,
      title: title,
      artist: artist,
      album: album,
    );
    final updated = track.copyWith(title: title, artist: artist, album: album);
    state = state.copyWith(
      tracks: state.tracks
          .map((item) => item.id == id ? updated : item)
          .toList(growable: false),
    );
    return updated;
  }

  Future<Track> pairAudioWithVideoTrack(Track track, String audioPath) async {
    if (track.id == null || !track.isVideoOnly) return track;
    final inspected = await _importer.inspect(audioPath);
    if (inspected.isVideoOnly) {
      throw StateError('请选择音频文件。');
    }
    final duplicate = state.tracks.any(
      (item) =>
          item.id != track.id &&
          (item.path == inspected.path ||
              item.contentHash == inspected.contentHash),
    );
    if (duplicate) {
      throw StateError('这首音频已经在曲库中。');
    }

    final updated = Track(
      id: track.id,
      path: inspected.path,
      title: inspected.title,
      artist: inspected.artist,
      album: inspected.album,
      duration: inspected.duration,
      fileSize: inspected.fileSize,
      contentHash: inspected.contentHash,
      importedAt: track.importedAt,
      isFavorite: track.isFavorite,
      playCount: track.playCount,
      lastPlayedAt: track.lastPlayedAt,
      videoPath: track.videoPath ?? track.path,
      mediaType: 'audio',
    );
    await _database.replaceTrackMedia(updated);
    state = state.copyWith(
      tracks: state.tracks
          .map((item) => item.id == track.id ? updated : item)
          .toList(growable: false),
    );
    return updated;
  }

  Future<void> createPlaylist(
    String name, {
    String description = '',
    String? coverPath,
  }) async {
    final normalized = name.trim();
    if (normalized.isEmpty) return;
    await _database.createPlaylist(
      normalized,
      description: description,
      coverPath: coverPath,
    );
    await _refreshPlaylists();
  }

  Future<void> updatePlaylist(
    int playlistId, {
    required String name,
    required String description,
    String? coverPath,
  }) async {
    if (name.trim().isEmpty) return;
    await _database.updatePlaylist(
      playlistId,
      name: name,
      description: description,
      coverPath: coverPath,
    );
    await _refreshPlaylists();
  }

  Future<void> deletePlaylist(int playlistId) async {
    await _database.deletePlaylist(playlistId);
    await _refreshPlaylists();
  }

  Future<bool> addTrackToPlaylist(PlaylistInfo playlist, Track track) async {
    return (await addTracksToPlaylist(playlist, [track])) > 0;
  }

  Future<int> addTracksToPlaylist(
    PlaylistInfo playlist,
    Iterable<Track> tracks,
  ) async {
    final ids = tracks.map((track) => track.id).whereType<int>().toSet();
    if (ids.isEmpty) return 0;
    final added = await _database.addTracksToPlaylist(playlist.id, ids);
    if (added > 0) await _refreshPlaylists();
    return added;
  }

  Future<List<Track>> tracksForPlaylist(int playlistId) {
    return _database.getTracksForPlaylist(playlistId);
  }

  Future<Map<int, int>> playCountsSince(DateTime since) {
    return _database.getPlayCountsSince(since);
  }

  Future<void> removeTrackFromPlaylist(int playlistId, int trackId) async {
    await removeTracksFromPlaylist(playlistId, [trackId]);
  }

  Future<int> removeTracksFromPlaylist(
    int playlistId,
    Iterable<int> trackIds,
  ) async {
    final removed = await _database.removeTracksFromPlaylist(
      playlistId,
      trackIds,
    );
    if (removed > 0) await _refreshPlaylists();
    return removed;
  }

  Future<void> _refreshPlaylists() async {
    state = state.copyWith(playlists: await _database.getPlaylists());
  }
}
