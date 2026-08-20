import 'package:flutter/material.dart';

abstract final class AppColors {
  static const background = Color(0xFFF5F7FA);
  static const sidebar = Color(0xFFF0F3F7);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceHigh = Color(0xFFF7F8FB);
  static const outline = Color(0xFFE5E9F0);
  static const accent = Color(0xFFFF4965);
  static const accentDark = Color(0xFFE73352);
  // These sit directly on artwork as well as on surfaces.  Keep the neutral
  // text deliberately deep so labels stay readable on bright themes.
  static const ink = Color(0xFF101A2E);
  static const textPrimary = ink;
  static const textSecondary = Color(0xFF34445C);
  static const mint = accent;
  static const lavender = Color(0xFF6E74F7);
  static const coral = accent;
  static const success = Color(0xFF22A879);
  static const playerInk = Color(0xFF0B1020);
}

abstract final class AppTheme {
  /// Compact music-row typography, tuned to the same restrained hierarchy as
  /// modern desktop sidebars: titles stay crisp without looking artificially
  /// bold, while artist/album metadata sits one quiet step below.
  static const trackTitleStyle = TextStyle(
    color: AppColors.ink,
    fontSize: 14,
    height: 1.24,
    fontWeight: FontWeight.w500,
    letterSpacing: 0,
  );

  static const trackSubtitleStyle = TextStyle(
    color: AppColors.textSecondary,
    fontSize: 12,
    height: 1.24,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
  );

  static ThemeData get light {
    const colorScheme = ColorScheme.light(
      primary: AppColors.accent,
      onPrimary: Colors.white,
      secondary: AppColors.lavender,
      onSecondary: Colors.white,
      surface: AppColors.surface,
      onSurface: AppColors.ink,
      error: Color(0xFFE33E4F),
      outline: AppColors.outline,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.background,
      canvasColor: AppColors.sidebar,
      dividerColor: AppColors.outline,
      splashColor: AppColors.accent.withValues(alpha: 0.07),
      highlightColor: AppColors.accent.withValues(alpha: 0.04),
      // Segoe UI Variable is the Windows equivalent of Apple's clean system
      // typography. YaHei UI supplies screen-hinted Simplified/Traditional
      // Chinese glyphs; the remaining entries keep the same intent on macOS
      // and Android instead of falling back to Flutter's unrelated defaults.
      fontFamily: 'Segoe UI Variable',
      fontFamilyFallback: const [
        'Microsoft YaHei UI',
        'Microsoft YaHei',
        'PingFang SC',
        'PingFang TC',
        'Noto Sans CJK SC',
        'Noto Sans CJK TC',
      ],
      textTheme: const TextTheme(
        displaySmall: TextStyle(
          color: AppColors.ink,
          fontSize: 34,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.45,
        ),
        headlineMedium: TextStyle(
          color: AppColors.ink,
          fontSize: 28,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.25,
        ),
        titleLarge: TextStyle(
          color: AppColors.ink,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
        titleMedium: TextStyle(
          color: AppColors.ink,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: TextStyle(
          color: AppColors.ink,
          fontSize: 15,
          height: 1.4,
          fontWeight: FontWeight.w400,
        ),
        bodyMedium: TextStyle(
          color: AppColors.textSecondary,
          fontSize: 14,
          height: 1.36,
          fontWeight: FontWeight.w400,
        ),
        labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF1F3F7),
        hintStyle: const TextStyle(color: AppColors.textSecondary),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.accent, width: 1.3),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.ink,
          backgroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 13),
          side: const BorderSide(color: AppColors.outline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: AppColors.textSecondary,
          highlightColor: AppColors.accent.withValues(alpha: 0.08),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? AppColors.ink
                : AppColors.textSecondary,
          ),
          textStyle: WidgetStateProperty.resolveWith(
            (states) => TextStyle(
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w900
                  : FontWeight.w600,
            ),
          ),
          side: WidgetStateProperty.resolveWith(
            (states) => BorderSide(
              color: states.contains(WidgetState.selected)
                  ? AppColors.accent
                  : const Color(0xFFCCD4E0),
              width: states.contains(WidgetState.selected) ? 1.4 : 1,
            ),
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? AppColors.accent.withValues(alpha: 0.13)
                : Colors.white.withValues(alpha: 0.72),
          ),
        ),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: AppColors.accent,
        inactiveTrackColor: AppColors.outline,
        thumbColor: AppColors.accent,
        overlayColor: Color(0x22FF4965),
        trackHeight: 3,
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: Color(0x1AFF4965),
        height: 66,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.ink,
        contentTextStyle: const TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
    );
  }
}
