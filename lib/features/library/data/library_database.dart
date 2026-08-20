import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path_util;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as mobile;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../domain/playlist_info.dart';
import '../domain/track.dart';

final libraryDatabaseProvider = Provider<LibraryDatabase>((ref) {
  throw UnimplementedError('LibraryDatabase must be overridden at startup.');
});

class LibraryDatabase {
  late final Database _database;
  String? _databasePath;
  static const _maxRepairScanEntriesPerRoot = 25000;

  String get databasePath => _databasePath ?? '';

  Future<void> initialize({String? databasePath}) async {
    if (databasePath == null) {
      final supportDirectory = await getApplicationSupportDirectory();
      final dataDirectory = Directory(
        path_util.join(supportDirectory.path, 'SonarVault'),
      );
      await dataDirectory.create(recursive: true);
      _databasePath = path_util.join(dataDirectory.path, 'sonar_vault.db');
    } else {
      _databasePath = databasePath;
      await File(databasePath).parent.create(recursive: true);
    }

    final DatabaseFactory factory;
    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      factory = databaseFactoryFfi;
    } else {
      factory = mobile.databaseFactory;
    }

    _database = await factory.openDatabase(
      _databasePath!,
      options: OpenDatabaseOptions(
        version: 7,
        onConfigure: (database) async {
          await database.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: _createSchema,
        onUpgrade: _upgradeSchema,
      ),
    );
  }

  Future<void> _createSchema(Database database, int version) async {
    await database.execute('''
      CREATE TABLE tracks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        path TEXT NOT NULL UNIQUE,
        title TEXT NOT NULL,
        artist TEXT NOT NULL,
        album TEXT NOT NULL,
        duration_ms INTEGER NOT NULL DEFAULT 0,
        file_size INTEGER NOT NULL DEFAULT 0,
        content_hash TEXT NOT NULL UNIQUE,
        imported_at TEXT NOT NULL,
        is_favorite INTEGER NOT NULL DEFAULT 0,
        play_count INTEGER NOT NULL DEFAULT 0,
        last_played_at TEXT,
        video_path TEXT,
        media_type TEXT NOT NULL DEFAULT 'audio'
      )
    ''');
    await database.execute(
      'CREATE INDEX idx_tracks_title ON tracks(title COLLATE NOCASE)',
    );
    await database.execute(
      'CREATE INDEX idx_tracks_artist ON tracks(artist COLLATE NOCASE)',
    );
    await database.execute('''
      CREATE TABLE playlists (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        created_at TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        cover_path TEXT,
        cloud_id TEXT UNIQUE,
        updated_at TEXT NOT NULL
      )
    ''');
    await database.execute('''
      CREATE TABLE playlist_items (
        playlist_id INTEGER NOT NULL,
        track_id INTEGER NOT NULL,
        sort_order INTEGER NOT NULL,
        added_at TEXT NOT NULL,
        PRIMARY KEY (playlist_id, track_id),
        FOREIGN KEY (playlist_id) REFERENCES playlists(id) ON DELETE CASCADE,
        FOREIGN KEY (track_id) REFERENCES tracks(id) ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
    await _createPlayEvents(database);
  }

  Future<void> _upgradeSchema(
    Database database,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await database.execute('ALTER TABLE tracks ADD COLUMN video_path TEXT');
      await database.execute('''
        CREATE TABLE IF NOT EXISTS settings (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        )
      ''');
    }
    if (oldVersion < 3) {
      await database.execute(
        "ALTER TABLE tracks ADD COLUMN media_type TEXT NOT NULL DEFAULT 'audio'",
      );
      await database.execute(
        "ALTER TABLE playlists ADD COLUMN description TEXT NOT NULL DEFAULT ''",
      );
      await database.execute(
        'ALTER TABLE playlists ADD COLUMN cover_path TEXT',
      );
    }
    if (oldVersion < 4) await _createPlayEvents(database);
    if (oldVersion >= 4 && oldVersion < 5) {
      await database.execute(
        'ALTER TABLE play_events ADD COLUMN event_id TEXT',
      );
      await database.execute(
        'ALTER TABLE play_events ADD COLUMN listened_ms INTEGER NOT NULL DEFAULT 0',
      );
      await database.execute(
        'ALTER TABLE play_events ADD COLUMN duration_ms INTEGER NOT NULL DEFAULT 0',
      );
      await database.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_play_events_event_id '
        'ON play_events(event_id)',
      );
    }
    if (oldVersion >= 4 && oldVersion < 6) {
      await database.execute(
        'ALTER TABLE play_events ADD COLUMN synced_at TEXT',
      );
    }
    if (oldVersion < 7) {
      await database.execute('ALTER TABLE playlists ADD COLUMN cloud_id TEXT');
      await database.execute(
        'ALTER TABLE playlists ADD COLUMN updated_at TEXT',
      );
      await database.execute(
        'UPDATE playlists SET updated_at = created_at WHERE updated_at IS NULL',
      );
      await database.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_playlists_cloud_id '
        'ON playlists(cloud_id) WHERE cloud_id IS NOT NULL',
      );
    }
  }

  Future<void> _createPlayEvents(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS play_events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        track_id INTEGER NOT NULL,
        played_at TEXT NOT NULL,
        event_id TEXT UNIQUE,
        listened_ms INTEGER NOT NULL DEFAULT 0,
        duration_ms INTEGER NOT NULL DEFAULT 0,
        synced_at TEXT,
        FOREIGN KEY (track_id) REFERENCES tracks(id) ON DELETE CASCADE
      )
    ''');
    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_play_events_time '
      'ON play_events(played_at)',
    );
    await database.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_play_events_event_id '
      'ON play_events(event_id)',
    );
  }

  Future<List<Track>> getTracks() async {
    final rows = await _database.query(
      'tracks',
      orderBy: 'title COLLATE NOCASE ASC',
    );
    return rows.map(Track.fromDatabaseMap).toList(growable: false);
  }

  /// Repairs records whose media was moved below an existing parent folder.
  ///
  /// A path is never rebound on filename alone: the candidate must also match
  /// the content hash captured when the track was imported.
  Future<List<Track>> repairMovedTrackPaths(List<Track> tracks) async {
    final missing = tracks
        .where((track) => track.id != null && !File(track.path).existsSync())
        .toList(growable: false);
    if (missing.isEmpty) return tracks;

    final wantedNames = missing
        .map((track) => _fileNameKey(track.path))
        .toSet();
    final roots = <String, Directory>{};
    for (final track in missing) {
      final root = _nearestExistingDirectory(track.path);
      // A missing removable drive can otherwise make us recursively scan an
      // entire volume (for example C:\\) during app startup.
      if (root != null && !_isFilesystemRoot(root)) {
        roots[root.path] = root;
      }
    }

    final candidatesByName = <String, List<File>>{};
    for (final root in roots.values) {
      try {
        var visited = 0;
        await for (final entity in root.list(
          recursive: true,
          followLinks: false,
        )) {
          if (++visited > _maxRepairScanEntriesPerRoot) break;
          if (entity is! File) continue;
          final key = _fileNameKey(entity.path);
          if (!wantedNames.contains(key)) continue;
          (candidatesByName[key] ??= []).add(entity);
        }
      } on FileSystemException {
        // An unavailable folder must not prevent the rest of the library from
        // loading. The unmatched entry remains visible as unavailable.
      }
    }

    final repaired = <int, Track>{};
    for (final track in missing) {
      final candidates = candidatesByName[_fileNameKey(track.path)] ?? const [];
      for (final candidate in candidates) {
        try {
          final digest = await sha256.bind(candidate.openRead()).first;
          if (digest.toString() != track.contentHash) continue;
          final updated = track.copyWith(path: candidate.path);
          await _database.update(
            'tracks',
            {'path': candidate.path},
            where: 'id = ?',
            whereArgs: [track.id],
          );
          repaired[track.id!] = updated;
          break;
        } on FileSystemException {
          // The file may have been moved again while the repair was running.
        }
      }
    }
    if (repaired.isEmpty) return tracks;
    return tracks
        .map((track) => track.id == null ? track : repaired[track.id] ?? track)
        .toList(growable: false);
  }

  Directory? _nearestExistingDirectory(String filePath) {
    var directory = Directory(path_util.dirname(filePath));
    while (true) {
      if (directory.existsSync()) return directory;
      final parent = directory.parent;
      if (parent.path == directory.path) return null;
      directory = parent;
    }
  }

  String _fileNameKey(String filePath) =>
      path_util.basename(filePath).toLowerCase();

  bool _isFilesystemRoot(Directory directory) {
    final normalized = path_util.normalize(directory.absolute.path);
    final parent = path_util.normalize(directory.parent.absolute.path);
    return normalized == parent;
  }

  Future<Track?> insertTrack(Track track) async {
    final id = await _database.insert(
      'tracks',
      track.toDatabaseMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    if (id == 0) return null;
    return track.copyWith(id: id);
  }

  Future<void> setFavorite(int trackId, {required bool value}) async {
    await _database.update(
      'tracks',
      {'is_favorite': value ? 1 : 0},
      where: 'id = ?',
      whereArgs: [trackId],
    );
  }

  Future<void> setFavorites(
    Iterable<int> trackIds, {
    required bool value,
  }) async {
    final ids = _uniquePositiveIds(trackIds);
    if (ids.isEmpty) return;
    await _database.transaction((transaction) async {
      for (final chunk in _idChunks(ids)) {
        final placeholders = List.filled(chunk.length, '?').join(',');
        await transaction.rawUpdate(
          'UPDATE tracks SET is_favorite = ? WHERE id IN ($placeholders)',
          [value ? 1 : 0, ...chunk],
        );
      }
    });
  }

  Future<void> recordPlay(
    int trackId, {
    Duration listenedDuration = Duration.zero,
    Duration mediaDuration = Duration.zero,
  }) async {
    final now = DateTime.now().toIso8601String();
    final eventId = '$trackId-${DateTime.now().microsecondsSinceEpoch}';
    await _database.transaction((transaction) async {
      await transaction.rawUpdate(
        '''
        UPDATE tracks
        SET play_count = play_count + 1
        WHERE id = ?
        ''',
        [trackId],
      );
      await transaction.insert('play_events', {
        'track_id': trackId,
        'played_at': now,
        'event_id': eventId,
        'listened_ms': listenedDuration.inMilliseconds,
        'duration_ms': mediaDuration.inMilliseconds,
      });
    });
  }

  Future<void> markRecentlyPlayed(int trackId) {
    return _database.update(
      'tracks',
      {'last_played_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [trackId],
    );
  }

  Future<void> clearLastPlayed(int trackId) {
    return _database.update(
      'tracks',
      {'last_played_at': null},
      where: 'id = ?',
      whereArgs: [trackId],
    );
  }

  Future<void> clearPlayHistory(int trackId) async {
    await _database.transaction((transaction) async {
      await transaction.delete(
        'play_events',
        where: 'track_id = ?',
        whereArgs: [trackId],
      );
      await transaction.update(
        'tracks',
        {'play_count': 0},
        where: 'id = ?',
        whereArgs: [trackId],
      );
    });
  }

  Future<Map<int, int>> getPlayCountsSince(DateTime since) async {
    final rows = await _database.rawQuery(
      '''
      SELECT track_id, COUNT(*) AS count
      FROM play_events
      WHERE played_at >= ?
      GROUP BY track_id
      ''',
      [since.toIso8601String()],
    );
    return {
      for (final row in rows) row['track_id']! as int: row['count']! as int,
    };
  }

  Future<List<Map<String, Object?>>> getPendingPlayEvents() {
    return _database.rawQuery('''
      SELECT e.event_id, e.played_at, e.listened_ms, e.duration_ms,
             t.content_hash
      FROM play_events e
      INNER JOIN tracks t ON t.id = e.track_id
      WHERE e.synced_at IS NULL AND e.event_id IS NOT NULL
      ORDER BY e.played_at ASC
    ''');
  }

  Future<void> markPlayEventsSynced(Iterable<String> eventIds) async {
    final ids = eventIds.toList(growable: false);
    if (ids.isEmpty) return;
    final placeholders = List.filled(ids.length, '?').join(',');
    await _database.rawUpdate(
      'UPDATE play_events SET synced_at = ? WHERE event_id IN ($placeholders)',
      [DateTime.now().toIso8601String(), ...ids],
    );
  }

  Future<void> mergeCloudPlayEvent({
    required String contentHash,
    required String eventId,
    required DateTime playedAt,
    required int listenedMs,
    required int durationMs,
  }) async {
    final tracks = await _database.query(
      'tracks',
      columns: ['id'],
      where: 'content_hash = ?',
      whereArgs: [contentHash],
      limit: 1,
    );
    if (tracks.isEmpty) return;
    await _database.insert('play_events', {
      'track_id': tracks.first['id'],
      'played_at': playedAt.toIso8601String(),
      'event_id': eventId,
      'listened_ms': listenedMs,
      'duration_ms': durationMs,
      'synced_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> mergeCloudTrackState({
    required String contentHash,
    required bool isFavorite,
    required int playCount,
    DateTime? lastPlayedAt,
  }) async {
    await _database.rawUpdate(
      '''
      UPDATE tracks
      SET is_favorite = CASE WHEN is_favorite = 1 OR ? = 1 THEN 1 ELSE 0 END,
          play_count = MAX(play_count, ?),
          last_played_at = CASE
            WHEN last_played_at IS NULL THEN ?
            WHEN ? IS NULL THEN last_played_at
            WHEN last_played_at < ? THEN ?
            ELSE last_played_at
          END
      WHERE content_hash = ?
      ''',
      [
        isFavorite ? 1 : 0,
        playCount,
        lastPlayedAt?.toIso8601String(),
        lastPlayedAt?.toIso8601String(),
        lastPlayedAt?.toIso8601String(),
        lastPlayedAt?.toIso8601String(),
        contentHash,
      ],
    );
  }

  Future<void> removeTrack(int trackId) async {
    await _database.delete('tracks', where: 'id = ?', whereArgs: [trackId]);
  }

  Future<int> removeTracks(Iterable<int> trackIds) async {
    final ids = _uniquePositiveIds(trackIds);
    if (ids.isEmpty) return 0;
    return _database.transaction((transaction) async {
      var removed = 0;
      for (final chunk in _idChunks(ids)) {
        final placeholders = List.filled(chunk.length, '?').join(',');
        removed += await transaction.delete(
          'tracks',
          where: 'id IN ($placeholders)',
          whereArgs: chunk,
        );
      }
      return removed;
    });
  }

  Future<void> setTrackVideoPath(int trackId, String? videoPath) async {
    await _database.update(
      'tracks',
      {'video_path': videoPath},
      where: 'id = ?',
      whereArgs: [trackId],
    );
  }

  Future<void> replaceTrackMedia(Track track) async {
    if (track.id == null) return;
    await _database.update(
      'tracks',
      track.toDatabaseMap(),
      where: 'id = ?',
      whereArgs: [track.id],
    );
  }

  Future<void> updateTrackMetadata(
    int trackId, {
    required String title,
    required String artist,
    required String album,
  }) async {
    await _database.update(
      'tracks',
      {'title': title.trim(), 'artist': artist.trim(), 'album': album.trim()},
      where: 'id = ?',
      whereArgs: [trackId],
    );
  }

  Future<void> setTrackDuration(int trackId, Duration duration) async {
    await _database.update(
      'tracks',
      {'duration_ms': duration.inMilliseconds},
      where: 'id = ?',
      whereArgs: [trackId],
    );
  }

  Future<String?> getSetting(String key) async {
    final rows = await _database.query(
      'settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> setSetting(String key, String value) async {
    await _database.insert('settings', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<PlaylistInfo>> getPlaylists() async {
    final rows = await _database.rawQuery('''
      SELECT p.id, p.name, p.created_at, p.description, p.cover_path,
             p.cloud_id, p.updated_at,
             COUNT(pi.track_id) AS track_count
      FROM playlists p
      LEFT JOIN playlist_items pi ON pi.playlist_id = p.id
      GROUP BY p.id
      ORDER BY p.created_at DESC
    ''');
    return rows.map(PlaylistInfo.fromDatabaseMap).toList(growable: false);
  }

  Future<int> createPlaylist(
    String name, {
    String description = '',
    String? coverPath,
    String? cloudId,
  }) {
    return _database.insert('playlists', {
      'name': name.trim(),
      'description': description.trim(),
      'cover_path': coverPath,
      'cloud_id': cloudId,
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> updatePlaylist(
    int playlistId, {
    required String name,
    required String description,
    String? coverPath,
  }) async {
    await _database.update(
      'playlists',
      {
        'name': name.trim(),
        'description': description.trim(),
        'cover_path': coverPath,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [playlistId],
    );
  }

  Future<void> bindPlaylistToCloud(int playlistId, String cloudId) {
    return _database.update(
      'playlists',
      {'cloud_id': cloudId, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [playlistId],
    );
  }

  Future<void> deletePlaylist(int playlistId) async {
    await _database.delete(
      'playlists',
      where: 'id = ?',
      whereArgs: [playlistId],
    );
  }

  Future<bool> addTrackToPlaylist(int playlistId, int trackId) async {
    return (await addTracksToPlaylist(playlistId, [trackId])) > 0;
  }

  Future<int> addTracksToPlaylist(
    int playlistId,
    Iterable<int> trackIds,
  ) async {
    final ids = _uniquePositiveIds(trackIds);
    if (ids.isEmpty) return 0;
    return _database.transaction((transaction) async {
      final orderRows = await transaction.rawQuery(
        'SELECT COALESCE(MAX(sort_order), -1) + 1 AS next_order '
        'FROM playlist_items WHERE playlist_id = ?',
        [playlistId],
      );
      var nextOrder = orderRows.first['next_order']! as int;
      var added = 0;
      final now = DateTime.now().toIso8601String();
      for (final trackId in ids) {
        final inserted = await transaction.insert('playlist_items', {
          'playlist_id': playlistId,
          'track_id': trackId,
          'sort_order': nextOrder,
          'added_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        if (inserted != 0) {
          added++;
          nextOrder++;
        }
      }
      if (added > 0) {
        await transaction.update(
          'playlists',
          {'updated_at': now},
          where: 'id = ?',
          whereArgs: [playlistId],
        );
      }
      return added;
    });
  }

  Future<void> removeTrackFromPlaylist(int playlistId, int trackId) async {
    await removeTracksFromPlaylist(playlistId, [trackId]);
  }

  Future<int> removeTracksFromPlaylist(
    int playlistId,
    Iterable<int> trackIds,
  ) async {
    final ids = _uniquePositiveIds(trackIds);
    if (ids.isEmpty) return 0;
    return _database.transaction((transaction) async {
      var removed = 0;
      for (final chunk in _idChunks(ids)) {
        final placeholders = List.filled(chunk.length, '?').join(',');
        removed += await transaction.delete(
          'playlist_items',
          where: 'playlist_id = ? AND track_id IN ($placeholders)',
          whereArgs: [playlistId, ...chunk],
        );
      }
      if (removed > 0) {
        await transaction.update(
          'playlists',
          {'updated_at': DateTime.now().toIso8601String()},
          where: 'id = ?',
          whereArgs: [playlistId],
        );
      }
      return removed;
    });
  }

  Future<void> replacePlaylistTracks(int playlistId, Iterable<int> trackIds) {
    return _database.transaction((transaction) async {
      await transaction.delete(
        'playlist_items',
        where: 'playlist_id = ?',
        whereArgs: [playlistId],
      );
      var order = 0;
      for (final trackId in _uniquePositiveIds(trackIds)) {
        await transaction.insert('playlist_items', {
          'playlist_id': playlistId,
          'track_id': trackId,
          'sort_order': order++,
          'added_at': DateTime.now().toIso8601String(),
        });
      }
      await transaction.update(
        'playlists',
        {'updated_at': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [playlistId],
      );
    });
  }

  List<int> _uniquePositiveIds(Iterable<int> ids) {
    final unique = <int>{};
    for (final id in ids) {
      if (id > 0) unique.add(id);
    }
    return unique.toList(growable: false);
  }

  Iterable<List<int>> _idChunks(List<int> ids, {int size = 400}) sync* {
    for (var start = 0; start < ids.length; start += size) {
      yield ids.sublist(
        start,
        start + size < ids.length ? start + size : ids.length,
      );
    }
  }

  Future<List<Track>> getTracksForPlaylist(int playlistId) async {
    final rows = await _database.rawQuery(
      '''
      SELECT t.*
      FROM tracks t
      INNER JOIN playlist_items pi ON pi.track_id = t.id
      WHERE pi.playlist_id = ?
      ORDER BY pi.sort_order ASC
      ''',
      [playlistId],
    );
    return rows.map(Track.fromDatabaseMap).toList(growable: false);
  }

  Future<void> close() => _database.close();
}
