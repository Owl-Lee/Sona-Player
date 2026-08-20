import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/localization/sona_localizations.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/item_snap_scroll_physics.dart';
import '../../../../core/widgets/liquid_glass.dart';
import '../../../../core/widgets/whole_item_viewport.dart';
import '../../../player/application/player_controller.dart';
import '../../../settings/application/appearance_controller.dart';
import '../../../settings/presentation/widgets/appearance_backdrop.dart';
import '../../application/library_controller.dart';
import '../library_actions.dart';
import '../widgets/track_artwork.dart';

enum RankingPeriod { week, month, all }

class RankingsPage extends ConsumerStatefulWidget {
  const RankingsPage({super.key});

  @override
  ConsumerState<RankingsPage> createState() => _RankingsPageState();
}

class _RankingsPageState extends ConsumerState<RankingsPage> {
  var _period = RankingPeriod.week;

  Future<Map<int, int>> _counts(LibraryState state) {
    final now = DateTime.now();
    return switch (_period) {
      RankingPeriod.week =>
        ref
            .read(libraryControllerProvider.notifier)
            .playCountsSince(now.subtract(const Duration(days: 7))),
      RankingPeriod.month =>
        ref
            .read(libraryControllerProvider.notifier)
            .playCountsSince(DateTime(now.year, now.month, 1)),
      RankingPeriod.all => Future.value({
        for (final track in state.tracks) track.id!: track.playCount,
      }),
    };
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(libraryControllerProvider);
    final current = ref.watch(playerControllerProvider).currentTrack;
    final appearance = ref.watch(appearanceControllerProvider);
    final mobile = MediaQuery.sizeOf(context).width < 760;
    final content = MediaQuery(
      // 排行页在手机上必须始终是信息密度较高的列表，不能因局部主题或
      // 设备的显示偏好把说明和空状态放大到挤坏整个页面。
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            mobile ? 16 : 30,
            mobile ? 12 : 26,
            mobile ? 16 : 30,
            18,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (mobile) ...[
                    IconButton(
                      tooltip: '返回',
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    const SizedBox(width: 4),
                  ],
                  Expanded(
                    child: Text(
                      '听歌排行',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ),
                  if (!mobile)
                    SegmentedButton<RankingPeriod>(
                      showSelectedIcon: false,
                      selected: {_period},
                      onSelectionChanged: (value) =>
                          setState(() => _period = value.first),
                      segments: const [
                        ButtonSegment(
                          value: RankingPeriod.week,
                          label: Text('近7天'),
                        ),
                        ButtonSegment(
                          value: RankingPeriod.month,
                          label: Text('本月'),
                        ),
                        ButtonSegment(
                          value: RankingPeriod.all,
                          label: Text('总排行'),
                        ),
                      ],
                    ),
                ],
              ),
              if (mobile) ...[
                const SizedBox(height: 10),
                _MobileRankingFilters(
                  period: _period,
                  onChanged: (value) => setState(() => _period = value),
                ),
                const SizedBox(height: 10),
                const Text(
                  '播放满 70% 才记为一次；旧版本记录仅计入总排行。',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ] else ...[
                const SizedBox(height: 6),
                const Text(
                  '播放满 70% 才记为一次；旧版本记录仅计入总排行。',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ],
              const SizedBox(height: 14),
              Expanded(
                child: FutureBuilder<Map<int, int>>(
                  future: _counts(state),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final counts = snapshot.data!;
                    final tracks =
                        state.tracks
                            .where((track) => (counts[track.id] ?? 0) > 0)
                            .toList()
                          ..sort(
                            (a, b) => (counts[b.id] ?? 0).compareTo(
                              counts[a.id] ?? 0,
                            ),
                          );
                    if (tracks.isEmpty) return const _RankingEmptyState();
                    return LiquidGlass(
                      borderRadius: 22,
                      blur: 8,
                      tint: appearance.accent,
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Column(
                        children: [
                          const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 15,
                              vertical: 8,
                            ),
                            child: Row(
                              children: [
                                SizedBox(width: 88, child: Text('#')),
                                Expanded(child: Text('歌曲')),
                                SizedBox(
                                  width: 96,
                                  child: Center(child: Text('播放次数')),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 2),
                          Expanded(
                            child: WholeItemViewport(
                              // Keep the rhythm compact enough that the
                              // available desktop height is used for complete
                              // rows, never a severed final card.
                              itemExtent: 62,
                              child: ListView.builder(
                                padding: const EdgeInsets.fromLTRB(8, 3, 8, 3),
                                physics: const ItemSnapScrollPhysics(
                                  itemExtent: 62,
                                  parent: ClampingScrollPhysics(),
                                ),
                                itemExtent: 62,
                                itemCount: tracks.length,
                                itemBuilder: (context, index) {
                                  final track = tracks[index];
                                  final selected = current?.id == track.id;
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 5),
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: selected
                                            ? appearance.accent.withValues(
                                                alpha: 0.15,
                                              )
                                            : Colors.white.withValues(
                                                alpha: 0.16,
                                              ),
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: selected
                                              ? appearance.accent.withValues(
                                                  alpha: 0.48,
                                                )
                                              : Colors.white.withValues(
                                                  alpha: 0.32,
                                                ),
                                          width: selected ? 1.15 : 0.8,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.white.withValues(
                                              alpha: 0.08,
                                            ),
                                            blurRadius: 12,
                                            offset: const Offset(0, 3),
                                          ),
                                        ],
                                      ),
                                      child: Material(
                                        color: Colors.transparent,
                                        borderRadius: BorderRadius.circular(14),
                                        child: GestureDetector(
                                          behavior: HitTestBehavior.translucent,
                                          onSecondaryTapDown: (details) =>
                                              showTrackContextMenu(
                                                context,
                                                ref,
                                                track,
                                                source: TrackMenuSource.ranking,
                                                position:
                                                    details.globalPosition,
                                              ),
                                          child: ListTile(
                                            dense: true,
                                            minVerticalPadding: 2,
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                  horizontal: 10,
                                                ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(15),
                                            ),
                                            selected: selected,
                                            leading: SizedBox(
                                              width: 74,
                                              child: Row(
                                                children: [
                                                  SizedBox(
                                                    width: 23,
                                                    child: Text(
                                                      '${index + 1}',
                                                      style: const TextStyle(
                                                        fontSize: 16,
                                                        fontWeight:
                                                            FontWeight.w800,
                                                      ),
                                                    ),
                                                  ),
                                                  TrackArtwork(
                                                    track: track,
                                                    size: 42,
                                                    borderRadius: 12,
                                                  ),
                                                ],
                                              ),
                                            ),
                                            title: Text(
                                              context.metadata(track.title),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: AppTheme.trackTitleStyle,
                                            ),
                                            subtitle: Text(
                                              context.metadata(track.artist),
                                            ),
                                            trailing: SizedBox(
                                              width: 88,
                                              child: _RankingCountBadge(
                                                count: counts[track.id] ?? 0,
                                                accent: appearance.accent,
                                              ),
                                            ),
                                            onLongPress: () =>
                                                showTrackContextMenu(
                                                  context,
                                                  ref,
                                                  track,
                                                  source:
                                                      TrackMenuSource.ranking,
                                                ),
                                            onTap: () => playTrack(
                                              ref,
                                              track,
                                              tracks,
                                              source: '听歌排行',
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mobile) return content;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          AppearanceBackdrop(appearance: appearance),
          Material(color: Colors.transparent, child: content),
        ],
      ),
    );
  }
}

class _RankingCountBadge extends StatelessWidget {
  const _RankingCountBadge({required this.count, required this.accent});

  final int count;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.34)),
      ),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(color: AppColors.ink),
          children: [
            TextSpan(
              text: '$count',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
            ),
            const TextSpan(
              text: ' 次',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileRankingFilters extends StatelessWidget {
  const _MobileRankingFilters({required this.period, required this.onChanged});

  final RankingPeriod period;
  final ValueChanged<RankingPeriod> onChanged;

  @override
  Widget build(BuildContext context) {
    const items = [
      (RankingPeriod.week, '近7天'),
      (RankingPeriod.month, '本月'),
      (RankingPeriod.all, '总排行'),
    ];
    return Container(
      height: 42,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .74),
        borderRadius: BorderRadius.circular(21),
        border: Border.all(color: AppColors.accent.withValues(alpha: .22)),
      ),
      child: Row(
        children: [
          for (final item in items)
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(17),
                onTap: () => onChanged(item.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: period == item.$1
                        ? AppColors.accent
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(17),
                  ),
                  child: Text(
                    item.$2,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: period == item.$1
                          ? Colors.white
                          : AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RankingEmptyState extends StatelessWidget {
  const _RankingEmptyState();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        margin: const EdgeInsets.only(top: 28),
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 25),
        decoration: BoxDecoration(
          color: const Color(0xFFF2F8F5).withValues(alpha: .92),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFD8E7E1)),
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bar_chart_rounded, size: 34, color: AppColors.accent),
            SizedBox(height: 10),
            Text(
              '这个时间段还没有播放记录',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            SizedBox(height: 6),
            Text(
              '完整播放一首歌后，这里会自动生成排行。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
