import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonar_vault/core/performance/visual_effects.dart';
import 'package:sonar_vault/core/widgets/liquid_glass.dart';
import 'package:sonar_vault/features/library/data/library_database.dart';
import 'package:sonar_vault/features/player/presentation/hover_volume_button.dart';
import 'package:sonar_vault/features/player/presentation/now_playing_page.dart';
import 'package:sonar_vault/features/settings/application/appearance_controller.dart';

void main() {
  group('visual effects policy', () {
    test('storage values are stable and invalid values fall back safely', () {
      expect(
        VisualEffectsMode.fromStorage('energy_saver'),
        VisualEffectsMode.energySaver,
      );
      expect(VisualEffectsMode.fromStorage('off'), VisualEffectsMode.off);
      expect(
        VisualEffectsMode.fromStorage('future-value'),
        VisualEffectsMode.full,
      );
      expect(
        imageCacheBudgetBytes(
          mode: VisualEffectsMode.energySaver,
          compactPlatform: true,
        ),
        lessThan(
          imageCacheBudgetBytes(
            mode: VisualEffectsMode.full,
            compactPlatform: true,
          ),
        ),
      );
    });

    testWidgets('off removes the expensive backdrop-filter layer', (
      tester,
    ) async {
      Future<void> pump(VisualEffectsMode mode) {
        return tester.pumpWidget(
          MaterialApp(
            home: VisualEffectsScope(
              mode: mode,
              child: const LiquidGlass(
                blur: 20,
                child: SizedBox(width: 120, height: 80),
              ),
            ),
          ),
        );
      }

      await pump(VisualEffectsMode.full);
      expect(find.byType(BackdropFilter), findsOneWidget);

      await pump(VisualEffectsMode.off);
      expect(find.byType(BackdropFilter), findsNothing);
    });

    test('player ambience and vinyl ticker honor the selected policy', () {
      expect(
        shouldUseDedicatedPlayerAmbient(
          presetId: 'aurora',
          visualMode: PlayerVisualMode.vinyl,
          effectsMode: VisualEffectsMode.full,
          animationsDisabled: false,
        ),
        isTrue,
      );
      expect(
        shouldUseDedicatedPlayerAmbient(
          presetId: 'aurora',
          visualMode: PlayerVisualMode.vinyl,
          effectsMode: VisualEffectsMode.energySaver,
          animationsDisabled: false,
        ),
        isFalse,
      );
      expect(
        shouldRunVinylTicker(
          isPlaying: true,
          effectsMode: VisualEffectsMode.off,
          animationsDisabled: false,
        ),
        isFalse,
      );
      expect(videoOutputSizeFor(VisualEffectsMode.full).width, 1920);
      expect(videoOutputSizeFor(VisualEffectsMode.energySaver).width, 1280);
      expect(videoOutputSizeFor(VisualEffectsMode.off).width, 960);
      expect(
        videoOutputSizeFor(VisualEffectsMode.off).width,
        lessThanOrEqualTo(
          videoOutputSizeFor(VisualEffectsMode.energySaver).width,
        ),
      );
      expect(hoverVolumePopoverBlurFor(VisualEffectsMode.off), 0);
      expect(
        hoverVolumePopoverBlurFor(VisualEffectsMode.energySaver),
        lessThan(hoverVolumePopoverBlurFor(VisualEffectsMode.full)),
      );
      expect(
        hoverVolumePopoverShadowBlurFor(VisualEffectsMode.energySaver),
        lessThan(hoverVolumePopoverShadowBlurFor(VisualEffectsMode.full)),
      );
    });
  });

  test(
    'rapid skin and performance changes persist the last selection',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'sona-visual-effects-test-',
      );
      final database = LibraryDatabase();
      await database.initialize(databasePath: '${directory.path}/library.db');
      addTearDown(() async {
        await database.close();
        await directory.delete(recursive: true);
      });

      final controller = AppearanceController(database);
      await controller.load();
      for (var index = 0; index < 240; index++) {
        await controller.setEffectsMode(
          VisualEffectsMode.values[index % VisualEffectsMode.values.length],
        );
        await controller.selectPreset(
          backgroundPresets[index % backgroundPresets.length].id,
        );
      }
      await controller.setEffectsMode(VisualEffectsMode.energySaver);
      await controller.selectPreset('cyan_glass');

      final reloaded = AppearanceController(database);
      await reloaded.load();
      expect(reloaded.state.effectsMode, VisualEffectsMode.energySaver);
      expect(reloaded.state.presetId, 'cyan_glass');
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
