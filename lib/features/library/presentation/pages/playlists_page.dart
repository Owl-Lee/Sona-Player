import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/localization/sona_localizations.dart';

import 'package:path/path.dart' as path_util;
import 'package:path_provider/path_provider.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/latest_snack_bar.dart';
import '../../../../core/widgets/liquid_glass.dart';
import '../../application/library_controller.dart';
import '../../domain/playlist_info.dart';
import '../../domain/track.dart';
import '../library_actions.dart';
import '../widgets/track_artwork.dart';
import '../../../settings/presentation/widgets/image_crop_dialog.dart';
import '../../../settings/application/appearance_controller.dart';

/// The playlist currently shown in the main content area.
final activePlaylistProvider = StateProvider<int?>((ref) => null);

// Playlist surfaces must follow the wallpaper's actual brightness.  The old
// preset flag treated every warm preset as a dark surface, which left the
// gold/wheat theme with a heavy brown veil and low-contrast text.
bool _usesDarkGlass(Color accent) => accent.computeLuminance() <= 0.27;

class PlaylistsPage extends ConsumerWidget {
  const PlaylistsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(libraryControllerProvider);
    final appearance = ref.watch(appearanceControllerProvider);
    final lightForeground = _usesDarkGlass(appearance.accent);
    final activePlaylistId = ref.watch(activePlaylistProvider);
    final activePlaylist = state.playlists.cast<PlaylistInfo?>().firstWhere(
      (item) => item?.id == activePlaylistId,
      orElse: () => null,
    );
    if (activePlaylistId != null && activePlaylist == null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => ref.read(activePlaylistProvider.notifier).state = null,
      );
    }
    if (activePlaylist != null) {
      return _PlaylistDetailDialog(
        playlist: activePlaylist,
        embedded: true,
        onEdit: () => _editPlaylist(context, ref, activePlaylist),
      );
    }
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, pageConstraints) {
          final mobile = pageConstraints.maxWidth < 430;
          return Padding(
            padding: EdgeInsets.fromLTRB(
              mobile ? 20 : 30,
              mobile ? 12 : 28,
              mobile ? 20 : 30,
              mobile ? 8 : 22,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.tr('我的歌单'),
                            style: Theme.of(context).textTheme.headlineMedium
                                ?.copyWith(
                                  fontSize: mobile ? 30 : 32,
                                  fontWeight: FontWeight.w900,
                                  color: lightForeground
                                      ? Colors.white
                                      : AppColors.ink,
                                  shadows: lightForeground
                                      ? const [
                                          Shadow(
                                            color: Colors.black38,
                                            blurRadius: 8,
                                          ),
                                        ]
                                      : null,
                                ),
                          ),
                        ],
                      ),
                    ),
                    _GlassCreateButton(
                      onPressed: () => _createPlaylist(context, ref),
                      label: Text(context.tr(mobile ? '新建' : '新建歌单')),
                      accent: appearance.accent,
                      compact: mobile,
                    ),
                  ],
                ),
                SizedBox(height: mobile ? 12 : 24),
                Expanded(
                  child: state.playlists.isEmpty
                      ? _EmptyPlaylists(
                          onCreate: () => _createPlaylist(context, ref),
                        )
                      : _PlaylistEntrance(
                          child: Scrollbar(
                            thumbVisibility: true,
                            child: ListView.separated(
                              padding: const EdgeInsets.only(
                                right: 18,
                                bottom: 8,
                              ),
                              physics: const ClampingScrollPhysics(),
                              itemCount: state.playlists.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final playlist = state.playlists[index];
                                return SizedBox(
                                  height: mobile ? 74 : 82,
                                  child: _PlaylistCard(
                                    playlist: playlist,
                                    index: index,
                                    onOpen: () =>
                                        ref
                                            .read(
                                              activePlaylistProvider.notifier,
                                            )
                                            .state = playlist
                                            .id,
                                    onDelete: () =>
                                        _deletePlaylist(context, ref, playlist),
                                    onEdit: () =>
                                        _editPlaylist(context, ref, playlist),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _createPlaylist(BuildContext context, WidgetRef ref) async {
    final draft = await showDialog<_PlaylistDraft>(
      context: context,
      builder: (context) => const _PlaylistEditorDialog(),
    );
    if (draft == null) return;
    await ref
        .read(libraryControllerProvider.notifier)
        .createPlaylist(
          draft.name,
          description: draft.description,
          coverPath: draft.coverPath,
        );
  }

  Future<void> _editPlaylist(
    BuildContext context,
    WidgetRef ref,
    PlaylistInfo playlist,
  ) async {
    final draft = await showDialog<_PlaylistDraft>(
      context: context,
      builder: (context) => _PlaylistEditorDialog(playlist: playlist),
    );
    if (draft == null) return;
    await ref
        .read(libraryControllerProvider.notifier)
        .updatePlaylist(
          playlist.id,
          name: draft.name,
          description: draft.description,
          coverPath: draft.coverPath,
        );
  }

  Future<void> _deletePlaylist(
    BuildContext context,
    WidgetRef ref,
    PlaylistInfo playlist,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('删除歌单？')),
        content: Text(
          context
              .tr('“{playlist}”会被删除，但其中的歌曲仍保留在本地曲库。')
              .replaceAll('{playlist}', playlist.name),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.tr('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.tr('删除')),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref
          .read(libraryControllerProvider.notifier)
          .deletePlaylist(playlist.id);
    }
  }
}

class _GlassCreateButton extends StatelessWidget {
  const _GlassCreateButton({
    required this.onPressed,
    required this.label,
    required this.accent,
    required this.compact,
  });

  final VoidCallback onPressed;
  final Widget label;
  final Color accent;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return LiquidGlass(
      borderRadius: 999,
      blur: 18,
      tint: accent,
      dark: true,
      borderWidth: 1.25,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onPressed,
          child: Container(
            constraints: const BoxConstraints(minHeight: 46),
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 16 : 20,
              vertical: 10,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.add_rounded, color: Colors.white),
                const SizedBox(width: 7),
                DefaultTextStyle(
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                  child: label,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlaylistDetailDialog extends ConsumerStatefulWidget {
  const _PlaylistDetailDialog({
    required this.playlist,
    required this.onEdit,
    this.embedded = false,
  });

  final PlaylistInfo playlist;
  final Future<void> Function() onEdit;
  final bool embedded;

  @override
  ConsumerState<_PlaylistDetailDialog> createState() =>
      _PlaylistDetailDialogState();
}

class _PlaylistDetailDialogState extends ConsumerState<_PlaylistDetailDialog> {
  late Future<List<Track>> _tracks;
  final Set<int> _selected = {};
  bool _selecting = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(covariant _PlaylistDetailDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    // This detail view is embedded in the tab page, so Flutter keeps its
    // State object when a sidebar playlist changes. The header received the
    // new playlist while the old Future stayed alive, making every sidebar
    // entry temporarily show the same songs. Reload only when the playlist
    // identity changes; ordinary count/metadata refreshes keep the list
    // stable and do not cause a needless database read.
    if (oldWidget.playlist.id != widget.playlist.id) {
      _selected.clear();
      _selecting = false;
      _reload();
    }
  }

  void _reload() {
    _tracks = ref
        .read(libraryControllerProvider.notifier)
        .tracksForPlaylist(widget.playlist.id);
  }

  void _closeDetail() {
    if (widget.embedded) {
      ref.read(activePlaylistProvider.notifier).state = null;
      return;
    }
    Navigator.pop(context);
  }

  Future<void> _removeSelected() async {
    if (_selected.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('从歌单移除？')),
        content: Text(
          context
              .tr('将从“{playlist}”移除 {count} 首歌曲，原文件仍保留。')
              .replaceAll('{playlist}', widget.playlist.name)
              .replaceAll('{count}', '${_selected.length}'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.tr('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.tr('确认移除')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final controller = ref.read(libraryControllerProvider.notifier);
    await controller.removeTracksFromPlaylist(widget.playlist.id, _selected);
    if (!mounted) return;
    setState(() {
      _selected.clear();
      _selecting = false;
      _reload();
    });
  }

  Future<void> _addTracks() async {
    final selected = await showDialog<List<Track>>(
      context: context,
      builder: (context) => _AddTracksDialog(target: widget.playlist),
    );
    if (selected == null || selected.isEmpty) return;
    final controller = ref.read(libraryControllerProvider.notifier);
    final added = await controller.addTracksToPlaylist(
      widget.playlist,
      selected,
    );
    if (!mounted) return;
    final skipped = selected.length - added;
    showLatestSnackBar(
      context,
      SnackBar(
        content: Text(
          skipped == 0
              ? context
                    .tr('已加入 {playlist}')
                    .replaceAll('{playlist}', widget.playlist.name)
              : context
                    .tr('已加入 {added} 首，跳过 {skipped} 首重复歌曲')
                    .replaceAll('{added}', '$added')
                    .replaceAll('{skipped}', '$skipped'),
        ),
      ),
    );
    setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width < 760;
    final appearance = ref.watch(appearanceControllerProvider);
    final darkGlass = _usesDarkGlass(appearance.accent);
    // These header actions are rendered directly over the wallpaper.  Do not
    // fall back to the ambient icon theme here: on dark presets it can turn
    // the icon-only actions almost invisible while the text actions remain
    // pink.  Keep the whole action group on the same readable accent system.
    const headerActionColor = AppColors.accent;
    final headerIconStyle = IconButton.styleFrom(
      foregroundColor: headerActionColor,
      backgroundColor: headerActionColor.withValues(alpha: 0.13),
      hoverColor: headerActionColor.withValues(alpha: 0.2),
      minimumSize: const Size.square(40),
    );
    final headerTextStyle = TextButton.styleFrom(
      foregroundColor: headerActionColor,
    );
    final content = SafeArea(
      child: ConstrainedBox(
        constraints: widget.embedded
            ? const BoxConstraints()
            : const BoxConstraints(maxWidth: 720, maxHeight: 680),
        child: Padding(
          padding: EdgeInsets.all(
            widget.embedded ? (mobile ? 14 : 18) : (mobile ? 18 : 22),
          ),
          child: Column(
            children: [
              if (mobile)
                Column(
                  children: [
                    Row(
                      children: [
                        _PlaylistCover(
                          playlist: widget.playlist,
                          index: widget.playlist.id,
                          size: 58,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.playlist.name,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              Text(
                                widget.playlist.description.isEmpty
                                    ? context
                                          .tr('{count} 首歌曲')
                                          .replaceAll(
                                            '{count}',
                                            '${widget.playlist.trackCount}',
                                          )
                                    : widget.playlist.description,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: context.tr(
                            widget.embedded ? '返回我的歌单' : '关闭',
                          ),
                          style: headerIconStyle,
                          onPressed: _closeDetail,
                          icon: Icon(
                            widget.embedded
                                ? Icons.arrow_back_rounded
                                : Icons.close_rounded,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 4,
                        children: [
                          TextButton.icon(
                            onPressed: _addTracks,
                            icon: const Icon(Icons.add_rounded),
                            label: Text(context.tr('添加歌曲')),
                            style: headerTextStyle,
                          ),
                          TextButton.icon(
                            onPressed: widget.onEdit,
                            icon: const Icon(Icons.edit_rounded),
                            label: Text(context.tr('编辑')),
                            style: headerTextStyle,
                          ),
                          IconButton(
                            tooltip: context.tr(_selecting ? '退出多选' : '多选歌曲'),
                            style: headerIconStyle,
                            onPressed: () => setState(() {
                              _selecting = !_selecting;
                              _selected.clear();
                            }),
                            icon: Icon(
                              _selecting
                                  ? Icons.close_rounded
                                  : Icons.library_add_check_rounded,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                )
              else
                Row(
                  children: [
                    _PlaylistCover(
                      playlist: widget.playlist,
                      index: widget.playlist.id,
                      size: 58,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.playlist.name,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          Text(
                            widget.playlist.description.isEmpty
                                ? context
                                      .tr('{count} 首歌曲')
                                      .replaceAll(
                                        '{count}',
                                        '${widget.playlist.trackCount}',
                                      )
                                : widget.playlist.description,
                          ),
                        ],
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _addTracks,
                      icon: const Icon(Icons.add_rounded),
                      label: Text(context.tr('添加歌曲')),
                      style: headerTextStyle,
                    ),
                    TextButton.icon(
                      onPressed: widget.onEdit,
                      icon: const Icon(Icons.edit_rounded),
                      label: Text(context.tr('编辑')),
                      style: headerTextStyle,
                    ),
                    IconButton(
                      tooltip: context.tr(_selecting ? '退出多选' : '多选歌曲'),
                      style: headerIconStyle,
                      onPressed: () => setState(() {
                        _selecting = !_selecting;
                        _selected.clear();
                      }),
                      icon: Icon(
                        _selecting
                            ? Icons.close_rounded
                            : Icons.library_add_check_rounded,
                      ),
                    ),
                    IconButton(
                      tooltip: context.tr(widget.embedded ? '返回我的歌单' : '关闭'),
                      style: headerIconStyle,
                      onPressed: _closeDetail,
                      icon: Icon(
                        widget.embedded
                            ? Icons.arrow_back_rounded
                            : Icons.close_rounded,
                      ),
                    ),
                  ],
                ),
              if (_selecting)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Row(
                    children: [
                      Text(
                        context
                            .tr('已选择 {count} 首')
                            .replaceAll('{count}', '${_selected.length}'),
                      ),
                      const Spacer(),
                      FilledButton.icon(
                        onPressed: _selected.isEmpty ? null : _removeSelected,
                        icon: const Icon(Icons.remove_circle_outline_rounded),
                        label: Text(context.tr('从歌单移除')),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 14),
              Expanded(
                child: FutureBuilder<List<Track>>(
                  future: _tracks,
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final tracks = snapshot.data!;
                    if (tracks.isEmpty) {
                      return Center(
                        child: Text(
                          context.tr('这个歌单还是空的。\n点击上方“添加歌曲”开始选择。'),
                          textAlign: TextAlign.center,
                        ),
                      );
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.only(bottom: 10),
                      itemCount: tracks.length,
                      itemBuilder: (context, index) {
                        final track = tracks[index];
                        final selected = _selected.contains(track.id);
                        Future<void> showActions([Offset? position]) =>
                            showTrackContextMenu(
                              context,
                              ref,
                              track,
                              source: TrackMenuSource.playlist,
                              position: position,
                              onRemoveFromPlaylist: () async {
                                await ref
                                    .read(libraryControllerProvider.notifier)
                                    .removeTrackFromPlaylist(
                                      widget.playlist.id,
                                      track.id!,
                                    );
                                if (mounted) setState(_reload);
                              },
                            );
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Material(
                            color: selected
                                ? appearance.accent.withValues(alpha: 0.16)
                                : Colors.white.withValues(
                                    alpha: darkGlass ? 0.08 : 0.16,
                                  ),
                            borderRadius: BorderRadius.circular(15),
                            child: GestureDetector(
                              behavior: HitTestBehavior.translucent,
                              onSecondaryTapDown: _selecting
                                  ? null
                                  : (details) =>
                                        showActions(details.globalPosition),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(15),
                                ),
                                leading: _selecting
                                    ? Checkbox(
                                        value: selected,
                                        onChanged: (_) => setState(
                                          () => selected
                                              ? _selected.remove(track.id)
                                              : _selected.add(track.id!),
                                        ),
                                      )
                                    : TrackArtwork(
                                        track: track,
                                        size: 45,
                                        borderRadius: 11,
                                      ),
                                title: Text(
                                  context.metadata(track.title),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTheme.trackTitleStyle,
                                ),
                                subtitle: Text(context.metadata(track.artist)),
                                trailing: Text(formatDuration(track.duration)),
                                onLongPress: _selecting ? null : showActions,
                                onTap: _selecting
                                    ? () => setState(
                                        () => selected
                                            ? _selected.remove(track.id)
                                            : _selected.add(track.id!),
                                      )
                                    : () {
                                        playTrack(
                                          ref,
                                          track,
                                          tracks,
                                          source: 'queue_source_playlist',
                                          sourceArgs: <String, String>{
                                            'playlist': widget.playlist.name,
                                          },
                                        );
                                        if (!widget.embedded) {
                                          Navigator.pop(context);
                                        }
                                      },
                              ),
                            ),
                          ),
                        );
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
    final guardedContent = PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selecting) {
          setState(() {
            _selecting = false;
            _selected.clear();
          });
        }
      },
      child: content,
    );
    if (widget.embedded) {
      // Keep playlist details in the same glass language as the library pages.
      // The outer inset also keeps the page visually separate from the player.
      return Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
        child: LiquidGlass(
          borderRadius: 26,
          blur: 18,
          tint: appearance.accent,
          dark: darkGlass,
          borderWidth: 1.1,
          child: guardedContent,
        ),
      );
    }
    return Dialog(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: LiquidGlass(
        borderRadius: 28,
        blur: 20,
        tint: appearance.accent,
        dark: darkGlass,
        child: guardedContent,
      ),
    );
  }
}

class _AddTracksDialog extends ConsumerStatefulWidget {
  const _AddTracksDialog({required this.target});

  final PlaylistInfo target;

  @override
  ConsumerState<_AddTracksDialog> createState() => _AddTracksDialogState();
}

class _AddTracksDialogState extends ConsumerState<_AddTracksDialog> {
  String _source = 'local';
  final Set<int> _selected = {};

  Future<List<Track>> _tracksForSource(LibraryState state) {
    if (_source == 'favorites') {
      return Future.value(
        state.tracks.where((track) => track.isFavorite).toList(),
      );
    }
    if (_source == 'recent') {
      return Future.value(state.recentlyPlayed.take(20).toList());
    }
    if (_source.startsWith('playlist:')) {
      final id = int.parse(_source.substring('playlist:'.length));
      return ref.read(libraryControllerProvider.notifier).tracksForPlaylist(id);
    }
    return Future.value(state.tracks);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(libraryControllerProvider);
    final sources = <DropdownMenuItem<String>>[
      DropdownMenuItem(value: 'local', child: Text(context.tr('本地曲库'))),
      DropdownMenuItem(value: 'favorites', child: Text(context.tr('我的收藏'))),
      DropdownMenuItem(value: 'recent', child: Text(context.tr('最近播放'))),
      ...state.playlists
          .where((playlist) => playlist.id != widget.target.id)
          .map(
            (playlist) => DropdownMenuItem(
              value: 'playlist:${playlist.id}',
              child: Text(
                context
                    .tr('歌单 · {playlist}')
                    .replaceAll('{playlist}', playlist.name),
              ),
            ),
          ),
    ];
    return AlertDialog(
      title: Text(context.tr('添加歌曲到歌单')),
      content: SizedBox(
        width: 620,
        height: 520,
        child: Column(
          children: [
            Row(
              children: [
                Text(context.tr('来源')),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _source,
                    items: sources,
                    onChanged: (value) => setState(() {
                      _source = value ?? 'local';
                      _selected.clear();
                    }),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  context
                      .tr('已选 {count} 首')
                      .replaceAll('{count}', '${_selected.length}'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: FutureBuilder<List<Track>>(
                future: _tracksForSource(state),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final tracks = snapshot.data!;
                  if (tracks.isEmpty) {
                    return Center(child: Text(context.tr('这个来源暂时没有歌曲')));
                  }
                  return ListView.builder(
                    itemCount: tracks.length,
                    itemBuilder: (context, index) {
                      final track = tracks[index];
                      final checked = _selected.contains(track.id);
                      return CheckboxListTile(
                        value: checked,
                        secondary: TrackArtwork(
                          track: track,
                          size: 42,
                          borderRadius: 10,
                        ),
                        title: Text(
                          context.metadata(track.title),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.trackTitleStyle,
                        ),
                        subtitle: Text(context.metadata(track.artist)),
                        onChanged: (_) => setState(
                          () => checked
                              ? _selected.remove(track.id)
                              : _selected.add(track.id!),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.tr('取消')),
        ),
        FilledButton(
          onPressed: _selected.isEmpty
              ? null
              : () {
                  _tracksForSource(state).then((tracks) {
                    if (!context.mounted) return;
                    Navigator.pop(
                      context,
                      tracks
                          .where((track) => _selected.contains(track.id))
                          .toList(),
                    );
                  });
                },
          child: Text(
            context
                .tr('添加 {count} 首')
                .replaceAll('{count}', '${_selected.length}'),
          ),
        ),
      ],
    );
  }
}

class _PlaylistCard extends ConsumerWidget {
  const _PlaylistCard({
    required this.playlist,
    required this.index,
    required this.onOpen,
    required this.onDelete,
    required this.onEdit,
  });

  final PlaylistInfo playlist;
  final int index;
  final VoidCallback onOpen;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  Future<void> _showContextMenu(BuildContext context, Offset position) async {
    final overlay = Navigator.of(context).overlay;
    if (overlay == null) return;
    final renderBox = overlay.context.findRenderObject() as RenderBox;
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 1, 1),
        Offset.zero & renderBox.size,
      ),
      items: [
        PopupMenuItem(
          value: 'open',
          child: ListTile(
            dense: true,
            leading: const Icon(Icons.open_in_new_rounded),
            title: Text(context.tr('打开歌单')),
          ),
        ),
        PopupMenuItem(
          value: 'edit',
          child: ListTile(
            dense: true,
            leading: const Icon(Icons.edit_rounded),
            title: Text(context.tr('编辑歌单')),
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'delete',
          child: ListTile(
            dense: true,
            leading: const Icon(
              Icons.delete_outline_rounded,
              color: Colors.red,
            ),
            title: Text(
              context.tr('删除歌单'),
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ),
      ],
    );
    switch (action) {
      case 'open':
        onOpen();
      case 'edit':
        onEdit();
      case 'delete':
        onDelete();
    }
  }

  static const _gradients = <List<Color>>[
    [Color(0xFF314E43), AppColors.mint],
    [Color(0xFF44376C), AppColors.lavender],
    [Color(0xFF6A403B), AppColors.coral],
    [Color(0xFF264C64), Color(0xFF79D5FF)],
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = _gradients[index % _gradients.length];
    final appearance = ref.watch(appearanceControllerProvider);
    final darkGlass = _usesDarkGlass(appearance.accent);
    final foreground = darkGlass ? Colors.white : AppColors.ink;
    final secondary = darkGlass
        ? Colors.white.withValues(alpha: 0.68)
        : AppColors.textSecondary;
    if (MediaQuery.sizeOf(context).width < 430) {
      return _CompactMobilePlaylistCard(
        playlist: playlist,
        index: index,
        colors: colors,
        onOpen: onOpen,
        onEdit: onEdit,
        onDelete: onDelete,
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onSecondaryTapDown: (details) =>
          _showContextMenu(context, details.globalPosition),
      child: LiquidGlass(
        borderRadius: 18,
        // A list can contain dozens of these. The translucent surface keeps the
        // glass visual while avoiding one expensive backdrop blur per row.
        blur: 0,
        tint: appearance.accent,
        dark: darkGlass,
        borderWidth: 1.1,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            onTap: onOpen,
            borderRadius: BorderRadius.circular(18),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withValues(alpha: 0.82)),
              ),
              child: Row(
                children: [
                  _PlaylistCover(
                    playlist: playlist,
                    index: index,
                    size: 54,
                    colors: colors,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          playlist.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: foreground,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          playlist.description.isEmpty
                              ? context
                                    .tr('{count} 首歌曲')
                                    .replaceAll(
                                      '{count}',
                                      '${playlist.trackCount}',
                                    )
                              : context
                                    .tr('{count} 首歌曲 · {description}')
                                    .replaceAll(
                                      '{count}',
                                      '${playlist.trackCount}',
                                    )
                                    .replaceAll(
                                      '{description}',
                                      playlist.description,
                                    ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: secondary),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: context.tr('歌单操作'),
                    iconColor: foreground,
                    onSelected: (value) {
                      if (value == 'edit') onEdit();
                      if (value == 'delete') onDelete();
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'edit',
                        child: Text(context.tr('编辑歌单')),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text(context.tr('删除歌单')),
                      ),
                    ],
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

class _CompactMobilePlaylistCard extends StatelessWidget {
  const _CompactMobilePlaylistCard({
    required this.playlist,
    required this.index,
    required this.colors,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
  });

  final PlaylistInfo playlist;
  final int index;
  final List<Color> colors;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x16081223),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.white.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOpen,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.76),
                width: 1,
              ),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: 0.24),
                  Colors.white.withValues(alpha: 0.04),
                ],
              ),
            ),
            child: Row(
              children: [
                _PlaylistCover(
                  playlist: playlist,
                  index: index,
                  size: 52,
                  colors: colors,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        playlist.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: AppColors.ink,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        playlist.description.isEmpty
                            ? context
                                  .tr('{count} 首歌曲')
                                  .replaceAll(
                                    '{count}',
                                    '${playlist.trackCount}',
                                  )
                            : context
                                  .tr('{count} 首歌曲 · {description}')
                                  .replaceAll(
                                    '{count}',
                                    '${playlist.trackCount}',
                                  )
                                  .replaceAll(
                                    '{description}',
                                    playlist.description,
                                  ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  color: Colors.white,
                  onSelected: (value) {
                    if (value == 'edit') onEdit();
                    if (value == 'delete') onDelete();
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'edit',
                      child: Text(context.tr('编辑歌单')),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text(context.tr('删除歌单')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlaylistEntrance extends StatefulWidget {
  const _PlaylistEntrance({required this.child});

  final Widget child;

  @override
  State<_PlaylistEntrance> createState() => _PlaylistEntranceState();
}

class _PlaylistEntranceState extends State<_PlaylistEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _curve;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _curve = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Avoid an opacity saveLayer for every playlist card entering the grid.
    // The short translation is enough to communicate that the page changed.
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 0.018),
        end: Offset.zero,
      ).animate(_curve),
      child: widget.child,
    );
  }
}

class _PlaylistCover extends StatelessWidget {
  const _PlaylistCover({
    required this.playlist,
    required this.index,
    required this.size,
    this.colors,
  });

  final PlaylistInfo playlist;
  final int index;
  final double size;
  final List<Color>? colors;

  @override
  Widget build(BuildContext context) {
    final cover = playlist.coverPath == null ? null : File(playlist.coverPath!);
    final fallback =
        colors ??
        _PlaylistCard._gradients[index % _PlaylistCard._gradients.length];
    final initial = _cleanInitial(playlist.name);
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.27),
      child: SizedBox.square(
        dimension: size,
        child: cover != null && cover.existsSync()
            ? Image.file(
                cover,
                fit: BoxFit.cover,
                cacheWidth: (size * MediaQuery.devicePixelRatioOf(context))
                    .ceil()
                    .clamp(96, 512),
                filterQuality: FilterQuality.low,
              )
            : DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: fallback,
                  ),
                ),
                child: Center(
                  child: Text(
                    initial,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: size * 0.42,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  String _cleanInitial(String name) {
    for (final character in name.trim().characters) {
      if (RegExp(r'[A-Za-z0-9\u3400-\u9FFF]').hasMatch(character)) {
        return character.toUpperCase();
      }
    }
    return '♫';
  }
}

class _PlaylistDraft {
  const _PlaylistDraft({
    required this.name,
    required this.description,
    this.coverPath,
  });

  final String name;
  final String description;
  final String? coverPath;
}

class _PlaylistEditorDialog extends StatefulWidget {
  const _PlaylistEditorDialog({this.playlist});

  final PlaylistInfo? playlist;

  @override
  State<_PlaylistEditorDialog> createState() => _PlaylistEditorDialogState();
}

class _PlaylistEditorDialogState extends State<_PlaylistEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  String? _coverPath;
  var _savingCover = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.playlist?.name ?? '');
    _description = TextEditingController(
      text: widget.playlist?.description ?? '',
    );
    _coverPath = widget.playlist?.coverPath;
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickCover() async {
    final picked = await FilePicker.pickFile(type: FileType.image);
    if (picked == null || !mounted) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    final cropped = await ImageCropDialog.show(
      context,
      imageBytes: bytes,
      aspectRatio: 1,
      title: context.tr('裁切歌单封面'),
      hint: context.tr('拖动并缩放，保留正方形区域'),
    );
    if (cropped == null || !mounted) return;
    setState(() => _savingCover = true);
    final support = await getApplicationSupportDirectory();
    final directory = Directory(
      path_util.join(support.path, 'SonarVault', 'playlist_covers'),
    );
    await directory.create(recursive: true);
    final destination = path_util.join(
      directory.path,
      'cover_${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    await File(destination).writeAsBytes(cropped, flush: true);
    if (!mounted) return;
    setState(() {
      _coverPath = destination;
      _savingCover = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cover = _coverPath == null ? null : File(_coverPath!);
    return AlertDialog(
      title: Text(context.tr(widget.playlist == null ? '新建歌单' : '编辑歌单')),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: SizedBox.square(
                  dimension: 166,
                  child: InkWell(
                    onTap: _savingCover ? null : _pickCover,
                    borderRadius: BorderRadius.circular(20),
                    child: Ink(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0ECFF),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: AppColors.lavender.withValues(alpha: 0.26),
                        ),
                        image: cover != null && cover.existsSync()
                            ? DecorationImage(
                                image: ResizeImage.resizeIfNeeded(
                                  512,
                                  512,
                                  FileImage(cover),
                                ),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: cover != null && cover.existsSync()
                              ? Colors.black.withValues(alpha: 0.24)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Center(
                          child: _savingCover
                              ? const CircularProgressIndicator()
                              : Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.add_photo_alternate_outlined,
                                      color: cover != null && cover.existsSync()
                                          ? Colors.white
                                          : AppColors.lavender,
                                      size: 35,
                                    ),
                                    const SizedBox(height: 7),
                                    Text(
                                      context.tr(
                                        cover != null && cover.existsSync()
                                            ? '点按更换并裁切封面'
                                            : '添加歌单封面（可选）',
                                      ),
                                      style: TextStyle(
                                        color:
                                            cover != null && cover.existsSync()
                                            ? Colors.white
                                            : AppColors.ink,
                                        fontWeight: FontWeight.w700,
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
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _name,
                      onChanged: (_) => setState(() {}),
                      autofocus: true,
                      maxLength: 40,
                      minLines: 2,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: context.tr('歌单名称'),
                        hintText: context.tr('例如：夜晚散步'),
                        alignLabelWithHint: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _description,
                      maxLength: 160,
                      minLines: 2,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: context.tr('歌单描述'),
                        hintText: context.tr('心情、场景或故事'),
                        alignLabelWithHint: true,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.tr('取消')),
        ),
        FilledButton(
          onPressed: _savingCover || _name.text.trim().isEmpty
              ? null
              : () => Navigator.of(context).pop(
                  _PlaylistDraft(
                    name: _name.text.trim(),
                    description: _description.text.trim(),
                    coverPath: _coverPath,
                  ),
                ),
          child: Text(context.tr(widget.playlist == null ? '创建' : '保存')),
        ),
      ],
    );
  }
}

class _EmptyPlaylists extends StatelessWidget {
  const _EmptyPlaylists({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: AppColors.lavender.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.queue_music_rounded,
              color: AppColors.lavender,
              size: 42,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            context.tr('创建你的第一个歌单'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            context.tr('比如通勤、睡前、运动，或者只属于某段时间的音乐。'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 19),
          FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add_rounded),
            label: Text(context.tr('新建歌单')),
          ),
        ],
      ),
    );
  }
}
