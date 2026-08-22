import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/cloud/cloud_config.dart';
import 'features/library/data/library_backup_service.dart';
import 'features/library/data/library_database.dart';
import 'features/library/domain/library_backup.dart';
import 'features/player/application/sona_audio_handler.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    const windowOptions = WindowOptions(
      title: 'Sona',
      minimumSize: Size(960, 620),
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: false,
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }
  MediaKit.ensureInitialized();

  final SonaAudioHandler audioHandler;
  if (Platform.isAndroid) {
    audioHandler = await AudioService.init(
      builder: SonaAudioHandler.new,
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.sonarvault.sona.playback',
        androidNotificationChannelName: 'Sona Playback',
        androidNotificationChannelDescription:
            'Current track information and playback controls',
        androidNotificationOngoing: false,
        androidStopForegroundOnPause: false,
        androidShowNotificationBadge: false,
      ),
    );
    final audioSession = await AudioSession.instance;
    await audioSession.configure(const AudioSessionConfiguration.music());
  } else {
    audioHandler = SonaAudioHandler();
  }

  final cloudConfig = CloudConfig.fromEnvironment();
  SupabaseClient? cloudClient;
  if (cloudConfig.isConfigured) {
    await Supabase.initialize(
      url: cloudConfig.url,
      publishableKey: cloudConfig.publishableKey,
    );
    cloudClient = Supabase.instance.client;
  }

  // A verified restore is applied before SQLite is opened. This is the only
  // point where replacing the database file is safe on every platform.
  try {
    await LibraryBackupService.applyPendingRestore();
  } on LibraryBackupException catch (error) {
    // A damaged pending restore must never prevent access to the existing
    // offline library. The marker is retained so Settings can report/retry it.
    debugPrint('Sona restore was not applied: ${error.message}');
    try {
      await LibraryBackupService.recordPendingRestoreFailure(error.message);
    } catch (statusError) {
      debugPrint(
        'Sona restore failure status could not be saved: $statusError',
      );
    }
  }
  final database = LibraryDatabase();
  await database.initialize();
  final backupService = LibraryBackupService(database: database);
  final autoBackupCoordinator = AutoBackupCoordinator(
    service: backupService,
    database: database,
  );
  await autoBackupCoordinator.start();

  runApp(
    ProviderScope(
      overrides: [
        libraryDatabaseProvider.overrideWithValue(database),
        libraryBackupServiceProvider.overrideWithValue(backupService),
        sonaAudioHandlerProvider.overrideWithValue(audioHandler),
        if (cloudClient != null)
          cloudClientProvider.overrideWithValue(cloudClient),
      ],
      child: const SonarVaultApp(),
    ),
  );
}
