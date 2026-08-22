import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/performance/visual_effects.dart';
import '../../application/appearance_controller.dart';

class VisualEffectsLabels {
  const VisualEffectsLabels({
    required this.full,
    required this.fullDescription,
    required this.energySaver,
    required this.energySaverDescription,
    required this.off,
    required this.offDescription,
  });

  final String full;
  final String fullDescription;
  final String energySaver;
  final String energySaverDescription;
  final String off;
  final String offDescription;

  String title(VisualEffectsMode mode) => switch (mode) {
    VisualEffectsMode.full => full,
    VisualEffectsMode.energySaver => energySaver,
    VisualEffectsMode.off => off,
  };

  String description(VisualEffectsMode mode) => switch (mode) {
    VisualEffectsMode.full => fullDescription,
    VisualEffectsMode.energySaver => energySaverDescription,
    VisualEffectsMode.off => offDescription,
  };
}

/// Reusable responsive control for the performance mode settings entry.
/// Localization stays at the settings page boundary through [labels].
class VisualEffectsSelector extends ConsumerWidget {
  const VisualEffectsSelector({
    super.key,
    required this.labels,
    this.onChanged,
  });

  final VisualEffectsLabels labels;
  final ValueChanged<VisualEffectsMode>? onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(
      appearanceControllerProvider.select((state) => state.effectsMode),
    );
    final accent = ref.watch(
      appearanceControllerProvider.select((state) => state.accent),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = constraints.maxWidth >= 680
            ? (constraints.maxWidth - 20) / 3
            : constraints.maxWidth;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final mode in VisualEffectsMode.values)
              SizedBox(
                width: cardWidth,
                child: _EffectsChoice(
                  mode: mode,
                  selected: selected == mode,
                  accent: accent,
                  title: labels.title(mode),
                  description: labels.description(mode),
                  onTap: () async {
                    await ref
                        .read(appearanceControllerProvider.notifier)
                        .setEffectsMode(mode);
                    onChanged?.call(mode);
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}

class _EffectsChoice extends StatelessWidget {
  const _EffectsChoice({
    required this.mode,
    required this.selected,
    required this.accent,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final VisualEffectsMode mode;
  final bool selected;
  final Color accent;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final icon = switch (mode) {
      VisualEffectsMode.full => Icons.auto_awesome_rounded,
      VisualEffectsMode.energySaver => Icons.battery_saver_rounded,
      VisualEffectsMode.off => Icons.motion_photos_off_rounded,
    };
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: selected
                  ? accent.withValues(alpha: 0.16)
                  : Colors.white.withValues(alpha: 0.44),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selected
                    ? accent.withValues(alpha: 0.82)
                    : Colors.white.withValues(alpha: 0.68),
                width: selected ? 1.6 : 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: selected ? accent : const Color(0xFF34425A)),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        description,
                        style: TextStyle(
                          color: const Color(0xFF34425A).withValues(alpha: .82),
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                if (selected) Icon(Icons.check_circle_rounded, color: accent),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
