import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/localization/sona_localizations.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/item_snap_scroll_physics.dart';
import '../../../../core/widgets/latest_snack_bar.dart';
import '../../../../core/widgets/liquid_glass.dart';
import '../../../../core/widgets/whole_item_viewport.dart';
import '../../../player/application/player_controller.dart';
import '../../../settings/application/appearance_controller.dart';
import '../../application/library_controller.dart';
import '../../domain/playlist_info.dart';
import '../../domain/track.dart';
import '../library_actions.dart';
import '../widgets/track_artwork.dart';

enum LibraryFilter { all, favorites, videos, recent }

final libraryFilterProvider = StateProvider<LibraryFilter>(
  (ref) => LibraryFilter.all,
);

final librarySelectionActiveProvider = StateProvider<bool>((ref) => false);

class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  var _query = '';
  var _selecting = false;
  final Set<int> _selectedIds = {};

  void _setSelecting(bool value) {
    setState(() {
      _selecting = value;
      _selectedIds.clear();
    });
    ref.read(librarySelectionActiveProvider.notifier).state = value;
  }

  @override
  void dispose() {
    ref.read(librarySelectionActiveProvider.notifier).state = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(libraryControllerProvider);
    final filter = ref.watch(libraryFilterProvider);
    final current = ref.watch(playerControllerProvider).currentTrack;
    final appearance = ref.watch(appearanceControllerProvider);
    final accent = appearance.accent;
    final lightForeground =
        !appearance.usesCustom && appearance.preset.prefersLightHomeForeground;
    final query = _query.trim().toLowerCase();
    final baseTracks = filter == LibraryFilter.recent
        ? state.recentlyPlayed.take(20)
        : state.tracks;
    final tracks = baseTracks
        .where((track) {
          if (filter == LibraryFilter.favorites && !track.isFavorite) {
            return false;
          }
          if (filter == LibraryFilter.videos &&
              !track.hasVideo &&
              !track.isVideoOnly) {
            return false;
          }
          if (query.isEmpty) {
            return true;
          }
          return track.title.toLowerCase().contains(query) ||
              track.artist.toLowerCase().contains(query) ||
              track.album.toLowerCase().contains(query);
        })
        .toList(growable: false);
    final queueSource = query.isNotEmpty
        ? '搜索“${_query.trim()}”'
        : switch (filter) {
            LibraryFilter.all => '本地曲库',
            LibraryFilter.favorites => '我的收藏',
            LibraryFilter.videos => '有 MV',
            LibraryFilter.recent => '最近播放',
          };

    final baseTheme = Theme.of(context);
    return Theme(
      data: baseTheme.copyWith(
        colorScheme: baseTheme.colorScheme.copyWith(primary: accent),
      ),
      child: PopScope(
        canPop: !_selecting,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && _selecting) {
            _setSelecting(false);
          }
        },
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final desktop = constraints.maxWidth >= 760;
              return Padding(
                padding: EdgeInsets.fromLTRB(
                  desktop ? 30 : 18,
                  desktop ? 24 : 16,
                  desktop ? 30 : 18,
                  0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Header(
                      state: state,
                      filter: filter,
                      desktop: desktop,
                      accent: accent,
                      lightForeground: lightForeground,
                      onImportFile: () =>
                          importMusic(context, ref, directory: false),
                      onImportFolder: () =>
                          importMusic(context, ref, directory: true),
                      onSmartOrganize: state.tracks.isEmpty
                          ? null
                          : () =>
                                smartOrganizeTracks(context, ref, state.tracks),
                      onBatch: tracks.isEmpty
                          ? null
                          : () => _setSelecting(!_selecting),
                    ),
                    const SizedBox(height: 18),
                    if (desktop)
                      Row(
                        children: [
                          Expanded(
                            child: _SearchField(
                              accent: accent,
                              onChanged: (value) =>
                                  setState(() => _query = value),
                            ),
                          ),
                          const SizedBox(width: 14),
                          _FilterTabs(
                            accent: accent,
                            value: filter,
                            onChanged: (value) =>
                                ref.read(libraryFilterProvider.notifier).state =
                                    value,
                          ),
                        ],
                      )
                    else ...[
                      _SearchField(
                        accent: accent,
                        onChanged: (value) => setState(() => _query = value),
                      ),
                      const SizedBox(height: 12),
                      _FilterTabs(
                        accent: accent,
                        value: filter,
                        onChanged: (value) =>
                            ref.read(libraryFilterProvider.notifier).state =
                                value,
                      ),
                    ],
                    const SizedBox(height: 14),
                    if (_selecting) ...[
                      _InlineBatchBar(
                        accent: accent,
                        selected: _selectedIds.length,
                        total: tracks.length,
                        onSelectAll: () => setState(() {
                          if (_selectedIds.length == tracks.length) {
                            _selectedIds.clear();
                          } else {
                            _selectedIds
                              ..clear()
                              ..addAll(tracks.map((track) => track.id!));
                          }
                        }),
                        onFavorite: _selectedIds.isEmpty
                            ? null
                            : () => _batchFavorite(tracks, true),
                        onUnfavorite: _selectedIds.isEmpty
                            ? null
                            : () => _batchFavorite(tracks, false),
                        onPlaylist: _selectedIds.isEmpty
                            ? null
                            : () => _batchAddToPlaylist(tracks),
                        onRemove: _selectedIds.isEmpty
                            ? null
                            : () => _batchRemove(tracks),
                        onClose: () => _setSelecting(false),
                      ),
                      const SizedBox(height: 8),
                    ],
                    Expanded(
                      child: state.isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : state.tracks.isEmpty
                          ? _EmptyLibrary(
                              onImport: () =>
                                  importMusic(context, ref, directory: false),
                            )
                          : tracks.isEmpty
                          ? const Center(
                              child: Text(
                                '没有找到符合条件的歌曲',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            )
                          : desktop
                          ? _DesktopTrackList(
                              tracks: tracks,
                              currentId: current?.id,
                              accent: accent,
                              onPlay: (track) => playTrack(
                                ref,
                                track,
                                tracks,
                                source: queueSource,
                              ),
                              onFavorite: _favorite,
                              onMore: (track, [position]) =>
                                  showTrackContextMenu(
                                    context,
                                    ref,
                                    track,
                                    source: filter == LibraryFilter.recent
                                        ? TrackMenuSource.recent
                                        : TrackMenuSource.library,
                                    position: position,
                                  ),
                              selecting: _selecting,
                              selectedIds: _selectedIds,
                              onSelect: _toggleSelection,
                            )
                          : _MobileTrackList(
                              tracks: tracks,
                              currentId: current?.id,
                              accent: accent,
                              lightForeground: lightForeground,
                              onPlay: (track) => playTrack(
                                ref,
                                track,
                                tracks,
                                source: queueSource,
                              ),
                              onFavorite: _favorite,
                              onMore: (track, [position]) =>
                                  showTrackContextMenu(
                                    context,
                                    ref,
                                    track,
                                    source: filter == LibraryFilter.recent
                                        ? TrackMenuSource.recent
                                        : TrackMenuSource.library,
                                    position: position,
                                  ),
                              selecting: _selecting,
                              selectedIds: _selectedIds,
                              onSelect: _toggleSelection,
                            ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  void _favorite(Track track) {
    ref.read(libraryControllerProvider.notifier).toggleFavorite(track);
  }

  void _toggleSelection(Track track) {
    setState(
      () => _selectedIds.contains(track.id)
          ? _selectedIds.remove(track.id)
          : _selectedIds.add(track.id!),
    );
  }

  Future<void> _batchFavorite(List<Track> tracks, bool value) async {
    final controller = ref.read(libraryControllerProvider.notifier);
    await controller.setFavorites(
      tracks.where(
        (track) => _selectedIds.contains(track.id) && track.isFavorite != value,
      ),
      value: value,
    );
    if (mounted) setState(_selectedIds.clear);
  }

  Future<void> _batchAddToPlaylist(List<Track> tracks) async {
    final playlists = ref.read(libraryControllerProvider).playlists;
    if (playlists.isEmpty) return;
    final target = await showDialog<PlaylistInfo>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('添加到哪个歌单？'),
        children: playlists
            .map(
              (playlist) => SimpleDialogOption(
                onPressed: () => Navigator.pop(context, playlist),
                child: Text(playlist.name),
              ),
            )
            .toList(),
      ),
    );
    if (target == null) return;
    final controller = ref.read(libraryControllerProvider.notifier);
    final selectedTracks = tracks
        .where((track) => _selectedIds.contains(track.id))
        .toList(growable: false);
    final added = await controller.addTracksToPlaylist(target, selectedTracks);
    if (mounted) {
      final skipped = selectedTracks.length - added;
      showLatestSnackBar(
        context,
        SnackBar(
          content: Text(
            skipped == 0
                ? '已加入 ${target.name}'
                : '已加入 $added 首，跳过 $skipped 首重复歌曲',
          ),
        ),
      );
      setState(_selectedIds.clear);
    }
  }

  Future<void> _batchRemove(List<Track> tracks) async {
    final selectedTracks = tracks
        .where((track) => _selectedIds.contains(track.id))
        .toList(growable: false);
    if (selectedTracks.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('从曲库移除所选歌曲？'),
        content: Text('将移除 ${selectedTracks.length} 首歌曲的曲库记录，不会删除电脑上的原始文件。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('移除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final controller = ref.read(libraryControllerProvider.notifier);
    await controller.removeTracks(selectedTracks);
    if (mounted) _setSelecting(false);
  }

  // ignore: unused_element
  Future<void> _showTrackMenu(Track track) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
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
                leading: const Icon(Icons.playlist_add_rounded),
                title: const Text('添加到歌单'),
                onTap: () => Navigator.pop(context, 'playlist'),
              ),
              ListTile(
                leading: const Icon(Icons.remove_circle_outline_rounded),
                title: const Text('从曲库移除'),
                onTap: () => Navigator.pop(context, 'remove'),
              ),
            ],
          ),
        ),
      ),
    );
    if (action == 'playlist') {
      await _addToPlaylist(track);
    }
    if (action == 'remove') {
      await _removeTrack(track);
    }
  }

  Future<void> _addToPlaylist(Track track) async {
    final playlists = ref.read(libraryControllerProvider).playlists;
    if (playlists.isEmpty) {
      if (!mounted) return;
      showLatestSnackBar(
        context,
        const SnackBar(content: Text('请先在“歌单”中新建一个歌单。')),
      );
      return;
    }
    final selected = await showDialog<PlaylistInfo>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('添加到歌单'),
        children: playlists
            .map(
              (playlist) => SimpleDialogOption(
                onPressed: () => Navigator.pop(context, playlist),
                child: ListTile(
                  leading: const Icon(
                    Icons.queue_music_rounded,
                    color: AppColors.accent,
                  ),
                  title: Text(playlist.name),
                  trailing: Text('${playlist.trackCount} 首'),
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
    if (!mounted) return;
    showLatestSnackBar(
      context,
      SnackBar(content: Text(added ? '已添加到“${selected.name}”' : '这首歌已经在该歌单中')),
    );
  }

  Future<void> _removeTrack(Track track) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('从曲库移除？'),
        content: Text('只移除“${track.title}”的曲库记录，不会删除电脑上的原文件。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(libraryControllerProvider.notifier).removeTrack(track);
    }
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.state,
    required this.filter,
    required this.desktop,
    required this.accent,
    required this.lightForeground,
    required this.onImportFile,
    required this.onImportFolder,
    required this.onSmartOrganize,
    required this.onBatch,
  });

  final LibraryState state;
  final LibraryFilter filter;
  final bool desktop;
  final Color accent;
  final bool lightForeground;
  final VoidCallback onImportFile;
  final VoidCallback onImportFolder;
  final VoidCallback? onSmartOrganize;
  final VoidCallback? onBatch;

  @override
  Widget build(BuildContext context) {
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          switch (filter) {
            LibraryFilter.all => '本地音乐',
            LibraryFilter.favorites => '我的收藏',
            LibraryFilter.videos => 'MV 专区',
            LibraryFilter.recent => '最近播放',
          },
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            color: lightForeground ? Colors.white : AppColors.ink,
            shadows: lightForeground
                ? const [Shadow(color: Colors.black38, blurRadius: 8)]
                : null,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${state.tracks.length} 首歌曲  ·  ${formatBytes(state.totalBytes)}',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: lightForeground
                ? Colors.white.withValues(alpha: 0.82)
                : AppColors.textSecondary,
          ),
        ),
      ],
    );
    final actions = Wrap(
      spacing: 9,
      children: [
        OutlinedButton.icon(
          onPressed: state.isImporting ? null : onSmartOrganize,
          icon: const Icon(Icons.auto_awesome_rounded, size: 18),
          label: const Text('智能整理'),
        ),
        OutlinedButton.icon(
          onPressed: onBatch,
          icon: const Icon(Icons.library_add_check_rounded, size: 18),
          label: const Text('批量管理'),
        ),
        OutlinedButton.icon(
          onPressed: state.isImporting ? null : onImportFolder,
          icon: const Icon(Icons.folder_open_rounded, size: 18),
          label: const Text('扫描文件夹'),
        ),
        FilledButton.icon(
          onPressed: state.isImporting ? null : onImportFile,
          icon: const Icon(Icons.add_rounded, size: 19),
          label: const Text('导入歌曲 / MV'),
          style: _importButtonStyle(accent),
        ),
      ],
    );
    if (desktop) {
      return Row(
        children: [
          Expanded(child: title),
          actions,
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: title),
        IconButton.filledTonal(
          tooltip: '一键智能整理',
          onPressed: state.isImporting ? null : onSmartOrganize,
          style: IconButton.styleFrom(
            backgroundColor: Colors.white.withValues(alpha: 0.78),
            foregroundColor: AppColors.ink,
            side: const BorderSide(color: Color(0x5C31465A)),
            elevation: 1,
          ),
          icon: const Icon(Icons.auto_awesome_rounded),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          tooltip: '批量管理',
          onPressed: onBatch,
          style: IconButton.styleFrom(
            backgroundColor: Colors.white.withValues(alpha: 0.78),
            foregroundColor: AppColors.ink,
            side: const BorderSide(color: Color(0x5C31465A)),
            elevation: 1,
          ),
          icon: const Icon(Icons.checklist_rounded),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: state.isImporting ? null : onImportFile,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('导入'),
          style: _importButtonStyle(accent),
        ),
      ],
    );
  }
}

ButtonStyle _importButtonStyle(Color color) {
  return FilledButton.styleFrom(
    backgroundColor: color.withValues(alpha: 0.86),
    foregroundColor: Colors.white,
    elevation: 0,
    padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 12),
    shape: const StadiumBorder(),
  );
}

class _InlineBatchBar extends StatelessWidget {
  const _InlineBatchBar({
    required this.accent,
    required this.selected,
    required this.total,
    required this.onSelectAll,
    required this.onFavorite,
    required this.onUnfavorite,
    required this.onPlaylist,
    required this.onRemove,
    required this.onClose,
  });

  final Color accent;
  final int selected;
  final int total;
  final VoidCallback onSelectAll;
  final VoidCallback? onFavorite;
  final VoidCallback? onUnfavorite;
  final VoidCallback? onPlaylist;
  final VoidCallback? onRemove;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 580;
          final accentForeground =
              ThemeData.estimateBrightnessForColor(accent) == Brightness.dark
              ? Colors.white
              : AppColors.ink;
          return compact
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Checkbox(
                          value: selected == total && total > 0,
                          tristate: selected > 0 && selected < total,
                          activeColor: accent,
                          onChanged: (_) => onSelectAll(),
                        ),
                        Expanded(child: Text('已选 $selected / $total 首')),
                        IconButton(
                          tooltip: '退出批量管理',
                          onPressed: onClose,
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        TextButton.icon(
                          onPressed: onUnfavorite,
                          style: TextButton.styleFrom(foregroundColor: accent),
                          icon: const Icon(Icons.heart_broken_outlined),
                          label: const Text('取消收藏'),
                        ),
                        TextButton.icon(
                          onPressed: onFavorite,
                          style: TextButton.styleFrom(foregroundColor: accent),
                          icon: const Icon(Icons.favorite_rounded),
                          label: const Text('收藏'),
                        ),
                        FilledButton.icon(
                          onPressed: onPlaylist,
                          style: FilledButton.styleFrom(
                            backgroundColor: accent,
                            foregroundColor: accentForeground,
                          ),
                          icon: const Icon(Icons.playlist_add_rounded),
                          label: const Text('加入歌单'),
                        ),
                        TextButton.icon(
                          onPressed: onRemove,
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFFD6405D),
                          ),
                          icon: const Icon(Icons.delete_outline_rounded),
                          label: const Text('移除'),
                        ),
                      ],
                    ),
                  ],
                )
              : Row(
                  children: [
                    Checkbox(
                      value: selected == total && total > 0,
                      tristate: selected > 0 && selected < total,
                      activeColor: accent,
                      onChanged: (_) => onSelectAll(),
                    ),
                    Text('已选 $selected / $total 首'),
                    const Spacer(),
                    TextButton(
                      onPressed: onUnfavorite,
                      style: TextButton.styleFrom(foregroundColor: accent),
                      child: const Text('取消收藏'),
                    ),
                    TextButton.icon(
                      onPressed: onFavorite,
                      style: TextButton.styleFrom(foregroundColor: accent),
                      icon: const Icon(Icons.favorite_rounded),
                      label: const Text('收藏'),
                    ),
                    FilledButton.icon(
                      onPressed: onPlaylist,
                      style: FilledButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: accentForeground,
                      ),
                      icon: const Icon(Icons.playlist_add_rounded),
                      label: const Text('加入歌单'),
                    ),
                    TextButton.icon(
                      onPressed: onRemove,
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFD6405D),
                      ),
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: const Text('移除'),
                    ),
                    IconButton(
                      tooltip: '退出批量管理',
                      onPressed: onClose,
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                );
        },
      ),
    );
  }
}

class _BatchManageDialog extends ConsumerStatefulWidget {
  const _BatchManageDialog({required this.tracks});

  final List<Track> tracks;

  @override
  ConsumerState<_BatchManageDialog> createState() => _BatchManageDialogState();
}

class _BatchManageDialogState extends ConsumerState<_BatchManageDialog> {
  final Set<int> _selected = {};

  List<Track> get _tracks => widget.tracks
      .where((track) => _selected.contains(track.id))
      .toList(growable: false);

  Future<void> _favorite(bool value) async {
    final controller = ref.read(libraryControllerProvider.notifier);
    await controller.setFavorites(
      _tracks.where((track) => track.isFavorite != value),
      value: value,
    );
    if (mounted) Navigator.pop(context);
  }

  Future<void> _addToPlaylist() async {
    final playlists = ref.read(libraryControllerProvider).playlists;
    if (playlists.isEmpty) return;
    final target = await showDialog<PlaylistInfo>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('添加到哪个歌单？'),
        children: playlists
            .map(
              (playlist) => SimpleDialogOption(
                onPressed: () => Navigator.pop(context, playlist),
                child: Text(playlist.name),
              ),
            )
            .toList(),
      ),
    );
    if (target == null) return;
    final controller = ref.read(libraryControllerProvider.notifier);
    final added = await controller.addTracksToPlaylist(target, _tracks);
    if (mounted) {
      final skipped = _tracks.length - added;
      showLatestSnackBar(
        context,
        SnackBar(
          content: Text(
            skipped == 0
                ? '已加入 ${target.name}'
                : '已加入 $added 首，跳过 $skipped 首重复歌曲',
          ),
        ),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasPlaylists = ref
        .watch(libraryControllerProvider)
        .playlists
        .isNotEmpty;
    return AlertDialog(
      title: Text('批量管理 · 已选 ${_selected.length} 首'),
      content: SizedBox(
        width: 620,
        height: 470,
        child: ListView.builder(
          itemCount: widget.tracks.length,
          itemBuilder: (context, index) {
            final track = widget.tracks[index];
            final checked = _selected.contains(track.id);
            return CheckboxListTile(
              value: checked,
              secondary: TrackArtwork(track: track, size: 42, borderRadius: 10),
              title: Text(
                track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(track.artist),
              onChanged: (_) => setState(
                () => checked
                    ? _selected.remove(track.id)
                    : _selected.add(track.id!),
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: _selected.isEmpty ? null : () => _favorite(false),
          child: const Text('取消收藏'),
        ),
        TextButton.icon(
          onPressed: _selected.isEmpty ? null : () => _favorite(true),
          icon: const Icon(Icons.favorite_rounded),
          label: const Text('收藏'),
        ),
        FilledButton.icon(
          onPressed: _selected.isEmpty || !hasPlaylists ? null : _addToPlaylist,
          icon: const Icon(Icons.playlist_add_rounded),
          label: const Text('加入歌单'),
        ),
      ],
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.onChanged, required this.accent});

  final ValueChanged<String> onChanged;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return LiquidGlass(
      borderRadius: 18,
      blur: 20,
      tint: accent,
      borderWidth: 1.25,
      child: TextField(
        onChanged: onChanged,
        style: const TextStyle(
          color: AppColors.ink,
          fontWeight: FontWeight.w600,
        ),
        decoration: const InputDecoration(
          hintText: '搜索歌名、歌手或专辑',
          hintStyle: TextStyle(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
          prefixIcon: Icon(Icons.search_rounded),
          suffixIcon: Icon(Icons.tune_rounded, size: 18),
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
        ),
      ),
    );
  }
}

class _FilterTabs extends StatelessWidget {
  const _FilterTabs({
    required this.value,
    required this.onChanged,
    required this.accent,
  });

  final LibraryFilter value;
  final ValueChanged<LibraryFilter> onChanged;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return LiquidGlass(
      borderRadius: 22,
      blur: 18,
      tint: accent,
      child: Container(
        padding: const EdgeInsets.all(4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children:
              [
                    (LibraryFilter.all, '全部'),
                    (LibraryFilter.favorites, '收藏'),
                    (LibraryFilter.videos, '有 MV'),
                    (LibraryFilter.recent, '最近'),
                  ]
                  .map((item) {
                    final selected = item.$1 == value;
                    return InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () => onChanged(item.$1),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutCubic,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 15,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          gradient: selected
                              ? LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Colors.white.withValues(alpha: 0.32),
                                    accent.withValues(alpha: 0.86),
                                  ],
                                )
                              : null,
                          border: selected
                              ? Border.all(
                                  color: Colors.white.withValues(alpha: 0.68),
                                )
                              : null,
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: selected
                              ? [
                                  BoxShadow(
                                    color: accent.withValues(alpha: 0.22),
                                    blurRadius: 10,
                                    offset: const Offset(0, 3),
                                  ),
                                ]
                              : null,
                        ),
                        child: Text(
                          item.$2,
                          style: TextStyle(
                            color: selected ? Colors.white : AppColors.ink,
                            fontWeight: selected
                                ? FontWeight.w800
                                : FontWeight.w600,
                          ),
                        ),
                      ),
                    );
                  })
                  .toList(growable: false),
        ),
      ),
    );
  }
}

class _DesktopTrackList extends StatelessWidget {
  const _DesktopTrackList({
    required this.tracks,
    required this.currentId,
    required this.accent,
    required this.onPlay,
    required this.onFavorite,
    required this.onMore,
    required this.selecting,
    required this.selectedIds,
    required this.onSelect,
  });

  final List<Track> tracks;
  final int? currentId;
  final Color accent;
  final ValueChanged<Track> onPlay;
  final ValueChanged<Track> onFavorite;

  /// A mouse position is supplied for desktop right-clicks.  Keeping that
  /// position lets the shared action menu use a lightweight popup instead of
  /// opening the touch-oriented bottom sheet over the whole page.
  final void Function(Track track, [Offset? position]) onMore;
  final bool selecting;
  final Set<int> selectedIds;
  final ValueChanged<Track> onSelect;

  @override
  Widget build(BuildContext context) {
    return LiquidGlass(
      borderRadius: 22,
      blur: 8,
      // This is a large background surface, not a destructive/action
      // control.  It must follow the selected wallpaper instead of using the
      // fixed coral brand colour (which made blue themes look pink).
      tint: accent,
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 15, vertical: 8),
            child: Row(
              children: [
                SizedBox(width: 40, child: Text('#')),
                Expanded(flex: 5, child: Text('歌曲')),
                Expanded(flex: 3, child: Text('专辑')),
                SizedBox(width: 66, child: Text('类型')),
                SizedBox(width: 65, child: Text('时长')),
                SizedBox(width: 86),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(0, 5, 0, 22),
              itemCount: tracks.length,
              itemBuilder: (context, index) {
                final track = tracks[index];
                final selected = currentId == track.id;
                return Material(
                  color: selected
                      ? accent.withValues(alpha: 0.10)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    onTap: () => selecting ? onSelect(track) : onPlay(track),
                    onSecondaryTapDown: selecting
                        ? null
                        : (details) => onMore(track, details.globalPosition),
                    onLongPress: selecting ? null : () => onMore(track),
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      height: 64,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 15),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 40,
                              child: selecting
                                  ? Checkbox(
                                      value: selectedIds.contains(track.id),
                                      onChanged: (_) => onSelect(track),
                                    )
                                  : selected
                                  ? Icon(
                                      Icons.graphic_eq_rounded,
                                      color: accent,
                                      size: 18,
                                    )
                                  : Text(
                                      '${index + 1}',
                                      style: const TextStyle(
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                            ),
                            Expanded(
                              flex: 5,
                              child: Row(
                                children: [
                                  TrackArtwork(
                                    track: track,
                                    size: 44,
                                    borderRadius: 9,
                                  ),
                                  const SizedBox(width: 11),
                                  Expanded(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          context.metadata(track.title),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: AppTheme.trackTitleStyle
                                              .copyWith(
                                                color: selected
                                                    ? accent
                                                    : AppColors.ink,
                                              ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          context.metadata(track.artist),
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
                            Expanded(
                              flex: 3,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                child: Text(
                                  context.metadata(track.album),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ),
                            ),
                            if (!selecting)
                              SizedBox(
                                width: 66,
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: _MediaTypeBadge(
                                    hasVideo:
                                        track.hasVideo || track.isVideoOnly,
                                    videoOnly: track.isVideoOnly,
                                  ),
                                ),
                              ),
                            SizedBox(
                              width: 65,
                              child: Text(
                                formatDuration(track.duration),
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                            SizedBox(
                              width: 86,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  IconButton(
                                    tooltip: context.tr(
                                      track.isFavorite ? '取消收藏' : '收藏',
                                    ),
                                    iconSize: 19,
                                    onPressed: () => onFavorite(track),
                                    color: track.isFavorite
                                        ? accent
                                        : AppColors.textSecondary,
                                    icon: Icon(
                                      track.isFavorite
                                          ? Icons.favorite_rounded
                                          : Icons.favorite_border_rounded,
                                    ),
                                  ),
                                  IconButton(
                                    iconSize: 19,
                                    onPressed: () => onMore(track),
                                    icon: const Icon(Icons.more_horiz_rounded),
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
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileTrackList extends StatelessWidget {
  const _MobileTrackList({
    required this.tracks,
    required this.currentId,
    required this.accent,
    required this.lightForeground,
    required this.onPlay,
    required this.onFavorite,
    required this.onMore,
    required this.selecting,
    required this.selectedIds,
    required this.onSelect,
  });

  final List<Track> tracks;
  final int? currentId;
  final Color accent;
  final bool lightForeground;
  final ValueChanged<Track> onPlay;
  final ValueChanged<Track> onFavorite;
  final ValueChanged<Track> onMore;
  final bool selecting;
  final Set<int> selectedIds;
  final ValueChanged<Track> onSelect;

  @override
  Widget build(BuildContext context) {
    return WholeItemViewport(
      itemExtent: 72,
      child: Material(
        color: Colors.white.withValues(alpha: lightForeground ? 0.88 : 0.78),
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: ListView.separated(
          padding: EdgeInsets.zero,
          physics: const ItemSnapScrollPhysics(
            itemExtent: 72,
            parent: ClampingScrollPhysics(),
          ),
          itemCount: tracks.length,
          separatorBuilder: (_, _) => Divider(
            height: 1,
            thickness: 0.7,
            indent: 76,
            endIndent: 14,
            color: AppColors.ink.withValues(alpha: 0.10),
          ),
          itemBuilder: (context, index) {
            final track = tracks[index];
            final selected = currentId == track.id;
            return SizedBox(
              height: 71,
              child: Material(
                color: selected
                    ? Color.alphaBlend(
                        accent.withValues(alpha: 0.17),
                        Colors.white.withValues(alpha: 0.72),
                      )
                    : Colors.transparent,
                child: InkWell(
                  onTap: () => selecting ? onSelect(track) : onPlay(track),
                  onLongPress: selecting ? null : () => onMore(track),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SizedBox.square(
                          dimension: 50,
                          child: selecting
                              ? Center(
                                  child: Checkbox(
                                    value: selectedIds.contains(track.id),
                                    onChanged: (_) => onSelect(track),
                                  ),
                                )
                              : Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    TrackArtwork(
                                      track: track,
                                      size: 48,
                                      borderRadius: 11,
                                    ),
                                    if (selected)
                                      const DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: Color(0x66000000),
                                          borderRadius: BorderRadius.all(
                                            Radius.circular(11),
                                          ),
                                        ),
                                        child: Icon(
                                          Icons.graphic_eq_rounded,
                                          color: Colors.white,
                                          size: 19,
                                        ),
                                      ),
                                  ],
                                ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      context.metadata(track.title),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppTheme.trackTitleStyle.copyWith(
                                        color: selected
                                            ? accent
                                            : AppColors.ink,
                                      ),
                                    ),
                                  ),
                                  if (track.hasVideo || track.isVideoOnly)
                                    const Padding(
                                      padding: EdgeInsets.only(left: 6),
                                      child: _MediaTypeBadge(hasVideo: true),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${context.metadata(track.artist)}  ·  ${context.metadata(track.album)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (!selecting)
                          IconButton(
                            onPressed: () => onMore(track),
                            icon: const Icon(Icons.more_vert_rounded),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _MediaTypeBadge extends StatelessWidget {
  const _MediaTypeBadge({required this.hasVideo, this.videoOnly = false});

  final bool hasVideo;
  final bool videoOnly;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: hasVideo ? const Color(0xFFFFEEF1) : const Color(0xFFF0F2F6),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        videoOnly
            ? '视频'
            : hasVideo
            ? '音频＋MV'
            : '音频',
        style: TextStyle(
          color: hasVideo ? AppColors.accent : AppColors.textSecondary,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.onImport});

  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: const BoxDecoration(
                color: Color(0xFFFFEEF1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.library_music_rounded,
                color: AppColors.accent,
                size: 42,
              ),
            ),
            const SizedBox(height: 18),
            Text('这里还没有音乐', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 7),
            Text(
              '把电脑里的 MP3 或 MP4/MV 导进来，建立你的音乐库。',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onImport,
              icon: const Icon(Icons.add_rounded),
              label: const Text('导入第一首歌 / MV'),
            ),
          ],
        ),
      ),
    );
  }
}
