import 'dart:async';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';

import '../../../core/localization/sona_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/latest_snack_bar.dart';
import '../../../core/widgets/liquid_glass.dart';
import '../../library/application/library_controller.dart';
import '../../library/domain/track.dart';
import '../../library/presentation/widgets/track_artwork.dart';
import '../../settings/application/appearance_controller.dart';
import '../../settings/presentation/widgets/appearance_picker.dart';
import '../../settings/presentation/widgets/appearance_backdrop.dart';
import '../application/player_controller.dart';
import '../application/video_playback_request.dart';
import 'hover_volume_button.dart';
import 'now_playing_track_resolver.dart';
import 'vinyl_record.dart';
import 'playback_mode_button.dart';

enum PlayerVisualMode { vinyl, musicVideo }

/// Lightweight Beta ambience for 冰青琉璃.
///
/// A single canvas repaint is driven by the existing vinyl controller, so the
/// effect allocates no extra ticker and stops automatically with playback.
class _CyanAmbientBeta extends StatelessWidget {
  const _CyanAmbientBeta({required this.progress});

  final Animation<double> progress;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(painter: _CyanAmbientPainter(progress)),
      ),
    );
  }
}

class _CyanAmbientPainter extends CustomPainter {
  _CyanAmbientPainter(this.progress) : super(repaint: progress);

  final Animation<double> progress;

  @override
  void paint(Canvas canvas, Size size) {
    final phase = progress.value * math.pi * 2;
    final breathe = 0.5 + 0.5 * math.sin(phase);
    final ribbonGlowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 8.0
      ..color = const Color(0xFFB9F7FF)
          .withValues(alpha: 0.12 + breathe * 0.09);
    final ribbonCorePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.8
      ..color = Colors.white.withValues(alpha: 0.24 + breathe * 0.16);
    final ribbon = Path()
      ..moveTo(-size.width * 0.08, size.height * 0.34)
      ..cubicTo(
        size.width * 0.23,
        size.height * (0.22 + 0.015 * math.sin(phase)),
        size.width * 0.67,
        size.height * (0.48 + 0.018 * math.cos(phase)),
        size.width * 1.08,
        size.height * 0.29,
      );
    canvas.drawPath(ribbon, ribbonGlowPaint);
    canvas.drawPath(ribbon, ribbonCorePaint);

    ribbonGlowPaint
      ..strokeWidth = 9.0
      ..color = const Color(0xFF79E6FF)
          .withValues(alpha: 0.08 + (1 - breathe) * 0.07);
    ribbonCorePaint
      ..strokeWidth = 3.0
      ..color = const Color(0xFFA4F1FF)
          .withValues(alpha: 0.18 + (1 - breathe) * 0.13);
    final lowerRibbon = Path()
      ..moveTo(-size.width * 0.06, size.height * 0.62)
      ..cubicTo(
        size.width * 0.28,
        size.height * (0.74 + 0.014 * math.cos(phase)),
        size.width * 0.72,
        size.height * (0.51 + 0.016 * math.sin(phase)),
        size.width * 1.06,
        size.height * 0.69,
      );
    canvas.drawPath(lowerRibbon, ribbonGlowPaint);
    canvas.drawPath(lowerRibbon, ribbonCorePaint);

    ribbonCorePaint
      ..strokeWidth = 2.0
      ..color = const Color(0xFFE6FCFF).withValues(alpha: 0.18);
    final middleRibbon = Path()
      ..moveTo(-size.width * 0.08, size.height * 0.50)
      ..cubicTo(
        size.width * 0.30,
        size.height * (0.41 + 0.012 * math.cos(phase)),
        size.width * 0.73,
        size.height * (0.61 + 0.014 * math.sin(phase)),
        size.width * 1.08,
        size.height * 0.47,
      );
    canvas.drawPath(middleRibbon, ribbonCorePaint);

    final crystalPaint = Paint()..style = PaintingStyle.fill;
    for (var index = 0; index < 75; index++) {
      final seed = index * 1.73;
      final x =
          size.width *
          (0.09 + ((index * 0.137) % 0.82) + 0.025 * math.sin(phase + seed));
      final y =
          size.height *
          (0.13 + ((index * 0.219) % 0.70) + 0.018 * math.cos(phase + seed));
      final radius = 1.5 + (index % 4) * 0.62;
      final alpha =
          0.12 + 0.18 * (0.5 + 0.5 * math.sin(phase * 2 + index * 0.91));
      crystalPaint.color = Colors.white.withValues(alpha: alpha);
      final diamond = Path()
        ..moveTo(x, y - radius * 1.5)
        ..lineTo(x + radius, y)
        ..lineTo(x, y + radius * 1.5)
        ..lineTo(x - radius, y)
        ..close();
      canvas.drawPath(diamond, crystalPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _CyanAmbientPainter oldDelegate) => false;
}

/// A restrained Sakura Soda ambience: drifting petals over a soft blush halo.
/// It shares the vinyl ticker, so pausing freezes the scene without hiding it.
class _SakuraAmbientBeta extends StatelessWidget {
  const _SakuraAmbientBeta({required this.progress});

  final Animation<double> progress;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(painter: _SakuraAmbientPainter(progress)),
      ),
    );
  }
}

class _SakuraAmbientPainter extends CustomPainter {
  _SakuraAmbientPainter(this.progress) : super(repaint: progress);

  final Animation<double> progress;

  @override
  void paint(Canvas canvas, Size size) {
    final cycle = progress.value;
    final phase = cycle * math.pi * 2;
    final breathe = 0.5 + 0.5 * math.sin(phase);
    final halo = Paint()
      ..shader =
          RadialGradient(
            colors: [
              const Color(0xFFFF8DBA).withValues(alpha: 0.13 + breathe * 0.05),
              const Color(0xFFFFD8E8).withValues(alpha: 0.03),
              Colors.transparent,
            ],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width * 0.72, size.height * 0.28),
              radius: size.shortestSide * 0.54,
            ),
          );
    canvas.drawCircle(
      Offset(size.width * 0.72, size.height * 0.28),
      size.shortestSide * 0.54,
      halo,
    );

    for (var index = 0; index < 38; index++) {
      final seed = index * 1.6180339887;
      final lane = (index * 0.173) % 1.0;
      final fall =
          (cycle * (0.42 + (index % 5) * 0.045) + (index * 0.113) % 1.0) % 1.0;
      final x =
          size.width *
          (0.03 + lane * 0.94 + 0.035 * math.sin(phase * 1.3 + seed));
      final y = size.height * (-0.08 + fall * 1.16);
      final radius = 2.8 + (index % 4) * 0.8;
      final rotation = phase * (0.22 + (index % 3) * 0.05) + seed;
      final alpha = 0.22 + (index % 5) * 0.055;
      final petalPaint = Paint()
        ..color = Color.lerp(
          const Color(0xFFFFF1F7),
          const Color(0xFFFF72A8),
          (index % 7) / 9,
        )!.withValues(alpha: alpha);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(rotation);
      final petal = Path()
        ..moveTo(0, -radius * 1.55)
        ..cubicTo(
          radius * 1.15,
          -radius * 0.85,
          radius * 1.05,
          radius * 0.78,
          0,
          radius * 1.45,
        )
        ..cubicTo(
          -radius * 1.05,
          radius * 0.78,
          -radius * 1.15,
          -radius * 0.85,
          0,
          -radius * 1.55,
        )
        ..close();
      canvas.drawPath(petal, petalPaint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _SakuraAmbientPainter oldDelegate) => false;
}

/// Flowing aurora ribbons and sparse light motes for 流光极彩.
/// Two simple strokes per ribbon avoid expensive full-screen blur layers.
class _AuroraAmbientBeta extends StatelessWidget {
  const _AuroraAmbientBeta({required this.progress});

  final Animation<double> progress;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(painter: _AuroraAmbientPainter(progress)),
      ),
    );
  }
}

class _AuroraAmbientPainter extends CustomPainter {
  _AuroraAmbientPainter(this.progress) : super(repaint: progress);

  final Animation<double> progress;

  @override
  void paint(Canvas canvas, Size size) {
    final phase = progress.value * math.pi * 2;
    const colors = [Color(0xFF63ECFF), Color(0xFF9C7CFF), Color(0xFFFF78D3)];
    for (var index = 0; index < colors.length; index++) {
      final local = phase + index * 1.7;
      final centerY = size.height * (0.23 + index * 0.23);
      final path = Path()
        ..moveTo(-size.width * 0.12, centerY)
        ..cubicTo(
          size.width * 0.23,
          centerY + size.height * 0.10 * math.sin(local),
          size.width * 0.68,
          centerY - size.height * 0.10 * math.cos(local * 0.83),
          size.width * 1.12,
          centerY + size.height * 0.045 * math.sin(local * 1.2),
        );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 8
          ..color = colors[index].withValues(alpha: 0.075),
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 1.6
          ..color = colors[index].withValues(alpha: 0.30),
      );
    }

    final motePaint = Paint()..style = PaintingStyle.fill;
    for (var index = 0; index < 22; index++) {
      final seed = index * 1.41;
      final x =
          size.width *
          (0.04 + (index * 0.193) % 0.92 + 0.018 * math.sin(phase + seed));
      final y =
          size.height *
          (0.08 + (index * 0.127) % 0.84 + 0.012 * math.cos(phase + seed));
      final pulse = 0.5 + 0.5 * math.sin(phase * 1.7 + seed);
      motePaint.color = colors[index % colors.length].withValues(
        alpha: 0.12 + pulse * 0.24,
      );
      canvas.drawCircle(Offset(x, y), 0.8 + (index % 3) * 0.55, motePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _AuroraAmbientPainter oldDelegate) => false;
}

/// Distinct lightweight ambience for the remaining built-in skins. Every
/// style reuses the vinyl controller rather than creating its own ticker.
class _PresetAmbientBeta extends StatelessWidget {
  const _PresetAmbientBeta({required this.progress, required this.presetId});

  final Animation<double> progress;
  final String presetId;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(painter: _PresetAmbientPainter(progress, presetId)),
      ),
    );
  }
}

class _PresetAmbientPainter extends CustomPainter {
  _PresetAmbientPainter(this.progress, this.presetId)
    : super(repaint: progress);

  final Animation<double> progress;
  final String presetId;

  @override
  void paint(Canvas canvas, Size size) {
    switch (presetId) {
      case 'clean':
        _paintPearl(canvas, size);
        return;
      case 'farm':
        _paintFarm(canvas, size);
        return;
      case 'vinyl_bloom':
        _paintBloom(canvas, size);
        return;
      case 'mist_orbs':
        _paintMist(canvas, size);
        return;
      case 'obsidian_rings':
        _paintObsidian(canvas, size);
        return;
    }
  }

  void _paintPearl(Canvas canvas, Size size) {
    final phase = progress.value * math.pi * 2;
    final center = Offset(size.width * 0.52, size.height * 0.31);
    for (var index = 0; index < 4; index++) {
      final breathe = 0.5 + 0.5 * math.sin(phase + index * 1.2);
      canvas.drawCircle(
        center,
        size.width * (0.22 + index * 0.105 + breathe * 0.012),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0 + index * 0.35
          ..color = Color.lerp(
            const Color(0xFFF7D6C4),
            const Color(0xFFD5D9FF),
            index / 3,
          )!.withValues(alpha: 0.12 + breathe * 0.14),
      );
    }
    final glint = Paint();
    for (var index = 0; index < 20; index++) {
      final local = phase + index * 1.71;
      final x = size.width * (0.08 + (index * 0.217) % 0.84);
      final y = size.height * (0.10 + (index * 0.137) % 0.78);
      glint.color = const Color(0xFFFFF3E8)
          .withValues(alpha: 0.12 + (0.5 + 0.5 * math.sin(local)) * 0.28);
      canvas.drawCircle(Offset(x, y), 0.9 + index % 3 * 0.5, glint);
    }
  }

  void _paintFarm(Canvas canvas, Size size) {
    final phase = progress.value * math.pi * 2;
    final sunCenter = Offset(size.width * 0.76, size.height * 0.20);
    canvas.drawCircle(
      sunCenter,
      size.shortestSide * 0.30,
      Paint()
        ..shader =
            RadialGradient(
              colors: [
                const Color(0xFFFFE7A3).withValues(alpha: 0.08),
                const Color(0xFFFFCD57).withValues(alpha: 0.025),
                Colors.transparent,
              ],
            ).createShader(
              Rect.fromCircle(
                center: sunCenter,
                radius: size.shortestSide * 0.30,
              ),
            ),
    );
    // Only elongated wheat chaff is animated here. Round light motes looked
    // like unexplained bubbles over the photographic field, so this preset
    // deliberately avoids circles and long decorative ribbons.
    for (var index = 0; index < 18; index++) {
      final local = phase * (0.045 + index % 3 * 0.008) + index * 1.37;
      final x = size.width * (0.06 + (index * 0.217) % 0.88);
      final y =
          size.height *
          (0.12 +
              ((index * 0.151 + progress.value * (0.018 + index % 4 * 0.005)) %
                  0.76));
      final chaffSize = 2.1 + index % 4 * 0.55;
      canvas.save();
      canvas.translate(x + math.sin(local) * 5, y);
      canvas.rotate(0.55 + math.sin(local * 0.35) * 0.45);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset.zero,
          width: chaffSize,
          height: chaffSize * 2.7,
        ),
        Paint()
          ..color = Color.lerp(
            const Color(0xFFFFF0B2),
            const Color(0xFFD89B2D),
            (index % 5) / 6,
          )!.withValues(alpha: 0.12 + (index % 4) * 0.035),
      );
      canvas.restore();
    }
  }

  void _paintBloom(Canvas canvas, Size size) {
    final phase = progress.value * math.pi * 2;
    final center = Offset(size.width * 0.50, size.height * 0.31);
    for (var index = 0; index < 34; index++) {
      final radius = size.width * (0.22 + (index % 5) * 0.055);
      final angle = phase * (0.10 + index % 3 * 0.015) + index * 0.77;
      final point = Offset(
        center.dx + math.cos(angle) * radius,
        center.dy + math.sin(angle) * radius * 0.58,
      );
      final petalSize = 2.6 + index % 4 * 0.75;
      canvas.save();
      canvas.translate(point.dx, point.dy);
      canvas.rotate(angle + math.pi / 2);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset.zero,
          width: petalSize * 1.3,
          height: petalSize * 2.4,
        ),
        Paint()
          ..color = Color.lerp(
            const Color(0xFFFF7A98),
            const Color(0xFFFFD1BD),
            (index % 6) / 6,
          )!.withValues(alpha: 0.22 + (index % 4) * 0.07),
      );
      canvas.restore();
    }
  }

  void _paintMist(Canvas canvas, Size size) {
    final phase = progress.value * math.pi * 2;
    const twilightColors = [
      Color(0xFFBFA9FF),
      Color(0xFF8FE6FF),
      Color(0xFFF4B9E8),
    ];

    // Large, soft light pools drift beneath the ribbons. The radial fade keeps
    // the ambience organic instead of reading as a set of mechanical rings.
    for (var index = 0; index < 3; index++) {
      final local = phase * (0.035 + index * 0.009) + index * 2.15;
      final center = Offset(
        size.width * (0.50 + math.cos(local) * (0.24 + index * 0.025)),
        size.height * (0.34 + math.sin(local * 0.82) * (0.15 + index * 0.02)),
      );
      final radius = size.width * (0.23 + index * 0.035);
      final color = twilightColors[index];
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: 0.10),
              color.withValues(alpha: 0.035),
              color.withValues(alpha: 0),
            ],
            stops: const [0, 0.48, 1],
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }

    // Three slow silk-like mist ribbons. Each uses a broad translucent body,
    // a slimmer colour edge and one fine highlight for a light, fluid finish.
    for (var index = 0; index < 3; index++) {
      final drift = math.sin(phase * (0.055 + index * 0.008) + index * 1.7);
      final baseY = size.height * (0.19 + index * 0.24);
      final path = Path()
        ..moveTo(-size.width * 0.12, baseY + drift * size.height * 0.025)
        ..cubicTo(
          size.width * 0.20,
          baseY - size.height * (0.09 + index * 0.012),
          size.width * 0.62,
          baseY + size.height * (0.11 - index * 0.015),
          size.width * 1.12,
          baseY - drift * size.height * 0.035,
        );
      final color = twilightColors[index];
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 22 + index * 5
          ..color = color.withValues(alpha: 0.035),
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 6 + index * 1.5
          ..color = color.withValues(alpha: 0.075),
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 1.15
          ..color = Colors.white.withValues(alpha: 0.16),
      );
    }

    // Sparse twilight dust adds motion without competing with the record.
    for (var index = 0; index < 24; index++) {
      final local = phase * (0.07 + index % 4 * 0.006) + index * 1.31;
      final x = size.width * (0.05 + (index * 0.193) % 0.90);
      final y =
          size.height *
          (0.07 +
              ((index * 0.127 + progress.value * (0.035 + index % 3 * 0.008)) %
                  0.86));
      final shimmer = 0.5 + 0.5 * math.sin(local);
      canvas.drawCircle(
        Offset(x + math.sin(local) * 5, y),
        0.75 + index % 3 * 0.48,
        Paint()
          ..color = twilightColors[index % twilightColors.length].withValues(
            alpha: 0.10 + shimmer * 0.24,
          ),
      );
    }
  }

  void _paintObsidian(Canvas canvas, Size size) {
    final phase = progress.value * math.pi * 2;
    const glowColors = [
      Color(0xFFFF7A32),
      Color(0xFFFFB05E),
      Color(0xFFD94B22),
    ];
    for (var index = 0; index < 3; index++) {
      final local = phase * (0.035 + index * 0.008) + index * 2.1;
      final center = Offset(
        size.width * (0.08 + index * 0.42 + math.sin(local) * 0.025),
        size.height * (0.20 + index * 0.27 + math.cos(local) * 0.02),
      );
      final radius = size.shortestSide * (0.16 + index * 0.025);
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [
              glowColors[index].withValues(alpha: 0.075),
              glowColors[index].withValues(alpha: 0.018),
              Colors.transparent,
            ],
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }
    for (var index = 0; index < 24; index++) {
      final local = phase + index * 1.43;
      final x = size.width * (0.04 + (index * 0.229) % 0.92);
      final y = size.height * (0.08 + (index * 0.163) % 0.82);
      canvas.drawCircle(
        Offset(x, y),
        0.8 + index % 3 * 0.55,
        Paint()
          ..color = const Color(0xFFFFA35B)
              .withValues(alpha: 0.12 + (0.5 + 0.5 * math.sin(local)) * 0.32),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PresetAmbientPainter oldDelegate) =>
      oldDelegate.presetId != presetId;
}

class NowPlayingPage extends ConsumerStatefulWidget {
  const NowPlayingPage({super.key, this.autoplayRequest});

  final VideoPlaybackRequest? autoplayRequest;

  @override
  ConsumerState<NowPlayingPage> createState() => _NowPlayingPageState();
}

class _NowPlayingPageState extends ConsumerState<NowPlayingPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin;
  late final VideoController _videoController;
  var _mode = PlayerVisualMode.vinyl;
  int? _visualTrackId;
  double? _limeSeekPreviewFraction;
  int _mvSurfaceRequest = 0;
  bool _mvSurfaceReady = false;
  bool _mvSurfaceTimedOut = false;
  String _mvSurfaceStatus = '正在准备 MV 画面';
  bool _initialVideoRequestPending = false;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 16),
    );
    _videoController = VideoController(
      ref.read(playerControllerProvider.notifier).player,
      // Several local MV files decode audio but render black through the
      // Windows GPU texture path. CPU output is more conservative, but keeps
      // the displayed frame reliable across the machines we support.
      configuration: const VideoControllerConfiguration(
        enableHardwareAcceleration: false,
      ),
    );
    final request = widget.autoplayRequest;
    if (request != null) {
      // Reserve the video stage during the initial build, before any call to
      // Player.open. This is the ordering Windows needs for the first MV.
      _visualTrackId = request.track.id;
      _mode = PlayerVisualMode.musicVideo;
      _initialVideoRequestPending = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_startRequestedVideo(request));
      });
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playback = ref.watch(playerControllerProvider);
    final library = ref.watch(libraryControllerProvider);
    final appearance = ref.watch(appearanceControllerProvider);
    // A video-only request mounts this page before the native video surface is
    // ready, so [playback.currentTrack] can still be the song that was playing
    // a moment ago. Prefer the requested MV only during that hand-off. Once it
    // settles, the controller must drive every later queue selection.
    final requestedTrack = widget.autoplayRequest?.track;
    final sourceTrack = resolveNowPlayingDisplayTrack(
      currentTrack: playback.currentTrack,
      requestedTrack: requestedTrack,
      isInitialVideoRequestPending: _initialVideoRequestPending,
    );
    final track = sourceTrack == null
        ? null
        : library.tracks.cast<Track?>().firstWhere(
            (item) => item?.id == sourceTrack.id,
            orElse: () => sourceTrack,
          );

    if (_visualTrackId != track?.id) {
      _visualTrackId = track?.id;
      _mode = track?.isVideoOnly == true
          ? PlayerVisualMode.musicVideo
          : PlayerVisualMode.vinyl;
      _mvSurfaceReady = false;
      if (_mode == PlayerVisualMode.musicVideo && track != null) {
        // Queue/next/previous can select a pure MV while this player is
        // already open. Mount the native stage first, then reopen that source
        // through the same hand-off used by an MV clicked from the library.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _visualTrackId == track.id) {
            unawaited(_openMvSource(track));
          }
        });
      }
    }

    if (playback.isPlaying && !_spin.isAnimating) {
      _spin.repeat();
    } else if (!playback.isPlaying && _spin.isAnimating) {
      _spin.stop();
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
        systemStatusBarContrastEnforced: false,
        systemNavigationBarContrastEnforced: false,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFF07101E),
        body: Stack(
          fit: StackFit.expand,
          children: [
            AppearanceBackdrop(appearance: appearance, forPlayer: true),
            if (appearance.preset.id == 'cyan_glass' &&
                _mode == PlayerVisualMode.vinyl)
              Positioned.fill(child: _CyanAmbientBeta(progress: _spin)),
            if (appearance.preset.id == 'sakura' &&
                _mode == PlayerVisualMode.vinyl)
              Positioned.fill(child: _SakuraAmbientBeta(progress: _spin)),
            if (appearance.preset.id == 'aurora' &&
                _mode == PlayerVisualMode.vinyl)
              Positioned.fill(child: _AuroraAmbientBeta(progress: _spin)),
            if (appearance.preset.id == 'farm' &&
                _mode == PlayerVisualMode.vinyl)
              Positioned.fill(
                child: _PresetAmbientBeta(
                  progress: _spin,
                  presetId: appearance.preset.id,
                ),
              ),
            if (_mode == PlayerVisualMode.vinyl &&
                (appearance.preset.id == 'clean' ||
                    appearance.preset.id == 'vinyl_bloom' ||
                    appearance.preset.id == 'mist_orbs' ||
                    appearance.preset.id == 'obsidian_rings'))
              Positioned.fill(
                child: _PresetAmbientBeta(
                  progress: _spin,
                  presetId: appearance.preset.id,
                ),
              ),
            const Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: 96,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x42000000), Color(0x00000000)],
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  _PlayerHeader(
                    themeName: appearance.usesCustom
                        ? '我的背景'
                        : appearance.preset.name,
                    onBack: () => Navigator.of(context).pop(),
                    onTheme: _showAppearancePicker,
                    onMore: () => _showMoreMenu(track),
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final desktop = constraints.maxWidth >= 820;
                        final tonearmColor =
                            !appearance.usesCustom &&
                                appearance.preset.id == 'clean'
                            ? null
                            : appearance.usesCustom
                            ? appearance.accent
                            : appearance.preset.tonearmColor ??
                                  appearance.accent;
                        return desktop
                            ? _buildDesktop(
                                context,
                                track,
                                playback,
                                constraints,
                                tonearmColor,
                              )
                            : _buildMobile(
                                context,
                                track,
                                playback,
                                constraints,
                                tonearmColor,
                              );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktop(
    BuildContext context,
    Track? track,
    PlaybackState playback,
    BoxConstraints constraints,
    Color? tonearmColor,
  ) {
    // On desktop an MV is the primary experience.  Keep the record layout
    // intact, but give video a cinema-sized stage and move every control into
    // one deliberately compact strip along the bottom.
    if (_mode == PlayerVisualMode.musicVideo) {
      return _buildDesktopMvLayout(context, track, playback);
    }
    final recordSize = (constraints.maxHeight * 0.52).clamp(280.0, 440.0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(54, 6, 54, 34),
      child: Row(
        children: [
          Expanded(
            flex: 11,
            child: Align(
              alignment: const Alignment(0, -0.12),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: _playerStageTransition,
                child: switch (_mode) {
                  PlayerVisualMode.vinyl =>
                    track?.isVideoOnly == true
                        ? _MissingMediaStage(
                            key: const ValueKey('missing-vinyl'),
                            icon: Icons.album_rounded,
                            label: '还没有配对唱片',
                            onTap: () => _attachAudio(track!),
                          )
                        : VinylRecord(
                            key: const ValueKey('vinyl'),
                            track: track,
                            size: recordSize,
                            turns: _spin,
                            isPlaying: playback.isPlaying,
                            limeJelly: false,
                            tonearmColor: tonearmColor,
                          ),
                  PlayerVisualMode.musicVideo => _MvStage(
                    key: const ValueKey('mv'),
                    track: track,
                    controller: _videoController,
                    videoReady: _mvSurfaceReady,
                    videoTimedOut: _mvSurfaceTimedOut,
                    videoStatus: _mvSurfaceStatus,
                    onAttachVideo: track == null
                        ? null
                        : () => _attachVideo(track),
                  ),
                },
              ),
            ),
          ),
          const SizedBox(width: 46),
          Expanded(
            flex: 9,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 590),
              child: _GlassPanel(
                limeJelly: false,
                child: PlayerInformation(
                  track: track,
                  playback: playback,
                  mode: _mode,
                  onModeChanged: _setMode,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopMvLayout(
    BuildContext context,
    Track? track,
    PlaybackState playback,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(54, 6, 54, 28),
      child: Column(
        children: [
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: _playerStageTransition,
              child: SizedBox.expand(
                key: const ValueKey('desktop-mv-stage'),
                child: _MvStage(
                  track: track,
                  controller: _videoController,
                  videoReady: _mvSurfaceReady,
                  videoTimedOut: _mvSurfaceTimedOut,
                  videoStatus: _mvSurfaceStatus,
                  expand: true,
                  onAttachVideo: track == null
                      ? null
                      : () => _attachVideo(track),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _DesktopMvControlBar(
            track: track,
            playback: playback,
            mode: _mode,
            onModeChanged: _setMode,
          ),
        ],
      ),
    );
  }

  Widget _buildMobile(
    BuildContext context,
    Track? track,
    PlaybackState playback,
    BoxConstraints constraints,
    Color? tonearmColor,
  ) {
    // The mobile player deliberately has no page scroll.  A media player must
    // look complete at a glance instead of letting the stage stop halfway.
    final panelHeight = (constraints.maxHeight * 0.44).clamp(300.0, 326.0);
    const panelGap = 12.0;
    final stageHeight = constraints.maxHeight - panelHeight - panelGap;
    final recordSize = (stageHeight * 0.72).clamp(190.0, 248.0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 2, 22, 14),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragEnd: (details) => _handlePlayerSwipe(details, track),
        child: Column(
          children: [
            SizedBox(
              height: stageHeight,
              width: double.infinity,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 190),
                reverseDuration: const Duration(milliseconds: 160),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                layoutBuilder: (currentChild, previousChildren) => Stack(
                  fit: StackFit.expand,
                  children: [...previousChildren, ?currentChild],
                ),
                transitionBuilder: _fixedMobileStageTransition,
                // Every mode owns the exact same full-size stage. Previously
                // the outgoing background was full-screen while the incoming
                // record was record-sized; AnimatedSwitcher therefore centered
                // it during the fade and moved it again when the old child died.
                child: switch (_mode) {
                  PlayerVisualMode.vinyl => SizedBox.expand(
                    key: const ValueKey('vinyl-stage'),
                    child: track?.isVideoOnly == true
                        ? _MissingMediaStage(
                            icon: Icons.album_rounded,
                            label: '还没有配对唱片',
                            onTap: () => _attachAudio(track!),
                          )
                        : Center(
                            child: RepaintBoundary(
                              child: VinylRecord(
                                track: track,
                                size: recordSize,
                                turns: _spin,
                                isPlaying: playback.isPlaying,
                                limeJelly: false,
                                tonearmColor: tonearmColor,
                              ),
                            ),
                          ),
                  ),
                  PlayerVisualMode.musicVideo => SizedBox.expand(
                    key: const ValueKey('mv-stage'),
                    child: _MvStage(
                      track: track,
                      controller: _videoController,
                      videoReady: _mvSurfaceReady,
                      videoTimedOut: _mvSurfaceTimedOut,
                      videoStatus: _mvSurfaceStatus,
                      onAttachVideo: track == null
                          ? null
                          : () => _attachVideo(track),
                    ),
                  ),
                },
              ),
            ),
            SizedBox(height: panelGap),
            SizedBox(
              height: panelHeight,
              child: _GlassPanel(
                compact: true,
                limeJelly: false,
                child: PlayerInformation(
                  track: track,
                  playback: playback,
                  mode: _mode,
                  compact: true,
                  onModeChanged: _setMode,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Retained only as a reversible record of the flattened-reference
  // experiment. The active mobile player uses the native responsive stage.
  // ignore: unused_element
  Widget _buildLimeReferenceMobile(
    BuildContext context,
    Track? track,
    PlaybackState playback,
    BoxConstraints constraints,
  ) {
    final player = ref.read(playerControllerProvider.notifier);
    final max = playback.duration.inMilliseconds > 0
        ? playback.duration.inMilliseconds.toDouble()
        : 1.0;
    final width = constraints.maxWidth;
    final height = constraints.maxHeight;
    final buttonSize = (width * 0.18).clamp(58.0, 74.0);
    final playVisualSize = (width * 0.125).clamp(46.0, 54.0);
    final buttonTop = height * 0.79;
    final liveProgress = playback.duration.inMilliseconds <= 0
        ? 0.0
        : (playback.position.inMilliseconds / max).clamp(0.0, 1.0);
    final visibleProgress = _limeSeekPreviewFraction ?? liveProgress;

    void seekFromPosition(double localX, double barWidth) {
      if (track == null || playback.duration.inMilliseconds <= 0) return;
      final fraction = (localX / barWidth).clamp(0.0, 1.0);
      setState(() => _limeSeekPreviewFraction = fraction);
      player.seek(Duration(milliseconds: (max * fraction).round()));
    }

    void settleSeekPreview() {
      Future<void>.delayed(const Duration(milliseconds: 140), () {
        if (mounted) setState(() => _limeSeekPreviewFraction = null);
      });
    }

    Widget interactionButton({
      required String label,
      required VoidCallback action,
      Widget? child,
    }) {
      return Semantics(
        button: true,
        enabled: track != null,
        label: label,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: track == null ? null : action,
          child: child ?? const SizedBox.expand(),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        if (track != null)
          Positioned(
            left: 44,
            right: 44,
            top: height * 0.655,
            child: IgnorePointer(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: Text(
                  context.metadata(track.title),
                  key: ValueKey(track.id),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFF4F8E7),
                    fontSize: 19,
                    height: 1.15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.1,
                    shadows: [
                      Shadow(
                        color: Color(0xB8001F10),
                        blurRadius: 12,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        Positioned(
          left: width * 0.22,
          top: buttonTop,
          width: buttonSize,
          height: buttonSize,
          child: interactionButton(label: '上一首', action: player.previous),
        ),
        Positioned(
          left: (width - buttonSize) / 2,
          top: buttonTop,
          width: buttonSize,
          height: buttonSize,
          child: interactionButton(
            label: playback.isPlaying ? '暂停' : '播放',
            action: player.togglePlayPause,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                width: playVisualSize,
                height: playVisualSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    center: const Alignment(-0.30, -0.38),
                    colors: playback.isPlaying
                        ? const [
                            Color(0xFFD8F2B9),
                            Color(0xFF75B96C),
                            Color(0xFF397A4B),
                          ]
                        : const [
                            Color(0xFFCDE9AE),
                            Color(0xFF69AA62),
                            Color(0xFF397449),
                          ],
                  ),
                  border: Border.all(
                    color: const Color(0xFFE9F4D5),
                    width: 1.1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF72D86C)
                          .withValues(alpha: playback.isPlaying ? 0.34 : 0.20),
                      blurRadius: playback.isPlaying ? 15 : 10,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 160),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(scale: animation, child: child),
                  ),
                  child: Icon(
                    playback.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    key: ValueKey(playback.isPlaying),
                    color: const Color(0xFFF5F5DF),
                    size: playVisualSize * 0.54,
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          right: width * 0.22,
          top: buttonTop,
          width: buttonSize,
          height: buttonSize,
          child: interactionButton(label: '下一首', action: player.next),
        ),
        Positioned(
          left: width * 0.14,
          right: width * 0.14,
          top: height * 0.865,
          height: 48,
          child: LayoutBuilder(
            builder: (context, barConstraints) => Semantics(
              slider: true,
              enabled: track != null,
              label: '播放进度',
              value: playback.duration.inMilliseconds <= 0
                  ? '0%'
                  : '${(visibleProgress * 100).round()}%',
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTapDown: track == null
                    ? null
                    : (details) => seekFromPosition(
                        details.localPosition.dx,
                        barConstraints.maxWidth,
                      ),
                onTapUp: track == null ? null : (_) => settleSeekPreview(),
                onTapCancel: track == null ? null : settleSeekPreview,
                onHorizontalDragUpdate: track == null
                    ? null
                    : (details) => seekFromPosition(
                        details.localPosition.dx,
                        barConstraints.maxWidth,
                      ),
                onHorizontalDragEnd: track == null
                    ? null
                    : (_) => settleSeekPreview(),
                onHorizontalDragCancel: track == null
                    ? null
                    : settleSeekPreview,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: width * 0.04),
                  child: CustomPaint(
                    painter: _LimeReferenceProgressPainter(visibleProgress),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _handlePlayerSwipe(DragEndDetails details, Track? track) {
    if (track == null) return;
    final velocity = details.primaryVelocity ?? 0;
    if (velocity.abs() < 260) return;
    if (velocity < 0) {
      _setMode(PlayerVisualMode.musicVideo);
    } else if (velocity > 0) {
      _setMode(PlayerVisualMode.vinyl);
    }
  }

  Future<void> _startRequestedVideo(VideoPlaybackRequest request) async {
    final track = request.track;
    final surfaceRequest = ++_mvSurfaceRequest;
    try {
      // [VideoController] creates its Windows output asynchronously after the
      // first widget frame. Do not open the media until that output is ready.
      await _videoController.platform.future.timeout(
        const Duration(seconds: 8),
      );
      if (!_isCurrentMvSurfaceRequest(surfaceRequest, track)) return;
      await ref
          .read(playerControllerProvider.notifier)
          .playTrack(
            track,
            request.queue,
            source: request.source,
            videoSurfaceReady: true,
          );
      if (!_isCurrentMvSurfaceRequest(surfaceRequest, track)) return;
      if (ref.read(playerControllerProvider).currentTrack?.id != track.id) {
        _markMvSurfaceFailed(
          surfaceRequest,
          track,
          StateError('The MV source could not be opened.'),
          StackTrace.current,
        );
        return;
      }
      _waitForMvFirstFrame(track);
    } on TimeoutException {
      _markMvSurfaceWaitingTooLong(surfaceRequest, track);
    } catch (error, stackTrace) {
      _markMvSurfaceFailed(surfaceRequest, track, error, stackTrace);
    } finally {
      if (mounted && _initialVideoRequestPending) {
        setState(() => _initialVideoRequestPending = false);
      }
    }
  }

  Future<void> _setMode(PlayerVisualMode mode) async {
    final track = ref.read(playerControllerProvider).currentTrack;
    if (track == null) return;
    final libraryTrack = ref
        .read(libraryControllerProvider)
        .tracks
        .cast<Track?>()
        .firstWhere((item) => item?.id == track.id, orElse: () => track)!;
    // A standalone MV has no audio/record source. Never let a generic mode
    // toggle replace it with the misleading "no paired record" placeholder.
    if (mode == PlayerVisualMode.vinyl && libraryTrack.isVideoOnly) return;
    if (mode == PlayerVisualMode.musicVideo &&
        (libraryTrack.hasVideo || libraryTrack.isVideoOnly)) {
      await _openMvSource(libraryTrack);
      return;
    } else if (mode == PlayerVisualMode.vinyl && !libraryTrack.isVideoOnly) {
      await ref
          .read(playerControllerProvider.notifier)
          .switchTrackSource(libraryTrack, libraryTrack.path);
    }
    if (!mounted) return;
    setState(() => _mode = mode);
  }

  /// Mounts the native output before assigning an MV source. On Windows the
  /// texture must stay alive throughout this hand-off or audio can start while
  /// the compositor has no frame sink.
  Future<void> _openMvSource(Track track) async {
    if (!mounted) return;
    setState(() {
      _visualTrackId = track.id;
      _mode = PlayerVisualMode.musicVideo;
      _mvSurfaceReady = false;
      _mvSurfaceTimedOut = false;
      _mvSurfaceStatus = '正在准备 MV 画面';
    });
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || _visualTrackId != track.id) return;
    try {
      await _videoController.platform.future.timeout(
        const Duration(seconds: 3),
      );
    } on TimeoutException {
      // Continue opening media; the platform can allocate its texture shortly
      // after this timeout without resetting the already-mounted video view.
    }
    if (!mounted || _visualTrackId != track.id) return;
    await ref
        .read(playerControllerProvider.notifier)
        .switchTrackSource(
          track,
          track.isVideoOnly ? track.path : track.videoPath!,
        );
    if (!mounted) return;
    _waitForMvFirstFrame(track);
  }

  /// Keeps the Windows native video texture mounted while its media source is
  /// changing and exposes it only after media_kit reports a rendered frame.
  ///
  /// A Flutter post-frame callback only means the widget tree was composed; it
  /// does not mean the Windows texture has received a decoded video frame. In
  /// particular, the first MV could start its audio while still presenting an
  /// all-black native surface. [VideoController.waitUntilFirstFrameRendered]
  /// is the media_kit signal for that second condition.
  void _waitForMvFirstFrame(Track track) {
    final request = ++_mvSurfaceRequest;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_awaitMvFirstFrame(track, request));
    });
  }

  Future<void> _awaitMvFirstFrame(Track track, int request) async {
    // Allow the stable [Video] widget to enter the composed tree before asking
    // media_kit for a first frame. Neither this wait nor any timeout below
    // rebuilds the native output widget.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted ||
        request != _mvSurfaceRequest ||
        _mode != PlayerVisualMode.musicVideo ||
        _visualTrackId != track.id) {
      return;
    }

    final platformFuture = _videoController.platform.future;
    final firstFrameFuture = _videoController.waitUntilFirstFrameRendered;
    try {
      await platformFuture.timeout(const Duration(seconds: 3));
      debugPrint(
        '[Sona/MV] platform initialized: track=${track.id}, '
        'texture=${_videoController.id.value}, rect=${_videoController.rect.value}',
      );
      await firstFrameFuture.timeout(const Duration(seconds: 8));
      _markMvSurfaceReady(request, track);
    } on TimeoutException {
      // The native controller/future continues running after [timeout]. If a
      // slow GPU eventually supplies a frame, the listener below removes the
      // temporary warning without resetting audio, position or the texture.
      _markMvSurfaceWaitingTooLong(request, track);
      unawaited(
        firstFrameFuture.then<void>(
          (_) => _markMvSurfaceReady(request, track),
          onError: (Object error, StackTrace stackTrace) =>
              _markMvSurfaceFailed(request, track, error, stackTrace),
        ),
      );
    } catch (error, stackTrace) {
      _markMvSurfaceFailed(request, track, error, stackTrace);
    }
  }

  bool _isCurrentMvSurfaceRequest(int request, Track track) =>
      mounted &&
      request == _mvSurfaceRequest &&
      _mode == PlayerVisualMode.musicVideo &&
      _visualTrackId == track.id;

  void _markMvSurfaceReady(int request, Track track) {
    if (!_isCurrentMvSurfaceRequest(request, track)) return;
    debugPrint(
      '[Sona/MV] first frame rendered: track=${track.id}, '
      'texture=${_videoController.id.value}, rect=${_videoController.rect.value}',
    );
    setState(() {
      _mvSurfaceReady = true;
      _mvSurfaceTimedOut = false;
      _mvSurfaceStatus = '正在准备 MV 画面';
    });
  }

  void _markMvSurfaceWaitingTooLong(int request, Track track) {
    if (!_isCurrentMvSurfaceRequest(request, track)) return;
    debugPrint(
      '[Sona/MV] first frame timeout: track=${track.id}, '
      'texture=${_videoController.id.value}, rect=${_videoController.rect.value}',
    );
    setState(() {
      _mvSurfaceReady = false;
      _mvSurfaceTimedOut = true;
      _mvSurfaceStatus = 'MV 画面准备超时，音频仍在播放';
    });
  }

  void _markMvSurfaceFailed(
    int request,
    Track track,
    Object error,
    StackTrace stackTrace,
  ) {
    debugPrint(
      '[Sona/MV] first frame failed: track=${track.id}, '
      'texture=${_videoController.id.value}, rect=${_videoController.rect.value}, '
      'error=$error\n$stackTrace',
    );
    if (!_isCurrentMvSurfaceRequest(request, track)) return;
    setState(() {
      _mvSurfaceReady = false;
      _mvSurfaceTimedOut = true;
      _mvSurfaceStatus = 'MV 画面暂时不可用，音频仍在播放';
    });
  }

  Widget _playerStageTransition(Widget child, Animation<double> animation) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(opacity: curved, child: child);
  }

  Widget _fixedMobileStageTransition(
    Widget child,
    Animation<double> animation,
  ) {
    return FadeTransition(
      opacity: CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      ),
      child: child,
    );
  }

  Future<void> _attachVideo(Track track) async {
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['mp4', 'mkv', 'mov', 'webm', 'avi'],
    );
    final selectedPath = picked?.path;
    if (selectedPath == null) return;
    await ref
        .read(libraryControllerProvider.notifier)
        .setVideoPath(track, selectedPath);
    if (!mounted) return;
    final updated = track.copyWith(videoPath: selectedPath);
    await _openMvSource(updated);
    if (!mounted) return;
    showLatestSnackBar(context, const SnackBar(content: Text('MV 已与这首歌配对。')));
  }

  Future<void> _attachAudio(Track track) async {
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const [
        'mp3',
        'flac',
        'm4a',
        'wav',
        'ogg',
        'opus',
        'aac',
        'aiff',
        'ape',
      ],
    );
    final selectedPath = picked?.path;
    if (selectedPath == null) return;
    try {
      final updated = await ref
          .read(libraryControllerProvider.notifier)
          .pairAudioWithVideoTrack(track, selectedPath);
      await ref
          .read(playerControllerProvider.notifier)
          .switchTrackSource(updated, selectedPath);
      if (!mounted) return;
      setState(() => _mode = PlayerVisualMode.vinyl);
      showLatestSnackBar(
        context,
        const SnackBar(content: Text('唱片音频已与这支 MV 配对。')),
      );
    } catch (error) {
      if (!mounted) return;
      final message = error is StateError
          ? error.message.toString()
          : '音频配对失败，请确认文件可用。';
      showLatestSnackBar(context, SnackBar(content: Text(message)));
    }
  }

  Future<void> _showAppearancePicker() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 20),
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.84,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 780),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '播放器背景',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            SizedBox(height: 3),
                            Text(
                              '多套明亮皮肤，也可以导入并裁切自己的图片。',
                              style: TextStyle(color: Color(0xFF7D8799)),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: AppearancePicker(
                      scrollable: true,
                      onSelectionComplete: () => Navigator.pop(context),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showMoreMenu(Track? track) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.info_outline_rounded),
                title: Text(
                  track == null
                      ? context.tr('当前没有歌曲')
                      : context.metadata(track.title),
                ),
                subtitle: track == null
                    ? null
                    : Text(
                        '${context.metadata(track.artist)} · ${context.metadata(track.album)}',
                      ),
              ),
              ListTile(
                enabled: track != null,
                leading: const Icon(Icons.video_library_outlined),
                title: Text(
                  track?.isVideoOnly == true
                      ? '替换视频文件'
                      : track?.hasVideo == true
                      ? '更换关联 MV'
                      : '关联一个 MV',
                ),
                onTap: track == null
                    ? null
                    : () {
                        Navigator.pop(sheetContext);
                        _attachVideo(track);
                      },
              ),
              if (track?.hasVideo == true && track?.isVideoOnly != true)
                ListTile(
                  leading: const Icon(Icons.link_off_rounded),
                  title: const Text('解除 MV 配对'),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await ref
                        .read(libraryControllerProvider.notifier)
                        .setVideoPath(track!, null);
                    if (mounted) await _setMode(PlayerVisualMode.vinyl);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.tune_rounded),
                title: const Text('播放器设置'),
                subtitle: const Text('睡眠定时、后台播放状态'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showPlayerSettings();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showPlayerSettings() async {
    final player = ref.read(playerControllerProvider.notifier);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 4, 22, 26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '播放器设置',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Consumer(
                builder: (context, ref, _) {
                  final remaining = ref
                      .watch(playerControllerProvider)
                      .sleepTimerRemaining;
                  return Text(
                    remaining == null
                        ? '睡眠定时会在时间到后暂停当前播放。'
                        : '将在 ${formatDuration(remaining)} 后暂停播放。',
                    style: const TextStyle(color: Color(0xFF6C788B)),
                  );
                },
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final minutes in [15, 30, 45, 60])
                    OutlinedButton(
                      onPressed: () {
                        player.setSleepTimer(Duration(minutes: minutes));
                      },
                      child: Text('$minutes 分钟'),
                    ),
                  OutlinedButton.icon(
                    onPressed: () => _showCustomSleepTimer(player),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('自定义'),
                  ),
                  TextButton(
                    onPressed: () {
                      player.setSleepTimer(null);
                    },
                    child: const Text('关闭定时'),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.notifications_active_outlined),
                title: Text('后台播放与系统通知'),
                subtitle: Text('Android 已接入系统媒体服务：支持后台播放、通知栏、耳机与锁屏控制。'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showCustomSleepTimer(PlayerController player) async {
    final minutesController = TextEditingController();
    String? validationMessage;
    final minutes = await showDialog<int>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('自定义定时'),
          content: TextField(
            controller: minutesController,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: '暂停前播放时长（分钟）',
              hintText: '例如 90',
              helperText: '可设 1–720 分钟',
              errorText: validationMessage,
            ),
            onSubmitted: (_) {
              final value = int.tryParse(minutesController.text);
              if (value != null && value >= 1 && value <= 720) {
                Navigator.pop(dialogContext, value);
              } else {
                setDialogState(() {
                  validationMessage = '请输入 1 到 720 之间的分钟数';
                });
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final value = int.tryParse(minutesController.text);
                if (value != null && value >= 1 && value <= 720) {
                  Navigator.pop(dialogContext, value);
                  return;
                }
                setDialogState(() {
                  validationMessage = '请输入 1 到 720 之间的分钟数';
                });
              },
              child: const Text('开始定时'),
            ),
          ],
        ),
      ),
    );
    minutesController.dispose();
    if (minutes != null) {
      player.setSleepTimer(Duration(minutes: minutes));
    }
  }
}

class _LimeReferenceProgressPainter extends CustomPainter {
  const _LimeReferenceProgressPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final fraction = progress.clamp(0.0, 1.0);
    final y = size.height / 2;
    final start = Offset(1, y);
    final end = Offset(size.width - 1, y);
    final thumb = Offset(start.dx + (end.dx - start.dx) * fraction, y);

    canvas.drawLine(
      start,
      end,
      Paint()
        ..color = const Color(0xD64C765B)
        ..strokeWidth = 11
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawLine(
      start,
      end,
      Paint()
        ..color = const Color(0xFFE5EDD3)
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round,
    );
    if (fraction > 0) {
      canvas.drawLine(
        start,
        thumb,
        Paint()
          ..color = const Color(0xFF17452F)
          ..strokeWidth = 3.1
          ..strokeCap = StrokeCap.round,
      );
    }
    canvas.drawCircle(
      thumb,
      6.3,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.35, -0.38),
          colors: [Color(0xFFCDEA9F), Color(0xFF4C9A51), Color(0xFF1F5A35)],
        ).createShader(Rect.fromCircle(center: thumb, radius: 6.3)),
    );
    canvas.drawCircle(
      thumb,
      6.3,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xFFEAF1D8),
    );
  }

  @override
  bool shouldRepaint(covariant _LimeReferenceProgressPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _PlayerHeader extends StatelessWidget {
  const _PlayerHeader({
    required this.themeName,
    required this.onBack,
    required this.onTheme,
    required this.onMore,
  });

  final String themeName;
  final VoidCallback onBack;
  final VoidCallback onTheme;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Row(
        children: [
          _GlassIconButton(
            icon: Icons.keyboard_arrow_down_rounded,
            onPressed: onBack,
          ),
          const Spacer(),
          _GlassPillButton(themeName: themeName, onPressed: onTheme),
          const SizedBox(width: 4),
          _GlassIconButton(icon: Icons.more_horiz_rounded, onPressed: onMore),
          const SizedBox(width: 6),
          const _PlayerWindowControls(),
        ],
      ),
    );
  }
}

/// The shell title bar is intentionally absent on the immersive player page,
/// so these controls stay available while keeping the player visually full
/// screen. They use the same window-manager actions as the native caption.
class _PlayerWindowControls extends StatelessWidget {
  const _PlayerWindowControls();

  @override
  Widget build(BuildContext context) {
    return LiquidGlass(
      borderRadius: 20,
      blur: 18,
      dark: true,
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PlayerWindowControlButton(
            tooltip: '最小化',
            icon: Icons.remove_rounded,
            onPressed: () => windowManager.minimize(),
          ),
          _PlayerWindowControlButton(
            tooltip: '最大化或还原',
            icon: Icons.crop_square_rounded,
            onPressed: () async {
              if (await windowManager.isMaximized()) {
                await windowManager.unmaximize();
              } else {
                await windowManager.maximize();
              }
            },
          ),
          _PlayerWindowControlButton(
            tooltip: '关闭',
            icon: Icons.close_rounded,
            onPressed: () => windowManager.close(),
          ),
        ],
      ),
    );
  }
}

class _PlayerWindowControlButton extends StatelessWidget {
  const _PlayerWindowControlButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        color: Colors.white,
        splashRadius: 18,
        constraints: const BoxConstraints.tightFor(width: 36, height: 40),
        padding: EdgeInsets.zero,
      ),
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 48,
      child: LiquidGlass(
        borderRadius: 24,
        blur: 18,
        dark: true,
        child: IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 48, height: 48),
          onPressed: onPressed,
          color: Colors.white,
          icon: Icon(icon),
        ),
      ),
    );
  }
}

class _GlassPillButton extends StatelessWidget {
  const _GlassPillButton({required this.themeName, required this.onPressed});

  final String themeName;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: LiquidGlass(
        borderRadius: 24,
        blur: 18,
        dark: true,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.palette_outlined,
                    color: Colors.white,
                    size: 18,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    themeName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassPanel extends StatelessWidget {
  const _GlassPanel({
    required this.child,
    this.compact = false,
    this.limeJelly = false,
  });

  final Widget child;
  final bool compact;
  final bool limeJelly;

  @override
  Widget build(BuildContext context) {
    return LiquidGlass(
      borderRadius: limeJelly ? 34 : 26,
      blur: compact ? 24 : 28,
      dark: true,
      borderWidth: 1.25,
      padding: EdgeInsets.all(compact ? (limeJelly ? 14 : 16) : 22),
      child: child,
    );
  }
}

class _DesktopMvControlBar extends ConsumerWidget {
  const _DesktopMvControlBar({
    required this.track,
    required this.playback,
    required this.mode,
    required this.onModeChanged,
  });

  final Track? track;
  final PlaybackState playback;
  final PlayerVisualMode mode;
  final ValueChanged<PlayerVisualMode> onModeChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.read(playerControllerProvider.notifier);
    final library = ref.read(libraryControllerProvider.notifier);
    final appearance = ref.watch(appearanceControllerProvider);
    final accent = appearance.accent;
    final accentForeground =
        ThemeData.estimateBrightnessForColor(accent) == Brightness.dark
        ? Colors.white
        : const Color(0xFF111523);
    return LiquidGlass(
      borderRadius: 24,
      blur: 26,
      dark: true,
      borderWidth: 1.15,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      child: SizedBox(
        height: 62,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final showModeSwitch = constraints.maxWidth >= 1080;
            return Row(
              children: [
                // Three balanced areas: song information, transport and
                // secondary actions. This keeps the playback button centered
                // while both sides remain intentionally useful.
                Expanded(
                  flex: 4,
                  child: Row(
                    children: [
                      TrackArtwork(track: track, size: 50, borderRadius: 15),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              track == null
                                  ? context.tr('还没有播放歌曲')
                                  : context.metadata(track!.title),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              track == null
                                  ? '从曲库中选择一首歌曲'
                                  : '${context.metadata(track!.artist)}  ·  ${context.metadata(track!.album)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.68),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 3,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        tooltip: '上一首',
                        onPressed: track == null ? null : player.previous,
                        color: Colors.white,
                        icon: const Icon(Icons.skip_previous_rounded),
                      ),
                      const SizedBox(width: 6),
                      _PrimaryPlayButton(
                        size: 46,
                        enabled: track != null,
                        isPlaying: playback.isPlaying,
                        onPressed: player.togglePlayPause,
                        accent: accent,
                        foreground: accentForeground,
                        limeJelly: false,
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        tooltip: '下一首',
                        onPressed: track == null ? null : player.next,
                        color: Colors.white,
                        icon: const Icon(Icons.skip_next_rounded),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 4,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (showModeSwitch)
                        _ModeSwitch(
                          mode: mode,
                          hasAudio: track != null && !track!.isVideoOnly,
                          hasVideo:
                              track?.hasVideo == true ||
                              track?.isVideoOnly == true,
                          onChanged: onModeChanged,
                        )
                      else
                        IconButton(
                          tooltip: '切换到唱片播放',
                          onPressed: track != null && !track!.isVideoOnly
                              ? () => onModeChanged(PlayerVisualMode.vinyl)
                              : null,
                          color: Colors.white.withValues(alpha: 0.88),
                          icon: const Icon(Icons.album_rounded),
                        ),
                      const SizedBox(width: 8),
                      PlaybackModeButton(
                        enabled: track != null,
                        color: Colors.white.withValues(alpha: 0.88),
                        activeColor: accent,
                        compact: true,
                        iconSize: 31,
                      ),
                      IconButton(
                        tooltip: '播放队列',
                        onPressed: track == null
                            ? null
                            : () => PlayerInformation.showQueue(context, ref),
                        color: Colors.white.withValues(alpha: 0.88),
                        iconSize: 31,
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.queue_music_rounded),
                      ),
                      _PlayerVolumeButton(
                        enabled: track != null,
                        accent: accent,
                      ),
                      IconButton(
                        tooltip: track?.isFavorite == true ? '取消收藏' : '收藏',
                        onPressed: track == null
                            ? null
                            : () => library.toggleFavorite(track!),
                        color: track?.isFavorite == true
                            ? accent
                            : Colors.white.withValues(alpha: 0.88),
                        iconSize: 31,
                        icon: Icon(
                          track?.isFavorite == true
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class PlayerInformation extends ConsumerWidget {
  const PlayerInformation({
    super.key,
    required this.track,
    required this.playback,
    required this.mode,
    required this.onModeChanged,
    this.compact = false,
  });

  final Track? track;
  final PlaybackState playback;
  final PlayerVisualMode mode;
  final ValueChanged<PlayerVisualMode> onModeChanged;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.read(playerControllerProvider.notifier);
    final library = ref.read(libraryControllerProvider.notifier);
    final appearance = ref.watch(appearanceControllerProvider);
    final accent = appearance.accent;
    final accentForeground =
        ThemeData.estimateBrightnessForColor(accent) == Brightness.dark
        ? Colors.white
        : const Color(0xFF111523);
    final timelineDuration = _seekableDuration(playback, track);
    final hasSeekableDuration = timelineDuration > Duration.zero;
    final max = hasSeekableDuration
        ? timelineDuration.inMilliseconds.toDouble()
        : 1.0;
    final value = hasSeekableDuration
        ? playback.position.inMilliseconds.clamp(0, max.toInt()).toDouble()
        : 0.0;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ModeSwitch(
          mode: mode,
          hasAudio: track != null && !track!.isVideoOnly,
          hasVideo: track?.hasVideo == true || track?.isVideoOnly == true,
          onChanged: onModeChanged,
        ),
        SizedBox(height: compact ? 12 : 26),
        if (compact)
          Row(
            children: [
              Expanded(
                child: Text(
                  track == null
                      ? context.tr('还没有播放歌曲')
                      : context.metadata(track!.title),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    height: 1.15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: track?.isFavorite == true ? '取消收藏' : '收藏',
                onPressed: track == null
                    ? null
                    : () => library.toggleFavorite(track!),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black.withValues(alpha: 0.14),
                  foregroundColor: track?.isFavorite == true
                      ? accent
                      : Colors.white.withValues(alpha: 0.88),
                  disabledForegroundColor: Colors.white30,
                ),
                icon: Icon(
                  track?.isFavorite == true
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                ),
              ),
            ],
          )
        else
          Text(
            track == null
                ? context.tr('还没有播放歌曲')
                : context.metadata(track!.title),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 30,
              height: 1.15,
              fontWeight: FontWeight.w800,
            ),
          ),
        SizedBox(height: compact ? 4 : 8),
        Text(
          track == null
              ? context.tr('从曲库中选择一首歌')
              : '${context.metadata(track!.artist)}  ·  ${context.metadata(track!.album)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.66),
            fontSize: compact ? 13 : 15,
          ),
        ),
        SizedBox(height: compact ? 8 : 18),
        _ResponsiveSeekBar(
          value: value,
          max: max,
          enabled: track != null && hasSeekableDuration,
          onSeek: player.seek,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              Text(
                formatDuration(playback.position),
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
              const Spacer(),
              Text(
                formatDuration(timelineDuration),
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ],
          ),
        ),
        SizedBox(height: compact ? 8 : 18),
        if (compact)
          _MobilePlayerControls(
            track: track,
            playback: playback,
            accent: accent,
            accentForeground: accentForeground,
            limeJelly: false,
            onShowQueue: () => PlayerInformation.showQueue(context, ref),
          ),
        if (!compact)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                tooltip: track?.isFavorite == true ? '取消收藏' : '收藏',
                onPressed: track == null
                    ? null
                    : () => library.toggleFavorite(track!),
                color: track?.isFavorite == true
                    ? accent
                    : Colors.white.withValues(alpha: 0.88),
                iconSize: compact ? 29 : 37,
                visualDensity: VisualDensity.compact,
                constraints: compact
                    ? const BoxConstraints.tightFor(width: 34, height: 44)
                    : null,
                padding: compact ? EdgeInsets.zero : null,
                icon: Icon(
                  track?.isFavorite == true
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                ),
              ),
              PlaybackModeButton(
                enabled: track != null,
                color: Colors.white.withValues(alpha: 0.88),
                activeColor: accent,
                compact: compact,
                iconSize: compact ? 29 : 37,
              ),
              IconButton(
                onPressed: track == null ? null : player.previous,
                color: Colors.white,
                iconSize: compact ? 29 : 37,
                visualDensity: VisualDensity.compact,
                constraints: compact
                    ? const BoxConstraints.tightFor(width: 36, height: 44)
                    : null,
                padding: compact ? EdgeInsets.zero : null,
                icon: const Icon(Icons.skip_previous_rounded),
              ),
              _PrimaryPlayButton(
                size: compact ? 58 : 72,
                enabled: track != null,
                isPlaying: playback.isPlaying,
                onPressed: player.togglePlayPause,
                accent: accent,
                foreground: accentForeground,
                limeJelly: false,
              ),
              IconButton(
                onPressed: track == null ? null : player.next,
                color: Colors.white,
                iconSize: compact ? 29 : 37,
                visualDensity: VisualDensity.compact,
                constraints: compact
                    ? const BoxConstraints.tightFor(width: 36, height: 44)
                    : null,
                padding: compact ? EdgeInsets.zero : null,
                icon: const Icon(Icons.skip_next_rounded),
              ),
              IconButton(
                tooltip: '播放队列',
                onPressed: track == null
                    ? null
                    : () => PlayerInformation.showQueue(context, ref),
                color: Colors.white.withValues(alpha: 0.88),
                iconSize: compact ? 29 : 37,
                visualDensity: VisualDensity.compact,
                constraints: compact
                    ? const BoxConstraints.tightFor(width: 34, height: 44)
                    : null,
                padding: compact ? EdgeInsets.zero : null,
                icon: const Icon(Icons.queue_music_rounded),
              ),
              if (!compact)
                _PlayerVolumeButton(
                  enabled: track != null,
                  accent: accent,
                  compact: compact,
                ),
            ],
          ),
      ],
    );
  }

  static Future<void> showQueue(BuildContext context, WidgetRef ref) async {
    final controller = ref.read(playerControllerProvider.notifier);
    final tracks = controller.queue;
    final playback = ref.read(playerControllerProvider);
    if (MediaQuery.sizeOf(context).width >= 760) {
      final accent = ref.read(appearanceControllerProvider).accent;
      await showGeneralDialog<void>(
        context: context,
        barrierDismissible: true,
        barrierLabel: '关闭播放队列',
        barrierColor: Colors.black.withValues(alpha: 0.10),
        transitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (dialogContext, _, _) => Align(
          alignment: Alignment.centerRight,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 18, 18, 126),
              child: SizedBox(
                width: 380,
                child: LiquidGlass(
                  borderRadius: 24,
                  blur: 26,
                  tint: accent,
                  padding: const EdgeInsets.fromLTRB(14, 16, 10, 10),
                  child: Material(
                    color: Colors.transparent,
                    child: SizedBox(
                      height: MediaQuery.sizeOf(context).height * 0.70,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(8, 0, 4, 12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        '播放队列',
                                        style: TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        '${playback.queueSource} · ${tracks.length} 首',
                                        style: const TextStyle(
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: '关闭',
                                  onPressed: () => Navigator.pop(dialogContext),
                                  icon: const Icon(Icons.close_rounded),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: ListView.separated(
                              padding: const EdgeInsets.only(right: 4),
                              itemCount: tracks.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 5),
                              itemBuilder: (context, index) {
                                final item = tracks[index];
                                final current =
                                    item.id == playback.currentTrack?.id;
                                return Material(
                                  color: current
                                      ? accent.withValues(alpha: 0.17)
                                      : Colors.white.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(15),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(15),
                                    onTap: () async {
                                      await controller.playTrack(
                                        item,
                                        tracks,
                                        source: playback.queueSource,
                                      );
                                      if (dialogContext.mounted) {
                                        Navigator.pop(dialogContext);
                                      }
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 8,
                                      ),
                                      child: Row(
                                        children: [
                                          TrackArtwork(
                                            track: item,
                                            size: 42,
                                            borderRadius: 12,
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  item.title,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    height: 1.24,
                                                    fontWeight: current
                                                        ? FontWeight.w600
                                                        : FontWeight.w500,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  item.artist,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    color:
                                                        AppColors.textSecondary,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          current
                                              ? Icon(
                                                  Icons.graphic_eq_rounded,
                                                  color: accent,
                                                )
                                              : Text(
                                                  formatDuration(item.duration),
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    color:
                                                        AppColors.textSecondary,
                                                  ),
                                                ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        transitionBuilder: (_, animation, _, child) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: SlideTransition(
            position:
                Tween<Offset>(
                  begin: const Offset(0.08, 0),
                  end: Offset.zero,
                ).animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  ),
                ),
            child: child,
          ),
        ),
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.62,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 2, 22, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '播放队列',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '来自：${playback.queueSource} · ${tracks.length} 首',
                      style: const TextStyle(color: Color(0xFF7D8799)),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: tracks.length,
                  itemBuilder: (context, index) {
                    final item = tracks[index];
                    final current = item.id == playback.currentTrack?.id;
                    return ListTile(
                      selected: current,
                      leading: TrackArtwork(
                        track: item,
                        size: 44,
                        borderRadius: 12,
                      ),
                      title: Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.trackTitleStyle,
                      ),
                      subtitle: Text(item.artist),
                      trailing: current
                          ? const Icon(Icons.graphic_eq_rounded)
                          : Text(formatDuration(item.duration)),
                      onTap: () async {
                        await ref
                            .read(playerControllerProvider.notifier)
                            .playTrack(
                              item,
                              tracks,
                              source: playback.queueSource,
                            );
                        if (sheetContext.mounted) Navigator.pop(sheetContext);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MobilePlayerControls extends ConsumerWidget {
  const _MobilePlayerControls({
    required this.track,
    required this.playback,
    required this.accent,
    required this.accentForeground,
    required this.limeJelly,
    required this.onShowQueue,
  });

  final Track? track;
  final PlaybackState playback;
  final Color accent;
  final Color accentForeground;
  final bool limeJelly;
  final VoidCallback onShowQueue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.read(playerControllerProvider.notifier);
    final enabled = track != null;
    return SizedBox(
      height: 58,
      child: Row(
        children: [
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                PlaybackModeButton(
                  enabled: enabled,
                  color: Colors.white.withValues(alpha: 0.88),
                  activeColor: accent,
                  compact: true,
                ),
                _CompactPlayerIcon(
                  enabled: enabled,
                  onPressed: player.previous,
                  icon: Icons.skip_previous_rounded,
                ),
              ],
            ),
          ),
          _PrimaryPlayButton(
            size: 58,
            enabled: enabled,
            isPlaying: playback.isPlaying,
            onPressed: player.togglePlayPause,
            accent: accent,
            foreground: accentForeground,
            limeJelly: limeJelly,
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _CompactPlayerIcon(
                  enabled: enabled,
                  onPressed: player.next,
                  icon: Icons.skip_next_rounded,
                ),
                _CompactPlayerIcon(
                  enabled: enabled,
                  onPressed: onShowQueue,
                  icon: Icons.queue_music_rounded,
                  color: Colors.white.withValues(alpha: 0.88),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PrimaryPlayButton extends StatelessWidget {
  const _PrimaryPlayButton({
    required this.size,
    required this.enabled,
    required this.isPlaying,
    required this.onPressed,
    required this.accent,
    required this.foreground,
    required this.limeJelly,
  });

  final double size;
  final bool enabled;
  final bool isPlaying;
  final VoidCallback onPressed;
  final Color accent;
  final Color foreground;
  final bool limeJelly;

  @override
  Widget build(BuildContext context) {
    final icon = Icon(
      isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
      size: size * 0.54,
      color: limeJelly ? const Color(0xFFF4FFE9) : foreground,
    );
    if (!limeJelly) {
      return SizedBox.square(
        dimension: size,
        child: FilledButton(
          onPressed: enabled ? onPressed : null,
          style: FilledButton.styleFrom(
            backgroundColor: accent,
            foregroundColor: foreground,
            padding: EdgeInsets.zero,
            shape: const CircleBorder(),
            elevation: 8,
            shadowColor: accent.withValues(alpha: 0.50),
          ),
          child: icon,
        ),
      );
    }
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            center: const Alignment(-0.34, -0.42),
            colors: [
              const Color(0xFFDFFFC9).withValues(alpha: enabled ? 0.76 : 0.30),
              const Color(0xFF78E879).withValues(alpha: enabled ? 0.54 : 0.20),
              const Color(0xFF256C44).withValues(alpha: enabled ? 0.68 : 0.28),
            ],
          ),
          border: Border.all(
            color: const Color(0xFFF0FFE8)
                .withValues(alpha: enabled ? 0.68 : 0.26),
            width: 1.25,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF75FF82)
                  .withValues(alpha: enabled ? 0.32 : 0.10),
              blurRadius: 18,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            onTap: enabled ? onPressed : null,
            customBorder: const CircleBorder(),
            child: Center(child: icon),
          ),
        ),
      ),
    );
  }
}

class _CompactPlayerIcon extends StatelessWidget {
  const _CompactPlayerIcon({
    required this.enabled,
    required this.onPressed,
    required this.icon,
    this.color = Colors.white,
  });

  final bool enabled;
  final VoidCallback onPressed;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: enabled ? onPressed : null,
      color: color,
      iconSize: 28,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 34, height: 44),
      padding: EdgeInsets.zero,
      icon: Icon(icon),
    );
  }
}

class _PlayerVolumeButton extends StatelessWidget {
  const _PlayerVolumeButton({
    required this.enabled,
    required this.accent,
    this.compact = false,
  });

  final bool enabled;
  final Color accent;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return HoverVolumeButton(
      enabled: enabled,
      accent: accent,
      mutedColor: Colors.white.withValues(alpha: 0.88),
      constraints: compact
          ? const BoxConstraints.tightFor(width: 36, height: 44)
          : null,
      padding: compact ? EdgeInsets.zero : null,
      iconSize: compact ? 29 : 37,
    );
  }
}

class _BottomEdgeTimeline extends StatelessWidget {
  const _BottomEdgeTimeline({
    required this.value,
    required this.max,
    required this.enabled,
    required this.accent,
    required this.onSeek,
  });

  final double value;
  final double max;
  final bool enabled;
  final Color accent;
  final Future<void> Function(Duration) onSeek;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 24,
      child: SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: 3,
          activeTrackColor: accent,
          inactiveTrackColor: Colors.white.withValues(alpha: 0.28),
          thumbColor: Colors.white,
          overlayColor: accent.withValues(alpha: 0.18),
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
        ),
        child: _ResponsiveSeekBar(
          value: value,
          max: max,
          enabled: enabled,
          onSeek: onSeek,
        ),
      ),
    );
  }
}

Duration _seekableDuration(PlaybackState playback, Track? track) {
  if (playback.duration > Duration.zero) return playback.duration;
  final fallbackDuration = track?.duration ?? Duration.zero;
  if (fallbackDuration > Duration.zero) return fallbackDuration;
  return Duration.zero;
}

class _ResponsiveSeekBar extends StatefulWidget {
  const _ResponsiveSeekBar({
    required this.value,
    required this.max,
    required this.enabled,
    required this.onSeek,
  });

  final double value;
  final double max;
  final bool enabled;
  final Future<void> Function(Duration) onSeek;

  @override
  State<_ResponsiveSeekBar> createState() => _ResponsiveSeekBarState();
}

class _ResponsiveSeekBarState extends State<_ResponsiveSeekBar> {
  double? _preview;

  @override
  void didUpdateWidget(covariant _ResponsiveSeekBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final preview = _preview;
    if (preview == null) return;
    // Only release the visual preview once the native player confirms the
    // target. Clearing it on a fixed timer exposed the old 0:00 position and
    // made every drag visibly snap back.
    if ((widget.value - preview).abs() < 750) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _preview = null);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Slider(
      value: (_preview ?? widget.value).clamp(0, widget.max),
      max: widget.max,
      activeColor: Colors.white,
      inactiveColor: Colors.white24,
      thumbColor: Colors.white,
      onChanged: widget.enabled
          ? (next) => setState(() => _preview = next)
          : null,
      onChangeEnd: widget.enabled
          ? (next) async {
              setState(() => _preview = next);
              await widget.onSeek(Duration(milliseconds: next.round()));
            }
          : null,
    );
  }
}

class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({
    required this.mode,
    required this.hasAudio,
    required this.hasVideo,
    required this.onChanged,
  });

  final PlayerVisualMode mode;
  final bool hasAudio;
  final bool hasVideo;
  final ValueChanged<PlayerVisualMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (hasAudio)
          _ModePill(
            selected: mode == PlayerVisualMode.vinyl,
            icon: Icons.album_rounded,
            label: '唱片',
            onTap: () => onChanged(PlayerVisualMode.vinyl),
          ),
        _ModePill(
          selected: mode == PlayerVisualMode.musicVideo,
          icon: Icons.ondemand_video_rounded,
          label: hasAudio ? (hasVideo ? 'MV · 已配对' : '关联 MV') : 'MV',
          onTap: () => onChanged(PlayerVisualMode.musicVideo),
        ),
      ],
    );
  }
}

class _ModePill extends StatelessWidget {
  const _ModePill({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return LiquidGlass(
      borderRadius: 30,
      blur: 16,
      dark: !selected,
      borderWidth: selected ? 1.35 : 1.05,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: selected ? null : onTap,
          borderRadius: BorderRadius.circular(30),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 17,
                  color: selected ? const Color(0xFF131827) : Colors.white,
                ),
                const SizedBox(width: 7),
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? const Color(0xFF131827) : Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MvStage extends ConsumerWidget {
  const _MvStage({
    super.key,
    required this.track,
    required this.controller,
    required this.onAttachVideo,
    required this.videoReady,
    required this.videoTimedOut,
    required this.videoStatus,
    this.expand = false,
  });

  final Track? track;
  final VideoController controller;
  final VoidCallback? onAttachVideo;
  final bool videoReady;
  final bool videoTimedOut;
  final String videoStatus;
  final bool expand;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (track?.hasVideo != true && track?.isVideoOnly != true) {
      return _MissingMediaStage(
        icon: Icons.ondemand_video_rounded,
        label: '还没有配对 MV',
        onTap: onAttachVideo,
      );
    }
    final playback = ref.watch(playerControllerProvider);
    final player = ref.read(playerControllerProvider.notifier);
    final appearance = ref.watch(appearanceControllerProvider);
    final timelineDuration = _seekableDuration(playback, track);
    final seekable = timelineDuration > Duration.zero;
    final max = seekable ? timelineDuration.inMilliseconds.toDouble() : 1.0;
    final value = seekable
        ? playback.position.inMilliseconds.clamp(0, max.toInt()).toDouble()
        : 0.0;
    final video = LiquidGlass(
      borderRadius: expand ? 30 : 26,
      // Windows renders media_kit's video as a native texture.  Keeping that
      // texture below a BackdropFilter makes its first compositor attach
      // unreliable (audio starts while the video stays black).  The stage
      // still keeps its translucent rim and layered surface, but must not
      // blur the native output itself.
      blur: 0,
      dark: true,
      borderWidth: 1.25,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Deliberately no tap handler here: clicking the MV is not a pause
          // gesture. Playback is controlled from the compact strip below.
          // Recreate the texture widget when the queue advances. Reusing one
          // native texture for a new media source is what left the previous
          // MV frame (or a black frame) on screen while audio had changed.
          Video(
            key: ValueKey('mv-output-${track?.id}'),
            controller: controller,
            controls: NoVideoControls,
          ),
          IgnorePointer(
            child: AnimatedOpacity(
              opacity: videoReady ? 0 : 1,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFF101827).withValues(alpha: 0.86),
                      const Color(0xFF07101E).withValues(alpha: 0.94),
                    ],
                  ),
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (videoTimedOut)
                        Icon(
                          Icons.videocam_off_rounded,
                          color: Colors.white.withValues(alpha: 0.76),
                          size: 25,
                        )
                      else
                        SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: appearance.accent,
                          ),
                        ),
                      const SizedBox(height: 12),
                      Text(
                        videoStatus,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: Colors.white.withValues(alpha: 0.88),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (seekable)
            Positioned(
              left: expand ? 24 : 16,
              right: expand ? 24 : 16,
              bottom: expand ? 12 : 8,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.32),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: _BottomEdgeTimeline(
                    value: value,
                    max: max,
                    enabled: true,
                    accent: appearance.accent,
                    onSeek: player.seek,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    if (expand) {
      return LayoutBuilder(
        builder: (context, constraints) => Center(
          child: AspectRatio(aspectRatio: 16 / 9, child: video),
        ),
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 660, maxHeight: 430),
      child: AspectRatio(aspectRatio: 16 / 9, child: video),
    );
  }
}

class _MissingMediaStage extends StatelessWidget {
  const _MissingMediaStage({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 660, maxHeight: 430),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: LiquidGlass(
            borderRadius: 26,
            blur: 26,
            dark: true,
            borderWidth: 1.25,
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: onTap,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, color: Colors.white, size: 58),
                    const SizedBox(height: 15),
                    Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
