import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path_util;
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img;

import '../../../core/performance/visual_effects.dart';
import '../../library/data/library_database.dart';

class BackgroundPreset {
  const BackgroundPreset({
    required this.id,
    required this.name,
    required this.accent,
    required this.fallbackColors,
    required this.playerScrimOpacity,
    this.tonearmColor,
    this.assetPath,
    this.playerAssetPath,
    this.desktopAssetPath,
    this.playerFocusY = 0.33,
    this.playerAssetAspectRatio = 941 / 1672,
    this.prefersLightHomeForeground = false,
  });

  final String id;
  final String name;
  final String? assetPath;
  final String? playerAssetPath;

  /// A separately composed wide image for Windows. It replaces the portrait
  /// artwork on large screens instead of relying on BoxFit to crop it.
  final String? desktopAssetPath;
  final Color accent;

  /// A calmer material color for the physical tonearm.
  ///
  /// This is deliberately separate from [accent], which may be highly
  /// saturated so interactive controls remain easy to find.
  final Color? tonearmColor;
  final List<Color> fallbackColors;
  final double playerScrimOpacity;

  /// Vertical center of the composition's record recess in the full asset.
  ///
  /// Player backgrounds deliberately use different artwork, so a single
  /// visual offset cannot keep the real record centered in every design.
  final double playerFocusY;
  final double playerAssetAspectRatio;
  final bool prefersLightHomeForeground;
}

class CustomBackground {
  const CustomBackground({required this.path, required this.accentValue});

  final String path;
  final int accentValue;

  Color get accent => Color(accentValue);

  Map<String, Object> toJson() => {'path': path, 'accent': accentValue};

  static CustomBackground? fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final filePath = value['path'];
    final accent = value['accent'];
    if (filePath is! String || accent is! int || !File(filePath).existsSync()) {
      return null;
    }
    return CustomBackground(path: filePath, accentValue: accent);
  }
}

const backgroundPresets = <BackgroundPreset>[
  BackgroundPreset(
    id: 'clean',
    name: '鎏光云纱',
    assetPath: 'assets/backgrounds/clean_player_v1.png',
    playerAssetPath: 'assets/backgrounds/clean_player_v1.png',
    desktopAssetPath: 'assets/backgrounds/clean_desktop_v1.png',
    playerFocusY: 0.285,
    accent: Color(0xFFD3A24B),
    fallbackColors: [Color(0xFFFFFBF4), Color(0xFFEAD9BE)],
    playerScrimOpacity: 0.32,
  ),
  BackgroundPreset(
    id: 'aurora',
    name: '流光极彩',
    assetPath: 'assets/backgrounds/aurora_violet_v4.png',
    playerAssetPath: 'assets/backgrounds/aurora_violet_player_v4.png',
    desktopAssetPath: 'assets/backgrounds/aurora_desktop_v1.png',
    playerFocusY: 0.300,
    playerAssetAspectRatio: 862 / 1825,
    prefersLightHomeForeground: true,
    accent: Color(0xFF9B63FF),
    tonearmColor: Color(0xFF9C7BC8),
    fallbackColors: [Color(0xFF24104B), Color(0xFF6F35C9)],
    playerScrimOpacity: 0.18,
  ),
  BackgroundPreset(
    id: 'sakura',
    name: '樱花汽水',
    assetPath: 'assets/backgrounds/sakura_soda_v2.png',
    playerAssetPath: 'assets/backgrounds/sakura_soda_v2.png',
    desktopAssetPath: 'assets/backgrounds/sakura_soda_desktop_v2.png',
    playerFocusY: 0.320,
    accent: Color(0xFFFF5F9E),
    tonearmColor: Color(0xFFE7A9BD),
    fallbackColors: [Color(0xFFFFB9D6), Color(0xFFA9E8FF)],
    playerScrimOpacity: 0.27,
  ),
  BackgroundPreset(
    id: 'farm',
    name: '鎏金麦境',
    assetPath: 'assets/backgrounds/farm_photo_v3.png',
    playerAssetPath: 'assets/backgrounds/farm_photo_player_v3.png',
    desktopAssetPath: 'assets/backgrounds/farm_desktop_v1.png',
    playerFocusY: 0.300,
    prefersLightHomeForeground: true,
    accent: Color(0xFFDFA338),
    fallbackColors: [Color(0xFF120B05), Color(0xFF6F3D10)],
    playerScrimOpacity: 0.24,
  ),
  BackgroundPreset(
    id: 'midnight',
    name: '青柠软糖',
    assetPath: 'assets/backgrounds/lime_jelly_v1.png',
    playerAssetPath: 'assets/backgrounds/lime_jelly_player_v2.png',
    desktopAssetPath: 'assets/backgrounds/lime_jelly_desktop_v1.png',
    playerFocusY: 0.335,
    accent: Color(0xFF68D83F),
    fallbackColors: [Color(0xFFE7F8D5), Color(0xFF72D982)],
    playerScrimOpacity: 0.24,
  ),
  BackgroundPreset(
    id: 'vinyl_bloom',
    name: '黑胶花信',
    assetPath: 'assets/backgrounds/vinyl_bloom_v1.png',
    playerAssetPath: 'assets/backgrounds/vinyl_bloom_player_v1.png',
    desktopAssetPath: 'assets/backgrounds/vinyl_bloom_desktop_v1.png',
    playerFocusY: 0.300,
    accent: Color(0xFFFF5B78),
    tonearmColor: Color(0xFFE3A197),
    fallbackColors: [Color(0xFFFFB29B), Color(0xFFFFE3C7)],
    playerScrimOpacity: 0.25,
  ),
  BackgroundPreset(
    id: 'mist_orbs',
    name: '雾紫星环',
    assetPath: 'assets/backgrounds/mist_orbs_v2.png',
    playerAssetPath: 'assets/backgrounds/mist_orbs_player_v2.png',
    desktopAssetPath: 'assets/backgrounds/mist_orbs_desktop_v2.png',
    playerFocusY: 0.325,
    accent: Color(0xFF8B6FD1),
    tonearmColor: Color(0xFFB7A6D8),
    fallbackColors: [Color(0xFFE7DDF5), Color(0xFFCBBCEB)],
    playerScrimOpacity: 0.22,
  ),
  BackgroundPreset(
    id: 'obsidian_rings',
    name: '曜石光环',
    assetPath: 'assets/backgrounds/obsidian_rings_v2.png',
    playerAssetPath: 'assets/backgrounds/obsidian_rings_player_v2.png',
    desktopAssetPath: 'assets/backgrounds/obsidian_rings_desktop_v2.png',
    playerFocusY: 0.305,
    prefersLightHomeForeground: true,
    accent: Color(0xFFE66E2F),
    tonearmColor: Color(0xFFB97952),
    fallbackColors: [Color(0xFF120D0B), Color(0xFF4A2418)],
    playerScrimOpacity: 0.12,
  ),
  BackgroundPreset(
    id: 'magma',
    name: '熔岩脉冲',
    assetPath: 'assets/backgrounds/magma_desktop_v1.png',
    playerAssetPath: 'assets/backgrounds/magma_desktop_v1.png',
    desktopAssetPath: 'assets/backgrounds/magma_desktop_v1.png',
    accent: Color(0xFFFF6A2D),
    tonearmColor: Color(0xFFE68A60),
    fallbackColors: [Color(0xFF120405), Color(0xFF4E1008)],
    playerScrimOpacity: 0.18,
    prefersLightHomeForeground: true,
  ),
  BackgroundPreset(
    id: 'cyan_glass',
    name: '冰晶琉璃',
    assetPath: 'assets/backgrounds/cyan_glass_v1.png',
    playerAssetPath: 'assets/backgrounds/cyan_glass_v1.png',
    desktopAssetPath: 'assets/backgrounds/cyan_glass_desktop_v1.png',
    playerFocusY: 0.318,
    accent: Color(0xFF16A9D1),
    tonearmColor: Color(0xFF8ECAD8),
    fallbackColors: [Color(0xFFCDEFF6), Color(0xFF6ED0E6)],
    playerScrimOpacity: 0.22,
  ),
  BackgroundPreset(
    id: 'orange_summer',
    name: '橙汽跃夏',
    assetPath: 'assets/backgrounds/orange_summer_v1.png',
    playerAssetPath: 'assets/backgrounds/orange_summer_player_v1.png',
    desktopAssetPath: 'assets/backgrounds/orange_summer_desktop_v1.png',
    playerFocusY: 0.305,
    playerAssetAspectRatio: 853 / 1844,
    accent: Color(0xFFFF7A18),
    tonearmColor: Color(0xFFE7A056),
    fallbackColors: [Color(0xFFFFC43D), Color(0xFFF06418)],
    playerScrimOpacity: 0.28,
  ),
  BackgroundPreset(
    id: 'titanium_silver',
    name: '钛银流界',
    assetPath: 'assets/backgrounds/titanium_silver_v1.png',
    playerAssetPath: 'assets/backgrounds/titanium_silver_player_v1.png',
    desktopAssetPath: 'assets/backgrounds/titanium_silver_desktop_v1.png',
    playerFocusY: 0.305,
    playerAssetAspectRatio: 841 / 1870,
    prefersLightHomeForeground: true,
    accent: Color(0xFF8E99A6),
    tonearmColor: Color(0xFFB8BEC5),
    fallbackColors: [Color(0xFF111418), Color(0xFF424850)],
    playerScrimOpacity: 0.16,
  ),
  BackgroundPreset(
    id: 'wine_nocturne',
    name: '醇红夜幕',
    // Keep the wine leather as a quiet backdrop: the framed texture stays at
    // the far edges so it never competes with the turntable or player panel.
    assetPath: 'assets/backgrounds/wine_nocturne_unframed_v4.png',
    playerAssetPath: 'assets/backgrounds/wine_nocturne_unframed_v4.png',
    desktopAssetPath: 'assets/backgrounds/wine_nocturne_unframed_v4.png',
    playerFocusY: 0.305,
    playerAssetAspectRatio: 853 / 1844,
    prefersLightHomeForeground: true,
    accent: Color(0xFFA85267),
    tonearmColor: Color(0xFFA67A7D),
    fallbackColors: [Color(0xFF16080C), Color(0xFF541622)],
    playerScrimOpacity: 0.10,
  ),
  BackgroundPreset(
    id: 'navy_tide',
    name: '深海静潮',
    assetPath: 'assets/backgrounds/navy_tide_v2.png',
    playerAssetPath: 'assets/backgrounds/navy_tide_player_v2.png',
    desktopAssetPath: 'assets/backgrounds/navy_tide_desktop_v1.png',
    playerFocusY: 0.305,
    playerAssetAspectRatio: 841 / 1870,
    prefersLightHomeForeground: true,
    accent: Color(0xFF5B87B3),
    tonearmColor: Color(0xFF7893AB),
    fallbackColors: [Color(0xFF07121F), Color(0xFF173653)],
    playerScrimOpacity: 0.10,
  ),
];

class AppearanceState {
  const AppearanceState({
    this.presetId = 'aurora',
    this.customBackgroundPath,
    this.customAccent,
    this.customBackgrounds = const [],
    this.effectsMode = VisualEffectsMode.full,
    this.isLoading = true,
  });

  final String presetId;
  final String? customBackgroundPath;
  final Color? customAccent;
  final List<CustomBackground> customBackgrounds;
  final VisualEffectsMode effectsMode;
  final bool isLoading;

  bool get usesCustom =>
      customBackgroundPath != null && customBackgroundPath!.isNotEmpty;

  BackgroundPreset get preset => backgroundPresets.firstWhere(
    (item) => item.id == presetId,
    orElse: () => backgroundPresets.first,
  );

  Color get accent =>
      usesCustom && customAccent != null ? customAccent! : preset.accent;

  AppearanceState copyWith({
    String? presetId,
    String? customBackgroundPath,
    Color? customAccent,
    List<CustomBackground>? customBackgrounds,
    VisualEffectsMode? effectsMode,
    bool clearCustomBackground = false,
    bool? isLoading,
  }) {
    return AppearanceState(
      presetId: presetId ?? this.presetId,
      customBackgroundPath: clearCustomBackground
          ? null
          : customBackgroundPath ?? this.customBackgroundPath,
      customAccent: clearCustomBackground
          ? null
          : customAccent ?? this.customAccent,
      customBackgrounds: customBackgrounds ?? this.customBackgrounds,
      effectsMode: effectsMode ?? this.effectsMode,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

final appearanceControllerProvider =
    StateNotifierProvider<AppearanceController, AppearanceState>((ref) {
      final controller = AppearanceController(
        ref.watch(libraryDatabaseProvider),
      );
      Future<void>.microtask(controller.load);
      return controller;
    });

class AppearanceController extends StateNotifier<AppearanceState> {
  AppearanceController(this._database) : super(const AppearanceState());

  final LibraryDatabase _database;

  Future<void> load() async {
    final preset = await _database.getSetting('appearance.preset');
    final requestedPreset = preset ?? 'aurora';
    final resolvedPreset =
        backgroundPresets.any((item) => item.id == requestedPreset)
        ? requestedPreset
        : 'aurora';
    if (resolvedPreset != requestedPreset) {
      await _database.setSetting('appearance.preset', resolvedPreset);
    }
    final customPath = await _database.getSetting('appearance.custom_path');
    final customAccentValue = await _database.getSetting(
      'appearance.custom_accent',
    );
    final customBackgroundsValue = await _database.getSetting(
      'appearance.custom_backgrounds',
    );
    final storedEffectsMode = await _database.getSetting(
      'appearance.effects_mode',
    );
    final effectsMode = VisualEffectsMode.fromStorage(storedEffectsMode);
    _applyImageCacheBudget(effectsMode);
    if (storedEffectsMode != null &&
        storedEffectsMode != effectsMode.storageValue) {
      await _database.setSetting(
        'appearance.effects_mode',
        effectsMode.storageValue,
      );
    }
    final customBackgrounds = <CustomBackground>[];
    if (customBackgroundsValue != null && customBackgroundsValue.isNotEmpty) {
      try {
        final decoded = jsonDecode(customBackgroundsValue);
        if (decoded is List) {
          customBackgrounds.addAll(
            decoded
                .map(CustomBackground.fromJson)
                .whereType<CustomBackground>(),
          );
        }
      } on FormatException {
        // Ignore a damaged legacy setting and keep the built-in backgrounds.
      }
    }
    if (customPath != null &&
        File(customPath).existsSync() &&
        !customBackgrounds.any((item) => item.path == customPath)) {
      customBackgrounds.insert(
        0,
        CustomBackground(
          path: customPath,
          accentValue: int.tryParse(customAccentValue ?? '') ?? 0xFFFF4F6D,
        ),
      );
    }
    state = state.copyWith(
      presetId: resolvedPreset,
      customBackgroundPath: customPath != null && File(customPath).existsSync()
          ? customPath
          : null,
      customAccent: customAccentValue == null || customAccentValue.isEmpty
          ? null
          : Color(int.tryParse(customAccentValue) ?? 0xFFFF4F6D),
      customBackgrounds: customBackgrounds.take(5).toList(growable: false),
      effectsMode: effectsMode,
      clearCustomBackground:
          customPath == null || !File(customPath).existsSync(),
      isLoading: false,
    );
  }

  Future<void> selectPreset(String presetId) async {
    state = state.copyWith(presetId: presetId, clearCustomBackground: true);
    await _database.setSetting('appearance.preset', presetId);
    await _database.setSetting('appearance.custom_path', '');
    await _database.setSetting('appearance.custom_accent', '');
  }

  Future<void> setEffectsMode(VisualEffectsMode mode) async {
    if (state.effectsMode == mode) return;
    _applyImageCacheBudget(mode);
    state = state.copyWith(effectsMode: mode);
    await _database.setSetting('appearance.effects_mode', mode.storageValue);
  }

  void _applyImageCacheBudget(VisualEffectsMode mode) {
    final compactPlatform =
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
    PaintingBinding.instance.imageCache.maximumSizeBytes =
        imageCacheBudgetBytes(mode: mode, compactPlatform: compactPlatform);
    PaintingBinding.instance.imageCache.maximumSize = switch (mode) {
      VisualEffectsMode.full => compactPlatform ? 120 : 180,
      VisualEffectsMode.energySaver => compactPlatform ? 80 : 120,
      VisualEffectsMode.off => compactPlatform ? 60 : 90,
    };
  }

  Future<void> selectCustomBackground(CustomBackground background) async {
    if (!File(background.path).existsSync()) return;
    state = state.copyWith(
      customBackgroundPath: background.path,
      customAccent: background.accent,
    );
    await _database.setSetting('appearance.custom_path', background.path);
    await _database.setSetting(
      'appearance.custom_accent',
      '${background.accentValue}',
    );
  }

  Future<Uint8List?> pickCustomBackground() async {
    final picked = await FilePicker.pickFile(type: FileType.image);
    if (picked == null) return null;
    return picked.readAsBytes();
  }

  Future<String> saveCustomBackground(Uint8List croppedBytes) async {
    // Decoding a 4K/8K user photo and sampling its accent on the UI isolate
    // stalls every animation in the app. Prepare it off-thread and cap the
    // stored wallpaper to a practical display resolution at the same time.
    final prepared = await compute(_prepareCustomBackground, croppedBytes);
    final backgroundBytes = prepared?.bytes ?? croppedBytes;
    final accent = prepared == null
        ? state.preset.accent
        : Color(prepared.accentValue);
    final support = await getApplicationSupportDirectory();
    final directory = Directory(
      path_util.join(support.path, 'SonarVault', 'backgrounds'),
    );
    await directory.create(recursive: true);

    // A unique filename deliberately changes FileImage's cache key. Reusing the
    // old fixed path made the fourth/fifth replacement look as if it had frozen.
    final destination = path_util.join(
      directory.path,
      'custom_${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    await File(destination).writeAsBytes(backgroundBytes, flush: true);
    final item = CustomBackground(
      path: destination,
      accentValue: accent.toARGB32(),
    );
    final backgrounds = [
      item,
      ...state.customBackgrounds.where((entry) => entry.path != destination),
    ].take(5).toList(growable: false);
    state = state.copyWith(
      customBackgroundPath: destination,
      customAccent: accent,
      customBackgrounds: backgrounds,
    );
    await _database.setSetting('appearance.custom_path', destination);
    await _database.setSetting(
      'appearance.custom_accent',
      '${accent.toARGB32()}',
    );
    await _database.setSetting(
      'appearance.custom_backgrounds',
      jsonEncode(backgrounds.map((entry) => entry.toJson()).toList()),
    );
    return destination;
  }
}

typedef _PreparedBackground = ({Uint8List bytes, int accentValue});

_PreparedBackground? _prepareCustomBackground(Uint8List bytes) {
  var decoded = img.decodeImage(bytes);
  if (decoded == null) return null;

  const maxEdge = 2560;
  if (decoded.width > maxEdge || decoded.height > maxEdge) {
    decoded = decoded.width >= decoded.height
        ? img.copyResize(
            decoded,
            width: maxEdge,
            interpolation: img.Interpolation.average,
          )
        : img.copyResize(
            decoded,
            height: maxEdge,
            interpolation: img.Interpolation.average,
          );
  }

  final sample = img.copyResize(decoded, width: 48, height: 48);
  var red = 0.0;
  var green = 0.0;
  var blue = 0.0;
  var weightTotal = 0.0;
  for (final pixel in sample) {
    final channels = [pixel.r, pixel.g, pixel.b];
    final maxChannel = channels.reduce((a, b) => a > b ? a : b);
    final minChannel = channels.reduce((a, b) => a < b ? a : b);
    final saturation = (maxChannel - minChannel) / 255.0;
    final weight = 0.35 + saturation * 1.65;
    red += pixel.r * weight;
    green += pixel.g * weight;
    blue += pixel.b * weight;
    weightTotal += weight;
  }
  final average = Color.fromARGB(
    255,
    (red / weightTotal).round(),
    (green / weightTotal).round(),
    (blue / weightTotal).round(),
  );
  final hsl = HSLColor.fromColor(average);
  final accent = hsl
      .withSaturation(hsl.saturation.clamp(0.42, 0.78))
      .withLightness(hsl.lightness.clamp(0.38, 0.58))
      .toColor();
  return (
    bytes: Uint8List.fromList(img.encodeJpg(decoded, quality: 90)),
    accentValue: accent.toARGB32(),
  );
}
