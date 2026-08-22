import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path_util;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/cloud/cloud_config.dart';
import '../../library/application/library_controller.dart';
import '../../library/data/library_database.dart';
import '../../library/domain/track.dart';

const _freeProjectFileLimit = 50 * 1024 * 1024;
const _cloudRequestTimeout = Duration(seconds: 5);

class CloudSyncState {
  const CloudSyncState({
    this.syncing = false,
    this.progress = 0,
    this.status = '',
    this.summary = '',
    this.error = '',
    this.cloudTracks = const [],
    this.loadingCloudTracks = false,
    this.offline = false,
    this.removingCloudTrackId,
  });

  final bool syncing;
  final double progress;
  final String status;
  final String summary;
  final String error;
  final List<CloudTrackSummary> cloudTracks;
  final bool loadingCloudTracks;
  final bool offline;
  final String? removingCloudTrackId;

  CloudSyncState copyWith({
    bool? syncing,
    double? progress,
    String? status,
    String? summary,
    String? error,
    List<CloudTrackSummary>? cloudTracks,
    bool? loadingCloudTracks,
    bool? offline,
    String? removingCloudTrackId,
    bool clearRemovingCloudTrackId = false,
  }) {
    return CloudSyncState(
      syncing: syncing ?? this.syncing,
      progress: progress ?? this.progress,
      status: status ?? this.status,
      summary: summary ?? this.summary,
      error: error ?? this.error,
      cloudTracks: cloudTracks ?? this.cloudTracks,
      loadingCloudTracks: loadingCloudTracks ?? this.loadingCloudTracks,
      offline: offline ?? this.offline,
      removingCloudTrackId: clearRemovingCloudTrackId
          ? null
          : removingCloudTrackId ?? this.removingCloudTrackId,
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
    );
  }
}

final cloudSyncControllerProvider =
    StateNotifierProvider<CloudSyncController, CloudSyncState>((ref) {
      return CloudSyncController(
        ref.read(cloudClientProvider),
        ref.read(libraryDatabaseProvider),
      );
    });

class CloudSyncController extends StateNotifier<CloudSyncState> {
  CloudSyncController(this._client, this._database)
    : super(const CloudSyncState());

  final SupabaseClient? _client;
  final LibraryDatabase _database;
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
        offline: false,
        error: 'Please sign in to manage cloud music.',
      );
      return;
    }
    state = state.copyWith(loadingCloudTracks: true, offline: false, error: '');
    try {
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
      state = state.copyWith(
        loadingCloudTracks: false,
        offline: false,
        cloudTracks: rows.map(CloudTrackSummary.fromRow).toList(),
      );
    } catch (error) {
      state = state.copyWith(
        loadingCloudTracks: false,
        offline: _isOfflineFailure(error),
        error: _friendlyError(error),
      );
    }
  }

  /// Removes only the cloud copy. The local file is deliberately kept and its
  /// hash is remembered so a later sync does not silently upload it again.
  Future<bool> deleteCloudTrack(CloudTrackSummary track) async {
    final client = _client;
    final user = client?.auth.currentUser;
    if (client == null || user == null) {
      state = state.copyWith(error: 'Please sign in to manage cloud music.');
      return false;
    }
    state = state.copyWith(
      removingCloudTrackId: track.id,
      offline: false,
      error: '',
    );
    try {
      final spaceId = await _spaceId(client, user.id);
      // A track id alone is not sufficient for a shared space operation.
      await _withCloudTimeout(
        client
            .from('cloud_tracks')
            .delete()
            .eq('id', track.id)
            .eq('space_id', spaceId),
      );
      final objects = [
        track.mediaObjectPath,
        track.videoObjectPath,
      ].whereType<String>().where((value) => value.isNotEmpty).toList();
      if (objects.isNotEmpty) {
        try {
          await _withCloudTimeout(
            client.storage.from('sona-media').remove(objects),
          );
        } catch (_) {
          // Database deletion is authoritative; a failed storage cleanup is
          // harmless and can be cleaned up by the storage lifecycle policy.
        }
      }
      final excluded = await _excludedCloudHashes();
      excluded.add(track.contentHash);
      await _saveExcludedCloudHashes(excluded);
      state = state.copyWith(
        cloudTracks: state.cloudTracks
            .where((item) => item.id != track.id)
            .toList(growable: false),
        summary:
            'Removed “${track.title}” from cloud. The local file is unchanged.',
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
      if (remoteRows.isEmpty) return null;
      final remote = remoteRows.first;
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
      state = state.copyWith(error: '请先登录 Sona 云账号。');
      return false;
    }
    state = const CloudSyncState(syncing: true, status: '正在生成同步计划…');
    try {
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
              .select('content_hash,media_object_path')
              .eq('space_id', spaceId),
        ),
      );
      final remoteHashes = remoteTracks
          .map((row) => row['content_hash'] as String)
          .toSet();
      final localHashes = library.tracks
          .map((track) => track.contentHash)
          .toSet();
      final upload = library.tracks
          .where((track) => !remoteHashes.contains(track.contentHash))
          .length;
      final download = remoteTracks
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
        summary:
            '同步预览：将上传 $upload 首歌曲，下载 $download 首歌曲；'
            '将恢复 $playlistDownload 个歌单；'
            '${library.tracks.length - upload} 首歌曲无变化。'
            '${tooLarge == 0 ? '' : ' $tooLarge 个超过 50 MB 的文件会跳过上传。'}',
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
      state = state.copyWith(error: '请先登录 Sona 云账号。');
      return false;
    }

    state = const CloudSyncState(syncing: true, status: '正在连接音乐空间…');
    var uploaded = 0;
    var downloaded = 0;
    var skippedLarge = 0;
    var eventSyncAvailable = true;

    try {
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
      final remoteByHash = <String, Map<String, dynamic>>{
        for (final row in remoteTrackRows) row['content_hash'] as String: row,
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
        if (excludedCloudHashes.contains(track.contentHash)) continue;
        state = state.copyWith(
          progress: library.tracks.isEmpty
              ? .2
              : .05 + .5 * index / library.tracks.length,
          status: '正在同步 ${track.title}',
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

      state = state.copyWith(progress: .58, status: '正在同步播放排行…');
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

      state = state.copyWith(progress: .66, status: '正在同步歌单…');
      await _uploadPlaylists(
        client,
        userId: user.id,
        spaceId: spaceId,
        library: library,
        cloudIdByHash: cloudIdByHash,
      );
      await _syncSettings(client, userId: user.id);

      state = state.copyWith(progress: .74, status: '正在下载其他设备的歌曲…');
      final latestCloudTracks = _rows(
        await client.from('cloud_tracks').select().eq('space_id', spaceId),
      );
      final latestStates = _rows(
        await client.from('user_track_state').select().eq('user_id', user.id),
      );
      final latestStateById = <String, Map<String, dynamic>>{
        for (final row in latestStates) row['track_id'] as String: row,
      };
      final localHashes = library.tracks
          .map((track) => track.contentHash)
          .toSet();
      for (final remote in latestCloudTracks) {
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

      state = state.copyWith(progress: .92, status: '正在恢复云端歌单…');
      await _downloadPlaylists(
        client,
        spaceId: spaceId,
        cloudTracks: latestCloudTracks,
      );

      state = state.copyWith(progress: 1, status: '同步完成');
      final notes = <String>[
        if (uploaded > 0 || downloaded > 0)
          '同步完成：已上传 $uploaded 个文件，已恢复 $downloaded 首歌曲。'
        else
          '已检查云端数据，这台设备已经是最新状态。',
        '播放排行已同步。',
        if (skippedLarge > 0) '$skippedLarge 个较大的文件暂未上传，它们仍安全保留在本机。',
      ];
      state = state.copyWith(
        syncing: false,
        summary: notes.join('；'),
        error: '',
      );
      return true;
    } catch (error) {
      state = state.copyWith(
        syncing: false,
        status: '同步中断',
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
    final file = File(localPath);
    if (!file.existsSync()) {
      await file.writeAsBytes(
        await client.storage.from('sona-media').download(objectPath),
        flush: true,
      );
    }

    String? videoPath;
    final videoObject = remote['video_object_path'] as String?;
    if (videoObject != null) {
      videoPath = path_util.join(folder.path, path_util.basename(videoObject));
      final videoFile = File(videoPath);
      if (!videoFile.existsSync()) {
        await videoFile.writeAsBytes(
          await client.storage.from('sona-media').download(videoObject),
          flush: true,
        );
      }
    }

    final inserted = await _database.insertTrack(
      Track(
        path: localPath,
        title: remote['title'] as String,
        artist: remote['artist'] as String? ?? '未知歌手',
        album: remote['album'] as String? ?? '未知专辑',
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
      await client
          .from('cloud_playlist_tracks')
          .delete()
          .eq('playlist_id', playlistId);
      final items = <Map<String, Object?>>[];
      for (var position = 0; position < tracks.length; position++) {
        final cloudTrackId = cloudIdByHash[tracks[position].contentHash];
        if (cloudTrackId == null) continue;
        items.add({
          'playlist_id': playlistId,
          'track_id': cloudTrackId,
          'sort_order': position,
        });
      }
      if (items.isNotEmpty) {
        await client.from('cloud_playlist_tracks').insert(items);
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
    final file = File(localPath);
    if (!file.existsSync()) {
      await file.writeAsBytes(
        await client.storage.from('sona-media').download(objectPath),
        flush: true,
      );
    }
    return localPath;
  }

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
      return '网络不可用：当前处于离线状态，无法连接至云端。本地曲库和播放仍可正常使用。';
    }
    if (value.contains('Invalid login credentials')) return '账号名或密码不正确。';
    if (value.contains('row-level security')) {
      return '云端权限暂时没有配置完整，本地数据不受影响。';
    }
    if (value.contains('SocketException')) {
      return '网络连接失败，本地数据没有受影响。';
    }
    if (value.contains('schema cache') || value.contains('PGRST204')) {
      return '云端资料结构正在更新，本地数据不受影响，请稍后重试。';
    }
    if (value.contains('StorageException')) {
      return '云端媒体暂时无法更新，本地文件不受影响，请稍后重试。';
    }
    return '云同步暂时没有完成，本地数据不受影响，请稍后重试。';
  }
}

class _UploadResult {
  const _UploadResult({this.path, this.tooLarge = false});

  final String? path;
  final bool tooLarge;
}
