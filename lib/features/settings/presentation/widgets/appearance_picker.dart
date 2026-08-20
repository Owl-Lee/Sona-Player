import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../application/appearance_controller.dart';
import 'image_crop_dialog.dart';

class AppearancePicker extends ConsumerWidget {
  const AppearancePicker({
    super.key,
    this.compact = false,
    this.scrollable = false,
    this.onSelectionComplete,
  });

  final bool compact;
  final bool scrollable;
  final VoidCallback? onSelectionComplete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appearance = ref.watch(appearanceControllerProvider);
    final useDesktopThumbnails = MediaQuery.sizeOf(context).width >= 760;
    return LayoutBuilder(
      builder: (context, constraints) {
        // The settings panel can become much wider when the desktop window is
        // maximised.  A fixed six-column grid left a large unused strip on the
        // right, while the tiles themselves stayed at their small-window size.
        // Choose a column count from the actual available width instead.
        const gap = 12.0;
        const preferredTileWidth = 190.0;
        final count = compact || constraints.maxWidth < 620
            ? 2
            : ((constraints.maxWidth + gap) / (preferredTileWidth + gap))
                  .floor()
                  .clamp(3, 8)
                  .toInt();
        final tileWidth = (constraints.maxWidth - ((count - 1) * gap)) / count;
        return GridView.count(
          shrinkWrap: !scrollable,
          physics: scrollable
              ? const BouncingScrollPhysics()
              : const NeverScrollableScrollPhysics(),
          crossAxisCount: count,
          mainAxisSpacing: gap,
          crossAxisSpacing: gap,
          // Preserve the visual proportions on compact windows, but allow a
          // little more breathing room as desktop cards scale up.
          childAspectRatio: tileWidth >= 210 ? 1.52 : 1.45,
          children: [
            for (final preset in backgroundPresets)
              _BackgroundTile(
                label: preset.name,
                selected:
                    !appearance.usesCustom && appearance.presetId == preset.id,
                image: _presetImage(preset, useDesktopThumbnails),
                fallbackColors: preset.fallbackColors,
                onTap: () async {
                  // In the player this closes the picker before the expensive
                  // full-screen composition changes.  Keeping the outgoing
                  // sheet, its grid thumbnails and a new wallpaper alive in
                  // the same transition was the main visible hitch.
                  if (onSelectionComplete != null) {
                    onSelectionComplete!.call();
                    await Future<void>.delayed(
                      const Duration(milliseconds: 180),
                    );
                  }
                  await ref
                      .read(appearanceControllerProvider.notifier)
                      .selectPreset(preset.id);
                },
              ),
            for (
              var index = 0;
              index < appearance.customBackgrounds.length;
              index++
            )
              _BackgroundTile(
                label: '我的背景 ${index + 1}',
                selected:
                    appearance.usesCustom &&
                    appearance.customBackgroundPath ==
                        appearance.customBackgrounds[index].path,
                image: FileImage(
                  File(appearance.customBackgrounds[index].path),
                ),
                onTap: () async {
                  if (onSelectionComplete != null) {
                    onSelectionComplete!.call();
                    await Future<void>.delayed(
                      const Duration(milliseconds: 180),
                    );
                  }
                  await ref
                      .read(appearanceControllerProvider.notifier)
                      .selectCustomBackground(
                        appearance.customBackgrounds[index],
                      );
                },
              ),
            _ImportTile(
              onTap: () async {
                final bytes = await ref
                    .read(appearanceControllerProvider.notifier)
                    .pickCustomBackground();
                if (!context.mounted || bytes == null) return;
                final viewport = MediaQuery.sizeOf(context);
                final cropped = await ImageCropDialog.show(
                  context,
                  imageBytes: bytes,
                  aspectRatio: (viewport.width / viewport.height).clamp(
                    9 / 16,
                    21 / 9,
                  ),
                  title: '裁切播放器背景',
                );
                if (!context.mounted || cropped == null) return;
                await ref
                    .read(appearanceControllerProvider.notifier)
                    .saveCustomBackground(cropped);
                if (context.mounted) onSelectionComplete?.call();
              },
            ),
          ],
        );
      },
    );
  }
}

ImageProvider? _presetImage(
  BackgroundPreset preset,
  bool useDesktopThumbnails,
) {
  final assetPath = useDesktopThumbnails
      ? preset.desktopAssetPath ?? preset.assetPath
      : preset.assetPath;
  return assetPath == null ? null : AssetImage(assetPath);
}

class _BackgroundTile extends StatelessWidget {
  const _BackgroundTile({
    required this.label,
    required this.selected,
    required this.image,
    this.fallbackColors = const [Color(0xFFFFFFFF), Color(0xFFF3F6FB)],
    required this.onTap,
  });

  final String label;
  final bool selected;
  final ImageProvider? image;
  final List<Color> fallbackColors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? AppColors.accent : AppColors.outline,
              width: selected ? 2 : 1,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              fit: StackFit.expand,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: fallbackColors,
                    ),
                  ),
                ),
                if (image != null) Image(image: image!, fit: BoxFit.cover),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Color(0xB8000000)],
                    ),
                  ),
                ),
                Positioned(
                  left: 9,
                  right: 9,
                  bottom: 8,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (selected)
                        const Icon(
                          Icons.check_circle_rounded,
                          color: Colors.white,
                          size: 17,
                        ),
                    ],
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

class _ImportTile extends StatelessWidget {
  const _ImportTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF7F8FB),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.outline, width: 1),
          ),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_photo_alternate_outlined, color: AppColors.accent),
              SizedBox(height: 7),
              Text(
                '导入自己的背景',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
