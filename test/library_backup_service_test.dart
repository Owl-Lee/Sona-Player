import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path_util;
import 'package:sonar_vault/features/library/data/library_backup_service.dart';
import 'package:sonar_vault/features/library/data/library_database.dart';
import 'package:sonar_vault/features/library/domain/library_backup.dart';
import 'package:sonar_vault/features/library/domain/track.dart';

void main() {
  late Directory temporaryDirectory;
  late Directory supportDirectory;
  late String databasePath;
  LibraryDatabase? database;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'sona-backup-test-',
    );
    supportDirectory = Directory(
      path_util.join(temporaryDirectory.path, 'support'),
    );
    databasePath = path_util.join(
      supportDirectory.path,
      'SonarVault',
      'sonar_vault.db',
    );
    database = LibraryDatabase();
    await database!.initialize(databasePath: databasePath);
  });

  tearDown(() async {
    await database?.close();
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  Future<File> createFile(String relativePath, String contents) async {
    final file = File(path_util.join(temporaryDirectory.path, relativePath));
    await file.parent.create(recursive: true);
    await file.writeAsString(contents, flush: true);
    return file;
  }

  test('round trip is self-contained and rewrites every stored path', () async {
    final media = await createFile('external/song.mp3', 'audio-payload');
    final video = await createFile('external/song.mp4', 'video-payload');
    final artwork = await createFile('external/art.jpg', 'art-payload');
    final cover = await createFile('external/cover.jpg', 'cover-payload');
    final background = await createFile('external/background.jpg', 'wallpaper');

    final inserted = await database!.insertTrack(
      Track(
        path: media.path,
        title: '完整备份',
        artist: 'Sona',
        album: 'Regression',
        duration: const Duration(minutes: 3),
        fileSize: await media.length(),
        contentHash: sha256.convert(await media.readAsBytes()).toString(),
        importedAt: DateTime.utc(2026, 8, 22),
        isFavorite: true,
        playCount: 7,
        videoPath: video.path,
        artworkPath: artwork.path,
      ),
    );
    final playlist = await database!.createPlaylist(
      '备份歌单',
      coverPath: cover.path,
    );
    await database!.addTrackToPlaylist(playlist, inserted!.id!);
    await database!.setSetting('appearance.custom_path', background.path);
    await database!.setSetting(
      'appearance.custom_backgrounds',
      jsonEncode([
        {'path': background.path, 'accent': 123},
      ]),
    );

    final backupPath = path_util.join(
      temporaryDirectory.path,
      'library.sonabackup',
    );
    final service = LibraryBackupService(
      database: database!,
      applicationSupportDirectory: supportDirectory,
    );
    final created = await service.createBackup(destinationPath: backupPath);
    expect(created.manifest.missingReferences, isEmpty);
    expect(created.manifest.entries, hasLength(6));
    expect(
      created.manifest.entries.expand((item) => item.roles),
      containsAll([
        'database',
        'track_media',
        'track_video',
        'track_artwork',
        'playlist_cover',
        'custom_background',
      ]),
    );
    expect((await service.inspectBackup(backupPath)).backupId, isNotEmpty);

    final prepared = await service.stageRestore(backupPath);
    expect(prepared.restartRequired, isTrue);
    await database!.close();
    database = null;
    expect(
      await LibraryBackupService.applyPendingRestore(
        applicationSupportDirectory: supportDirectory,
        databasePath: databasePath,
      ),
      isTrue,
    );

    database = LibraryDatabase();
    await database!.initialize(databasePath: databasePath);
    expect(await database!.validateIntegrity(), isTrue);
    final restored = (await database!.getTracks()).single;
    expect(restored.title, '完整备份');
    expect(restored.isFavorite, isTrue);
    expect(restored.playCount, 7);
    expect(restored.path, isNot(media.path));
    expect(await File(restored.path).readAsString(), 'audio-payload');
    expect(await File(restored.videoPath!).readAsString(), 'video-payload');
    expect(await File(restored.artworkPath!).readAsString(), 'art-payload');

    final restoredPlaylist = (await database!.getPlaylists()).single;
    expect(
      await File(restoredPlaylist.coverPath!).readAsString(),
      'cover-payload',
    );
    final restoredBackground = await database!.getSetting(
      'appearance.custom_path',
    );
    expect(restoredBackground, isNot(background.path));
    expect(await File(restoredBackground!).readAsString(), 'wallpaper');
    final backgroundList = jsonDecode(
      (await database!.getSetting('appearance.custom_backgrounds'))!,
    ) as List;
    expect((backgroundList.single as Map)['path'], restoredBackground);
    expect(
      (await database!.getTracksForPlaylist(restoredPlaylist.id)).single.id,
      restored.id,
    );
    expect(
      await File('$databasePath.pre_restore').exists(),
      isTrue,
      reason: 'one rollback database is intentionally retained',
    );
  });

  test('corruption is rejected without touching the live database', () async {
    final media = await createFile('song.mp3', 'payload-to-corrupt');
    await database!.insertTrack(_track(media));
    final backup = path_util.join(temporaryDirectory.path, 'valid.sonabackup');
    final service = LibraryBackupService(
      database: database!,
      applicationSupportDirectory: supportDirectory,
    );
    await service.createBackup(destinationPath: backup);
    final bytes = await File(backup).readAsBytes();
    bytes[bytes.length ~/ 2] ^= 0x5A;
    final corrupt = path_util.join(
      temporaryDirectory.path,
      'corrupt.sonabackup',
    );
    await File(corrupt).writeAsBytes(bytes);

    await expectLater(
      service.stageRestore(corrupt),
      throwsA(isA<LibraryBackupException>()),
    );
    expect(await File(databasePath).exists(), isTrue);
    expect(
      await File(
        path_util.join(
          supportDirectory.path,
          'SonarVault',
          'pending_restore.json',
        ),
      ).exists(),
      isFalse,
    );
    expect((await database!.getTracks()).single.title, 'Song');
  });

  test('restore rejects a self-consistent manifest that omits a database reference', () async {
    final media = await createFile('reference-check/song.mp3', 'audio');
    await database!.insertTrack(_track(media));
    final service = LibraryBackupService(
      database: database!,
      applicationSupportDirectory: supportDirectory,
    );
    final backup = File(
      path_util.join(temporaryDirectory.path, 'reference-check.sonabackup'),
    );
    await service.createBackup(destinationPath: backup.path);

    final unrelatedPath = media.path.replaceAll(RegExp('[A-Za-z0-9]'), 'x');
    expect(unrelatedPath.length, media.path.length);
    await _rewriteManifestOriginalPath(
      backup,
      from: media.path,
      to: unrelatedPath,
    );

    await expectLater(
      service.stageRestore(backup.path),
      throwsA(
        isA<LibraryBackupException>().having(
          (error) => error.code,
          'code',
          'backup_restore_reference_outside_package',
        ),
      ),
    );
    expect(await service.hasPendingRestore(), isFalse);
  });

  test('a pending restore can be safely discarded', () async {
    final media = await createFile('discard/song.mp3', 'still-live');
    await database!.insertTrack(_track(media));
    final service = LibraryBackupService(
      database: database!,
      applicationSupportDirectory: supportDirectory,
    );
    final backup = path_util.join(
      temporaryDirectory.path,
      'discard.sonabackup',
    );
    await service.createBackup(destinationPath: backup);
    await service.stageRestore(backup);
    expect(await service.hasPendingRestore(), isTrue);
    expect((await service.pendingRestoreStatus())?.hasFailed, isFalse);
    await LibraryBackupService.recordPendingRestoreFailure(
      'backup_restore_pending_database_integrity_failed',
      applicationSupportDirectory: supportDirectory,
    );
    final failure = await service.pendingRestoreStatus();
    expect(failure?.hasFailed, isTrue);
    expect(
      failure?.lastErrorCode,
      'backup_restore_pending_database_integrity_failed',
    );
    expect(failure?.lastFailureAt, isNotNull);

    await service.discardPendingRestore();

    expect(await service.hasPendingRestore(), isFalse);
    expect(await service.pendingRestoreStatus(), isNull);
    expect((await database!.getTracks()).single.title, 'Song');
    expect(await media.readAsString(), 'still-live');
  });

  test('cold-start restore recovers an interrupted first rename', () async {
    final media = await createFile('interrupted/song.mp3', 'recoverable');
    final inserted = await database!.insertTrack(_track(media));
    final service = LibraryBackupService(
      database: database!,
      applicationSupportDirectory: supportDirectory,
    );
    final backup = path_util.join(
      temporaryDirectory.path,
      'interrupted.sonabackup',
    );
    await service.createBackup(destinationPath: backup);
    await database!.updateTrackMetadata(
      inserted!.id!,
      title: 'Newer live title',
      artist: inserted.artist,
      album: inserted.album,
    );
    await service.stageRestore(backup);
    await database!.close();
    database = null;

    final target = File(databasePath);
    final rollback = File('$databasePath.pre_restore');
    await target.rename(rollback.path);
    expect(await target.exists(), isFalse);

    expect(
      await LibraryBackupService.applyPendingRestore(
        applicationSupportDirectory: supportDirectory,
        databasePath: databasePath,
      ),
      isTrue,
    );
    database = LibraryDatabase();
    await database!.initialize(databasePath: databasePath);
    expect((await database!.getTracks()).single.title, 'Song');

    final rollbackDatabase = LibraryDatabase();
    await rollbackDatabase.initialize(databasePath: rollback.path);
    try {
      expect(
        (await rollbackDatabase.getTracks()).single.title,
        'Newer live title',
      );
    } finally {
      await rollbackDatabase.close();
    }
  });

  test(
    'cold-start failures stay recoverable and preserve the live database',
    () async {
      await database!.close();
      database = null;
      final liveHash = sha256.convert(await File(databasePath).readAsBytes());

      final root = Directory(
        path_util.join(supportDirectory.path, 'SonarVault'),
      );
      final staged = File(
        path_util.join(
          root.path,
          'restore_staging',
          'damaged',
          'database',
          'sonar_vault.db',
        ),
      );
      await staged.parent.create(recursive: true);
      await staged.writeAsString('not a sqlite database', flush: true);
      final assets = Directory(
        path_util.join(root.path, 'restored', 'damaged'),
      );
      await assets.create(recursive: true);
      final marker = File(path_util.join(root.path, 'pending_restore.json'));
      await marker.writeAsString(
        jsonEncode({
          'format_version': 1,
          'backup_id': 'damaged',
          'staged_database': staged.path,
          'staged_database_sha256': sha256
              .convert(await staged.readAsBytes())
              .toString(),
          'restored_assets': assets.path,
          'prepared_at': DateTime.utc(2026, 8, 22).toIso8601String(),
        }),
        flush: true,
      );

      await expectLater(
        LibraryBackupService.applyPendingRestore(
          applicationSupportDirectory: supportDirectory,
          databasePath: databasePath,
        ),
        throwsA(isA<LibraryBackupException>()),
      );
      expect(sha256.convert(await File(databasePath).readAsBytes()), liveHash);
      expect(await marker.exists(), isTrue);
    },
  );

  test('archive traversal path is rejected before extraction', () async {
    final backup = path_util.join(temporaryDirectory.path, 'valid.sonabackup');
    final service = LibraryBackupService(
      database: database!,
      applicationSupportDirectory: supportDirectory,
    );
    await service.createBackup(destinationPath: backup);
    final bytes = await File(backup).readAsBytes();
    final needle = utf8.encode('database/sonar_vault.db');
    final offset = _indexOf(bytes, needle);
    expect(offset, greaterThan(0));
    bytes[offset] = 0x2E;
    bytes[offset + 1] = 0x2E;
    bytes[offset + 2] = 0x2F;
    final traversal = path_util.join(
      temporaryDirectory.path,
      'traversal.sonabackup',
    );
    await File(traversal).writeAsBytes(bytes);

    await expectLater(
      service.stageRestore(traversal),
      throwsA(
        isA<LibraryBackupException>().having(
          (error) => error.code,
          'code',
          'backup_entry_path_unsafe_or_duplicate',
        ),
      ),
    );
    expect(
      await File(path_util.join(temporaryDirectory.path, 'abase')).exists(),
      isFalse,
    );
  });

  test('manual backup fails closed when referenced media is missing', () async {
    final missing = File(path_util.join(temporaryDirectory.path, 'gone.mp3'));
    await database!.insertTrack(_track(missing));
    final service = LibraryBackupService(
      database: database!,
      applicationSupportDirectory: supportDirectory,
    );
    final destination = path_util.join(
      temporaryDirectory.path,
      'missing.sonabackup',
    );
    await expectLater(
      service.createBackup(destinationPath: destination),
      throwsA(
        isA<LibraryBackupException>().having(
          (error) => error.code,
          'code',
          'backup_required_files_missing',
        ),
      ),
    );
    expect(await File(destination).exists(), isFalse);
    expect(await File('$destination.partial').exists(), isFalse);
  });

  test(
    'manual backup fails before publishing when optional files are missing',
    () async {
      final media = await createFile('optional/song.mp3', 'audio');
      final missingArtwork = File(
        path_util.join(temporaryDirectory.path, 'optional', 'gone.jpg'),
      );
      await database!.insertTrack(
        _track(media).copyWith(artworkPath: missingArtwork.path),
      );
      final service = LibraryBackupService(
        database: database!,
        applicationSupportDirectory: supportDirectory,
      );
      final destination = path_util.join(
        temporaryDirectory.path,
        'optional-missing.sonabackup',
      );
      await expectLater(
        service.createBackup(destinationPath: destination),
        throwsA(
          isA<LibraryBackupException>().having(
            (error) => error.code,
            'code',
            'backup_required_files_missing',
          ),
        ),
      );
      expect(await File(destination).exists(), isFalse);
      expect(await File('$destination.partial').exists(), isFalse);
      expect(await service.hasPendingRestore(), isFalse);
    },
  );

  test('backup refuses to overwrite a referenced media file', () async {
    final media = await createFile('protected/song.mp3', 'do-not-overwrite');
    await database!.insertTrack(_track(media));
    final service = LibraryBackupService(
      database: database!,
      applicationSupportDirectory: supportDirectory,
    );

    await expectLater(
      service.createBackup(destinationPath: media.path),
      throwsA(isA<LibraryBackupException>()),
    );
    expect(await media.readAsString(), 'do-not-overwrite');
  });

  test('automatic backups keep a bounded newest history', () async {
    final media = await createFile('song.mp3', 'small');
    await database!.insertTrack(_track(media));
    var clock = DateTime.utc(2026, 8, 22);
    final service = LibraryBackupService(
      database: database!,
      applicationSupportDirectory: supportDirectory,
      clock: () => clock,
    );
    for (var index = 0; index < 4; index++) {
      clock = clock.add(const Duration(minutes: 1));
      final result = await service.createAutomaticBackup(keep: 2);
      await File(result.path).setLastModified(clock);
    }
    final backups = await service.automaticBackups();
    expect(backups, hasLength(2));
    expect(path_util.basename(backups.first.path), contains('202608220004'));
  });

  test(
    'automatic backups keep metadata small instead of copying media',
    () async {
      final media = await createFile(
        'large/song.mp3',
        List.filled(256 * 1024, 'm').join(),
      );
      final artwork = await createFile('managed/cover.jpg', 'cover');
      await database!.insertTrack(
        _track(media).copyWith(artworkPath: artwork.path),
      );
      final service = LibraryBackupService(
        database: database!,
        applicationSupportDirectory: supportDirectory,
      );

      final result = await service.createAutomaticBackup(keep: 1);

      expect(result.manifest.kind, LibraryBackupKind.automatic);
      expect(
        result.manifest.entries.expand((entry) => entry.roles),
        isNot(contains('track_media')),
      );
      expect(
        result.manifest.entries.expand((entry) => entry.roles),
        contains('track_artwork'),
      );
      expect(await File(result.path).length(), lessThan(await media.length()));
      await expectLater(
        service.stageRestore(result.path),
        throwsA(
          isA<LibraryBackupException>().having(
            (error) => error.code,
            'code',
            'backup_restore_kind_automatic_not_manual',
          ),
        ),
      );
      expect(
        await File(
          path_util.join(
            supportDirectory.path,
            'SonarVault',
            'pending_restore.json',
          ),
        ).exists(),
        isFalse,
      );
    },
  );

  test(
    'automatic snapshot restores database and visuals on its source device',
    () async {
      final media = await createFile('auto-restore/song.mp3', 'audio');
      final artwork = await createFile('auto-restore/cover.jpg', 'cover');
      await database!.insertTrack(
        _track(media).copyWith(artworkPath: artwork.path),
      );
      await database!.setSetting('snapshot.marker', 'before');
      final service = LibraryBackupService(
        database: database!,
        applicationSupportDirectory: supportDirectory,
      );
      final backup = await service.createAutomaticBackup(keep: 1);
      await database!.setSetting('snapshot.marker', 'after');
      await artwork.delete();

      final prepared = await service.stageAutomaticRestore(backup.path);
      expect(prepared.manifest.kind, LibraryBackupKind.automatic);
      await database!.close();
      database = null;
      expect(
        await LibraryBackupService.applyPendingRestore(
          applicationSupportDirectory: supportDirectory,
          databasePath: databasePath,
        ),
        isTrue,
      );

      database = LibraryDatabase();
      await database!.initialize(databasePath: databasePath);
      expect(await database!.getSetting('snapshot.marker'), 'before');
      final restored = (await database!.getTracks()).single;
      expect(restored.path, media.path);
      expect(await File(restored.path).readAsString(), 'audio');
      expect(restored.artworkPath, isNot(artwork.path));
      expect(await File(restored.artworkPath!).readAsString(), 'cover');
    },
  );

  test('automatic snapshot refuses missing on-device media', () async {
    final media = await createFile('auto-missing/song.mp3', 'audio');
    await database!.insertTrack(_track(media));
    final service = LibraryBackupService(
      database: database!,
      applicationSupportDirectory: supportDirectory,
    );
    final backup = await service.createAutomaticBackup(keep: 1);
    await media.delete();

    await expectLater(
      service.stageAutomaticRestore(backup.path),
      throwsA(
        isA<LibraryBackupException>().having(
          (error) => error.code,
          'code',
          'backup_restore_local_media_missing',
        ),
      ),
    );
    expect(await service.hasPendingRestore(), isFalse);
  });

  test('damaged automatic snapshot is rejected without a marker', () async {
    final media = await createFile('auto-damaged/song.mp3', 'audio');
    await database!.insertTrack(_track(media));
    final service = LibraryBackupService(
      database: database!,
      applicationSupportDirectory: supportDirectory,
    );
    final backup = await service.createAutomaticBackup(keep: 1);
    final bytes = await File(backup.path).readAsBytes();
    bytes[bytes.length ~/ 3] ^= 0x39;
    await File(backup.path).writeAsBytes(bytes, flush: true);

    await expectLater(
      service.stageAutomaticRestore(backup.path),
      throwsA(isA<LibraryBackupException>()),
    );
    expect(await service.hasPendingRestore(), isFalse);
  });

  test(
    'concurrent backup requests are serialized without losing a target',
    () async {
      final media = await createFile('queue/song.mp3', 'queued');
      await database!.insertTrack(_track(media));
      final service = LibraryBackupService(
        database: database!,
        applicationSupportDirectory: supportDirectory,
      );
      final firstPath = path_util.join(
        temporaryDirectory.path,
        'first.sonabackup',
      );
      final secondPath = path_util.join(
        temporaryDirectory.path,
        'second.sonabackup',
      );

      final first = service.createBackup(destinationPath: firstPath);
      final second = service.createBackup(destinationPath: secondPath);
      await Future.wait([first, second]);

      expect(await File(firstPath).exists(), isTrue);
      expect(await File(secondPath).exists(), isTrue);
      expect((await service.inspectBackup(firstPath)).entries, isNotEmpty);
      expect((await service.inspectBackup(secondPath)).entries, isNotEmpty);
    },
  );

  test(
    'a failed queued backup does not poison later backup requests',
    () async {
      final media = await createFile('queue-recovery/song.mp3', 'queued');
      await database!.insertTrack(_track(media));
      final service = LibraryBackupService(
        database: database!,
        applicationSupportDirectory: supportDirectory,
      );
      final paths = List.generate(
        20,
        (index) => path_util.join(
          temporaryDirectory.path,
          'queued-recovery-$index.sonabackup',
        ),
      );

      final results = await Future.wait<Object>([
        _captureBackupResult(service.createBackup(destinationPath: '')),
        for (final path in paths)
          _captureBackupResult(service.createBackup(destinationPath: path)),
      ]);

      expect(results.first, isA<LibraryBackupException>());
      expect(results.skip(1).whereType<LibraryBackupResult>(), hasLength(20));
      for (final path in paths) {
        expect((await service.inspectBackup(path)).entries, isNotEmpty);
      }
    },
  );

  test(
    'concurrent restore staging accepts exactly one pending restore',
    () async {
      final media = await createFile('restore-race/song.mp3', 'restorable');
      await database!.insertTrack(_track(media));
      final service = LibraryBackupService(
        database: database!,
        applicationSupportDirectory: supportDirectory,
      );
      final backup = path_util.join(
        temporaryDirectory.path,
        'restore-race.sonabackup',
      );
      await service.createBackup(destinationPath: backup);

      final results = await Future.wait<Object>(
        List.generate(
          16,
          (_) => _captureBackupResult(service.stageRestore(backup)),
        ),
      );

      expect(results.whereType<LibraryRestorePreparation>(), hasLength(1));
      expect(results.whereType<LibraryBackupException>(), hasLength(15));
      expect(await service.hasPendingRestore(), isTrue);
      expect((await database!.getTracks()).single.title, 'Song');
      final restoredRoot = Directory(
        path_util.join(supportDirectory.path, 'SonarVault', 'restored'),
      );
      expect(
        await restoredRoot
            .list(followLinks: false)
            .where((entry) => entry is Directory)
            .length,
        1,
      );
    },
  );

  test('damaged restore does not poison a valid queued restore', () async {
    final media = await createFile('restore-recovery/song.mp3', 'restorable');
    await database!.insertTrack(_track(media));
    final service = LibraryBackupService(
      database: database!,
      applicationSupportDirectory: supportDirectory,
    );
    final valid = path_util.join(
      temporaryDirectory.path,
      'restore-recovery.sonabackup',
    );
    final damaged = path_util.join(
      temporaryDirectory.path,
      'restore-damaged.sonabackup',
    );
    await service.createBackup(destinationPath: valid);
    await File(damaged).writeAsString('not a Sona backup', flush: true);

    final results = await Future.wait<Object>([
      _captureBackupResult(service.stageRestore(damaged)),
      _captureBackupResult(service.stageRestore(valid)),
    ]);

    expect(results.first, isA<LibraryBackupException>());
    expect(results.last, isA<LibraryRestorePreparation>());
    expect(await service.hasPendingRestore(), isTrue);
  });

  test('database mutations emit an automatic-backup change signal', () async {
    final changed = database!.changes.first.timeout(const Duration(seconds: 1));
    await database!.setSetting('test.changed', 'yes');
    await expectLater(changed, completes);
  });

  test('automatic coordinator backs up changes and remains periodic', () async {
    final media = await createFile('coordinator/song.mp3', 'scheduled');
    await database!.insertTrack(_track(media));
    final service = LibraryBackupService(
      database: database!,
      applicationSupportDirectory: supportDirectory,
    );
    final coordinator = AutoBackupCoordinator(
      service: service,
      database: database!,
      initialDelay: const Duration(milliseconds: 5),
      changeDebounce: const Duration(milliseconds: 5),
      minimumInterval: Duration.zero,
      maximumInterval: const Duration(milliseconds: 80),
      retryDelay: const Duration(milliseconds: 20),
      keep: 3,
    );
    await coordinator.start();
    try {
      await _waitForBackupCount(service, 1);

      await database!.setSetting('coordinator.changed', 'yes');
      await _waitForBackupCount(service, 2);

      // No further mutation: maximumInterval still creates a periodic safety
      // snapshot instead of relying solely on later user activity.
      await _waitForBackupCount(service, 3);
    } finally {
      await coordinator.dispose();
    }
  });
}

Track _track(File file) {
  final bytes = file.existsSync()
      ? file.readAsBytesSync()
      : utf8.encode('gone');
  return Track(
    path: file.path,
    title: 'Song',
    artist: 'Artist',
    album: 'Album',
    duration: const Duration(minutes: 1),
    fileSize: file.existsSync() ? file.lengthSync() : 0,
    contentHash: sha256.convert(bytes).toString(),
    importedAt: DateTime.utc(2026, 8, 22),
  );
}

int _indexOf(List<int> haystack, List<int> needle) {
  for (var start = 0; start <= haystack.length - needle.length; start++) {
    var matches = true;
    for (var index = 0; index < needle.length; index++) {
      if (haystack[start + index] != needle[index]) {
        matches = false;
        break;
      }
    }
    if (matches) return start;
  }
  return -1;
}

Future<void> _waitForBackupCount(
  LibraryBackupService service,
  int expected,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (DateTime.now().isBefore(deadline)) {
    if ((await service.automaticBackups()).length >= expected) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Timed out waiting for $expected automatic backups.');
}

Future<Object> _captureBackupResult(Future<Object> operation) async {
  try {
    return await operation;
  } catch (error) {
    return error;
  }
}

Future<void> _rewriteManifestOriginalPath(
  File backup, {
  required String from,
  required String to,
}) async {
  final bytes = Uint8List.fromList(await backup.readAsBytes());
  final data = ByteData.sublistView(bytes);
  final entryCount = data.getUint32(12, Endian.little);
  final headerLength = data.getUint32(16, Endian.little);
  var offset = 20 + headerLength;
  for (var index = 0; index < entryCount; index++) {
    final pathLength = data.getUint32(offset, Endian.little);
    offset += 4 + pathLength;
    final entryLength = data.getUint64(offset, Endian.little);
    offset += 8 + entryLength + 32;
  }

  final manifestLength = data.getUint64(offset, Endian.little);
  final manifestStart = offset + 8;
  final manifestEnd = manifestStart + manifestLength;
  final manifest = Map<String, Object?>.from(
    jsonDecode(utf8.decode(bytes.sublist(manifestStart, manifestEnd))) as Map,
  );
  var replaced = false;
  for (final rawEntry in (manifest['entries'] as List).whereType<Map>()) {
    final entry = Map<String, Object?>.from(rawEntry);
    final paths = (entry['original_paths'] as List).cast<String>();
    for (var index = 0; index < paths.length; index++) {
      if (paths[index] == from) {
        paths[index] = to;
        replaced = true;
      }
    }
    entry['original_paths'] = paths;
    final entries = manifest['entries'] as List;
    entries[entries.indexOf(rawEntry)] = entry;
  }
  expect(replaced, isTrue);
  final rewritten = utf8.encode(jsonEncode(manifest));
  expect(rewritten.length, manifestLength);
  bytes.setRange(manifestStart, manifestEnd, rewritten);
  final digest = sha256.convert(rewritten).bytes;
  bytes.setRange(manifestEnd, manifestEnd + digest.length, digest);
  await backup.writeAsBytes(bytes, flush: true);
}
