import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path_util;
import 'package:sonar_vault/features/library/data/library_database.dart';
import 'package:sonar_vault/features/library/domain/track.dart';

void main() {
  late Directory temporaryDirectory;
  late LibraryDatabase database;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp('sona-db-test-');
    database = LibraryDatabase();
    await database.initialize(
      databasePath: path_util.join(temporaryDirectory.path, 'library.db'),
    );
  });

  tearDown(() async {
    await database.close();
    await temporaryDirectory.delete(recursive: true);
  });

  test('batch mutations stay consistent across tracks and playlists', () async {
    final first = await database.insertTrack(_track(1));
    final second = await database.insertTrack(_track(2));
    expect(first, isNotNull);
    expect(second, isNotNull);

    final playlistId = await database.createPlaylist('回归测试歌单');
    expect(
      await database.addTracksToPlaylist(playlistId, [
        first!.id!,
        second!.id!,
        first.id!,
      ]),
      2,
    );
    expect(
      (await database.getTracksForPlaylist(playlistId))
          .map((track) => track.id),
      [first.id, second.id],
    );

    await database.setFavorites([first.id!, second.id!], value: true);
    expect(
      (await database.getTracks()).every((track) => track.isFavorite),
      isTrue,
    );

    expect(await database.removeTracks([first.id!, first.id!]), 1);
    expect((await database.getTracks()).map((track) => track.id), [second.id]);
    expect(
      (await database.getTracksForPlaylist(playlistId))
          .map((track) => track.id),
      [second.id],
    );
    expect((await database.getPlaylists()).single.trackCount, 1);
  });

  test('playlist replacement de-duplicates IDs before writing', () async {
    final first = await database.insertTrack(_track(10));
    final second = await database.insertTrack(_track(11));
    final playlistId = await database.createPlaylist('去重测试');

    await database.replacePlaylistTracks(playlistId, [
      first!.id!,
      first.id!,
      second!.id!,
      first.id!,
    ]);

    expect(
      (await database.getTracksForPlaylist(playlistId))
          .map((track) => track.id),
      [first.id, second.id],
    );
  });

  test(
    'rapid bulk playlist and favorite operations remain internally consistent',
    () async {
      final tracks = <Track>[];
      for (var index = 0; index < 40; index++) {
        final inserted = await database.insertTrack(_track(100 + index));
        expect(inserted, isNotNull);
        tracks.add(inserted!);
      }
      final playlistId = await database.createPlaylist('高频操作回归');
      final ids = tracks.map((track) => track.id!).toList(growable: false);

      for (var round = 0; round < 30; round++) {
        final rotating = [
          ...ids.skip(round % ids.length),
          ...ids.take(round % ids.length),
          ids.first,
        ];
        await database.replacePlaylistTracks(playlistId, rotating);
        await database.setFavorites(ids, value: round.isEven);
      }

      expect(
        (await database.getTracksForPlaylist(playlistId)).length,
        ids.length,
      );
      expect(
        (await database.getTracks()).every((track) => track.isFavorite),
        isFalse,
      );
    },
  );
}

Track _track(int seed) {
  return Track(
    path: 'C:/test/track-$seed.mp3',
    title: 'Track $seed',
    artist: 'Artist',
    album: 'Album',
    duration: const Duration(minutes: 3),
    fileSize: 1024,
    contentHash: 'hash-$seed',
    importedAt: DateTime(2026, 8, 17),
  );
}
