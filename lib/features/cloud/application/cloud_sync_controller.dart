import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path_util;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/cloud/cloud_config.dart';
import '../../../core/utils/serialized_task_queue.dart';
import '../../library/application/library_controller.dart';
import '../../library/data/library_database.dart';
import '../../library/domain/track.dart';
import '../../library/domain/track_identification.dart';
import '../domain/cloud_file_cache.dart';
import '../domain/cloud_recycle_policy.dart';
import '../domain/cloud_storage_delete_outbox.dart';

const _freeProjectFileLimit = 50 * 1024 * 1024;
const _cloudRequestTimeout = Duration(seconds: 5);
const _storageDeleteOutboxPrefix = 'cloud.storage_delete_outbox.v1';

class CloudSyncState {
  const CloudSyncState({
    this.syncing = false,
    this.progress = 0,
    this.status = '',
    this.statusArgs = const {},
    this.summary = '',
    this.summaryArgs = const {},
    this.error = '',
    this.errorArgs = const {},
    this.cloudTracks = const [],
    this.recycledTracks = const [],
    this.loadingCloudTracks = false,
    this.offline = false,
    this.removingCloudTrackId,
    this.restoringCloudTrackId,
    this.emptyingRecycleBin = false,
  });

  final bool syncing;
  final double progress;
  final String status;
  final Map<String, String> statusArgs;
  final String summary;
  final Map<String, String> summaryArgs;
  final String error;
  final Map<String, String> errorArgs;
  final List<CloudTrackSummary> cloudTracks;
  final List<CloudTrackSummary> recycledTracks;
  final bool loadingCloudTracks;
  final bool offline;
  final String? removingCloudTrackId;
  final String? restoringCloudTrackId;
  final bool emptyingRecycleBin;

  CloudSyncState copyWith({
    bool? syncing,
    double? progress,
    String? status,
    Map<String, String>? statusArgs,
    String? summary,
    Map<String, String>? summaryArgs,
    String? error,
    Map<String, String>? errorArgs,
    List<CloudTrackSummary>? cloudTracks,
    List<CloudTrackSummary>? recycledTracks,
    bool? loadingCloudTracks,
    bool? offline,
    String? removingCloudTrackId,
    bool clearRemovingCloudTrackId = false,
    String? restoringCloudTrackId,
    bool clearRestoringCloudTrackId = false,
    bool? emptyingRecycleBin,
  }) {
    return CloudSyncState(
      syncing: syncing ?? this.syncing,
      progress: progress ?? this.progress,
      status: status ?? this.status,
      statusArgs: statusArgs ?? (status != null ? const {} : this.statusArgs),
      summary: summary ?? this.summary,
      summaryArgs:
          summaryArgs ?? (summary != null ? const {} : this.summaryArgs),
      error: error ?? this.error,
      errorArgs: errorArgs ?? (error != null ? const {} : this.errorArgs),
      cloudTracks: cloudTracks ?? this.cloudTracks,
      recycledTracks: recycledTracks ?? this.recycledTracks,
      loadingCloudTracks: loadingCloudTracks ?? this.loadingCloudTracks,
      offline: offline ?? this.offline,
      removingCloudTrackId: clearRemovingCloudTrackId
          ? null
          : removingCloudTrackId ?? this.removingCloudTrackId,
      restoringCloudTrackId: clearRestoringCloudTrackId
          ? null
          : restoringCloudTrackId ?? this.restoringCloudTrackId,
      emptyingRecycleBin: emptyingRecycleBin ?? this.emptyingRecycleBin,
    );
  }
}

class CloudTrackSummary {
  const CloudTrackSummary({
    required this.id,
    required this.contentHash,
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    required this.fileSize,
    required this.mediaType,
    this.updatedAt,
    this.mediaObjectPath,
    this.videoObjectPath,
    this.deletedAt,
  });

  final String id;
  final String contentHash;
  final String title;
  final String artist;
  final String album;
  final Duration duration;
  final int fileSize;
  final String mediaType;
  final DateTime? updatedAt;
  final String? mediaObjectPath;
  final String? videoObjectPath;
  final DateTime? deletedAt;

  bool get isDeleted => deletedAt != null;

  DateTime? get purgeAt => deletedAt?.add(cloudRecycleRetention);

  factory CloudTrackSummary.fromRow(Map<String, dynamic> row) {
    return CloudTrackSummary(
      id: row['id'] as String,
      contentHash: row['content_hash'] as String,
      title: row['title'] as String? ?? 'Unknown title',
      artist: row['artist'] as String? ?? 'Unknown artist',
      album: row['album'] as String? ?? '',
      duration: Duration(
        milliseconds: (row['duration_ms'] as num? ?? 0).toInt(),
      ),
      fileSize: (row['file_size'] as num? ?? 0).toInt(),
      mediaType: row['media_type'] as String? ?? 'audio',
      updatedAt: DateTime.tryParse(row['updated_at'] as String? ?? '')
          ?.toLocal(),
      mediaObjectPath: row['media_object_path'] as String?,
      videoObjectPath: row['video_object_path'] as String?,
      deletedAt: cloudDeletedAt(row)?.toLocal(),
    );
  }
}

bool cloudMutationAffectedTrack(
  Iterable<Map<String, dynamic>> rows,
  String trackId,
) => rows.any((row) => row['id'] == trackId);

final cloudSyncControllerProvider =
    StateNotifierProvider<CloudSyncController, CloudSyncState>((ref) {
      return CloudSyncController(
        ref.read(cloudClientProvider),
        ref.read(libraryDatabaseProvider),
      );
    });

class CloudSyncController extends StateNotifier<CloudSyncState> {
  CloudSyncController(this._client, this._database)
    : super(const CloudSyncState()) {
    _initialMaintenance = _cleanupInterruptedCloudDownloads();
  }

  final SupabaseClient? _client;
  final LibraryDatabase _database;
  final _destructiveTasks = SerializedTaskQueue();
  final _storageCleanupTasks = SerializedTaskQueue();
  final _cloudFiles = AtomicCloudFileCache();
  late final Future<void> _initialMaintenance;
  // Repeated taps must share one cache download/database insertion. Otherwise
  // two downloads of the same file can race and make a healthy cloud look
  // offline.
  final Map<String, Future<Track?>> _pendingPlaybackPreparations = {};

  Future<void> loadCloudTracks() async {
    final client = _client;
    final user = client?.auth.currentUser;
    if (client == null || user == null) {
      state = state.copyWith(
        cloudTracks: const [],
        recycledTracks: const [],
        offline: false,
        error: 'cloud_sign_in_required',
      );
      return;
    }
    state = state.copyWith(loadingCloudTracks: true, offline: false, error: '');
    try {
      await _initialMaintenance;
      await _drainStorageDeleteOutbox(client);
      final spaceId = await _spaceId(client, user.id);
      final rows = _rows(
        await _withCloudTimeout(
          client
              .from('cloud_tracks')
              .select()
              .eq('space_id', spaceId)
              .order('updated_at', ascending: false),
        ),
      );
      final activeRows = activeCloudTrackRows(rows);
      final recycleRows = recoverableCloudTrackRows(rows);
      state = state.copyWith(
        loadingCloudTracks: false,
        offline: false,
        cloudTracks: activeRows.map(CloudTrackSummary.fromRow).toList(),
        recycledTracks: recycleRows
            .map(CloudTrackSummary.fromRow)
            .toList(growable: false),
      );
      // Expired entries are hidden immediately, then cleaned in the
      // background. A failed cleanup leaves the recoverable row intact.
      unawaited(_destructiveTasks.run(() => _purgeExpiredCloudTracks(rows)));
    } catch (error) {
      state = state.copyWith(
        loadingCloudTracks: false,
        offline: _isOfflineFailure(error),
        error: _friendlyError(error),
      );
    }
  }

  /// Moves only the cloud copy to the recycle bin. Media objects and local
  /// files are kept, making this operation recoverable for 30 days.
  Future<bool> deleteCloudTrack(CloudTrackSummary track) =>
      _destructiveTasks.run(() => _deleteCloudTrack(track));

  Future<bool> _deleteCloudTrack(CloudTrackSummary track) async {
    final client = _client;
    final user = client?.auth.currentUser;
    if (client == null || user == null) {
      state = state.copyWith(error: 'cloud_sign_in_required');
      return false;
    }
    state = state.copyWith(
      removingCloudTrackId: track.id,
      offline: false,
      error: '',
    );
    try {
      await _initialMaintenance;
      final spaceId = await _spaceId(client, user.id);
      final deletedAt = DateTime.now().toUtc();
      // A track id alone is not sufficient for a shared space operation.
      final updatedRows = _rows(
        await _withCloudTimeout(
          client
              .from('cloud_tracks')
              .update({
                'deleted_at': deletedAt.toIso8601String(),
                'updated_at': deletedAt.toIso8601String(),
              })
              .eq('id', track.id)
              .eq('space_id', spaceId)
              .select('id'),
        ),
      );
      if (!cloudMutationAffectedTrack(updatedRows, track.id)) {
        throw StateError('cloud_track_soft_delete_not_applied');
      }
      final excluded = await _excludedCloudHashes();
      excluded.add(track.contentHash);
      await _saveExcludedCloudHashes(excluded);
      final recycled = CloudTrackSummary(
        id: track.id,
        contentHash: track.contentHash,
        title: track.title,
        artist: track.artist,
        album: track.album,
        duration: track.duration,
        fileSize: track.fileSize,
        mediaType: track.mediaType,
        updatedAt: deletedAt.toLocal(),
        mediaObjectPath: track.mediaObjectPath,
        videoObjectPath: track.videoObjectPath,
        deletedAt: deletedAt.toLocal(),
      );
      state = state.copyWith(
        cloudTracks: state.cloudTracks
            .where((item) => item.id != track.id)
            .toList(growable: false),
        recycledTracks: [
          recycled,
          ...state.recycledTracks.where((item) => item.id != track.id),
        ],
        summary: 'cloud_track_recycled',
        summaryArgs: {'title': track.title},
        clearRemovingCloudTrackId: true,
      );
      return true;
    } catch (error) {
      state = state.copyWith(
        error: _friendlyError(error),
        offline: _isOfflineFailure(error),
        clearRemovingCloudTrackId: true,
      );
      return false;
    }
  }

  Future<bool> restoreCloudTrack(CloudTrackSummary track) =>
      _destructiveTasks.run(() => _restoreCloudTrack(track));

  Future<bool> _restoreCloudTrack(CloudTrackSummary track) async {
    final client = _client;
    final user = client?.auth.currentUser;
    if (client == null || user == null) {
      state = state.copyWith(error: 'cloud_sign_in_required');
      return false;
    }
    state = state.copyWith(
      restoringCloudTrackId: track.id,
      offline: false,
      error: '',
    );
    try {
      final spaceId = await _spaceId(client, user.id);
      final updatedAt = DateTime.now().toUtc();
      final updatedRows = _rows(
        await _withCloudTimeout(
          client
              .from('cloud_tracks')
              .update({
                'deleted_at': null,
                'updated_at': updatedAt.toIso8601String(),
              })
              .eq('id', track.id)
              .eq('space_id', spaceId)
              .select('id'),
        ),
      );
      if (!cloudMutationAffectedTrack(updatedRows, track.id)) {
        throw StateError('cloud_track_restore_not_applied');
      }
      final excluded = await _excludedCloudHashes();
      excluded.remove(track.contentHash);
      await _saveExcludedCloudHashes(excluded);
      await _discardStorageDeletes(
        userId: user.id,
        objects: [track.mediaObjectPath, track.videoObjectPath],
      );
      final restored = CloudTrackSummary(
        id: track.id,
        contentHash: track.contentHash,
        title: track.title,
        artist: track.artist,
        album: track.album,
        duration: track.duration,
        fileSize: track.fileSize,
        mediaType: track.mediaType,
        updatedAt: updatedAt.toLocal(),
        mediaObjectPath: track.mediaObjectPath,
        videoObjectPath: track.videoObjectPath,
      );
      state = state.copyWith(
        cloudTracks: [
          restored,
          ...state.cloudTracks.where((item) => item.id != track.id),
        ],
        recycledTracks: state.recycledTracks
            .where((item) => item.id != track.id)
            .toList(growable: false),
        summary: 'cloud_track_restored',
        summaryArgs: {'title': track.title},
        clearRestoringCloudTrackId: true,
      );
      return true;
    } catch (error) {
      state = state.copyWith(
        error: _friendlyError(error),
        offline: _isOfflineFailure(error),
        clearRestoringCloudTrackId: true,
      );
      return false;
    }
  }

  Future<bool> permanentlyDeleteCloudTrack(CloudTrackSummary track) async {
    return _destructiveTasks.run(
      () => _permanentlyDeleteCloudTrack(track, updateBusyState: true),
    );
  }

  Future<bool> _permanentlyDeleteCloudTrack(
    CloudTrackSummary track, {
    required bool updateBusyState,
  }) async {
    final client = _client;
    final user = client?.auth.currentUser;
    if (client == null || user == null) return false;
    if (updateBusyState) {
      state = state.copyWith(removingCloudTrackId: track.id, error: '');
    }
    try {
      await _initialMaintenance;
      final objects = [
        track.mediaObjectPath,
        track.videoObjectPath,
      ].whereType<String>().where((value) => value.isNotEmpty).toList();
      // Persist the cleanup intent before the RPC. If the request times out
      // after committing server-side, a later launch still knows which orphan
      // objects to remove. Storage RLS rejects deletion while any live row
      // still references the path, making retries safe and idempotent.
      await _enqueueStorageDeletes(userId: user.id, objects: objects);
      final deleted = await _withCloudTimeout(
        client.rpc(
          'permanently_delete_cloud_track',
          params: {'target_track': track.id},
        ),
      );
      if (deleted != true) {
        throw StateError('The cloud track was not permanently deleted.');
      }
      await _drainStorageDeleteOutbox(client);
      state = state.copyWith(
        recycledTracks: state.recycledTracks
            .where((item) => item.id != track.id)
            .toList(growable: false),
        clearRemovingCloudTrackId: updateBusyState,
      );
      return true;
    } catch (error) {
      state = state.copyWith(
        error: _friendlyError(error),
        offline: _isOfflineFailure(error),
        clearRemovingCloudTrackId: updateBusyState,
      );
      return false;
    }
  }

  Future<int> emptyCloudRecycleBin() =>
      _destructiveTasks.run(_emptyCloudRecycleBin);

  Future<int> _emptyCloudRecycleBin() async {
    if (state.emptyingRecycleBin) return 0;
    state = state.copyWith(emptyingRecycleBin: true, error: '');
    var removed = 0;
    for (final track in List<CloudTrackSummary>.of(state.recycledTracks)) {
      if (await _permanentlyDeleteCloudTrack(track, updateBusyState: false)) {
        removed += 1;
      } else if (state.offline) {
        break;
      }
    }
    state = state.copyWith(emptyingRecycleBin: false);
    return removed;
  }

  Future<void> _purgeExpiredCloudTracks(List<Map<String, dynamic>> rows) async {
    final expired = expiredCloudTrackRows(rows)
        .map(CloudTrackSummary.fromRow)
        .toList(growable: false);
    for (final track in expired) {
      final removed = await _permanentlyDeleteCloudTrack(
        track,
        updateBusyState: false,
      );
      if (!removed && state.offline) return;
    }
  }

  /// Resolves a cloud item into a local playable track. Existing local media
  /// starts immediately; a cloud-only item is downloaded once into Sona's
  /// managed cache before playback. This keeps the player itself offline-first
  /// and avoids streaming a fragile remote URL directly into the audio engine.
  Future<Track?> prepareCloudTrackForPlayback(CloudTrackSummary track) {
    final pending = _pendingPlaybackPreparations[track.contentHash];
    if (pending != null) return pending;
    late final Future<Track?> request;
    request = _prepareCloudTrackForPlayback(track);
    _pendingPlaybackPreparations[track.contentHash] = request;
    return request.whenComplete(() {
      if (identical(_pendingPlaybackPreparations[track.contentHash], request)) {
        _pendingPlaybackPreparations.remove(track.contentHash);
      }
    });
  }

  /// A cloud queue may contain only ready cloud cache entries, never unrelated
  /// local-library tracks or files which have not finished downloading.
  Future<List<Track>> cachedCloudTracksForPlayback(
    Iterable<CloudTrackSummary> cloudTracks,
  ) async {
    final localByHash = <String, Track>{
      for (final track in await _database.getTracks())
        if (File(track.path).existsSync()) track.contentHash: track,
    };
    final seen = <String>{};
    return [
      for (final cloud in cloudTracks)
        if (seen.add(cloud.contentHash) &&
            localByHash[cloud.contentHash] != null)
          localByHash[cloud.contentHash]!,
    ];
  }

  Future<Track?> _prepareCloudTrackForPlayback(CloudTrackSummary track) async {
    final localTracks = await _database.getTracks();
    for (final local in localTracks) {
      if (local.contentHash == track.contentHash &&
          File(local.path).existsSync()) {
        return local;
      }
    }

    final client = _client;
    final user = client?.auth.currentUser;
    if (client == null || user == null) return null;
    try {
      await _initialMaintenance;
      await _drainStorageDeleteOutbox(client);
      final spaceId = await _spaceId(client, user.id);
      final remoteRows = _rows(
        await _withCloudTimeout(
          client
              .from('cloud_tracks')
              .select()
              .eq('id', track.id)
              .eq('space_id', spaceId),
        ),
      );
      final activeRows = activeCloudTrackRows(remoteRows);
      if (activeRows.isEmpty) return null;
      final remote = activeRows.first;
      final stateRows = _rows(
        await _withCloudTimeout(
          client
              .from('user_track_state')
              .select()
              .eq('user_id', user.id)
              .eq('track_id', track.id),
        ),
      );
      await _downloadTrack(
        client,
        remote,
        stateRows.isEmpty ? null : stateRows.first,
      );
      final refreshedTracks = await _database.getTracks();
      for (final local in refreshedTracks) {
        if (local.contentHash == track.contentHash &&
            File(local.path).existsSync()) {
          return local;
        }
      }
      return null;
    } catch (error) {
      state = state.copyWith(
        error: _friendlyError(error),
        offline: _isOfflineFailure(error),
      );
      return null;
    }
  }

  Future<bool> previewSync(LibraryState library) async {
    final client = _client;
    final user = client?.auth.currentUser;
    if (client == null || user == null) {
      state = state.copyWith(error: 'cloud_sign_in_required');
      return false;
    }
    state = const CloudSyncState(syncing: true, status: 'cloud_sync_planning');
    try {
      await _initialMaintenance;
      await _drainStorageDeleteOutbox(client);
      final membership = await _withCloudTimeout(
        client
            .from('space_members')
            .select('space_id')
            .eq('user_id', user.id)
            .limit(1)
            .single(),
      );
      final spaceId = membership['space_id'] as String;
      final remoteTracks = _rows(
        await _withCloudTimeout(
          client
              .from('cloud_tracks')
              .select('content_hash,media_object_path,deleted_at')
              .eq('space_id', spaceId),
        ),
      );
      final activeRemoteTracks = activeCloudTrackRows(remoteTracks);
      final remoteHashes = activeRemoteTracks
          .map((row) => row['content_hash'] as String)
          .toSet();
      final deletedHashes = recycledCloudTrackRows(remoteTracks)
          .map((row) => row['content_hash'] as String)
          .toSet();
      final localHashes = library.tracks
          .map((track) => track.contentHash)
          .toSet();
      final upload = library.tracks
          .where(
            (track) =>
                !remoteHashes.contains(track.contentHash) &&
                !deletedHashes.contains(track.contentHash),
          )
          .length;
      final download = activeRemoteTracks
          .where((row) => !localHashes.contains(row['content_hash'] as String))
          .length;
      final tooLarge = library.tracks
          .where((track) => track.fileSize > _freeProjectFileLimit)
          .length;
      final remotePlaylists = _rows(
        await _withCloudTimeout(
          client.from('cloud_playlists').select('id').eq('space_id', spaceId),
        ),
      );
      final localCloudIds = library.playlists
          .map((playlist) => playlist.cloudId)
          .whereType<String>()
          .toSet();
      final playlistDownload = remotePlaylists
          .where(
            (playlist) => !localCloudIds.contains(playlist['id'] as String),
          )
          .length;
      state = CloudSyncState(
        summary: tooLarge == 0
            ? 'cloud_sync_preview'
            : 'cloud_sync_preview_with_skipped',
        summaryArgs: {
          'upload': '$upload',
          'download': '$download',
          'playlistDownload': '$playlistDownload',
          'unchanged': '${library.tracks.length - upload}',
          'tooLarge': '$tooLarge',
        },
      );
      return true;
    } catch (error) {
      state = CloudSyncState(
        error: _friendlyError(error),
        offline: _isOfflineFailure(error),
      );
      return false;
    }
  }

  Future<bool> sync(LibraryState library) async {
    final client = _client;
    final user = client?.auth.currentUser;
    if (client == null || user == null) {
      state = state.copyWith(error: 'cloud_sign_in_required');
      return false;
    }

    state = const CloudSyncState(
      syncing: true,
      status: 'cloud_sync_connecting',
    );
    var uploaded = 0;
    var downloaded = 0;
    var skippedLarge = 0;
    var eventSyncAvailable = true;

    try {
      await _initialMaintenance;
      await _drainStorageDeleteOutbox(client);
      final membership = await _withCloudTimeout(
        client
            .from('space_members')
            .select('space_id')
            .eq('user_id', user.id)
            .limit(1)
            .single(),
      );
      final spaceId = membership['space_id'] as String;

      final remoteTrackRows = _rows(
        await _withCloudTimeout(
          client.from('cloud_tracks').select().eq('space_id', spaceId),
        ),
      );
      final activeRemoteTrackRows = activeCloudTrackRows(remoteTrackRows);
      final deletedRemoteHashes = recycledCloudTrackRows(remoteTrackRows)
          .map((row) => row['content_hash'] as String)
          .toSet();
      final remoteByHash = <String, Map<String, dynamic>>{
        for (final row in activeRemoteTrackRows)
          row['content_hash'] as String: row,
      };
      final remoteStates = _rows(
        await _withCloudTimeout(
          client.from('user_track_state').select().eq('user_id', user.id),
        ),
      );
      final stateByTrackId = <String, Map<String, dynamic>>{
        for (final row in remoteStates) row['track_id'] as String: row,
      };

      final cloudIdByHash = <String, String>{};
      final excludedCloudHashes = await _excludedCloudHashes();
      for (var index = 0; index < library.tracks.length; index++) {
        final track = library.tracks[index];
        if (excludedCloudHashes.contains(track.contentHash) ||
            deletedRemoteHashes.contains(track.contentHash)) {
          continue;
        }
        state = state.copyWith(
          progress: library.tracks.isEmpty
              ? .2
              : .05 + .5 * index / library.tracks.length,
          status: 'cloud_syncing_track',
          statusArgs: {'title': track.title},
          error: '',
        );
        final previous = remoteByHash[track.contentHash];
        var mediaObjectPath = previous?['media_object_path'] as String?;
        var videoObjectPath = previous?['video_object_path'] as String?;

        if (mediaObjectPath == null) {
          final result = await _uploadFile(
            client,
            spaceId: spaceId,
            contentHash: track.contentHash,
            localPath: track.path,
            folder: 'tracks',
          );
          mediaObjectPath = result.path;
          skippedLarge += result.tooLarge ? 1 : 0;
          if (result.path != null) uploaded++;
        }
        if (track.hasVideo && videoObjectPath == null) {
          final result = await _uploadFile(
            client,
            spaceId: spaceId,
            contentHash: track.contentHash,
            localPath: track.videoPath!,
            folder: 'videos',
          );
          videoObjectPath = result.path;
          skippedLarge += result.tooLarge ? 1 : 0;
          if (result.path != null) uploaded++;
        }

        final cloudTrack = await client
            .from('cloud_tracks')
            .upsert({
              'space_id': spaceId,
              'created_by': user.id,
              'content_hash': track.contentHash,
              'title': track.title,
              'artist': track.artist,
              'album': track.album,
              'duration_ms': track.duration.inMilliseconds,
              'file_size': track.fileSize,
              'media_type': track.mediaType,
              'media_object_path': mediaObjectPath,
              'video_object_path': videoObjectPath,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            }, onConflict: 'space_id,content_hash')
            .select()
            .single();
        final cloudTrackId = cloudTrack['id'] as String;
        cloudIdByHash[track.contentHash] = cloudTrackId;

        final remoteState = stateByTrackId[cloudTrackId];
        final remoteFavorite = remoteState?['is_favorite'] as bool? ?? false;
        final remotePlayCount = remoteState?['play_count'] as int? ?? 0;
        final remoteLastPlayed = _date(remoteState?['last_played_at']);
        final lastPlayed = _latest(track.lastPlayedAt, remoteLastPlayed);
        await client.from('user_track_state').upsert({
          'user_id': user.id,
          'track_id': cloudTrackId,
          'is_favorite': track.isFavorite || remoteFavorite,
          'play_count': track.playCount > remotePlayCount
              ? track.playCount
              : remotePlayCount,
          'last_played_at': lastPlayed?.toUtc().toIso8601String(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }, onConflict: 'user_id,track_id');
      }

      state = state.copyWith(progress: .58, status: 'cloud_syncing_rankings');
      final pendingEvents = await _database.getPendingPlayEvents();
      if (pendingEvents.isNotEmpty) {
        try {
          final payload = <Map<String, Object?>>[];
          final syncedIds = <String>[];
          for (final event in pendingEvents) {
            final eventId = event['event_id'] as String;
            final cloudTrackId = cloudIdByHash[event['content_hash'] as String];
            if (cloudTrackId == null) continue;
            payload.add({
              'user_id': user.id,
              'track_id': cloudTrackId,
              'client_event_id': eventId,
              'listened_seconds': ((event['listened_ms'] as int? ?? 0) / 1000)
                  .round()
                  .clamp(1, 1 << 31),
              'occurred_at': event['played_at'],
            });
            syncedIds.add(eventId);
          }
          if (payload.isNotEmpty) {
            await client
                .from('play_events')
                .upsert(payload, onConflict: 'user_id,client_event_id');
            await _database.markPlayEventsSynced(syncedIds);
          }
        } on PostgrestException {
          eventSyncAvailable = false;
        }
      }

      state = state.copyWith(progress: .66, status: 'cloud_syncing_playlists');
      await _uploadPlaylists(
        client,
        userId: user.id,
        spaceId: spaceId,
        library: library,
        cloudIdByHash: cloudIdByHash,
      );
      await _syncSettings(client, userId: user.id);

      state = state.copyWith(
        progress: .74,
        status: 'cloud_sync_downloading_tracks',
      );
      final latestCloudTracks = _rows(
        await client.from('cloud_tracks').select().eq('space_id', spaceId),
      );
      final activeLatestCloudTracks = activeCloudTrackRows(latestCloudTracks);
      final latestStates = _rows(
        await client.from('user_track_state').select().eq('user_id', user.id),
      );
      final latestStateById = <String, Map<String, dynamic>>{
        for (final row in latestStates) row['track_id'] as String: row,
      };
      final localHashes = library.tracks
          .map((track) => track.contentHash)
          .toSet();
      for (final remote in activeLatestCloudTracks) {
        final hash = remote['content_hash'] as String;
        final remoteState = latestStateById[remote['id'] as String];
        if (!localHashes.contains(hash)) {
          final inserted = await _downloadTrack(client, remote, remoteState);
          if (inserted) {
            downloaded++;
            localHashes.add(hash);
          }
        }
        await _database.mergeCloudTrackState(
          contentHash: hash,
          isFavorite: remoteState?['is_favorite'] as bool? ?? false,
          playCount: remoteState?['play_count'] as int? ?? 0,
          lastPlayedAt: _date(remoteState?['last_played_at']),
        );
      }

      if (eventSyncAvailable) {
        final hashByCloudId = <String, String>{
          for (final row in latestCloudTracks)
            if (!isCloudTrackDeleted(row))
              row['id'] as String: row['content_hash'] as String,
        };
        final cloudEvents = _rows(
          await client
              .from('play_events')
              .select('track_id,client_event_id,listened_seconds,occurred_at')
              .eq('user_id', user.id)
              .not('client_event_id', 'is', null),
        );
        for (final event in cloudEvents) {
          final hash = hashByCloudId[event['track_id'] as String];
          final eventId = event['client_event_id'] as String?;
          if (hash == null || eventId == null) continue;
          await _database.mergeCloudPlayEvent(
            contentHash: hash,
            eventId: eventId,
            playedAt: DateTime.parse(event['occurred_at'] as String),
            listenedMs: (event['listened_seconds'] as int? ?? 0) * 1000,
            durationMs: 0,
          );
        }
      }

      state = state.copyWith(
        progress: .92,
        status: 'cloud_sync_restoring_playlists',
      );
      await _downloadPlaylists(
        client,
        spaceId: spaceId,
        cloudTracks: activeLatestCloudTracks,
      );

      state = state.copyWith(progress: 1, status: 'cloud_sync_complete');
      final changed = uploaded > 0 || downloaded > 0;
      state = state.copyWith(
        syncing: false,
        cloudTracks: activeLatestCloudTracks
            .map(CloudTrackSummary.fromRow)
            .toList(growable: false),
        recycledTracks: recycledCloudTrackRows(latestCloudTracks)
            .map(CloudTrackSummary.fromRow)
            .toList(growable: false),
        summary: switch ((changed, skippedLarge > 0)) {
          (true, true) => 'cloud_sync_complete_changes_with_skipped',
          (true, false) => 'cloud_sync_complete_changes',
          (false, true) => 'cloud_sync_complete_unchanged_with_skipped',
          (false, false) => 'cloud_sync_complete_unchanged',
        },
        summaryArgs: {
          'uploaded': '$uploaded',
          'downloaded': '$downloaded',
          'skippedLarge': '$skippedLarge',
        },
        error: '',
      );
      return true;
    } catch (error) {
      state = state.copyWith(
        syncing: false,
        status: 'cloud_sync_interrupted',
        offline: _isOfflineFailure(error),
        error: _friendlyError(error),
      );
      return false;
    }
  }

  Future<_UploadResult> _uploadFile(
    SupabaseClient client, {
    required String spaceId,
    required String contentHash,
    required String localPath,
    required String folder,
  }) async {
    final file = File(localPath);
    if (!file.existsSync()) return const _UploadResult();
    if (await file.length() > _freeProjectFileLimit) {
      return const _UploadResult(tooLarge: true);
    }
    final extension = path_util.extension(localPath).toLowerCase();
    final objectPath = '$spaceId/$folder/$contentHash$extension';
    await client.storage
        .from('sona-media')
        .upload(objectPath, file, fileOptions: const FileOptions(upsert: true));
    return _UploadResult(path: objectPath);
  }

  Future<bool> _downloadTrack(
    SupabaseClient client,
    Map<String, dynamic> remote,
    Map<String, dynamic>? remoteState,
  ) async {
    final objectPath = remote['media_object_path'] as String?;
    if (objectPath == null) return false;
    final support = await getApplicationSupportDirectory();
    final folder = Directory(
      path_util.join(
        support.path,
        'SonaCloud',
        remote['content_hash'] as String,
      ),
    );
    await folder.create(recursive: true);
    final localPath = path_util.join(
      folder.path,
      path_util.basename(objectPath),
    );
    await _cloudFiles.ensure(
      destination: File(localPath),
      openStream: () =>
          client.storage.from('sona-media').downloadStream(objectPath),
      expectedLength: (remote['file_size'] as num?)?.toInt(),
      expectedSha256: remote['content_hash'] as String?,
    );

    String? videoPath;
    final videoObject = remote['video_object_path'] as String?;
    if (videoObject != null) {
      videoPath = path_util.join(folder.path, path_util.basename(videoObject));
      await _cloudFiles.ensure(
        destination: File(videoPath),
        openStream: () =>
            client.storage.from('sona-media').downloadStream(videoObject),
      );
    }

    final inserted = await _database.insertTrack(
      Track(
        path: localPath,
        title: remote['title'] as String,
        artist: remote['artist'] as String? ?? TrackNameParser.unknownArtist,
        album: remote['album'] as String? ?? TrackNameParser.unknownAlbum,
        duration: Duration(
          milliseconds: (remote['duration_ms'] as num? ?? 0).toInt(),
        ),
        fileSize: (remote['file_size'] as num? ?? 0).toInt(),
        contentHash: remote['content_hash'] as String,
        importedAt: DateTime.now(),
        isFavorite: remoteState?['is_favorite'] as bool? ?? false,
        playCount: remoteState?['play_count'] as int? ?? 0,
        lastPlayedAt: _date(remoteState?['last_played_at']),
        videoPath: videoPath,
        mediaType: remote['media_type'] as String? ?? 'audio',
      ),
    );
    return inserted != null;
  }

  Future<void> _uploadPlaylists(
    SupabaseClient client, {
    required String userId,
    required String spaceId,
    required LibraryState library,
    required Map<String, String> cloudIdByHash,
  }) async {
    final existing = _rows(
      await client
          .from('cloud_playlists')
          .select()
          .eq('space_id', spaceId)
          .eq('owner_id', userId),
    );
    final existingById = <String, Map<String, dynamic>>{
      for (final row in existing) row['id'] as String: row,
    };
    for (var index = 0; index < library.playlists.length; index++) {
      final playlist = library.playlists[index];
      final String playlistId;
      final previous = playlist.cloudId == null
          ? null
          : existingById[playlist.cloudId!];
      if (previous == null) {
        final row = await client
            .from('cloud_playlists')
            .insert({
              'space_id': spaceId,
              'owner_id': userId,
              'name': playlist.name,
              'description': playlist.description,
              'sort_order': index,
            })
            .select('id')
            .single();
        playlistId = row['id'] as String;
        await _database.bindPlaylistToCloud(playlist.id, playlistId);
      } else {
        playlistId = previous['id'] as String;
        await client
            .from('cloud_playlists')
            .update({
              'description': playlist.description,
              'sort_order': index,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('id', playlistId);
      }
      final coverPath = await _uploadPlaylistCover(
        client,
        spaceId: spaceId,
        playlistId: playlistId,
        localPath: playlist.coverPath,
        previousPath: previous?['cover_path'] as String?,
      );
      if (coverPath != previous?['cover_path']) {
        await client
            .from('cloud_playlists')
            .update({'cover_path': coverPath})
            .eq('id', playlistId);
      }
      final tracks = await _database.getTracksForPlaylist(playlist.id);
      final trackIds = <String>[];
      for (final track in tracks) {
        final cloudTrackId = cloudIdByHash[track.contentHash];
        if (cloudTrackId == null) {
          // Publishing a shortened list would make the atomic RPC faithfully
          // replace the cloud playlist with incomplete data. Fail the sync
          // instead, leaving the previous cloud playlist untouched.
          throw StateError('cloud_playlist_track_not_uploaded');
        }
        trackIds.add(cloudTrackId);
      }
      final replaced = await _withCloudTimeout(
        client.rpc(
          'replace_cloud_playlist_tracks',
          params: {
            'target_playlist': playlistId,
            'target_space': spaceId,
            'requested_track_ids': trackIds,
          },
        ),
      );
      if (replaced is! num || replaced.toInt() != trackIds.length) {
        throw StateError(
          'Cloud playlist replacement returned an unexpected row count.',
        );
      }
    }
  }

  Future<void> _downloadPlaylists(
    SupabaseClient client, {
    required String spaceId,
    required List<Map<String, dynamic>> cloudTracks,
  }) async {
    final localPlaylists = await _database.getPlaylists();
    final localByCloudId = <String, dynamic>{
      for (final item in localPlaylists)
        if (item.cloudId != null) item.cloudId!: item,
    };
    final localTracks = await _database.getTracks();
    final localByHash = <String, Track>{
      for (final track in localTracks) track.contentHash: track,
    };
    final hashByCloudId = <String, String>{
      for (final track in cloudTracks)
        track['id'] as String: track['content_hash'] as String,
    };
    final remotePlaylists = _rows(
      await client
          .from('cloud_playlists')
          .select()
          .eq('space_id', spaceId)
          .order('sort_order'),
    );
    for (final remote in remotePlaylists) {
      final remoteId = remote['id'] as String;
      final existing = localByCloudId[remoteId];
      final coverPath = await _downloadPlaylistCover(client, remote);
      final int localPlaylistId;
      if (existing == null) {
        localPlaylistId = await _database.createPlaylist(
          remote['name'] as String,
          description: remote['description'] as String? ?? '',
          coverPath: coverPath,
          cloudId: remoteId,
        );
      } else {
        localPlaylistId = existing.id as int;
        await _database.updatePlaylist(
          localPlaylistId,
          name: remote['name'] as String,
          description: remote['description'] as String? ?? '',
          coverPath: coverPath ?? existing.coverPath as String?,
        );
      }
      final remoteItems = _rows(
        await client
            .from('cloud_playlist_tracks')
            .select('track_id,sort_order')
            .eq('playlist_id', remote['id'] as String)
            .order('sort_order'),
      );
      final localTrackIds = <int>[];
      for (final item in remoteItems) {
        final hash = hashByCloudId[item['track_id'] as String];
        final localTrack = hash == null ? null : localByHash[hash];
        if (localTrack?.id != null) localTrackIds.add(localTrack!.id!);
      }
      await _database.replacePlaylistTracks(localPlaylistId, localTrackIds);
    }
  }

  Future<String?> _uploadPlaylistCover(
    SupabaseClient client, {
    required String spaceId,
    required String playlistId,
    required String? localPath,
    required String? previousPath,
  }) async {
    if (localPath == null || !File(localPath).existsSync()) return previousPath;
    final extension = path_util.extension(localPath).toLowerCase();
    final objectPath = '$spaceId/playlist-covers/$playlistId$extension';
    await client.storage
        .from('sona-media')
        .upload(
          objectPath,
          File(localPath),
          fileOptions: const FileOptions(upsert: true),
        );
    return objectPath;
  }

  Future<String?> _downloadPlaylistCover(
    SupabaseClient client,
    Map<String, dynamic> remote,
  ) async {
    final objectPath = remote['cover_path'] as String?;
    if (objectPath == null || objectPath.isEmpty) return null;
    final support = await getApplicationSupportDirectory();
    final folder = Directory(
      path_util.join(support.path, 'SonaCloud', 'covers'),
    );
    await folder.create(recursive: true);
    final localPath = path_util.join(
      folder.path,
      path_util.basename(objectPath),
    );
    await _cloudFiles.ensure(
      destination: File(localPath),
      openStream: () =>
          client.storage.from('sona-media').downloadStream(objectPath),
    );
    return localPath;
  }

  Future<void> _cleanupInterruptedCloudDownloads() async {
    try {
      final support = await getApplicationSupportDirectory();
      await AtomicCloudFileCache.cleanupPartFiles(
        Directory(path_util.join(support.path, 'SonaCloud')),
      );
    } catch (_) {
      // A locked partial is never a final cache hit and is retried next time.
    }
  }

  Future<void> _enqueueStorageDeletes({
    required String userId,
    required Iterable<String> objects,
  }) {
    final normalized = objects
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    if (normalized.isEmpty) return Future<void>.value();
    return _storageCleanupTasks.run(() async {
      final key = _storageDeleteOutboxKey(userId);
      final current = CloudStorageDeleteOutbox.decode(
        await _database.getSetting(key),
      );
      await _database.setSetting(key, current.addAll(normalized).encode());
    });
  }

  Future<void> _discardStorageDeletes({
    required String userId,
    required Iterable<String?> objects,
  }) {
    final normalized = objects
        .whereType<String>()
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    if (normalized.isEmpty) return Future<void>.value();
    return _storageCleanupTasks.run(() async {
      final key = _storageDeleteOutboxKey(userId);
      final current = CloudStorageDeleteOutbox.decode(
        await _database.getSetting(key),
      );
      if (current.isEmpty) return;
      await _database.setSetting(key, current.removeAll(normalized).encode());
    });
  }

  Future<void> _drainStorageDeleteOutbox(SupabaseClient client) {
    return _storageCleanupTasks.run(() async {
      final userId = client.auth.currentUser?.id;
      if (userId == null) return;
      final key = _storageDeleteOutboxKey(userId);
      final current = CloudStorageDeleteOutbox.decode(
        await _database.getSetting(key),
      );
      if (current.isEmpty) return;
      final batch = current.objects.toList(growable: false)..sort();
      try {
        await _withCloudTimeout(
          client.storage.from('sona-media').remove(batch),
        );
      } catch (_) {
        // Keep every path. A partially successful batch remains safe because
        // Storage removal is idempotent and orphan-only RLS protects live rows.
        return;
      }
      await _database.setSetting(key, current.removeAll(batch).encode());
    });
  }

  String _storageDeleteOutboxKey(String userId) =>
      '$_storageDeleteOutboxPrefix.$userId';

  Future<void> _syncSettings(
    SupabaseClient client, {
    required String userId,
  }) async {
    final rows = _rows(
      await client
          .from('user_settings')
          .select('settings')
          .eq('user_id', userId)
          .limit(1),
    );
    final remote = rows.isEmpty
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(
            rows.first['settings'] as Map? ?? const <String, dynamic>{},
          );
    final localPreset = await _database.getSetting('appearance.preset');
    if (remote.isEmpty) {
      await client.from('user_settings').upsert({
        'user_id': userId,
        'settings': {'appearance.preset': ?localPreset},
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'user_id');
      return;
    }
    final cloudPreset = remote['appearance.preset'];
    if (cloudPreset is String && cloudPreset.isNotEmpty) {
      await _database.setSetting('appearance.preset', cloudPreset);
    }
  }

  Future<String> _spaceId(SupabaseClient client, String userId) async {
    final membership = await _withCloudTimeout(
      client
          .from('space_members')
          .select('space_id')
          .eq('user_id', userId)
          .limit(1)
          .single(),
    );
    return membership['space_id'] as String;
  }

  Future<T> _withCloudTimeout<T>(Future<T> request) {
    return request.timeout(
      _cloudRequestTimeout,
      onTimeout: () => throw TimeoutException('Cloud request timed out.'),
    );
  }

  bool _isOfflineFailure(Object error) {
    if (error is TimeoutException || error is SocketException) return true;
    final value = '$error'.toLowerCase();
    return value.contains('socketexception') ||
        value.contains('failed host lookup') ||
        value.contains('network is unreachable') ||
        value.contains('connection refused') ||
        value.contains('connection reset') ||
        value.contains('timed out');
  }

  Future<Set<String>> _excludedCloudHashes() async {
    final raw = await _database.getSetting('cloud.excluded_hashes');
    if (raw == null || raw.isEmpty) return <String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <String>{};
      return decoded.whereType<String>().toSet();
    } catch (_) {
      return <String>{};
    }
  }

  Future<void> _saveExcludedCloudHashes(Set<String> hashes) {
    return _database.setSetting(
      'cloud.excluded_hashes',
      jsonEncode(hashes.toList()..sort()),
    );
  }

  List<Map<String, dynamic>> _rows(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  DateTime? _date(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value)?.toLocal();
  }

  DateTime? _latest(DateTime? first, DateTime? second) {
    if (first == null) return second;
    if (second == null) return first;
    return first.isAfter(second) ? first : second;
  }

  String _friendlyError(Object error) {
    final value = '$error';
    if (_isOfflineFailure(error)) {
      return 'cloud_error_offline';
    }
    if (value.contains('Invalid login credentials')) {
      return 'cloud_error_invalid_credentials';
    }
    if (value.contains('row-level security')) {
      return 'cloud_error_permission';
    }
    if (value.contains('SocketException')) {
      return 'cloud_error_connection';
    }
    if (value.contains('schema cache') || value.contains('PGRST204')) {
      return 'cloud_error_schema';
    }
    if (value.contains('StorageException')) {
      return 'cloud_error_media';
    }
    return 'cloud_error_generic';
  }
}

class _UploadResult {
  const _UploadResult({this.path, this.tooLarge = false});

  final String? path;
  final bool tooLarge;
}
