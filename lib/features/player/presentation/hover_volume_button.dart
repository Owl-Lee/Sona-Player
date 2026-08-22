import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/performance/visual_effects.dart';
import '../application/player_controller.dart';

double hoverVolumePopoverBlurFor(VisualEffectsMode mode) => 20 * mode.blurScale;

double hoverVolumePopoverShadowBlurFor(VisualEffectsMode mode) =>
    switch (mode) {
      VisualEffectsMode.full => 22,
      VisualEffectsMode.energySaver => 12,
      VisualEffectsMode.off => 5,
    };

/// Desktop-first volume control: hover to adjust, click to toggle mute.
///
/// The floating control lives in the root overlay so it is never clipped by
/// the compact player bar or by the full-player glass panels. Touch users can
/// still long-press the same icon to open the slider.
class HoverVolumeButton extends ConsumerStatefulWidget {
  const HoverVolumeButton({
    super.key,
    required this.enabled,
    required this.accent,
    required this.mutedColor,
    this.iconSize = 31,
    this.constraints,
    this.padding,
    this.visualDensity,
  });

  final bool enabled;
  final Color accent;
  final Color mutedColor;
  final double iconSize;
  final BoxConstraints? constraints;
  final EdgeInsetsGeometry? padding;
  final VisualDensity? visualDensity;

  @override
  ConsumerState<HoverVolumeButton> createState() => _HoverVolumeButtonState();
}

class _HoverVolumeButtonState extends ConsumerState<HoverVolumeButton> {
  static const _dismissDelay = Duration(milliseconds: 320);

  final _layerLink = LayerLink();
  OverlayEntry? _popoverEntry;
  Timer? _dismissTimer;
  var _buttonHovered = false;
  var _popoverHovered = false;

  void _showPopover() {
    if (!widget.enabled) return;
    _dismissTimer?.cancel();
    if (_popoverEntry != null) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    final entry = OverlayEntry(
      builder: (context) => Positioned(
        width: 64,
        height: 204,
        child: CompositedTransformFollower(
          link: _layerLink,
          targetAnchor: Alignment.topCenter,
          followerAnchor: Alignment.bottomCenter,
          offset: const Offset(0, -10),
          child: MouseRegion(
            onEnter: (_) {
              _popoverHovered = true;
              _dismissTimer?.cancel();
            },
            onExit: (_) {
              _popoverHovered = false;
              _scheduleDismiss();
            },
            child: _HoverVolumePopover(accent: widget.accent),
          ),
        ),
      ),
    );
    _popoverEntry = entry;
    overlay.insert(entry);
  }

  void _scheduleDismiss() {
    _dismissTimer?.cancel();
    _dismissTimer = Timer(_dismissDelay, () {
      if (!_buttonHovered && !_popoverHovered) _removePopover();
    });
  }

  void _removePopover() {
    _dismissTimer?.cancel();
    _dismissTimer = null;
    _popoverEntry?.remove();
    _popoverEntry = null;
  }

  @override
  void dispose() {
    _removePopover();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final volume = ref.watch(
      playerControllerProvider.select((state) => state.volume),
    );
    final controller = ref.read(playerControllerProvider.notifier);
    final icon = volume == 0
        ? Icons.volume_off_rounded
        : volume < 45
        ? Icons.volume_down_rounded
        : Icons.volume_up_rounded;
    return CompositedTransformTarget(
      link: _layerLink,
      child: MouseRegion(
        onEnter: (_) {
          if (!_buttonHovered) setState(() => _buttonHovered = true);
          _showPopover();
        },
        onExit: (_) {
          if (_buttonHovered) setState(() => _buttonHovered = false);
          _scheduleDismiss();
        },
        child: AnimatedScale(
          scale: _buttonHovered ? 1.13 : 1,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          child: IconButton(
            // The control is self-explanatory. Keeping this tooltip empty also
            // avoids a second floating label competing with the volume slider.
            tooltip: null,
            onPressed: widget.enabled ? controller.toggleMute : null,
            onLongPress: widget.enabled ? _showPopover : null,
            color: volume == 0 ? widget.mutedColor : widget.accent,
            iconSize: widget.iconSize,
            constraints: widget.constraints,
            padding: widget.padding,
            visualDensity: widget.visualDensity,
            icon: Icon(icon),
          ),
        ),
      ),
    );
  }
}

class _HoverVolumePopover extends ConsumerWidget {
  const _HoverVolumePopover({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(
      playerControllerProvider.select((state) => state.volume),
    );
    final controller = ref.read(playerControllerProvider.notifier);
    final effectsMode = VisualEffectsScope.maybeOf(context);
    final blur = hoverVolumePopoverBlurFor(effectsMode);
    final shadowAlpha = switch (effectsMode) {
      VisualEffectsMode.full => 0x26,
      VisualEffectsMode.energySaver => 0x16,
      VisualEffectsMode.off => 0x0C,
    };
    final surface = Container(
      width: 64,
      height: 204,
      padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.52)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.25),
            accent.withValues(alpha: 0.16),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: Color.fromARGB(shadowAlpha, 0, 0, 0),
            blurRadius: hoverVolumePopoverShadowBlurFor(effectsMode),
            offset: Offset(0, effectsMode == VisualEffectsMode.full ? 9 : 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            '${current.round()}%',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: Colors.white,
              fontSize: 11,
            ),
          ),
          Expanded(
            child: RotatedBox(
              quarterTurns: 3,
              child: Slider(
                value: current.clamp(0, 100),
                max: 100,
                activeColor: accent,
                inactiveColor: Colors.white30,
                onChanged: controller.setVolume,
              ),
            ),
          ),
        ],
      ),
    );
    return Material(
      type: MaterialType.transparency,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: blur <= 0
            ? surface
            : BackdropFilter(
                filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                child: surface,
              ),
      ),
    );
  }
}
