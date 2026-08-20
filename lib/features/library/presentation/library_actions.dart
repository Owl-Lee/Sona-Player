import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/sona_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/latest_snack_bar.dart';
import '../application/library_controller.dart';
import '../domain/playlist_info.dart';
import '../domain/track.dart';
import '../domain/track_identification.dart';
import '../../player/application/player_controller.dart';
import 'widgets/track_artwork.dart';

enum TrackMenuSource { library, recent, ranking, playlist }

Future<void> importMusic(
  BuildContext context,
  WidgetRef ref, {
  required bool directory,
}) async {
  final controller = ref.read(libraryControllerProvider.notifier);
  final summary = directory
      ? await controller.importDirectory()
      : await controller.importFiles();
  if (!context.mounted || summary == null) return;
  showLatestSnackBar(context, SnackBar(content: Text(summary.message)));
}

Future<void> smartOrganizeTracks(
  BuildContext context,
  WidgetRef ref,
  Iterable<Track> tracks,
) async {
  final targets = tracks
      .where((track) => track.id != null && needsSmartOrganization(track))
      .toList(growable: false);
  if (targets.isEmpty) {
    showLatestSnackBar(
      context,
      const SnackBar(content: Text('没有发现需要整理的低可信度歌曲。')),
    );
    return;
  }

  final start = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.auto_awesome_rounded),
          SizedBox(width: 10),
          Text('一键智能整理'),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 470),
        child: Text(
          '发现 ${targets.length} 首信息不完整或可信度较低的歌曲。\n\n'
          '将优先使用音频声纹加强识别（已配置时），'
          '再使用免费公开曲库校准。结果会先给你预览，'
          '确认后才会修改曲库。',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('暂不整理'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(dialogContext, true),
          icon: const Icon(Icons.search_rounded),
          label: const Text('开始识别'),
        ),
      ],
    ),
  );
  if (start != true || !context.mounted) return;

  final suggestions = await showDialog<List<_SmartSuggestion>>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _SmartScanDialog(tracks: targets),
  );
  if (!context.mounted || suggestions == null) return;
  if (suggestions.isEmpty) {
    showLatestSnackBar(
      context,
      const SnackBar(content: Text('没有找到可靠的批量整理结果。')),
    );
    return;
  }

  final accepted = await showDialog<List<_SmartSuggestion>>(
    context: context,
    builder: (_) => _SmartReviewDialog(suggestions: suggestions),
  );
  if (!context.mounted || accepted == null || accepted.isEmpty) return;
  final controller = ref.read(libraryControllerProvider.notifier);
  var applied = 0;
  for (final suggestion in accepted) {
    final updated = await controller.applyIdentification(
      suggestion.track,
      suggestion.candidate,
    );
    if (updated != null) applied++;
  }
  if (!context.mounted) return;
  showLatestSnackBar(
    context,
    SnackBar(content: Text('已完成 $applied 首歌曲的智能整理。')),
  );
}

class _SmartSuggestion {
  const _SmartSuggestion({required this.track, required this.candidate});

  final Track track;
  final TrackIdentificationCandidate candidate;
}

class _SmartScanDialog extends ConsumerStatefulWidget {
  const _SmartScanDialog({required this.tracks});

  final List<Track> tracks;

  @override
  ConsumerState<_SmartScanDialog> createState() => _SmartScanDialogState();
}

class _SmartScanDialogState extends ConsumerState<_SmartScanDialog> {
  final List<_SmartSuggestion> _suggestions = [];
  var _completed = 0;
  var _stopping = false;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_scan);
  }

  Future<void> _scan() async {
    final controller = ref.read(libraryControllerProvider.notifier);
    for (final track in widget.tracks) {
      if (_stopping) break;
      TrackIdentificationResult result;
      try {
        result = await controller.identifyTrack(track);
      } catch (_) {
        result = const TrackIdentificationResult(message: '识别失败。');
      }
      final candidate = result.candidate;
      if (candidate != null && _changesTrack(track, candidate)) {
        _suggestions.add(
          _SmartSuggestion(
            track: track,
            candidate: TrackIdentificationCandidate(
              title: candidate.title,
              artist: candidate.artist,
              album: candidate.album.trim().isEmpty
                  ? track.album
                  : candidate.album,
              confidence: candidate.confidence,
              source: candidate.source,
              explanation: candidate.explanation,
            ),
          ),
        );
      }
      if (!mounted) return;
      setState(() => _completed++);
    }
    if (!mounted) return;
    Navigator.pop(context, List<_SmartSuggestion>.unmodifiable(_suggestions));
  }

  bool _changesTrack(Track track, TrackIdentificationCandidate candidate) =>
      candidate.title.trim() != track.title.trim() ||
      candidate.artist.trim() != track.artist.trim() ||
      (candidate.album.trim().isNotEmpty &&
          candidate.album.trim() != track.album.trim());

  @override
  Widget build(BuildContext context) {
    final total = widget.tracks.length;
    final current = _completed >= total ? total : _completed + 1;
    return AlertDialog(
      title: const Text('正在智能整理'),
      content: SizedBox(
        width: 430,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(value: total == 0 ? 1 : _completed / total),
            const SizedBox(height: 16),
            Text(_stopping ? '正在停止，请稍候…' : '正在识别第 $current / $total 首'),
            const SizedBox(height: 6),
            Text(
              _completed < total ? widget.tracks[_completed].title : '即将完成',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            Text(
              '已找到 ${_suggestions.length} 条可预览的建议',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _stopping ? null : () => setState(() => _stopping = true),
          child: const Text('停止扫描'),
        ),
      ],
    );
  }
}

class _SmartReviewDialog extends StatefulWidget {
  const _SmartReviewDialog({required this.suggestions});

  final List<_SmartSuggestion> suggestions;

  @override
  State<_SmartReviewDialog> createState() => _SmartReviewDialogState();
}

class _SmartReviewDialogState extends State<_SmartReviewDialog> {
  late final Set<int> _selected = {
    for (var index = 0; index < widget.suggestions.length; index++)
      if (widget.suggestions[index].candidate.confidence >= 0.68) index,
  };

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('整理预览 · 已选 ${_selected.length} 首'),
      content: SizedBox(
        width: 680,
        height: 480,
        child: ListView.separated(
          itemCount: widget.suggestions.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final suggestion = widget.suggestions[index];
            final candidate = suggestion.candidate;
            return CheckboxListTile(
              value: _selected.contains(index),
              secondary: TrackArtwork(
                track: suggestion.track,
                size: 46,
                borderRadius: 12,
              ),
              title: Text(
                '${candidate.title}  ·  ${candidate.artist}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '原：${suggestion.track.title}  ·  ${suggestion.track.artist}\n'
                '${candidate.source} · 可信度 ${(candidate.confidence * 100).round()}%',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              isThreeLine: true,
              onChanged: (_) => setState(() {
                _selected.contains(index)
                    ? _selected.remove(index)
                    : _selected.add(index);
              }),
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
          onPressed: () => setState(() {
            if (_selected.length == widget.suggestions.length) {
              _selected.clear();
            } else {
              _selected.addAll(
                List<int>.generate(widget.suggestions.length, (index) => index),
              );
            }
          }),
          child: Text(
            _selected.length == widget.suggestions.length ? '全不选' : '全选',
          ),
        ),
        FilledButton.icon(
          onPressed: _selected.isEmpty
              ? null
              : () => Navigator.pop(context, [
                  for (
                    var index = 0;
                    index < widget.suggestions.length;
                    index++
                  )
                    if (_selected.contains(index)) widget.suggestions[index],
                ]),
          icon: const Icon(Icons.check_rounded),
          label: Text('应用 ${_selected.length} 项'),
        ),
      ],
    );
  }
}

Future<void> playTrack(
  WidgetRef ref,
  Track track,
  List<Track> queue, {
  String source = '本地曲库',
}) async {
  // PlayerController owns the media-type route. That keeps a click from the
  // library, queue drawer, or next/previous buttons on one safe MV hand-off.
  await ref
      .read(playerControllerProvider.notifier)
      .playTrack(track, queue, source: source);
}

/// Shared song actions for mouse right-click on Windows and long-press on
/// touch devices.  The original media file is never removed from disk.
Future<void> showTrackContextMenu(
  BuildContext context,
  WidgetRef ref,
  Track track, {
  TrackMenuSource source = TrackMenuSource.library,
  Offset? position,
  Future<void> Function()? onRemoveFromPlaylist,
}) async {
  final action = await _chooseTrackAction(
    context,
    track,
    source: source,
    position: position,
  );
  if (action == null || !context.mounted) return;

  final library = ref.read(libraryControllerProvider.notifier);
  switch (action) {
    case 'identify':
      await _identifyTrack(context, ref, track);
    case 'favorite':
      await library.toggleFavorite(track);
    case 'playlist':
      await _addTrackToPlaylist(context, ref, track);
    case 'source':
      if (source == TrackMenuSource.recent) {
        await library.clearFromRecentlyPlayed(track);
      } else if (source == TrackMenuSource.ranking) {
        await library.clearFromRankings(track);
      } else if (source == TrackMenuSource.playlist) {
        await onRemoveFromPlaylist?.call();
      }
    case 'library':
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(context.tr('从本地曲库移除？')),
          content: Text(
            '“${context.metadata(track.title)}”${context.tr('将不再显示在 Sona 中，电脑里的原始文件不会被删除。')}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(context.tr('取消')),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.remove_circle_outline_rounded),
              label: Text(context.tr('移除')),
            ),
          ],
        ),
      );
      if (confirmed == true) await library.removeTrack(track);
    default:
      return;
  }
}

Future<String?> _chooseTrackAction(
  BuildContext context,
  Track track, {
  required TrackMenuSource source,
  Offset? position,
}) {
  final items = _trackMenuItems(context, track, source);
  final overlay = Navigator.of(context).overlay;
  if (position != null &&
      overlay != null &&
      MediaQuery.sizeOf(context).width >= 760) {
    final overlayBox = overlay.context.findRenderObject() as RenderBox;
    return showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 1, 1),
        Offset.zero & overlayBox.size,
      ),
      items: items
          .map(
            (item) => PopupMenuItem<String>(
              value: item.$1,
              child: Row(
                children: [
                  Icon(
                    item.$2,
                    color: item.$1 == 'library' ? AppColors.accent : null,
                  ),
                  const SizedBox(width: 10),
                  Text(item.$3),
                ],
              ),
            ),
          )
          .toList(growable: false),
    );
  }
  return showModalBottomSheet<String>(
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
                context.metadata(track.title),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.trackTitleStyle,
              ),
              subtitle: Text(
                context.metadata(track.artist),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Divider(),
            ...items.map(
              (item) => ListTile(
                leading: Icon(
                  item.$2,
                  color: item.$1 == 'library' ? AppColors.accent : null,
                ),
                title: Text(item.$3),
                onTap: () => Navigator.pop(sheetContext, item.$1),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

List<(String, IconData, String)> _trackMenuItems(
  BuildContext context,
  Track track,
  TrackMenuSource source,
) => [
  ('identify', Icons.auto_fix_high_rounded, context.tr('AI 识别歌曲信息')),
  (
    'favorite',
    track.isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
    context.tr(track.isFavorite ? '取消收藏' : '收藏'),
  ),
  ('playlist', Icons.playlist_add_rounded, context.tr('加入歌单')),
  if (source == TrackMenuSource.recent)
    ('source', Icons.history_toggle_off_rounded, context.tr('从最近播放中移除')),
  if (source == TrackMenuSource.ranking)
    ('source', Icons.leaderboard_outlined, context.tr('从听歌排行中移除')),
  if (source == TrackMenuSource.playlist)
    ('source', Icons.playlist_remove_rounded, context.tr('从歌单中移除')),
  ('library', Icons.remove_circle_outline_rounded, context.tr('从本地曲库移除')),
];

Future<void> _identifyTrack(
  BuildContext context,
  WidgetRef ref,
  Track track,
) async {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      content: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox.square(
            dimension: 24,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          const SizedBox(width: 16),
          Flexible(child: Text(context.tr('正在分析标签、文件名和公开曲库…'))),
        ],
      ),
    ),
  );

  TrackIdentificationResult result;
  try {
    result = await ref
        .read(libraryControllerProvider.notifier)
        .identifyTrack(track);
  } catch (_) {
    result = const TrackIdentificationResult(message: '识别过程中出现异常，原歌曲信息没有被修改。');
  }
  if (!context.mounted) return;
  Navigator.of(context, rootNavigator: true).pop();

  final candidate = result.candidate;
  if (candidate == null) {
    showLatestSnackBar(context, SnackBar(content: Text(result.message)));
    return;
  }

  final accepted = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.auto_fix_high_rounded),
          const SizedBox(width: 10),
          Text(context.tr('识别结果')),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.tr(result.message)),
            const SizedBox(height: 16),
            _MetadataComparisonRow(
              label: context.tr('歌曲'),
              before: context.metadata(track.title),
              after: context.metadata(candidate.title),
            ),
            _MetadataComparisonRow(
              label: context.tr('歌手'),
              before: context.metadata(track.artist),
              after: context.metadata(candidate.artist),
            ),
            _MetadataComparisonRow(
              label: context.tr('专辑'),
              before: context.metadata(track.album),
              after: candidate.album.isEmpty
                  ? context.tr('未提供')
                  : context.metadata(candidate.album),
            ),
            const SizedBox(height: 12),
            Text(
              '${context.tr(candidate.source)} · ${context.tr('可信度')} ${(candidate.confidence * 100).round()}%',
              style: Theme.of(dialogContext).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Text(
              context.tr(candidate.explanation),
              style: Theme.of(dialogContext).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(context.tr('保留原信息')),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(dialogContext, true),
          icon: const Icon(Icons.check_rounded),
          label: Text(context.tr('应用校准')),
        ),
      ],
    ),
  );
  if (accepted != true || !context.mounted) return;
  await ref
      .read(libraryControllerProvider.notifier)
      .applyIdentification(track, candidate);
  if (!context.mounted) return;
  showLatestSnackBar(
    context,
    SnackBar(content: Text('已更新为“${candidate.title}”－${candidate.artist}')),
  );
}

class _MetadataComparisonRow extends StatelessWidget {
  const _MetadataComparisonRow({
    required this.label,
    required this.before,
    required this.after,
  });

  final String label;
  final String before;
  final String after;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 42,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(
            child: Text(
              before == after ? after : '$before  →  $after',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _addTrackToPlaylist(
  BuildContext context,
  WidgetRef ref,
  Track track,
) async {
  final playlists = ref.read(libraryControllerProvider).playlists;
  if (playlists.isEmpty) {
    showLatestSnackBar(
      context,
      const SnackBar(content: Text('请先在“歌单”中创建一个歌单。')),
    );
    return;
  }
  final selected = await showDialog<PlaylistInfo>(
    context: context,
    builder: (dialogContext) => SimpleDialog(
      title: const Text('加入歌单'),
      children: playlists
          .map(
            (playlist) => SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, playlist),
              child: Text(playlist.name),
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
    SnackBar(content: Text(added ? '已加入“${selected.name}”' : '这首歌已经在该歌单中')),
  );
}
