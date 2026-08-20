import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/sona_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/liquid_glass.dart';
import '../../library/presentation/widgets/track_artwork.dart';
import '../application/player_controller.dart';
import 'now_playing_page.dart';
import 'hover_volume_button.dart';
import 'playback_mode_button.dart';
import '../../settings/application/appearance_controller.dart';

class NowPlayingBar extends ConsumerWidget {
  const NowPlayingBar({super.key, required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playback = ref.watch(playerControllerProvider);
    final controller = ref.read(playerControllerProvider.notifier);
    final appearance = ref.watch(appearanceControllerProvider);
    final accent = appearance.accent;
    final lightForeground =
        !appearance.usesCustom && appearance.preset.prefersLightHomeForeground;
    final foreground = lightForeground ? Colors.white : AppColors.textPrimary;
    final mutedForeground = lightForeground
        ? Colors.white.withValues(alpha: 0.88)
        : AppColors.textSecondary;
    final accentForeground =
        ThemeData.estimateBrightnessForColor(accent) == Brightness.dark
        ? Colors.white
        : AppColors.ink;
    final track = playback.currentTrack;
    final progress = playback.duration.inMilliseconds == 0
        ? 0.0
        : (playback.position.inMilliseconds / playback.duration.inMilliseconds)
              .clamp(0.0, 1.0);

    if (compact) {
      return Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Color.alphaBlend(
            accent.withValues(alpha: 0.07),
            Colors.white.withValues(alpha: 0.94),
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppColors.outline),
          boxShadow: const [
            BoxShadow(
              color: Color(0x160B1730),
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(
              minHeight: 2,
              value: progress,
              color: accent,
              backgroundColor: Colors.transparent,
            ),
            SizedBox(
              height: 60,
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: track == null ? null : () => _openPlayer(context),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(9, 5, 4, 5),
                        child: Row(
                          children: [
                            TrackArtwork(
                              track: track,
                              size: 46,
                              borderRadius: 23,
                            ),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    track == null
                                        ? context.tr('还没有播放歌曲')
                                        : context.metadata(track.title),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTheme.trackTitleStyle,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    track == null
                                        ? context.tr('从曲库选择一首歌')
                                        : context.metadata(track.artist),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  SizedBox.square(
                    dimension: 42,
                    child: FilledButton(
                      onPressed: track == null
                          ? null
                          : controller.togglePlayPause,
                      style: FilledButton.styleFrom(
                        padding: EdgeInsets.zero,
                        shape: const CircleBorder(),
                        backgroundColor: accent,
                        foregroundColor: accentForeground,
                      ),
                      child: Icon(
                        playback.isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        size: 26,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: track == null ? null : controller.next,
                    iconSize: 26,
                    icon: const Icon(Icons.skip_next_rounded),
                  ),
                  const SizedBox(width: 5),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // An idle player is an invitation to choose music, not a disabled version
    // of the full transport bar. Keep this state intentionally small and calm.
    if (track == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
        child: LiquidGlass(
          borderRadius: 24,
          blur: 18,
          tint: accent.withValues(alpha: 0.28),
          dark: false,
          child: SizedBox(
            height: 84,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Row(
                children: [
                  TrackArtwork(track: null, size: 58, borderRadius: 29),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.tr('还没有播放歌曲'),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          context.tr('从曲库中选择一首歌，播放控制会出现在这里。'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () =>
                        Navigator.of(context)
                            .popUntil((route) => route.isFirst),
                    icon: const Icon(Icons.library_music_outlined),
                    label: Text(context.tr('去曲库')),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final currentTrack = track;

    final maxPosition = playback.duration.inMilliseconds > 0
        ? playback.duration.inMilliseconds.toDouble()
        : 1.0;
    final currentPosition = playback.position.inMilliseconds
        .clamp(0, maxPosition.toInt())
        .toDouble();

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
      child: LiquidGlass(
        borderRadius: 26,
        blur: 22,
        tint: accent,
        dark: lightForeground,
        child: IconTheme(
          data: IconThemeData(color: mutedForeground),
          child: SizedBox(
            height: 102,
            child: Column(
              children: [
                SizedBox(
                  height: 3,
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      thumbShape: SliderComponentShape.noThumb,
                      overlayShape: SliderComponentShape.noOverlay,
                      trackHeight: 3,
                    ),
                    child: _DeferredSeekSlider(
                      value: currentPosition,
                      max: maxPosition,
                      enabled: true,
                      accent: accent,
                      onSeek: controller.seek,
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        // The shell keeps its navigation rail on desktop, so the
                        // available player width can be much smaller than the
                        // window width. Collapse secondary controls first rather
                        // than letting the title or transport controls wrap.
                        final condensed = constraints.maxWidth < 1010;
                        final veryTight = constraints.maxWidth < 700;
                        final infoWidth = condensed
                            ? (veryTight ? 170.0 : 230.0)
                            : 280.0;
                        final utilityWidth = condensed
                            ? (veryTight ? 48.0 : 140.0)
                            : 190.0;

                        return Row(
                          children: [
                            SizedBox(
                              width: infoWidth,
                              child: InkWell(
                                onTap: () => _openPlayer(context),
                                borderRadius: BorderRadius.circular(14),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 7,
                                  ),
                                  child: Row(
                                    children: [
                                      TrackArtwork(
                                        track: currentTrack,
                                        size: 64,
                                        borderRadius: 32,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              context.metadata(
                                                currentTrack.title,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleMedium
                                                  ?.copyWith(color: foreground),
                                            ),
                                            const SizedBox(height: 3),
                                            Text(
                                              context.metadata(
                                                currentTrack.artist,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodyMedium
                                                  ?.copyWith(
                                                    color: mutedForeground,
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  PlaybackModeButton(
                                    enabled: true,
                                    color: mutedForeground,
                                    activeColor: accent,
                                  ),
                                  IconButton(
                                    tooltip: context.tr('上一首'),
                                    onPressed: controller.previous,
                                    icon: const Icon(
                                      Icons.skip_previous_rounded,
                                    ),
                                    color: mutedForeground,
                                    iconSize: 31,
                                  ),
                                  const SizedBox(width: 4),
                                  FilledButton(
                                    onPressed: controller.togglePlayPause,
                                    style: FilledButton.styleFrom(
                                      shape: const CircleBorder(),
                                      padding: const EdgeInsets.all(15),
                                      backgroundColor: accent,
                                      foregroundColor: accentForeground,
                                      shadowColor: accent.withValues(
                                        alpha: 0.42,
                                      ),
                                      elevation: 5,
                                    ),
                                    child: Icon(
                                      playback.isPlaying
                                          ? Icons.pause_rounded
                                          : Icons.play_arrow_rounded,
                                      size: 31,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  IconButton(
                                    tooltip: context.tr('下一首'),
                                    onPressed: controller.next,
                                    icon: const Icon(Icons.skip_next_rounded),
                                    color: mutedForeground,
                                    iconSize: 31,
                                  ),
                                  IconButton(
                                    tooltip: context.tr('播放队列'),
                                    onPressed: () =>
                                        PlayerInformation.showQueue(
                                          context,
                                          ref,
                                        ),
                                    icon: const Icon(Icons.queue_music_rounded),
                                    color: mutedForeground,
                                    iconSize: 31,
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(
                              width: utilityWidth,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  if (!veryTight)
                                    Text(
                                      condensed
                                          ? formatDuration(playback.position)
                                          : '${formatDuration(playback.position)} / ${formatDuration(playback.duration)}',
                                      maxLines: 1,
                                      overflow: TextOverflow.clip,
                                      style: TextStyle(
                                        color: mutedForeground,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  if (!veryTight)
                                    SizedBox(width: condensed ? 2 : 8),
                                  HoverVolumeButton(
                                    enabled: true,
                                    accent: accent,
                                    mutedColor: mutedForeground,
                                    iconSize: 31,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openPlayer(BuildContext context) {
    return Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 150),
        reverseTransitionDuration: const Duration(milliseconds: 120),
        pageBuilder: (_, animation, _) => const NowPlayingPage(),
        transitionsBuilder: (_, animation, _, child) => FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          ),
          child: child,
        ),
      ),
    );
  }
}

class _DeferredSeekSlider extends StatefulWidget {
  const _DeferredSeekSlider({
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
  State<_DeferredSeekSlider> createState() => _DeferredSeekSliderState();
}

class _DeferredSeekSliderState extends State<_DeferredSeekSlider> {
  double? _preview;

  @override
  Widget build(BuildContext context) {
    return Slider(
      value: (_preview ?? widget.value).clamp(0, widget.max),
      max: widget.max,
      activeColor: widget.accent,
      onChanged: widget.enabled
          ? (value) => setState(() => _preview = value)
          : null,
      onChangeEnd: widget.enabled
          ? (value) async {
              setState(() => _preview = value);
              await widget.onSeek(Duration(milliseconds: value.round()));
              await Future<void>.delayed(const Duration(milliseconds: 120));
              if (mounted) setState(() => _preview = null);
            }
          : null,
    );
  }
}
