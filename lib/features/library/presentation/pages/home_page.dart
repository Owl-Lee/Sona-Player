import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/localization/sona_localizations.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/latest_snack_bar.dart';
import '../../../../core/widgets/liquid_glass.dart';
import '../../../player/application/player_controller.dart';
import '../../../settings/application/appearance_controller.dart';
import '../../application/library_controller.dart';
import '../../domain/track.dart';
import '../library_actions.dart';
import '../widgets/track_artwork.dart';
import 'library_page.dart';
import 'rankings_page.dart';
import '../../../shell/application/shell_navigation.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(libraryControllerProvider);
    final appearance = ref.watch(appearanceControllerProvider);
    final accent = appearance.accent;
    final darkHome =
        !appearance.usesCustom && appearance.preset.prefersLightHomeForeground;
    final recent = library.recentlyPlayed
        // Desktop has a two-column grid: always fill complete rows so the
        // home page does not end with one orphaned card.
        .take(MediaQuery.sizeOf(context).width >= 760 ? 6 : 2)
        .toList(growable: false);

    final baseTheme = Theme.of(context);
    return Theme(
      data: darkHome
          ? baseTheme.copyWith(
              textTheme: baseTheme.textTheme.copyWith(
                headlineMedium: baseTheme.textTheme.headlineMedium?.copyWith(
                  color: Colors.white,
                ),
                titleLarge: baseTheme.textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                  shadows: const [Shadow(color: Colors.black38, blurRadius: 8)],
                ),
                bodyMedium: baseTheme.textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.82),
                ),
              ),
            )
          : baseTheme,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final desktop = constraints.maxWidth >= 760;
            // Large desktop windows should use the extra space instead of
            // keeping the same narrow two-column canvas as a laptop.
            final wideDesktop = constraints.maxWidth >= 1320;
            final content = SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                wideDesktop ? 56 : (desktop ? 48 : 18),
                desktop ? 36 : 10,
                wideDesktop ? 56 : (desktop ? 48 : 18),
                desktop ? 48 : 32,
              ),
              child: Align(
                alignment: Alignment.topLeft,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: wideDesktop ? 1440 : 1180,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (desktop)
                        _DesktopWelcome(
                          accent: accent,
                          dark: darkHome,
                          child: _TopHeader(
                            totalBytes: library.totalBytes,
                            accent: accent,
                            dark: darkHome,
                            onImport: () =>
                                importMusic(context, ref, directory: false),
                          ),
                        ),
                      SizedBox(height: desktop ? 38 : 22),
                      Text(
                        '音乐概览 · 数据统计',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 9),
                      _QuickLibrary(
                        library: library,
                        desktop: desktop,
                        glassTint: accent,
                        onOpen: (filter) {
                          ref.read(libraryFilterProvider.notifier).state =
                              filter;
                          ref.read(shellDestinationProvider.notifier).state = 1;
                        },
                      ),
                      const SizedBox(height: 28),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '最近播放',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          Text(
                            '${recent.length} 首',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (library.isLoading)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(40),
                            child: CircularProgressIndicator(),
                          ),
                        )
                      else if (recent.isEmpty)
                        const SizedBox.shrink()
                      else
                        _RecentList(
                          tracks: recent,
                          columns: wideDesktop ? 3 : (desktop ? 2 : 1),
                          accent: accent,
                        ),
                      if (!library.isLoading && library.tracks.isNotEmpty) ...[
                        const SizedBox(height: 26),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '听歌排行',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () {
                                if (desktop) {
                                  ref
                                          .read(
                                            shellDestinationProvider.notifier,
                                          )
                                          .state =
                                      4;
                                  return;
                                }
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => const RankingsPage(),
                                  ),
                                );
                              },
                              icon: const Icon(
                                Icons.bar_chart_rounded,
                                size: 18,
                              ),
                              label: const Text('查看全部'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _RankingPreview(
                          tracks: library.tracks,
                          desktop: desktop,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
            if (desktop) return content;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
                  child: _TopHeader(
                    totalBytes: library.totalBytes,
                    accent: accent,
                    dark: darkHome,
                    onImport: () => importMusic(context, ref, directory: false),
                  ),
                ),
                const Divider(height: 1, color: Color(0x22002B27)),
                Expanded(
                  child: Scrollbar(thumbVisibility: true, child: content),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TopHeader extends StatelessWidget {
  const _TopHeader({
    required this.onImport,
    required this.totalBytes,
    required this.accent,
    required this.dark,
  });

  final VoidCallback onImport;
  final int totalBytes;
  final Color accent;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr('只属于你的音乐空间'),
                style: TextStyle(
                  color: dark
                      ? Colors.white.withValues(alpha: 0.88)
                      : AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Text(
                    'Sona',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(width: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.68),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: accent.withValues(alpha: 0.24)),
                      boxShadow: const [
                        BoxShadow(color: Color(0x120E1A2C), blurRadius: 12),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.storage_rounded, size: 15, color: accent),
                        const SizedBox(width: 6),
                        Text(
                          formatBytes(totalBytes),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        FilledButton.icon(
          onPressed: onImport,
          icon: const Icon(Icons.add_rounded),
          label: Text(context.tr('导入音乐')),
          style: FilledButton.styleFrom(
            backgroundColor: accent.withValues(alpha: 0.84),
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            shape: const StadiumBorder(),
          ),
        ),
      ],
    );
  }
}

class _DesktopWelcome extends StatelessWidget {
  const _DesktopWelcome({
    required this.child,
    required this.accent,
    required this.dark,
  });

  final Widget child;
  final Color accent;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return LiquidGlass(
      borderRadius: 28,
      blur: 22,
      tint: accent,
      dark: dark,
      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 28),
      child: SizedBox(width: double.infinity, child: child),
    );
  }
}

class _QuickLibrary extends StatelessWidget {
  const _QuickLibrary({
    required this.library,
    required this.desktop,
    required this.glassTint,
    required this.onOpen,
  });

  final LibraryState library;
  final bool desktop;
  final Color glassTint;
  final ValueChanged<LibraryFilter> onOpen;

  @override
  Widget build(BuildContext context) {
    final cards = [
      _QuickCardData(
        Icons.music_note_rounded,
        context.tr('本地歌曲'),
        '${library.tracks.length}${context.tr('首')}',
        AppColors.accent,
        LibraryFilter.all,
      ),
      _QuickCardData(
        Icons.favorite_rounded,
        context.tr('我的收藏'),
        '${library.tracks.where((item) => item.isFavorite).length}${context.tr('首')}',
        const Color(0xFF8A65F7),
        LibraryFilter.favorites,
      ),
      _QuickCardData(
        Icons.video_library_rounded,
        context.tr('已配对 MV'),
        '${library.tracks.where((item) => item.hasVideo || item.isVideoOnly).length} ${context.tr('个')}',
        const Color(0xFF267EDB),
        LibraryFilter.videos,
      ),
    ];
    if (!desktop) {
      return Row(
        children: [
          for (var index = 0; index < cards.length; index++) ...[
            if (index > 0) const SizedBox(width: 8),
            Expanded(
              child: _CompactQuickCard(
                card: cards[index],
                glassTint: glassTint,
                onOpen: onOpen,
              ),
            ),
          ],
        ],
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: desktop ? 3 : 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: desktop ? 2.55 : 1.5,
      ),
      itemCount: cards.length,
      itemBuilder: (context, index) {
        final card = cards[index];
        return LiquidGlass(
          borderRadius: desktop ? 22 : 14,
          blur: 16,
          // Card icons keep their semantic colour; the glass itself follows
          // the wallpaper so a warm card cannot stain an ice/blue theme pink.
          tint: glassTint,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: () => onOpen(card.filter),
              borderRadius: BorderRadius.circular(desktop ? 22 : 14),
              child: Padding(
                padding: EdgeInsets.all(desktop ? 20 : 16),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: card.color.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(desktop ? 16 : 13),
                      ),
                      child: Icon(card.icon, color: card.color, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            card.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            card.value,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.ink,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
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
        );
      },
    );
  }
}

class _CompactQuickCard extends StatelessWidget {
  const _CompactQuickCard({
    required this.card,
    required this.glassTint,
    required this.onOpen,
  });

  final _QuickCardData card;
  final Color glassTint;
  final ValueChanged<LibraryFilter> onOpen;

  @override
  Widget build(BuildContext context) {
    return LiquidGlass(
      borderRadius: 18,
      blur: 15,
      tint: glassTint,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: () => onOpen(card.filter),
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 13),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(card.icon, color: card.color, size: 23),
                const SizedBox(height: 7),
                Text(
                  card.value,
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  card.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
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

class _QuickCardData {
  const _QuickCardData(
    this.icon,
    this.label,
    this.value,
    this.color,
    this.filter,
  );
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final LibraryFilter filter;
}

class _RecentList extends ConsumerWidget {
  const _RecentList({
    required this.tracks,
    required this.columns,
    required this.accent,
  });

  final List<Track> tracks;
  final int columns;
  final Color accent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(playerControllerProvider).currentTrack;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 12,
        mainAxisSpacing: 8,
        childAspectRatio: columns >= 3 ? 4.7 : (columns == 2 ? 5.4 : 5.1),
      ),
      itemCount: tracks.length,
      itemBuilder: (context, index) {
        final track = tracks[index];
        final selected = current?.id == track.id;
        return LiquidGlass(
          borderRadius: 20,
          // One real backdrop capture per dense recent item is unnecessary;
          // the opaque glass gradient keeps text readable without it.
          blur: 0,
          tint: accent,
          child: Material(
            color: selected
                ? accent.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              onLongPress: () => showTrackContextMenu(
                context,
                ref,
                track,
                source: TrackMenuSource.recent,
              ),
              onSecondaryTapDown: (details) => showTrackContextMenu(
                context,
                ref,
                track,
                source: TrackMenuSource.recent,
                position: details.globalPosition,
              ),
              onTap: () => playTrack(ref, track, tracks, source: '最近播放'),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: selected
                        ? accent.withValues(alpha: 0.34)
                        : Colors.white.withValues(alpha: 0.86),
                  ),
                ),
                child: Row(
                  children: [
                    TrackArtwork(track: track, size: 52, borderRadius: 12),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.metadata(track.title),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.trackTitleStyle.copyWith(
                              color: selected ? accent : AppColors.ink,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${context.metadata(track.artist)}  ·  ${context.metadata(track.album)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      selected
                          ? Icons.graphic_eq_rounded
                          : Icons.play_arrow_rounded,
                      color: selected ? accent : AppColors.textSecondary,
                    ),
                    const SizedBox(width: 5),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ignore: unused_element
Future<void> _showRecentTrackMenu(
  BuildContext context,
  WidgetRef ref,
  Track track,
) async {
  final action = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: TrackArtwork(track: track, size: 46, borderRadius: 12),
              title: Text(
                track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                track.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.history_toggle_off_rounded),
              title: const Text('从最近播放中移除'),
              subtitle: const Text('保留歌曲和播放次数'),
              onTap: () => Navigator.pop(sheetContext, 'recent'),
            ),
            ListTile(
              leading: const Icon(
                Icons.remove_circle_outline_rounded,
                color: AppColors.accent,
              ),
              title: const Text('从本地曲库移除'),
              subtitle: const Text('不会删除手机里的原始文件'),
              onTap: () => Navigator.pop(sheetContext, 'library'),
            ),
          ],
        ),
      ),
    ),
  );
  if (action == 'recent') {
    await ref
        .read(libraryControllerProvider.notifier)
        .clearFromRecentlyPlayed(track);
    return;
  }
  if (action != 'library' || !context.mounted) return;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('从本地曲库移除？'),
      content: Text('“${track.title}”将不再显示在 Sona 中，原始文件不会被删除。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('移除'),
        ),
      ],
    ),
  );
  if (confirmed == true) {
    await ref.read(libraryControllerProvider.notifier).removeTrack(track);
  }
}

// ignore: unused_element
Future<void> _showRecentTrackMenuV2(
  BuildContext context,
  WidgetRef ref,
  Track track,
) async {
  final action = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: TrackArtwork(track: track, size: 46, borderRadius: 12),
              title: Text(
                track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                track.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Divider(),
            ListTile(
              leading: Icon(
                track.isFavorite
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
              ),
              title: Text(track.isFavorite ? '取消收藏' : '收藏'),
              onTap: () => Navigator.pop(sheetContext, 'favorite'),
            ),
            ListTile(
              leading: const Icon(Icons.playlist_add_rounded),
              title: const Text('加入歌单'),
              onTap: () => Navigator.pop(sheetContext, 'playlist'),
            ),
            ListTile(
              leading: const Icon(Icons.history_toggle_off_rounded),
              title: const Text('从最近播放中移除'),
              onTap: () => Navigator.pop(sheetContext, 'recent'),
            ),
            ListTile(
              leading: const Icon(
                Icons.remove_circle_outline_rounded,
                color: AppColors.accent,
              ),
              title: const Text('从本地曲库移除'),
              onTap: () => Navigator.pop(sheetContext, 'library'),
            ),
          ],
        ),
      ),
    ),
  );
  final library = ref.read(libraryControllerProvider.notifier);
  if (action == 'favorite') {
    await library.toggleFavorite(track);
    return;
  }
  if (action == 'playlist') {
    if (!context.mounted) return;
    await _addTrackToPlaylistFromHome(context, ref, track);
    return;
  }
  if (action == 'recent') {
    await library.clearFromRecentlyPlayed(track);
    return;
  }
  if (action != 'library' || !context.mounted) return;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('从本地曲库移除？'),
      content: Text('移除“${track.title}”？'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('移除'),
        ),
      ],
    ),
  );
  if (confirmed == true) await library.removeTrack(track);
}

Future<void> _addTrackToPlaylistFromHome(
  BuildContext context,
  WidgetRef ref,
  Track track,
) async {
  final playlists = ref.read(libraryControllerProvider).playlists;
  if (playlists.isEmpty) {
    showLatestSnackBar(context, const SnackBar(content: Text('还没有歌单')));
    return;
  }
  final selected = await showDialog(
    context: context,
    builder: (dialogContext) => SimpleDialog(
      backgroundColor: Colors.white,
      title: const Text('加入歌单', style: TextStyle(color: AppColors.ink)),
      children: playlists
          .map(
            (playlist) => SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, playlist),
              child: Text(
                playlist.name,
                style: const TextStyle(color: AppColors.ink),
              ),
            ),
          )
          .toList(growable: false),
    ),
  );
  if (selected == null) return;
  final added = await ref
      .read(libraryControllerProvider.notifier)
      .addTrackToPlaylist(selected, track);
  if (!context.mounted) return;
  showLatestSnackBar(
    context,
    SnackBar(content: Text(added ? '已加入 ${selected.name}' : '这首歌已经在该歌单中')),
  );
}

class _RankingPreview extends ConsumerWidget {
  const _RankingPreview({required this.tracks, required this.desktop});

  final List<Track> tracks;
  final bool desktop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = ref.watch(appearanceControllerProvider).accent;
    final ranked = tracks.where((track) => track.playCount > 0).toList()
      ..sort((a, b) => b.playCount.compareTo(a.playCount));
    if (ranked.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.84),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.outline),
        ),
        child: const Text(
          '听满一首歌的一半后，它会出现在这里。',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }
    // The phone home page is a preview, not the full ranking. Keeping one
    // complete row here guarantees that the fixed mini-player never leaves a
    // second ranking row visibly chopped in half on short displays. The full
    // list remains one tap away through "查看全部".
    final items = ranked.take(desktop ? 6 : 1).toList(growable: false);
    return LiquidGlass(
      tint: accent,
      borderRadius: 18,
      blur: 18,
      padding: EdgeInsets.zero,
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          children: [
            for (var index = 0; index < items.length; index++)
              Padding(
                padding: EdgeInsets.fromLTRB(6, index == 0 ? 6 : 2, 6, 4),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onSecondaryTapDown: (details) => showTrackContextMenu(
                    context,
                    ref,
                    items[index],
                    source: TrackMenuSource.ranking,
                    position: details.globalPosition,
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: LinearGradient(
                        colors: [
                          Colors.white.withValues(alpha: 0.44),
                          Colors.white.withValues(alpha: 0.20),
                        ],
                      ),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.52),
                      ),
                    ),
                    child: ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      dense: true,
                      leading: SizedBox(
                        width: 68,
                        child: Row(
                          children: [
                            SizedBox(
                              width: 19,
                              child: Text(
                                '${index + 1}',
                                style: TextStyle(
                                  color: index == 0
                                      ? accent
                                      : AppColors.textSecondary,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            TrackArtwork(
                              track: items[index],
                              size: 46,
                              borderRadius: 10,
                            ),
                          ],
                        ),
                      ),
                      title: Text(
                        context.metadata(items[index].title),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.trackTitleStyle,
                      ),
                      subtitle: Text(
                        context.metadata(items[index].artist),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 11,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          gradient: LinearGradient(
                            colors: [
                              accent.withValues(alpha: 0.24),
                              Colors.white.withValues(alpha: 0.44),
                            ],
                          ),
                          border: Border.all(
                            color: accent.withValues(alpha: 0.42),
                          ),
                        ),
                        child: Text(
                          '${items[index].playCount} 次',
                          style: TextStyle(
                            color: Color.lerp(AppColors.ink, accent, 0.38),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      onLongPress: () => showTrackContextMenu(
                        context,
                        ref,
                        items[index],
                        source: TrackMenuSource.ranking,
                      ),
                      onTap: () =>
                          playTrack(ref, items[index], ranked, source: '听歌排行'),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ignore: unused_element
class _EmptyHome extends StatelessWidget {
  const _EmptyHome({required this.onImport});
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 42, horizontal: 22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        children: [
          const Icon(Icons.album_outlined, color: AppColors.accent, size: 46),
          const SizedBox(height: 12),
          const Text('导入第一首音乐，开始建立你的私人曲库。', textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onImport,
            icon: const Icon(Icons.add_rounded),
            label: const Text('导入音乐'),
          ),
        ],
      ),
    );
  }
}
