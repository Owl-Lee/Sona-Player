import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path_util;
import 'package:sonar_vault/core/performance/visual_effects.dart';
import 'package:sonar_vault/features/library/application/library_controller.dart';
import 'package:sonar_vault/features/library/data/library_database.dart';
import 'package:sonar_vault/features/settings/application/appearance_controller.dart';
import 'package:sonar_vault/features/settings/application/language_controller.dart';
import 'package:sonar_vault/features/settings/presentation/settings_page.dart';

void main() {
  testWidgets('performance and backup controls are reachable from Settings', (
    tester,
  ) async {
    late Directory directory;
    late LibraryDatabase database;
    late AppearanceController appearance;
    late LibraryController library;
    late LanguageController language;
    await tester.runAsync(() async {
      directory = await Directory.systemTemp.createTemp(
        'sona-settings-reachability-',
      );
      database = LibraryDatabase();
      await database.initialize(
        databasePath: path_util.join(directory.path, 'library.db'),
      );
      appearance = AppearanceController(database);
      await appearance.load();
      await appearance.setEffectsMode(VisualEffectsMode.off);
      library = LibraryController(database);
      await library.load();
      language = LanguageController(database);
      await language.load();
    });
    addTearDown(() async {
      await database.close();
      await directory.delete(recursive: true);
    });
    await tester.binding.setSurfaceSize(const Size(1100, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          libraryDatabaseProvider.overrideWithValue(database),
          appearanceControllerProvider.overrideWith((ref) => appearance),
          libraryControllerProvider.overrideWith((ref) => library),
          languageControllerProvider.overrideWith((ref) => language),
        ],
        child: const MaterialApp(
          locale: Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
          supportedLocales: [
            Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
          ],
          localizationsDelegates: [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(body: SettingsPage()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.text('外观与播放器'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('动态特效与性能'), findsOneWidget);
    expect(find.text('完整特效'), findsOneWidget);
    expect(find.text('节能特效'), findsOneWidget);
    expect(find.text('关闭动态特效'), findsOneWidget);

    await tester.tap(find.byTooltip('返回设置'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('存储与数据'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('完整备份与恢复'), findsOneWidget);
    expect(find.text('导出完整备份'), findsOneWidget);
    expect(find.text('从备份恢复'), findsOneWidget);
    expect(find.text('恢复当前设备快照'), findsOneWidget);

    // Dispose the Settings backdrop explicitly. This keeps the suite free of
    // leaked animation timers even if a future default enables motion again.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
