import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/sona_localizations.dart';
import '../application/player_controller.dart';

class PlaybackModeButton extends ConsumerWidget {
  const PlaybackModeButton({
    super.key,
    this.enabled = true,
    this.color,
    this.activeColor,
    this.compact = false,
    this.iconSize,
  });

  final bool enabled;
  final Color? color;
  final Color? activeColor;
  final bool compact;
  final double? iconSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(
      playerControllerProvider.select((state) => state.playbackMode),
    );
    final controller = ref.read(playerControllerProvider.notifier);
    final label = context.tr(switch (mode) {
      VaultPlaybackMode.loop => '列表循环',
      VaultPlaybackMode.one => '单曲循环',
      VaultPlaybackMode.shuffle => '随机播放',
    });
    final icon = switch (mode) {
      VaultPlaybackMode.loop => Icons.repeat_rounded,
      VaultPlaybackMode.one => Icons.repeat_one_rounded,
      VaultPlaybackMode.shuffle => Icons.shuffle_rounded,
    };
    return PopupMenuButton<VaultPlaybackMode>(
      enabled: enabled,
      tooltip: label,
      onSelected: controller.setPlaybackMode,
      itemBuilder: (_) => [
        PopupMenuItem(
          value: VaultPlaybackMode.loop,
          child: ListTile(
            leading: const Icon(Icons.repeat_rounded),
            title: Text(context.tr('列表循环')),
            dense: true,
          ),
        ),
        PopupMenuItem(
          value: VaultPlaybackMode.one,
          child: ListTile(
            leading: const Icon(Icons.repeat_one_rounded),
            title: Text(context.tr('单曲循环')),
            dense: true,
          ),
        ),
        PopupMenuItem(
          value: VaultPlaybackMode.shuffle,
          child: ListTile(
            leading: const Icon(Icons.shuffle_rounded),
            title: Text(context.tr('随机播放')),
            dense: true,
          ),
        ),
      ],
      child: Padding(
        padding: EdgeInsets.all(compact ? 6 : 12),
        child: Icon(
          icon,
          size: iconSize ?? (compact ? 28 : 31),
          color: mode == VaultPlaybackMode.loop
              ? color
              : (activeColor ?? color),
        ),
      ),
    );
  }
}
