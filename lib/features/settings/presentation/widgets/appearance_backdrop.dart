import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../application/appearance_controller.dart';

class AppearanceBackdrop extends StatelessWidget {
  const AppearanceBackdrop({
    super.key,
    required this.appearance,
    this.forPlayer = false,
    this.usePlayerComposition = false,
    this.vividContent = false,
  });

  final AppearanceState appearance;
  final bool forPlayer;
  final bool usePlayerComposition;
  final bool vividContent;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 760;
    final preset = appearance.preset;
    final customFile = appearance.usesCustom
        ? File(appearance.customBackgroundPath!)
        : null;
    final wantsPlayerComposition = forPlayer || usePlayerComposition;
    final portraitAssetPath = wantsPlayerComposition
        ? preset.playerAssetPath ?? preset.assetPath
        : preset.assetPath ?? preset.playerAssetPath;
    final builtInAssetPath = !compact && !appearance.usesCustom
        ? preset.desktopAssetPath ?? portraitAssetPath
        : portraitAssetPath;
    final image = customFile != null && customFile.existsSync()
        ? FileImage(customFile) as ImageProvider
        : builtInAssetPath == null
        ? null
        : AssetImage(builtInAssetPath) as ImageProvider;

    final imageKey = customFile != null && customFile.existsSync()
        ? customFile.path
        : builtInAssetPath ?? 'gradient-only';
    final highQualityPlayerArtwork =
        forPlayer && !appearance.usesCustom && preset.id == 'midnight';
    final scrim = forPlayer
        ? LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(
                alpha: appearance.usesCustom ? 0.32 : preset.playerScrimOpacity,
              ),
              Colors.black.withValues(
                alpha: appearance.usesCustom
                    ? 0.39
                    : preset.playerScrimOpacity + 0.08,
              ),
            ],
          )
        : vividContent &&
              !appearance.usesCustom &&
              preset.prefersLightHomeForeground
        ? LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.black.withValues(alpha: 0.10),
              Colors.black.withValues(alpha: 0.17),
            ],
          )
        : LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withValues(
                alpha: vividContent
                    ? appearance.usesCustom
                          ? 0.24
                          : 0.12
                    : compact
                    ? 0.38
                    : 0.44,
              ),
              Colors.white.withValues(
                alpha: vividContent
                    ? appearance.usesCustom
                          ? 0.32
                          : 0.20
                    : compact
                    ? 0.48
                    : 0.54,
              ),
            ],
          );

    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: preset.fallbackColors,
            ),
          ),
        ),
        // Do not cross-fade two full-screen photos behind the player's glass
        // panels.  That forces every BackdropFilter to sample and blur two
        // changing 1080p layers for ~180ms, which is the source of the skin
        // switch hitch on Windows. The picker has already put its thumbnails
        // in Flutter's image cache; swapping the cached image in one composed
        // frame is both cleaner and substantially cheaper.
        RepaintBoundary(
          child: image == null
              ? const SizedBox.expand()
              : Image(
                  key: ValueKey(imageKey),
                  image: image,
                  fit: BoxFit.cover,
                  filterQuality: highQualityPlayerArtwork
                      ? FilterQuality.high
                      : FilterQuality.low,
                  gaplessPlayback: true,
                ),
        ),
        if (!appearance.usesCustom)
          IgnorePointer(child: _AmbientSkinEffect(presetId: preset.id)),
        AnimatedContainer(
          duration: const Duration(milliseconds: 170),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(gradient: scrim),
        ),
      ],
    );
  }
}

/// A low-contrast motion layer that gives the desktop backgrounds depth
/// without animating any interactive surface. Every preset gets one visual
/// language; imported personal wallpapers deliberately stay untouched.
class _AmbientSkinEffect extends StatefulWidget {
  const _AmbientSkinEffect({required this.presetId});

  final String presetId;

  @override
  State<_AmbientSkinEffect> createState() => _AmbientSkinEffectState();
}

class _AmbientSkinEffectState extends State<_AmbientSkinEffect>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 22),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          painter: _AmbientSkinPainter(widget.presetId, _controller.value),
          size: Size.infinite,
          isComplex: false,
          willChange: true,
        ),
      ),
    );
  }
}

class _AmbientSkinPainter extends CustomPainter {
  const _AmbientSkinPainter(this.presetId, this.progress);

  final String presetId;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    switch (presetId) {
      case 'farm':
        _paintFallingLeaves(canvas, size);
      case 'sakura':
        _paintPetals(canvas, size);
      case 'navy_tide':
        // The sea wallpaper already carries depth. Extra bubbles look like
        // decorative stickers, so this skin intentionally stays still.
        return;
      case 'aurora':
        _paintAurora(canvas, size);
      case 'obsidian_rings':
        _paintEmbers(canvas, size);
      case 'cyan_glass':
        _paintCrystalReflections(canvas, size);
      case 'titanium_silver':
        _paintMetallicSweep(canvas, size);
      case 'mist_orbs':
        _paintMistOrbs(canvas, size);
      case 'vinyl_bloom':
        _paintBloomPetals(canvas, size);
      case 'midnight':
        _paintLimeBubbles(canvas, size);
      case 'orange_summer':
        _paintSunFlecks(canvas, size);
      case 'wine_nocturne':
        _paintWineVeil(canvas, size);
      case 'clean':
        _paintSilkGlows(canvas, size);
    }
  }

  void _paintFallingLeaves(Canvas canvas, Size size) {
    final desktop = size.shortestSide >= 700;
    final count = desktop ? 24 : 14;
    for (var index = 0; index < count; index++) {
      final cycle = (progress * .42 + index * .173) % 1;
      final leafSize = (desktop ? 30.0 : 20.0) + (index % 4) * 4.0;
      final x =
          (index * 137.0 % size.width) +
          math.sin(cycle * math.pi * 3 + index) * (desktop ? 54 : 32);
      final y = -leafSize + cycle * (size.height + leafSize * 2);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(cycle * math.pi * 2 + index * .7);
      final leaf = Path()
        ..moveTo(0, -leafSize * .55)
        ..cubicTo(
          leafSize * .54,
          -leafSize * .22,
          leafSize * .44,
          leafSize * .43,
          0,
          leafSize * .58,
        )
        ..cubicTo(
          -leafSize * .44,
          leafSize * .43,
          -leafSize * .54,
          -leafSize * .22,
          0,
          -leafSize * .55,
        )
        ..close();
      canvas.drawPath(
        leaf,
        Paint()..color = const Color(0xFFFFD36A).withValues(alpha: 0.38),
      );
      canvas.drawLine(
        Offset(0, -leafSize * .37),
        Offset(0, leafSize * .42),
        Paint()
          ..color = const Color(0xFFBF7622).withValues(alpha: 0.30)
          ..strokeWidth = 1.0,
      );
      canvas.restore();
    }
  }

  void _paintPetals(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFFFE0EC).withValues(alpha: 0.38);
    final count = size.shortestSide >= 700 ? 20 : 12;
    for (var index = 0; index < count; index++) {
      final cycle = (progress * .72 + index * .149) % 1;
      final x = (index * 101.0 % size.width) + math.sin(cycle * 9 + index) * 38;
      final y = -18 + cycle * (size.height + 42);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(cycle * math.pi * 3 + index);
      canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: 13, height: 7),
        paint,
      );
      canvas.restore();
    }
  }

  void _paintAurora(Canvas canvas, Size size) {
    final phase = progress * math.pi * 2;
    for (var band = 0; band < 3; band++) {
      final path = Path()..moveTo(-30, size.height * (.16 + band * .13));
      for (var x = 0.0; x <= size.width + 40; x += 36) {
        final y =
            size.height * (.16 + band * .13) +
            math.sin(x / 128 + phase + band * 1.3) * (18 + band * 5);
        path.lineTo(x, y);
      }
      final paint = Paint()
        ..color = const Color(0xFFDAB8FF).withValues(alpha: .10 - band * .018)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12 - band * 2
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
      canvas.drawPath(path, paint);
    }
  }

  void _paintEmbers(Canvas canvas, Size size) {
    final count = size.shortestSide >= 700 ? 19 : 11;
    for (var index = 0; index < count; index++) {
      final cycle = (progress * .35 + index * .137) % 1;
      final x = index * 149.0 % size.width + math.sin(cycle * 7 + index) * 22;
      final y = size.height - cycle * (size.height + 20);
      canvas.drawCircle(
        Offset(x, y),
        1.2 + index % 3,
        Paint()..color = const Color(0xFFFFA263).withValues(alpha: .38),
      );
    }
  }

  void _paintCrystalReflections(Canvas canvas, Size size) {
    final count = size.shortestSide >= 700 ? 12 : 7;
    for (var index = 0; index < count; index++) {
      final cycle = (progress * .18 + index * .19) % 1;
      final x = index * 191.0 % size.width + math.sin(cycle * 6) * 24;
      final y = index * 117.0 % size.height + math.cos(cycle * 5) * 16;
      // Larger facets remain sparse, so the glass reads as calm refraction
      // instead of a layer of confetti on top of the wallpaper.
      final r = 14.0 + index % 4 * 6;
      final facet = Path()
        ..moveTo(x, y - r)
        ..lineTo(x + r * .7, y + r * .55)
        ..lineTo(x - r * .8, y + r * .42)
        ..close();
      canvas.drawPath(
        facet,
        Paint()..color = const Color(0xFFDFFBFF).withValues(alpha: .12),
      );
    }
  }

  void _paintMetallicSweep(Canvas canvas, Size size) {
    final x = ((progress * 1.15) % 1) * (size.width + 280) - 140;
    final paint = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.transparent,
          const Color(0xFFF5FAFF).withValues(alpha: .18),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(x - 80, 0, 160, size.height));
    canvas.save();
    canvas.skew(-.22, 0);
    canvas.drawRect(Rect.fromLTWH(x, 0, 84, size.height), paint);
    canvas.restore();
  }

  void _paintMistOrbs(Canvas canvas, Size size) {
    for (var index = 0; index < 4; index++) {
      final cycle = (progress * .16 + index * .24) % 1;
      final r = size.shortestSide * (.10 + index * .018);
      final x = (index * .31 + cycle * .18) * size.width;
      final y =
          (.18 + index * .20 + math.sin(cycle * math.pi * 2) * .05) *
          size.height;
      canvas.drawCircle(
        Offset(x, y),
        r,
        Paint()
          ..color = const Color(0xFFE7D7FF).withValues(alpha: .07)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22),
      );
    }
  }

  void _paintBloomPetals(Canvas canvas, Size size) {
    final count = size.shortestSide >= 700 ? 12 : 8;
    final petalWidth = size.shortestSide >= 700 ? 25.0 : 22.0;
    final petalHeight = size.shortestSide >= 700 ? 11.0 : 9.5;
    for (var index = 0; index < count; index++) {
      final cycle = (progress * .31 + index * .19) % 1;
      final x = index * 173.0 % size.width + math.sin(cycle * 5) * 20;
      final y = size.height + 20 - cycle * (size.height + 40);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(index + cycle * 5);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset.zero,
          width: petalWidth,
          height: petalHeight,
        ),
        Paint()..color = const Color(0xFFFFD1CF).withValues(alpha: .25),
      );
      canvas.restore();
    }
  }

  void _paintLimeBubbles(Canvas canvas, Size size) {
    // Soft oversized jelly highlights create a visible breathing effect,
    // rather than repeating the same small particle field as other skins.
    for (var index = 0; index < 4; index++) {
      final phase = progress * math.pi * 2 + index * 1.6;
      final scale = 1 + math.sin(phase) * .08;
      final width = size.width * (.18 + index * .035) * scale;
      final height = width * (.56 + math.cos(phase) * .05);
      final x = (index * .29 + .08) * size.width + math.sin(phase) * 14;
      final y = (.16 + index * .21) * size.height + math.cos(phase) * 11;
      final rect = Rect.fromCenter(
        center: Offset(x, y),
        width: width,
        height: height,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(height / 2)),
        Paint()
          ..color = const Color(0xFFD9FFB7).withValues(alpha: .105)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
      );
      canvas.drawCircle(
        Offset(x - width * .19, y - height * .16),
        height * .10,
        Paint()..color = Colors.white.withValues(alpha: .16),
      );
    }
  }

  void _paintSunFlecks(Canvas canvas, Size size) {
    final phase = (progress * .34) % 1;
    final x = phase * (size.width + 320) - 160;
    final paint = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.transparent,
          const Color(0xFFFFF1B7).withValues(alpha: .20),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(x - 120, 0, 240, size.height));
    canvas.save();
    canvas.skew(-.28, 0);
    canvas.drawRect(Rect.fromLTWH(x, 0, 130, size.height), paint);
    canvas.restore();
    canvas.drawCircle(
      Offset(size.width * .77, size.height * .20),
      30 + math.sin(progress * math.pi * 2) * 5,
      Paint()
        ..color = const Color(0xFFFFEAA6).withValues(alpha: .10)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
    );
  }

  void _paintWineVeil(Canvas canvas, Size size) {
    for (var band = 0; band < 2; band++) {
      final path = Path()..moveTo(-40, size.height * (.72 + band * .10));
      for (var x = 0.0; x < size.width + 80; x += 32) {
        path.lineTo(
          x,
          size.height * (.72 + band * .10) +
              math.sin(x / 120 + progress * math.pi * 2 + band) * 12,
        );
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFFFFB2C0).withValues(alpha: .10)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 16
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
      );
    }
  }

  void _paintSilkGlows(Canvas canvas, Size size) {
    final offset = (progress * 2 - 1) * size.width * .16;
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.transparent,
          const Color(0xFFFFFFFF).withValues(alpha: .16),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(offset, 0, size.width * .55, size.height));
    canvas.drawRect(
      Rect.fromLTWH(offset, 0, size.width * .55, size.height),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _AmbientSkinPainter oldDelegate) =>
      oldDelegate.presetId != presetId || oldDelegate.progress != progress;
}
