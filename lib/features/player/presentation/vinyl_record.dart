import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../library/domain/track.dart';

class VinylRecord extends StatelessWidget {
  const VinylRecord({
    super.key,
    required this.track,
    required this.size,
    required this.turns,
    required this.isPlaying,
    this.showTonearm = true,
    this.limeJelly = false,
    this.farmGold = false,
    this.tonearmColor,
  });

  final Track? track;
  final double size;
  final Animation<double> turns;
  final bool isPlaying;
  final bool showTonearm;
  final bool limeJelly;
  final bool farmGold;
  final Color? tonearmColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: size * 1.035,
            height: size * 1.035,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF171A20).withValues(alpha: 0.78),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.12),
                width: 1.5,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x78000000),
                  blurRadius: 38,
                  offset: Offset(0, 20),
                ),
              ],
            ),
          ),
          RotationTransition(
            turns: turns,
            child: Container(
              width: size,
              height: size,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  ClipOval(
                    child: Image.asset(
                      'assets/vinyl/premium_vinyl_v2.png',
                      fit: BoxFit.cover,
                    ),
                  ),
                  if (limeJelly)
                    Container(
                      width: size * 0.325,
                      height: size * 0.325,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          center: Alignment(-0.32, -0.36),
                          colors: const [
                            Color(0xFFBFFFA5),
                            Color(0xFF5BD66E),
                            Color(0xFF176A43),
                          ],
                        ),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.54),
                          width: 1.25,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF9DFF72)
                                .withValues(alpha: 0.30),
                            blurRadius: size * 0.045,
                          ),
                        ],
                      ),
                      child: Center(
                        child: Container(
                          width: size * 0.034,
                          height: size * 0.034,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFFF1FFDE),
                            border: Border.all(
                              color: const Color(0xFF215E3B),
                              width: 1,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (showTonearm)
            Positioned.fill(
              // Keep the original tonearm silhouette from the reference
              // player.  The later play/pause travel changed both its curve
              // and resting position, so the old fixed, lowered position is
              // intentionally restored here.
              child: CustomPaint(
                painter: _TonearmPainter(
                  limeJelly: limeJelly,
                  farmGold: farmGold,
                  tonearmColor: tonearmColor,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TonearmPainter extends CustomPainter {
  const _TonearmPainter({
    required this.limeJelly,
    required this.farmGold,
    required this.tonearmColor,
  });

  final bool limeJelly;
  final bool farmGold;
  final Color? tonearmColor;

  @override
  void paint(Canvas canvas, Size size) {
    final themeTone = tonearmColor;
    final toneHsl = themeTone == null ? null : HSLColor.fromColor(themeTone);
    final toneLight = toneHsl
        ?.withLightness((toneHsl.lightness + 0.24).clamp(0.0, 0.92))
        .toColor();
    final toneDark = toneHsl
        ?.withLightness((toneHsl.lightness - 0.18).clamp(0.12, 0.70))
        .toColor();
    // Original fixed tonearm geometry from the reference player.  All
    // coordinates remain proportional so this exact silhouette scales across
    // phones without device-specific pixel offsets.
    // Keep the pivot above the record's top-right edge, with the cartridge and
    // stylus resting on the black groove area. The stylus extends beyond the
    // cartridge in [headDirection], so the cartridge itself must stay well
    // outside the centre label rather than merely placing its centre on the
    // label edge.
    final pivot = Offset(size.width * 0.90, -size.height * 0.065);
    final controlA = Offset(size.width * 0.90, size.height * 0.08);
    final controlB = Offset(size.width * 0.87, size.height * 0.19);
    final bend = Offset(size.width * 0.82, size.height * 0.24);
    final approach = Offset(size.width * 0.77, size.height * 0.265);
    final headCenter = Offset(size.width * 0.70, size.height * 0.30);
    final shadow = Paint()
      ..color = Colors.black.withValues(alpha: 0.26)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = size.width * 0.026
      ..style = PaintingStyle.stroke;
    final arm = Paint()
      ..shader = LinearGradient(
        colors: themeTone != null
            ? [toneLight!, themeTone, toneDark!]
            : limeJelly
            ? const [Color(0xFFF3FFE9), Color(0xFF8DE9A8), Color(0xFFCFFFE0)]
            : farmGold
            ? const [Color(0xFFFFF0C6), Color(0xFFD7A749), Color(0xFFFFD77A)]
            : const [Color(0xFFFFFFFF), Color(0xFFC9CFD8)],
      ).createShader(Offset.zero & size)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = size.width * 0.018
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..moveTo(pivot.dx, pivot.dy)
      ..cubicTo(
        controlA.dx,
        controlA.dy,
        controlB.dx,
        controlB.dy,
        bend.dx,
        bend.dy,
      )
      ..quadraticBezierTo(
        approach.dx,
        approach.dy,
        headCenter.dx,
        headCenter.dy,
      );
    canvas.drawPath(path.shift(const Offset(2, 3)), shadow);
    canvas.drawPath(path, arm);

    final headDirection = headCenter - approach;
    final headRotation = math.atan2(headDirection.dy, headDirection.dx);
    canvas.save();
    canvas.translate(headCenter.dx, headCenter.dy);
    canvas.rotate(headRotation);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset.zero,
          width: size.width * 0.14,
          height: size.height * 0.052,
        ),
        Radius.circular(size.width * 0.014),
      ),
      Paint()
        ..shader =
            LinearGradient(
              colors: themeTone != null
                  ? [toneLight!, toneDark!]
                  : limeJelly
                  ? const [Color(0xFFE5FFE2), Color(0xFF86DFA2)]
                  : farmGold
                  ? const [Color(0xFFFFE8AE), Color(0xFFB97A24)]
                  : const [Color(0xFFFFFFFF), Color(0xFFD7DCE3)],
            ).createShader(
              Rect.fromLTWH(
                -size.width * 0.07,
                -size.height * 0.03,
                size.width * 0.14,
                size.height * 0.06,
              ),
            ),
    );
    canvas.drawLine(
      Offset(size.width * 0.055, 0),
      Offset(size.width * 0.095, size.height * 0.018),
      Paint()
        ..color = const Color(0xFF151820)
        ..strokeWidth = size.width * 0.010
        ..strokeCap = StrokeCap.round,
    );
    canvas.restore();

    canvas.drawCircle(
      pivot,
      size.width * 0.050,
      Paint()
        ..color = themeTone != null
            ? toneDark!
            : limeJelly
            ? const Color(0xFF27543C)
            : farmGold
            ? const Color(0xFF5E421F)
            : const Color(0xFF343842),
    );
    canvas.drawCircle(
      pivot,
      size.width * 0.022,
      Paint()..color = const Color(0xFFF8F8F8),
    );
  }

  @override
  bool shouldRepaint(covariant _TonearmPainter oldDelegate) =>
      oldDelegate.limeJelly != limeJelly ||
      oldDelegate.farmGold != farmGold ||
      oldDelegate.tonearmColor != tonearmColor;
}
