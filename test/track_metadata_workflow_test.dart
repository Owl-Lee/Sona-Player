import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path_util;
import 'package:sonar_vault/features/library/application/library_controller.dart';
import 'package:sonar_vault/features/library/data/library_database.dart';
import 'package:sonar_vault/features/library/domain/track.dart';
import 'package:sonar_vault/features/library/presentation/library_actions.dart';

void main() {
  testWidgets('right-click workflow edits metadata and undoes from history', (
    tester,
  ) async {
    late Directory temporaryDirectory;
    late LibraryDatabase database;
    late LibraryController controller;
    late Track inserted;
    await tester.runAsync(() async {
      temporaryDirectory = await Directory.systemTemp.createTemp(
        'sona-metadata-widget-',
      );
      database = LibraryDatabase();
      await database.initialize(
        databasePath: path_util.join(temporaryDirectory.path, 'library.db'),
      );
      inserted = (await database.insertTrack(_track()))!;
      controller = LibraryController(database);
      await controller.load();
    });
    addTearDown(() async {
      await database.close();
      await temporaryDirectory.delete(recursive: true);
    });

    await tester.binding.setSurfaceSize(const Size(540, 760));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          libraryControllerProvider.overrideWith((ref) => controller),
        ],
        child: MaterialApp(
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [Locale('zh', 'CN')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => Center(
                child: FilledButton(
                  onPressed: () =>
                      unawaited(showTrackContextMenu(context, ref, inserted)),
                  child: const Text('打开歌曲菜单'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开歌曲菜单'));
    await _finishTransition(tester);
    expect(find.text('编辑歌曲信息与封面'), findsOneWidget);
    expect(find.text('识别与编辑历史'), findsOneWidget);

    await tester.tap(find.text('编辑歌曲信息与封面'));
    await _finishTransition(tester);
    expect(find.text('编辑歌曲信息'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(0), '用户修正歌名');
    await tester.enterText(find.byType(TextField).at(1), '用户修正歌手');
    await tester.enterText(find.byType(TextField).at(2), '用户修正专辑');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pump();
    await tester.runAsync(
      () => _waitUntil(() => controller.state.tracks.single.title == '用户修正歌名'),
    );
    await _finishTransition(tester);

    expect(controller.state.tracks.single.title, '用户修正歌名');
    final editedHistory = await tester.runAsync(
      () => controller.metadataHistory(inserted),
    );
    expect(editedHistory, hasLength(1));

    await tester.tap(find.text('打开歌曲菜单'));
    await _finishTransition(tester);
    await tester.tap(find.text('识别与编辑历史'));
    await tester.pump();
    await tester.runAsync(
      () => _waitUntil(
        () async => (await controller.metadataHistory(inserted)).isNotEmpty,
      ),
    );
    await _finishTransition(tester);
    expect(find.text('撤销最近一次'), findsOneWidget);
    expect(find.text('手动编辑'), findsOneWidget);

    await tester.tap(find.text('撤销最近一次'));
    await tester.pump();
    await tester.runAsync(
      () => _waitUntil(() => controller.state.tracks.single.title == '原歌名'),
    );
    await _finishTransition(tester);
    expect(controller.state.tracks.single.title, '原歌名');
    final revertedHistory = await tester.runAsync(
      () => controller.metadataHistory(inserted),
    );
    expect(revertedHistory!.single.isReverted, isTrue);
  });
}

Future<void> _finishTransition(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 450));
}

Future<void> _waitUntil(FutureOr<bool> Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (!await condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('metadata workflow did not complete');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

Track _track() => Track(
  path: r'C:\Music\workflow.mp3',
  title: '原歌名',
  artist: '原歌手',
  album: '原专辑',
  duration: const Duration(minutes: 3),
  fileSize: 1024,
  contentHash: 'metadata-workflow-hash',
  importedAt: DateTime(2026, 8, 22),
);
