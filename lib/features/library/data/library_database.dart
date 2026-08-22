import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path_util;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as mobile;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../domain/playlist_info.dart';
import '../domain/library_backup.dart';
import '../domain/track.dart';
import '../domain/track_metadata_revision.dart';

final libraryDatabaseProvider = Provider<LibraryDatabase>((ref) {
  throw UnimplementedError('LibraryDatabase must be overridden at startup.');
});

class LibraryDatabase {
  late final Database _database;
  String? _databasePath;
  final StreamController<void> _changeController =
      StreamController<void>.broadcast();
  static const _maxRepairScanEntriesPerRoot = 25000;

  String get databasePath => _databasePath ?? '';
  Stream<void> get changes => _changeController.stream;

  void _markChanged() {
    if (!_changeController.isClosed) _changeController.add(null);
  }

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
        version: 8,
        onConfigure: (database) async {
          await database.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: _createSchema,
        onUpgrade: _upgradeSchema,
      ),
    );
  }

  /// Produces a transactionally consistent standalone SQLite image while the
  /// live database remains open. `VACUUM INTO` also folds any WAL pages into
  /// the snapshot, so copying the resulting file never races a writer.
  Future<void> createConsistentSnapshot(String destinationPath) async {
    final destination = File(destinationPath);
    await destination.parent.create(recursive: true);
    if (await destination.exists()) await destination.delete();
    final escaped = destination.absolute.path.replaceAll("'", "''");
    await _database.execute("VACUUM INTO '$escaped'");
    if (!await destination.exists() || await destination.length() == 0) {
      throw StateError('SQLite did not create a backup snapshot.');
    }
  }

  Future<bool> validateIntegrity() async {
    final rows = await _database.rawQuery('PRAGMA integrity_check');
    if (rows.length != 1) return false;
    return rows.single.values.single.toString().toLowerCase() == 'ok';
  }

  /// Returns every external file referenced by the database. Duplicate paths
  /// are coalesced so a paired item or reused cover is stored only once.
  Future<List<ReferencedLibraryFile>> getReferencedLibraryFiles() async {
    final rolesByPath = <String, Set<String>>{};
    void add(Object? value, String role) {
      final filePath = value is String ? value.trim() : '';
      if (filePath.isEmpty || filePath.startsWith('assets/')) return;
      (rolesByPath[filePath] ??= <String>{}).add(role);
    }

    final tracks = await _database.query(
      'tracks',
      columns: ['path', 'video_path', 'artwork_path'],
    );
    for (final track in tracks) {
      add(track['path'], 'track_media');
      add(track['video_path'], 'track_video');
      add(track['artwork_path'], 'track_artwork');
    }
    final revisions = await _database.query(
      'track_metadata_revisions',
      columns: ['previous_artwork_path', 'new_artwork_path'],
    );
    for (final revision in revisions) {
      add(revision['previous_artwork_path'], 'metadata_revision_artwork');
      add(revision['new_artwork_path'], 'metadata_revision_artwork');
    }
    final playlists = await _database.query(
      'playlists',
      columns: ['cover_path'],
    );
    for (final playlist in playlists) {
      add(playlist['cover_path'], 'playlist_cover');
    }
    final appearanceRows = await _database.query(
      'settings',
      columns: ['key', 'value'],
      where: 'key IN (?, ?)',
      whereArgs: ['appearance.custom_path', 'appearance.custom_backgrounds'],
    );
    for (final row in appearanceRows) {
      final key = row['key'] as String;
      final value = row['value'] as String;
      if (key == 'appearance.custom_path') {
        add(value, 'custom_background');
        continue;
      }
      try {
        final decoded = jsonDecode(value);
        if (decoded is List) {
          for (final item in decoded.whereType<Map>()) {
            add(item['path'], 'custom_background');
          }
        }
      } on FormatException {
        // A damaged optional appearance list must not block library backup.
      }
    }
    final result = rolesByPath.entries
        .map(
          (entry) => ReferencedLibraryFile(path: entry.key, roles: entry.value),
        )
        .toList(growable: false);
    result.sort((a, b) => a.path.compareTo(b.path));
    return result;
  }

  /// Rebinds all file references after a self-contained backup was extracted
  /// into this device's managed data folder.
  Future<void> rewriteStoredFilePaths(Map<String, String> replacements) async {
    if (replacements.isEmpty) return;
    await _database.transaction((transaction) async {
      for (final entry in replacements.entries) {
        await transaction.rawUpdate(
          'UPDATE tracks SET path = ? WHERE path = ?',
          [entry.value, entry.key],
        );
        await transaction.rawUpdate(
          'UPDATE tracks SET video_path = ? WHERE video_path = ?',
          [entry.value, entry.key],
        );
        await transaction.rawUpdate(
          'UPDATE tracks SET artwork_path = ? WHERE artwork_path = ?',
          [entry.value, entry.key],
        );
        await transaction.rawUpdate(
          'UPDATE playlists SET cover_path = ? WHERE cover_path = ?',
          [entry.value, entry.key],
        );
        await transaction.rawUpdate(
          'UPDATE track_metadata_revisions SET previous_artwork_path = ? '
          'WHERE previous_artwork_path = ?',
          [entry.value, entry.key],
        );
        await transaction.rawUpdate(
          'UPDATE track_metadata_revisions SET new_artwork_path = ? '
          'WHERE new_artwork_path = ?',
          [entry.value, entry.key],
        );
      }

      final customPathRows = await transaction.query(
        'settings',
        columns: ['value'],
        where: 'key = ?',
        whereArgs: ['appearance.custom_path'],
        limit: 1,
      );
      if (customPathRows.isNotEmpty) {
        final oldPath = customPathRows.single['value'] as String;
        final newPath = replacements[oldPath];
        if (newPath != null) {
          await transaction.update(
            'settings',
            {'value': newPath},
            where: 'key = ?',
            whereArgs: ['appearance.custom_path'],
          );
        }
      }

      final backgroundRows = await transaction.query(
        'settings',
        columns: ['value'],
        where: 'key = ?',
        whereArgs: ['appearance.custom_backgrounds'],
        limit: 1,
      );
      if (backgroundRows.isNotEmpty) {
        final raw = backgroundRows.single['value'] as String;
        try {
          final decoded = jsonDecode(raw);
          if (decoded is List) {
            var changed = false;
            final rewritten = decoded
                .map((item) {
                  if (item is! Map) return item;
                  final copy = Map<String, Object?>.from(item);
                  final current = copy['path'];
                  final replacement = current is String
                      ? replacements[current]
                      : null;
                  if (replacement != null) {
                    copy['path'] = replacement;
                    changed = true;
                  }
                  return copy;
                })
                .toList(growable: false);
            if (changed) {
              await transaction.update(
                'settings',
                {'value': jsonEncode(rewritten)},
                where: 'key = ?',
                whereArgs: ['appearance.custom_backgrounds'],
              );
            }
          }
        } on FormatException {
          // Preserve an invalid optional legacy value verbatim.
        }
      }
    });
    _markChanged();
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
        media_type TEXT NOT NULL DEFAULT 'audio',
        artwork_path TEXT
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
    await _createTrackMetadataRevisions(database);
  }

  Future<void> _upgradeSchema(
    Database database,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await _ensureColumn(database, 'tracks', 'video_path', 'TEXT');
      await database.execute('''
        CREATE TABLE IF NOT EXISTS settings (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        )
      ''');
    }
    if (oldVersion < 3) {
      await _ensureColumn(
        database,
        'tracks',
        'media_type',
        "TEXT NOT NULL DEFAULT 'audio'",
      );
      await _ensureColumn(
        database,
        'playlists',
        'description',
        "TEXT NOT NULL DEFAULT ''",
      );
      await _ensureColumn(database, 'playlists', 'cover_path', 'TEXT');
    }
    if (oldVersion < 4) await _createPlayEvents(database);
    if (oldVersion >= 4 && oldVersion < 5) {
      await _ensureColumn(database, 'play_events', 'event_id', 'TEXT');
      await _ensureColumn(
        database,
        'play_events',
        'listened_ms',
        'INTEGER NOT NULL DEFAULT 0',
      );
      await _ensureColumn(
        database,
        'play_events',
        'duration_ms',
        'INTEGER NOT NULL DEFAULT 0',
      );
      await database.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_play_events_event_id '
        'ON play_events(event_id)',
      );
    }
    if (oldVersion >= 4 && oldVersion < 6) {
      await _ensureColumn(database, 'play_events', 'synced_at', 'TEXT');
    }
    if (oldVersion < 7) {
      await _ensureColumn(database, 'playlists', 'cloud_id', 'TEXT');
      await _ensureColumn(database, 'playlists', 'updated_at', 'TEXT');
      await database.execute(
        'UPDATE playlists SET updated_at = created_at WHERE updated_at IS NULL',
      );
      await database.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_playlists_cloud_id '
        'ON playlists(cloud_id) WHERE cloud_id IS NOT NULL',
      );
    }
    if (oldVersion < 8) {
      await _ensureColumn(database, 'tracks', 'artwork_path', 'TEXT');
      await _createTrackMetadataRevisions(database);
    }
  }

  Future<void> _ensureColumn(
    Database database,
    String table,
    String column,
    String definition,
  ) async {
    final columns = await database.rawQuery('PRAGMA table_info($table)');
    if (columns.any((entry) => entry['name'] == column)) return;
    await database.execute('ALTER TABLE $table ADD COLUMN $column $definition');
  }

  Future<void> _createTrackMetadataRevisions(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS track_metadata_revisions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        track_id INTEGER NOT NULL,
        change_kind TEXT NOT NULL,
        source TEXT NOT NULL,
        previous_title TEXT NOT NULL,
        previous_artist TEXT NOT NULL,
        previous_album TEXT NOT NULL,
        previous_artwork_path TEXT,
        new_title TEXT NOT NULL,
        new_artist TEXT NOT NULL,
        new_album TEXT NOT NULL,
        new_artwork_path TEXT,
        created_at TEXT NOT NULL,
        reverted_at TEXT,
        FOREIGN KEY (track_id) REFERENCES tracks(id) ON DELETE CASCADE
      )
    ''');
    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_track_metadata_revisions_track_time '
      'ON track_metadata_revisions(track_id, id DESC)',
    );
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
    _markChanged();
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
    _markChanged();
    return track.copyWith(id: id);
  }

  Future<void> setFavorite(int trackId, {required bool value}) async {
    await _database.update(
      'tracks',
      {'is_favorite': value ? 1 : 0},
      where: 'id = ?',
      whereArgs: [trackId],
    );
    _markChanged();
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
    _markChanged();
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
    _markChanged();
  }

  Future<void> markRecentlyPlayed(int trackId) async {
    await _database.update(
      'tracks',
      {'last_played_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [trackId],
    );
    _markChanged();
  }

  Future<void> clearLastPlayed(int trackId) async {
    await _database.update(
      'tracks',
      {'last_played_at': null},
      where: 'id = ?',
      whereArgs: [trackId],
    );
    _markChanged();
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
    _markChanged();
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
    _markChanged();
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
    _markChanged();
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
    _markChanged();
  }

  Future<void> removeTrack(int trackId) async {
    await _database.delete('tracks', where: 'id = ?', whereArgs: [trackId]);
    _markChanged();
  }

  Future<int> removeTracks(Iterable<int> trackIds) async {
    final ids = _uniquePositiveIds(trackIds);
    if (ids.isEmpty) return 0;
    final removed = await _database.transaction((transaction) async {
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
    if (removed > 0) _markChanged();
    return removed;
  }

  Future<void> setTrackVideoPath(int trackId, String? videoPath) async {
    await _database.update(
      'tracks',
      {'video_path': videoPath},
      where: 'id = ?',
      whereArgs: [trackId],
    );
    _markChanged();
  }

  Future<void> replaceTrackMedia(Track track) async {
    if (track.id == null) return;
    await _database.update(
      'tracks',
      track.toDatabaseMap(),
      where: 'id = ?',
      whereArgs: [track.id],
    );
    _markChanged();
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
    _markChanged();
  }

  /// Applies a user-visible metadata change and stores an exact before/after
  /// snapshot in the same transaction. No history row is created for a no-op.
  Future<TrackMetadataRevision?> updateTrackMetadataWithHistory(
    int trackId, {
    required String title,
    required String artist,
    required String album,
    required String? artworkPath,
    required String changeKind,
    required String source,
  }) async {
    final revision = await _database.transaction((transaction) async {
      final rows = await transaction.query(
        'tracks',
        where: 'id = ?',
        whereArgs: [trackId],
        limit: 1,
      );
      if (rows.isEmpty) return null;

      final row = rows.first;
      final previous = TrackMetadataValues(
        title: row['title']! as String,
        artist: row['artist']! as String,
        album: row['album']! as String,
        artworkPath: row['artwork_path'] as String?,
      );
      final current = TrackMetadataValues(
        title: title.trim(),
        artist: artist.trim(),
        album: album.trim(),
        artworkPath: _normalizedOptionalPath(artworkPath),
      );
      if (previous.sameAs(current)) return null;

      await transaction.update(
        'tracks',
        {
          'title': current.title,
          'artist': current.artist,
          'album': current.album,
          'artwork_path': current.artworkPath,
        },
        where: 'id = ?',
        whereArgs: [trackId],
      );
      final createdAt = DateTime.now();
      final revisionId = await transaction.insert('track_metadata_revisions', {
        'track_id': trackId,
        'change_kind': changeKind.trim().isEmpty ? 'manual' : changeKind,
        'source': source.trim().isEmpty ? 'Sona' : source,
        'previous_title': previous.title,
        'previous_artist': previous.artist,
        'previous_album': previous.album,
        'previous_artwork_path': previous.artworkPath,
        'new_title': current.title,
        'new_artist': current.artist,
        'new_album': current.album,
        'new_artwork_path': current.artworkPath,
        'created_at': createdAt.toIso8601String(),
      });
      return TrackMetadataRevision(
        id: revisionId,
        trackId: trackId,
        kind: changeKind.trim().isEmpty ? 'manual' : changeKind,
        source: source.trim().isEmpty ? 'Sona' : source,
        previous: previous,
        current: current,
        createdAt: createdAt,
      );
    });
    if (revision != null) _markChanged();
    return revision;
  }

  Future<List<TrackMetadataRevision>> getTrackMetadataHistory(
    int trackId, {
    int limit = 50,
  }) async {
    final rows = await _database.query(
      'track_metadata_revisions',
      where: 'track_id = ?',
      whereArgs: [trackId],
      orderBy: 'id DESC',
      limit: limit.clamp(1, 200),
    );
    return rows
        .map(TrackMetadataRevision.fromDatabaseMap)
        .toList(growable: false);
  }

  /// Reverts the latest active revision only when the track still matches its
  /// recorded after-state. This prevents an undo from overwriting a newer
  /// write made outside the editor while a dialog was open.
  Future<Track?> undoLatestTrackMetadataRevision(int trackId) async {
    final track = await _database.transaction((transaction) async {
      final revisionRows = await transaction.query(
        'track_metadata_revisions',
        where: 'track_id = ? AND reverted_at IS NULL',
        whereArgs: [trackId],
        orderBy: 'id DESC',
        limit: 1,
      );
      if (revisionRows.isEmpty) return null;
      final revision = TrackMetadataRevision.fromDatabaseMap(
        revisionRows.first,
      );
      final trackRows = await transaction.query(
        'tracks',
        where: 'id = ?',
        whereArgs: [trackId],
        limit: 1,
      );
      if (trackRows.isEmpty) return null;
      final row = trackRows.first;
      final actual = TrackMetadataValues(
        title: row['title']! as String,
        artist: row['artist']! as String,
        album: row['album']! as String,
        artworkPath: row['artwork_path'] as String?,
      );
      if (!actual.sameAs(revision.current)) return null;

      await transaction.update(
        'tracks',
        {
          'title': revision.previous.title,
          'artist': revision.previous.artist,
          'album': revision.previous.album,
          'artwork_path': revision.previous.artworkPath,
        },
        where: 'id = ?',
        whereArgs: [trackId],
      );
      await transaction.update(
        'track_metadata_revisions',
        {'reverted_at': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [revision.id],
      );
      final updatedRows = await transaction.query(
        'tracks',
        where: 'id = ?',
        whereArgs: [trackId],
        limit: 1,
      );
      return Track.fromDatabaseMap(updatedRows.single);
    });
    if (track != null) _markChanged();
    return track;
  }

  String? _normalizedOptionalPath(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  Future<void> setTrackDuration(int trackId, Duration duration) async {
    await _database.update(
      'tracks',
      {'duration_ms': duration.inMilliseconds},
      where: 'id = ?',
      whereArgs: [trackId],
    );
    _markChanged();
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
    _markChanged();
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
  }) async {
    final id = await _database.insert('playlists', {
      'name': name.trim(),
      'description': description.trim(),
      'cover_path': coverPath,
      'cloud_id': cloudId,
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });
    _markChanged();
    return id;
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
    _markChanged();
  }

  Future<void> bindPlaylistToCloud(int playlistId, String cloudId) async {
    await _database.update(
      'playlists',
      {'cloud_id': cloudId, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [playlistId],
    );
    _markChanged();
  }

  Future<void> deletePlaylist(int playlistId) async {
    await _database.delete(
      'playlists',
      where: 'id = ?',
      whereArgs: [playlistId],
    );
    _markChanged();
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
    final added = await _database.transaction((transaction) async {
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
    if (added > 0) _markChanged();
    return added;
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
    final removed = await _database.transaction((transaction) async {
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
    if (removed > 0) _markChanged();
    return removed;
  }

  Future<void> replacePlaylistTracks(
    int playlistId,
    Iterable<int> trackIds,
  ) async {
    await _database.transaction((transaction) async {
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
    _markChanged();
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

  Future<void> close() async {
    await _database.close();
    await _changeController.close();
  }
}
