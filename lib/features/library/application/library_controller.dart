import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path_util;

import '../data/library_database.dart';
import '../data/track_importer.dart';
import '../data/track_identifier.dart';
import '../domain/playlist_info.dart';
import '../domain/track.dart';
import '../domain/track_identification.dart';
import '../domain/track_metadata_revision.dart';

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
}

/// A locale-neutral failure emitted by library-domain operations.
/// Presentation code translates [code] at the point of display.
class LibraryOperationException implements Exception {
  const LibraryOperationException(this.code);

  final String code;

  @override
  String toString() => code;
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
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'library_read_failed',
      );
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
      return const TrackIdentificationResult(message: 'track_not_persisted');
    }
    if (!_identifyingTrackIds.add(id)) {
      return const TrackIdentificationResult(
        message: 'identification_in_progress',
      );
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
    // Persist the provider's canonical spelling. Locale conversion belongs in
    // the presentation layer so switching Sona between Hans, Hant and English
    // never destroys the original metadata returned by AcoustID/MusicBrainz.
    final title = candidate.title.trim();
    final artist = candidate.artist.trim();
    final album = candidate.album.trim().isEmpty
        ? track.album.trim()
        : candidate.album.trim();
    if (title.isEmpty || artist.isEmpty) return null;
    return updateTrackDetails(
      track,
      title: title,
      artist: artist,
      album: album,
      changeKind: 'identification',
      source: candidate.source,
    );
  }

  Future<Track?> updateTrackDetails(
    Track track, {
    required String title,
    required String artist,
    required String album,
    String? selectedArtworkPath,
    bool clearArtwork = false,
    String changeKind = 'manual',
    String source = 'manual_edit',
  }) async {
    final id = track.id;
    if (id == null) return null;
    final normalizedTitle = title.trim();
    final normalizedArtist = artist.trim();
    final normalizedAlbum = album.trim();
    if (normalizedTitle.isEmpty || normalizedArtist.isEmpty) return null;

    final liveTrack =
        state.tracks.cast<Track?>().firstWhere(
          (item) => item?.id == id,
          orElse: () => track,
        ) ??
        track;
    String? managedArtworkPath;
    var nextArtworkPath = clearArtwork ? null : liveTrack.artworkPath;
    if (!clearArtwork && selectedArtworkPath?.trim().isNotEmpty == true) {
      managedArtworkPath = await _copyArtworkToManagedDirectory(
        id,
        selectedArtworkPath!.trim(),
      );
      nextArtworkPath = managedArtworkPath;
    }

    try {
      final revision = await _database.updateTrackMetadataWithHistory(
        id,
        title: normalizedTitle,
        artist: normalizedArtist,
        album: normalizedAlbum,
        artworkPath: nextArtworkPath,
        changeKind: changeKind,
        source: source,
      );
      if (revision == null) {
        if (managedArtworkPath != null &&
            managedArtworkPath != liveTrack.artworkPath) {
          await _deleteQuietly(managedArtworkPath);
        }
        return liveTrack;
      }
    } catch (_) {
      if (managedArtworkPath != null &&
          managedArtworkPath != liveTrack.artworkPath) {
        await _deleteQuietly(managedArtworkPath);
      }
      rethrow;
    }

    final updated = liveTrack.copyWith(
      title: normalizedTitle,
      artist: normalizedArtist,
      album: normalizedAlbum,
      artworkPath: nextArtworkPath,
      clearArtworkPath: nextArtworkPath == null,
    );
    state = state.copyWith(
      tracks: state.tracks
          .map((item) => item.id == id ? updated : item)
          .toList(growable: false),
    );
    return updated;
  }

  Future<List<TrackMetadataRevision>> metadataHistory(Track track) {
    final id = track.id;
    if (id == null) return Future.value(const []);
    return _database.getTrackMetadataHistory(id);
  }

  Future<Track?> undoLatestMetadataChange(Track track) async {
    final id = track.id;
    if (id == null) return null;
    final updated = await _database.undoLatestTrackMetadataRevision(id);
    if (updated == null) return null;
    state = state.copyWith(
      tracks: state.tracks
          .map((item) => item.id == id ? updated : item)
          .toList(growable: false),
    );
    return updated;
  }

  Future<String> _copyArtworkToManagedDirectory(
    int trackId,
    String sourcePath,
  ) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw const LibraryOperationException('cover_file_missing');
    }
    const supported = {'.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp'};
    final extension = path_util.extension(source.path).toLowerCase();
    if (!supported.contains(extension)) {
      throw const LibraryOperationException('cover_file_type_unsupported');
    }
    final size = await source.length();
    if (size <= 0 || size > 30 * 1024 * 1024) {
      throw const LibraryOperationException('cover_file_too_large');
    }
    final databaseDirectory = Directory(
      path_util.dirname(_database.databasePath),
    );
    final artworkDirectory = Directory(
      path_util.join(databaseDirectory.path, 'track_artwork'),
    );
    await artworkDirectory.create(recursive: true);
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final destination = path_util.join(
      artworkDirectory.path,
      'track-$trackId-$stamp$extension',
    );
    final temporary = '$destination.part';
    final temporaryFile = File(temporary);
    try {
      await source.copy(temporary);
      return (await temporaryFile.rename(destination)).path;
    } finally {
      try {
        if (await temporaryFile.exists()) await temporaryFile.delete();
      } on FileSystemException {
        // Cleanup must not hide the original copy/rename failure. A stale
        // partial is never referenced by SQLite and is safe to prune later.
      }
    }
  }

  Future<void> _deleteQuietly(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // An orphaned cover is harmless and can be cleaned by maintenance later.
    }
  }

  Future<Track> pairAudioWithVideoTrack(Track track, String audioPath) async {
    if (track.id == null || !track.isVideoOnly) return track;
    final inspected = await _importer.inspect(audioPath);
    if (inspected.isVideoOnly) {
      throw const LibraryOperationException('audio_file_required');
    }
    final duplicate = state.tracks.any(
      (item) =>
          item.id != track.id &&
          (item.path == inspected.path ||
              item.contentHash == inspected.contentHash),
    );
    if (duplicate) {
      throw const LibraryOperationException('audio_already_in_library');
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
