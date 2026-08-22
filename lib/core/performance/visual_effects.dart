import 'package:flutter/widgets.dart';

/// Controls decorative rendering cost without changing playback behavior.
enum VisualEffectsMode {
  /// All wallpaper ambience, particles and full-strength glass blur.
  full('full'),

  /// Lower-rate ambience, fewer particles and a cheaper glass blur radius.
  energySaver('energy_saver'),

  /// Static wallpaper surfaces with no decorative animation or backdrop blur.
  off('off');

  const VisualEffectsMode(this.storageValue);

  final String storageValue;

  static VisualEffectsMode fromStorage(String? value) {
    return VisualEffectsMode.values.firstWhere(
      (mode) => mode.storageValue == value,
      orElse: () => VisualEffectsMode.full,
    );
  }

  bool get allowsAmbientMotion => this != VisualEffectsMode.off;

  int get ambientFramesPerSecond => switch (this) {
    VisualEffectsMode.full => 24,
    VisualEffectsMode.energySaver => 12,
    VisualEffectsMode.off => 0,
  };

  double get particleDensity => switch (this) {
    VisualEffectsMode.full => 1,
    VisualEffectsMode.energySaver => 0.52,
    VisualEffectsMode.off => 0,
  };

  double get blurScale => switch (this) {
    VisualEffectsMode.full => 1,
    VisualEffectsMode.energySaver => 0.55,
    VisualEffectsMode.off => 0,
  };

  double get imageDecodeScale => switch (this) {
    VisualEffectsMode.full => 1,
    VisualEffectsMode.energySaver => 0.82,
    VisualEffectsMode.off => 0.72,
  };
}

int imageCacheBudgetBytes({
  required VisualEffectsMode mode,
  required bool compactPlatform,
}) {
  final megabytes = switch ((mode, compactPlatform)) {
    (VisualEffectsMode.full, false) => 96,
    (VisualEffectsMode.full, true) => 56,
    (VisualEffectsMode.energySaver, false) => 56,
    (VisualEffectsMode.energySaver, true) => 36,
    (VisualEffectsMode.off, false) => 40,
    (VisualEffectsMode.off, true) => 28,
  };
  return megabytes * 1024 * 1024;
}

/// Makes the selected performance policy available to low-level glass
/// surfaces without coupling the core widgets to Riverpod or feature code.
class VisualEffectsScope extends InheritedWidget {
  const VisualEffectsScope({
    super.key,
    required this.mode,
    required super.child,
  });

  final VisualEffectsMode mode;

  static VisualEffectsMode maybeOf(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<VisualEffectsScope>()
            ?.mode ??
        VisualEffectsMode.full;
  }

  @override
  bool updateShouldNotify(VisualEffectsScope oldWidget) =>
      oldWidget.mode != mode;
}
