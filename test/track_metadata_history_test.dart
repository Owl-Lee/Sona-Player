import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path_util;
import 'package:sonar_vault/features/library/application/library_controller.dart';
import 'package:sonar_vault/features/library/data/library_database.dart';
import 'package:sonar_vault/features/library/domain/track.dart';
import 'package:sonar_vault/features/library/domain/track_identification.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory temporaryDirectory;
  late LibraryDatabase database;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'sona-metadata-history-',
    );
    database = LibraryDatabase();
    await database.initialize(
      databasePath: path_util.join(temporaryDirectory.path, 'library.db'),
    );
  });

  tearDown(() async {
    await database.close();
    await temporaryDirectory.delete(recursive: true);
  });

  test('metadata changes store exact before and after snapshots', () async {
    final track = (await database.insertTrack(_track()))!;

    final revision = await database.updateTrackMetadataWithHistory(
      track.id!,
      title: '校准歌名',
      artist: '校准歌手',
      album: '校准专辑',
      artworkPath: r'C:\Sona\artwork\cover.png',
      changeKind: 'identification',
      source: 'AcoustID',
    );

    expect(revision, isNotNull);
    expect(revision!.previous.title, '原歌名');
    expect(revision.current.title, '校准歌名');
    expect(revision.current.artworkPath, r'C:\Sona\artwork\cover.png');
    final history = await database.getTrackMetadataHistory(track.id!);
    expect(history, hasLength(1));
    expect(history.single.source, 'AcoustID');
    expect(history.single.isReverted, isFalse);
    final updated = (await database.getTracks()).single;
    expect(updated.title, '校准歌名');
    expect(updated.artworkPath, r'C:\Sona\artwork\cover.png');
  });

  test(
    'identification preserves provider spelling instead of forcing Hans',
    () async {
      final inserted = (await database.insertTrack(_track()))!;
      final controller = LibraryController(database);
      await controller.load();

      final updated = await controller.applyIdentification(
        inserted,
        const TrackIdentificationCandidate(
          title: '美麗的神話 I',
          artist: '成龍、金喜善',
          album: '神話',
          confidence: .91,
          source: 'identification_source_acoustid',
          explanation: 'identification_acoustid_explanation',
        ),
      );

      expect(updated, isNotNull);
      expect(updated!.title, '美麗的神話 I');
      expect(updated.artist, '成龍、金喜善');
      expect(updated.album, '神話');
      final persisted = (await database.getTracks()).single;
      expect(persisted.title, '美麗的神話 I');
      expect(persisted.artist, '成龍、金喜善');
    },
  );

  test(
    'undo walks active revisions backwards without adding fake edits',
    () async {
      final track = (await database.insertTrack(_track()))!;
      await database.updateTrackMetadataWithHistory(
        track.id!,
        title: '手动名称',
        artist: '原歌手',
        album: '原专辑',
        artworkPath: null,
        changeKind: 'manual',
        source: '手动编辑',
      );
      await database.updateTrackMetadataWithHistory(
        track.id!,
        title: '声纹名称',
        artist: '声纹歌手',
        album: '声纹专辑',
        artworkPath: null,
        changeKind: 'identification',
        source: 'AcoustID',
      );

      final firstUndo = await database.undoLatestTrackMetadataRevision(
        track.id!,
      );
      expect(firstUndo!.title, '手动名称');
      final secondUndo = await database.undoLatestTrackMetadataRevision(
        track.id!,
      );
      expect(secondUndo!.title, '原歌名');
      expect(await database.undoLatestTrackMetadataRevision(track.id!), isNull);
      final history = await database.getTrackMetadataHistory(track.id!);
      expect(history, hasLength(2));
      expect(history.every((revision) => revision.isReverted), isTrue);
    },
  );

  test('undo refuses to overwrite an untracked newer write', () async {
    final track = (await database.insertTrack(_track()))!;
    await database.updateTrackMetadataWithHistory(
      track.id!,
      title: '有历史的名称',
      artist: '原歌手',
      album: '原专辑',
      artworkPath: null,
      changeKind: 'manual',
      source: '手动编辑',
    );
    await database.updateTrackMetadata(
      track.id!,
      title: '外部的新名称',
      artist: '外部歌手',
      album: '外部专辑',
    );

    expect(await database.undoLatestTrackMetadataRevision(track.id!), isNull);
    expect((await database.getTracks()).single.title, '外部的新名称');
  });

  test('seeded edit and undo stack restores every exact revision', () async {
    final original = (await database.insertTrack(_track()))!;
    final expectedTitles = <String>[original.title];
    final random = Random(0x5A17);

    for (var index = 0; index < 120; index++) {
      final title = 'Revision $index-${random.nextInt(1 << 20)}';
      final revision = await database.updateTrackMetadataWithHistory(
        original.id!,
        title: title,
        artist: 'Artist $index',
        album: 'Album ${index % 9}',
        artworkPath: index.isEven ? 'C:/covers/$index.jpg' : null,
        changeKind: index.isEven ? 'manual' : 'identification',
        source: index.isEven ? 'stress edit' : 'stress fingerprint',
      );
      expect(revision, isNotNull);
      expectedTitles.add(title);
    }

    for (var index = 119; index >= 0; index--) {
      final restored = await database.undoLatestTrackMetadataRevision(
        original.id!,
      );
      expect(restored, isNotNull);
      expect(restored!.title, expectedTitles[index]);
    }
    expect(
      await database.undoLatestTrackMetadataRevision(original.id!),
      isNull,
    );
    final history = await database.getTrackMetadataHistory(original.id!);
    // The persistence stack keeps every revision for undo. The UI-facing
    // query intentionally returns only its newest bounded page.
    expect(history, hasLength(50));
    expect(history.every((revision) => revision.isReverted), isTrue);
  });

  test(
    'version 7 database with artwork column upgrades idempotently',
    () async {
      final databasePath = database.databasePath;
      await database.close();
      sqfliteFfiInit();
      final raw = await databaseFactoryFfi.openDatabase(databasePath);
      await raw.execute('DROP TABLE track_metadata_revisions');
      await raw.execute('PRAGMA user_version = 7');
      await raw.close();

      database = LibraryDatabase();
      await database.initialize(databasePath: databasePath);
      final inserted = await database.insertTrack(_track());

      expect(inserted, isNotNull);
      expect(await database.getTrackMetadataHistory(inserted!.id!), isEmpty);

      final revision = await database.updateTrackMetadataWithHistory(
        inserted.id!,
        title: '迁移后名称',
        artist: inserted.artist,
        album: inserted.album,
        artworkPath: null,
        changeKind: 'manual',
        source: '迁移回归',
      );
      expect(revision, isNotNull);
    },
  );

  test('controller copies, clears, and restores managed artwork', () async {
    final track = (await database.insertTrack(_track()))!;
    final source = File(path_util.join(temporaryDirectory.path, 'picked.png'));
    await source.writeAsBytes(const [137, 80, 78, 71, 13, 10, 26, 10]);
    final controller = LibraryController(database);
    await controller.load();

    final edited = await controller.updateTrackDetails(
      track,
      title: track.title,
      artist: track.artist,
      album: track.album,
      selectedArtworkPath: source.path,
    );

    expect(edited!.artworkPath, isNot(source.path));
    expect(await File(edited.artworkPath!).exists(), isTrue);
    await source.delete();
    expect(await File(edited.artworkPath!).exists(), isTrue);

    final cleared = await controller.updateTrackDetails(
      edited,
      title: edited.title,
      artist: edited.artist,
      album: edited.album,
      clearArtwork: true,
    );
    expect(cleared!.artworkPath, isNull);

    final restored = await controller.undoLatestMetadataChange(cleared);
    expect(restored!.artworkPath, edited.artworkPath);
    expect(await File(restored.artworkPath!).exists(), isTrue);
    controller.dispose();
  });
}

Track _track() {
  return Track(
    path: r'C:\Music\original.mp3',
    title: '原歌名',
    artist: '原歌手',
    album: '原专辑',
    duration: const Duration(minutes: 3),
    fileSize: 1024,
    contentHash: 'metadata-history-hash',
    importedAt: DateTime(2026, 8, 22),
  );
}
