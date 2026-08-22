import 'package:flutter_test/flutter_test.dart';
import 'package:sonar_vault/core/performance/visual_effects.dart';
import 'package:sonar_vault/features/settings/presentation/widgets/appearance_backdrop.dart';

void main() {
  group('ambient wallpaper motion', () {
    test('runs only for a visible animated built-in skin', () {
      expect(
        shouldAnimateAmbientSkin(
          presetId: 'farm',
          usesCustomBackground: false,
          animationsDisabled: false,
          routeIsCurrent: true,
        ),
        isTrue,
      );
    });

    test('stops when hidden, disabled, custom, or intentionally static', () {
      bool enabled({
        String presetId = 'farm',
        bool custom = false,
        bool disabled = false,
        bool current = true,
      }) => shouldAnimateAmbientSkin(
        presetId: presetId,
        usesCustomBackground: custom,
        animationsDisabled: disabled,
        routeIsCurrent: current,
      );

      expect(enabled(custom: true), isFalse);
      expect(enabled(disabled: true), isFalse);
      expect(enabled(current: false), isFalse);
      expect(enabled(presetId: 'navy_tide'), isFalse);
      expect(enabled(presetId: 'magma'), isFalse);
    });

    test('energy saver keeps a capped ambience while off disables it', () {
      bool enabled(VisualEffectsMode mode) => shouldAnimateAmbientSkin(
        presetId: 'farm',
        usesCustomBackground: false,
        animationsDisabled: false,
        routeIsCurrent: true,
        effectsMode: mode,
      );

      expect(enabled(VisualEffectsMode.energySaver), isTrue);
      expect(
        VisualEffectsMode.energySaver.ambientFramesPerSecond,
        lessThan(VisualEffectsMode.full.ambientFramesPerSecond),
      );
      expect(enabled(VisualEffectsMode.off), isFalse);
    });
  });
}
