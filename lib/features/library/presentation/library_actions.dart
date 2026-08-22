import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';

import '../../../core/localization/sona_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/latest_snack_bar.dart';
import '../application/library_controller.dart';
import '../domain/playlist_info.dart';
import '../domain/track.dart';
import '../domain/track_identification.dart';
import '../domain/track_metadata_revision.dart';
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
  final base = context
      .tr('导入 {added} 首，跳过 {skipped} 首，失败 {failed} 首')
      .replaceAll('{added}', '${summary.added}')
      .replaceAll('{skipped}', '${summary.skipped}')
      .replaceAll('{failed}', '${summary.failed}');
  final message = summary.needsReview == 0
      ? base
      : '$base · ${context.tr('{count} 首可智能整理').replaceAll('{count}', '${summary.needsReview}')}';
  showLatestSnackBar(context, SnackBar(content: Text(message)));
}

Future<void> smartOrganizeTracks(
  BuildContext context,
  WidgetRef ref,
  Iterable<Track> tracks,
) async {
  final targets = fullLibraryIdentificationTargets(tracks);
  if (targets.isEmpty) {
    showLatestSnackBar(
      context,
      SnackBar(content: Text(context.tr('曲库里没有可识别的歌曲。'))),
    );
    return;
  }

  final start = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.fingerprint_rounded),
          const SizedBox(width: 10),
          Text(context.tr('全面识别')),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 470),
        child: Text(
          context
              .tr(
                '将逐首扫描曲库中的 {count} 首歌曲。Windows 且已配置 AcoustID 时优先使用音频声纹；其他情况使用标签、文件名和免费公开曲库。所有建议都会先预览，确认后才修改曲库。\n\n公开曲库限制为每秒最多 1 次请求，歌曲较多时会花更长时间。',
              )
              .replaceAll('{count}', '${targets.length}'),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(context.tr('暂不扫描')),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(dialogContext, true),
          icon: const Icon(Icons.search_rounded),
          label: Text(context.tr('开始全面识别')),
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
      SnackBar(content: Text(context.tr('没有发现需要修改的歌曲信息。'))),
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
    SnackBar(
      content: Text(
        context.tr('已完成 {count} 首歌曲的信息校准。').replaceAll('{count}', '$applied'),
      ),
    ),
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
        result = const TrackIdentificationResult(
          message: 'unexpected_library_error',
        );
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
      title: Text(context.tr('正在全面识别')),
      content: SizedBox(
        width: 430,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(value: total == 0 ? 1 : _completed / total),
            const SizedBox(height: 16),
            Text(
              _stopping
                  ? context.tr('正在停止，请稍候…')
                  : context
                        .tr('正在识别第 {current} / {total} 首')
                        .replaceAll('{current}', '$current')
                        .replaceAll('{total}', '$total'),
            ),
            const SizedBox(height: 6),
            Text(
              _completed < total
                  ? context.metadata(widget.tracks[_completed].title)
                  : context.tr('即将完成'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            Text(
              context
                  .tr('已找到 {count} 条可预览的建议')
                  .replaceAll('{count}', '${_suggestions.length}'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _stopping ? null : () => setState(() => _stopping = true),
          child: Text(context.tr('停止扫描')),
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
      title: Text(
        context
            .tr('整理预览 · 已选 {count} 首')
            .replaceAll('{count}', '${_selected.length}'),
      ),
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
                '${context.tr('原信息')}：${context.metadata(suggestion.track.title)}  ·  '
                '${context.metadata(suggestion.track.artist)}\n'
                '${context.metadata(candidate.source)} · ${context.tr('可信度')} '
                '${(candidate.confidence * 100).round()}%',
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
          child: Text(context.tr('取消')),
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
            context.tr(
              _selected.length == widget.suggestions.length ? '全不选' : '全选',
            ),
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
          label: Text(
            context
                .tr('应用 {count} 项')
                .replaceAll('{count}', '${_selected.length}'),
          ),
        ),
      ],
    );
  }
}

Future<void> playTrack(
  WidgetRef ref,
  Track track,
  List<Track> queue, {
  String source = 'queue_source_local_library',
  Map<String, String> sourceArgs = const {},
}) async {
  // PlayerController owns the media-type route. That keeps a click from the
  // library, queue drawer, or next/previous buttons on one safe MV hand-off.
  await ref
      .read(playerControllerProvider.notifier)
      .playTrack(track, queue, source: source, sourceArgs: sourceArgs);
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
    case 'edit':
      await _editTrackDetails(context, ref, track);
    case 'history':
      await _showTrackMetadataHistory(context, ref, track);
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
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.82,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
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
  ('edit', Icons.edit_note_rounded, context.tr('编辑歌曲信息与封面')),
  ('history', Icons.manage_history_rounded, context.tr('识别与编辑历史')),
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

Future<void> _editTrackDetails(
  BuildContext context,
  WidgetRef ref,
  Track track,
) async {
  final draft = await showDialog<_TrackEditDraft>(
    context: context,
    builder: (_) => _TrackEditorDialog(track: track),
  );
  if (draft == null || !context.mounted) return;
  try {
    final updated = await ref
        .read(libraryControllerProvider.notifier)
        .updateTrackDetails(
          track,
          title: draft.title,
          artist: draft.artist,
          album: draft.album,
          selectedArtworkPath: draft.selectedArtworkPath,
          clearArtwork: draft.clearArtwork,
        );
    if (!context.mounted) return;
    showLatestSnackBar(
      context,
      SnackBar(
        content: Text(
          context.tr(updated == null ? '歌名和歌手不能为空。' : '歌曲信息已保存，可随时从历史中撤销。'),
        ),
      ),
    );
  } catch (error) {
    if (!context.mounted) return;
    showLatestSnackBar(
      context,
      SnackBar(
        content: Text(
          '${context.tr('保存失败')}：${_localizedLibraryError(context, error)}',
        ),
      ),
    );
  }
}

String _localizedLibraryError(BuildContext context, Object error) {
  if (error is LibraryOperationException) return context.tr(error.code);
  return context.tr('unexpected_library_error');
}

Future<void> _showTrackMetadataHistory(
  BuildContext context,
  WidgetRef ref,
  Track track,
) async {
  final controller = ref.read(libraryControllerProvider.notifier);
  final history = await controller.metadataHistory(track);
  if (!context.mounted) return;
  if (history.isEmpty) {
    showLatestSnackBar(
      context,
      SnackBar(content: Text(context.tr('这首歌还没有识别或手动编辑记录。'))),
    );
    return;
  }
  final shouldUndo = await showDialog<bool>(
    context: context,
    builder: (_) => _TrackHistoryDialog(track: track, revisions: history),
  );
  if (shouldUndo != true || !context.mounted) return;
  final updated = await controller.undoLatestMetadataChange(track);
  if (!context.mounted) return;
  showLatestSnackBar(
    context,
    SnackBar(
      content: Text(
        updated == null
            ? context.tr('无法撤销：歌曲信息已被其他操作修改，请重新打开历史。')
            : '${context.tr('已撤销最近一次校准，恢复为')}“${context.metadata(updated.title)}”。',
      ),
    ),
  );
}

class _TrackEditDraft {
  const _TrackEditDraft({
    required this.title,
    required this.artist,
    required this.album,
    this.selectedArtworkPath,
    this.clearArtwork = false,
  });

  final String title;
  final String artist;
  final String album;
  final String? selectedArtworkPath;
  final bool clearArtwork;
}

class _TrackEditorDialog extends StatefulWidget {
  const _TrackEditorDialog({required this.track});

  final Track track;

  @override
  State<_TrackEditorDialog> createState() => _TrackEditorDialogState();
}

class _TrackEditorDialogState extends State<_TrackEditorDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _artistController;
  late final TextEditingController _albumController;
  String? _selectedArtworkPath;
  var _clearArtwork = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.track.title);
    _artistController = TextEditingController(text: widget.track.artist);
    _albumController = TextEditingController(text: widget.track.album);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _artistController.dispose();
    _albumController.dispose();
    super.dispose();
  }

  Future<void> _chooseArtwork() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp'],
    );
    if (!mounted || file?.path == null) return;
    setState(() {
      _selectedArtworkPath = file!.path;
      _clearArtwork = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final previewTrack = _clearArtwork
        ? widget.track.copyWith(clearArtworkPath: true)
        : _selectedArtworkPath == null
        ? widget.track
        : widget.track.copyWith(artworkPath: _selectedArtworkPath);
    final canClear =
        !_clearArtwork &&
        (_selectedArtworkPath != null || widget.track.artworkPath != null);
    return AlertDialog(
      title: Text(context.tr('编辑歌曲信息')),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TrackArtwork(track: previewTrack, size: 84, borderRadius: 20),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.tr('歌曲封面'),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          context.tr(
                            '图片会复制到 Sona 的托管目录，移动原图不会影响封面。清除后自动回退到文字封面。',
                          ),
                          style: const TextStyle(fontSize: 12),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _chooseArtwork,
                              icon: const Icon(Icons.image_outlined),
                              label: Text(context.tr('选择图片')),
                            ),
                            TextButton.icon(
                              onPressed: canClear
                                  ? () => setState(() {
                                      _selectedArtworkPath = null;
                                      _clearArtwork = true;
                                    })
                                  : null,
                              icon: const Icon(Icons.auto_awesome_rounded),
                              label: Text(context.tr('使用文字封面')),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _titleController,
                autofocus: true,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: context.tr('歌名'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _artistController,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: context.tr('歌手'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _albumController,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: context.tr('专辑（可留空）'),
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (_) => _save(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.tr('取消')),
        ),
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.save_rounded),
          label: Text(context.tr('保存')),
        ),
      ],
    );
  }

  void _save() {
    final title = _titleController.text.trim();
    final artist = _artistController.text.trim();
    if (title.isEmpty || artist.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(context.tr('歌名和歌手不能为空。'))));
      return;
    }
    Navigator.pop(
      context,
      _TrackEditDraft(
        title: title,
        artist: artist,
        album: _albumController.text.trim(),
        selectedArtworkPath: _selectedArtworkPath,
        clearArtwork: _clearArtwork,
      ),
    );
  }
}

class _TrackHistoryDialog extends StatelessWidget {
  const _TrackHistoryDialog({required this.track, required this.revisions});

  final Track track;
  final List<TrackMetadataRevision> revisions;

  @override
  Widget build(BuildContext context) {
    final canUndo = revisions.any((revision) => !revision.isReverted);
    return AlertDialog(
      title: Text(
        '${context.tr('识别与编辑历史')} · ${context.metadata(track.title)}',
      ),
      content: SizedBox(
        width: 650,
        height: 440,
        child: ListView.separated(
          itemCount: revisions.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final revision = revisions[index];
            final time = revision.createdAt.toLocal();
            final timestamp =
                '${time.year}-${time.month.toString().padLeft(2, '0')}-'
                '${time.day.toString().padLeft(2, '0')} '
                '${time.hour.toString().padLeft(2, '0')}:'
                '${time.minute.toString().padLeft(2, '0')}';
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 4,
                vertical: 8,
              ),
              leading: CircleAvatar(
                child: Icon(
                  revision.kind == 'identification'
                      ? Icons.auto_fix_high_rounded
                      : Icons.edit_note_rounded,
                ),
              ),
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      context.tr(revision.source),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (revision.isReverted)
                    Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text(context.tr('已撤销')),
                    ),
                ],
              ),
              subtitle: Text(
                '${context.metadata(revision.previous.title)} · ${context.metadata(revision.previous.artist)}\n'
                '→ ${context.metadata(revision.current.title)} · ${context.metadata(revision.current.artist)}\n'
                '$timestamp${_artworkChangeLabel(context, revision)}',
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
              isThreeLine: true,
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.tr('关闭')),
        ),
        FilledButton.icon(
          onPressed: canUndo ? () => Navigator.pop(context, true) : null,
          icon: const Icon(Icons.undo_rounded),
          label: Text(context.tr('撤销最近一次')),
        ),
      ],
    );
  }

  String _artworkChangeLabel(
    BuildContext context,
    TrackMetadataRevision revision,
  ) {
    if (revision.previous.artworkPath == revision.current.artworkPath) {
      return '';
    }
    if (revision.current.artworkPath == null) {
      return ' · ${context.tr('清除封面')}';
    }
    return ' · ${context.tr('更新封面')}';
  }
}

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
    result = const TrackIdentificationResult(
      message: 'unexpected_library_error',
    );
  }
  if (!context.mounted) return;
  Navigator.of(context, rootNavigator: true).pop();

  final candidate = result.candidate;
  if (candidate == null) {
    showLatestSnackBar(
      context,
      SnackBar(content: Text(context.tr(result.message))),
    );
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
    SnackBar(
      content: Text(
        context
            .tr('已更新为“{title}”－{artist}')
            .replaceAll('{title}', context.metadata(candidate.title))
            .replaceAll('{artist}', context.metadata(candidate.artist)),
      ),
    ),
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
      SnackBar(content: Text(context.tr('请先在“歌单”中创建一个歌单。'))),
    );
    return;
  }
  final selected = await showDialog<PlaylistInfo>(
    context: context,
    builder: (dialogContext) => SimpleDialog(
      title: Text(context.tr('加入歌单')),
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
    SnackBar(
      content: Text(
        added
            ? context
                  .tr('已加入“{playlist}”')
                  .replaceAll('{playlist}', selected.name)
            : context.tr('这首歌已经在该歌单中'),
      ),
    ),
  );
}
