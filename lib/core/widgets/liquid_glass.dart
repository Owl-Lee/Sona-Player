import 'dart:ui';

import 'package:flutter/material.dart';

/// A reusable, deliberately restrained liquid-glass surface.
///
/// The blur is real (rather than a translucent flat fill), while the layered
/// gradient and bright rim keep the edge readable over both light photos and
/// dark player artwork.
class LiquidGlass extends StatelessWidget {
  const LiquidGlass({
    super.key,
    required this.child,
    this.borderRadius = 24,
    this.blur = 20,
    this.padding = EdgeInsets.zero,
    this.tint = Colors.white,
    this.dark = false,
    this.darkOverlayAlpha = 0.26,
    this.darkShadowAlpha,
    this.borderWidth = 1.15,
  });

  final Widget child;
  final double borderRadius;
  final double blur;
  final EdgeInsetsGeometry padding;
  final Color tint;
  final bool dark;
  final double darkOverlayAlpha;
  final double? darkShadowAlpha;
  final double borderWidth;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);
    final surfaceColors = dark
        ? [
            Colors.white.withValues(alpha: 0.20),
            tint.withValues(alpha: 0.12),
            Colors.black.withValues(alpha: darkOverlayAlpha),
          ]
        : [
            // Keep light surfaces legible without bleaching the active
            // wallpaper.  Each stop carries the current theme tint so warm
            // themes stay warm and cool themes stay cool instead of becoming
            // a generic white card.
            Color.alphaBlend(
              tint.withValues(alpha: 0.16),
              Colors.white,
            ).withValues(alpha: 0.72),
            Color.alphaBlend(
              tint.withValues(alpha: 0.28),
              Colors.white,
            ).withValues(alpha: 0.68),
            Color.alphaBlend(
              tint.withValues(alpha: 0.22),
              Colors.white,
            ).withValues(alpha: 0.58),
          ];
    final rim = Colors.white.withValues(alpha: dark ? 0.58 : 0.78);

    return RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(
                alpha: dark ? (darkShadowAlpha ?? 0.30) : 0.13,
              ),
              blurRadius: dark ? 28 : 22,
              offset: const Offset(0, 9),
            ),
            BoxShadow(
              color: tint.withValues(alpha: dark ? 0.08 : 0.12),
              blurRadius: 16,
              spreadRadius: -4,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: blur <= 0
              ? _GlassSurface(
                  radius: radius,
                  padding: padding,
                  surfaceColors: surfaceColors,
                  rim: rim,
                  borderWidth: borderWidth,
                  child: child,
                )
              : BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                  child: _GlassSurface(
                    radius: radius,
                    padding: padding,
                    surfaceColors: surfaceColors,
                    rim: rim,
                    borderWidth: borderWidth,
                    child: child,
                  ),
                ),
        ),
      ),
    );
  }
}

/// Keeps the liquid colour and rim while allowing dense scrolling lists to
/// opt out of the expensive per-item backdrop capture with [LiquidGlass.blur]
/// set to zero.
class _GlassSurface extends StatelessWidget {
  const _GlassSurface({
    required this.radius,
    required this.padding,
    required this.surfaceColors,
    required this.rim,
    required this.borderWidth,
    required this.child,
  });

  final BorderRadius radius;
  final EdgeInsetsGeometry padding;
  final List<Color> surfaceColors;
  final Color rim;
  final double borderWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: const [0, 0.48, 1],
          colors: surfaceColors,
        ),
        border: Border.all(color: rim, width: borderWidth),
      ),
      child: child,
    );
  }
}
