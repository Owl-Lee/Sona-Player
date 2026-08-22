import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/sona_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/latest_request_gate.dart';
import '../../../core/widgets/latest_snack_bar.dart';
import '../../../core/widgets/liquid_glass.dart';
import '../../cloud/application/cloud_sync_controller.dart';
import '../../library/application/library_controller.dart';
import '../../library/presentation/library_actions.dart';
import '../../settings/application/appearance_controller.dart';
import '../../settings/presentation/widgets/image_crop_dialog.dart';
import '../application/account_controller.dart';

class AccountSyncCard extends ConsumerWidget {
  const AccountSyncCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(accountControllerProvider);
    final controller = ref.read(accountControllerProvider.notifier);
    final sync = ref.watch(cloudSyncControllerProvider);
    final syncController = ref.read(cloudSyncControllerProvider.notifier);
    final library = ref.watch(libraryControllerProvider);
    final glassTint = ref.watch(appearanceControllerProvider).accent;
    if (!account.configured) {
      return _CloudPanel(
        icon: Icons.cloud_sync_outlined,
        title: '云账号框架已就绪',
        description: '等待连接 Supabase 项目。连接后先同步账号、头像、歌单、收藏、播放统计和设置；歌曲文件稍后单独启用。',
        badge: '等待密钥',
        actions: const [],
        glassTint: glassTint,
      );
    }
    final user = account.user;
    if (user != null) {
      final displayName = account.displayName.isNotEmpty
          ? account.displayName
          : account.username.isNotEmpty
          ? account.username
          : 'Sona 用户';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CloudPanel(
            icon: Icons.account_circle_outlined,
            title: displayName,
            description: '管理头像、名称和当前登录账号。',
            badge: '已连接',
            avatarUrl: account.avatarUrl,
            busy: account.loading,
            message: account.error.isNotEmpty ? account.error : account.message,
            isError: account.error.isNotEmpty,
            glassTint: glassTint,
            actions: [
              OutlinedButton.icon(
                onPressed: account.loading || sync.syncing
                    ? null
                    : () => _pickAndUploadAvatar(context, controller),
                icon: const Icon(Icons.add_a_photo_outlined),
                label: const Text('更换头像'),
              ),
              OutlinedButton.icon(
                onPressed: account.loading || sync.syncing
                    ? null
                    : () => _showNameDialog(context, ref, account.displayName),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('修改名称'),
              ),
              OutlinedButton.icon(
                onPressed: account.loading || sync.syncing
                    ? null
                    : controller.signOut,
                icon: const Icon(Icons.logout_rounded),
                label: const Text('退出账号'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _CloudPanel(
            icon: Icons.cloud_sync_outlined,
            title: '云同步',
            description: sync.offline
                ? '离线状态，无法连接至云端。本地曲库和播放不受影响。'
                : '查看同步预览、同步状态，并管理云端保存的歌曲。',
            badge: sync.offline ? '离线' : (sync.syncing ? '同步中' : '云空间'),
            busy: sync.syncing,
            progress: sync.syncing ? sync.progress : null,
            message: sync.error.isNotEmpty
                ? sync.error
                : sync.summary.isNotEmpty
                ? sync.summary
                : sync.status,
            isError: sync.error.isNotEmpty,
            glassTint: glassTint,
            actions: [
              OutlinedButton.icon(
                onPressed: sync.syncing
                    ? null
                    : () => syncController.previewSync(library),
                icon: const Icon(Icons.preview_outlined),
                label: const Text('同步预览'),
              ),
              FilledButton.icon(
                onPressed: sync.syncing
                    ? null
                    : () async {
                        final success = await syncController.sync(library);
                        if (success) {
                          await ref
                              .read(libraryControllerProvider.notifier)
                              .load();
                          await syncController.loadCloudTracks();
                        }
                      },
                icon: const Icon(Icons.sync_rounded),
                label: Text(sync.syncing ? '同步中' : '立即同步'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _CloudLibraryPanel(glassTint: glassTint),
        ],
      );
    }
    return _CloudPanel(
      icon: user == null ? Icons.account_circle_outlined : Icons.cloud_done,
      title: user == null
          ? '登录 Sona 云账号'
          : account.displayName.isNotEmpty
          ? account.displayName
          : account.username.isNotEmpty
          ? account.username
          : 'Sona 用户',
      description: user == null
          ? '使用账号名和密码登录；同一账号可同步头像、收藏、歌单、播放记录和音乐数据。'
          : '你的收藏、歌单、播放记录和小于 50 MB 的音乐可在已登录设备间同步；本地原文件仍保留在本机。',
      badge: user == null ? '未登录' : '已连接',
      avatarUrl: account.avatarUrl,
      busy: account.loading || sync.syncing,
      progress: sync.syncing ? sync.progress : null,
      message: account.error.isNotEmpty
          ? account.error
          : sync.error.isNotEmpty
          ? sync.error
          : sync.summary.isNotEmpty
          ? sync.summary
          : sync.status.isNotEmpty
          ? sync.status
          : account.message,
      isError: account.error.isNotEmpty || sync.error.isNotEmpty,
      actions: user == null
          ? [
              OutlinedButton(
                onPressed: account.loading
                    ? null
                    : () => _showAuthDialog(context, ref, register: false),
                child: const Text('登录'),
              ),
              FilledButton(
                onPressed: account.loading
                    ? null
                    : () => _showAuthDialog(context, ref, register: true),
                child: const Text('注册'),
              ),
            ]
          : [
              OutlinedButton.icon(
                onPressed: sync.syncing
                    ? null
                    : () => syncController.previewSync(library),
                icon: const Icon(Icons.preview_outlined),
                label: const Text('同步预览'),
              ),
              FilledButton.icon(
                onPressed: sync.syncing
                    ? null
                    : () async {
                        final success = await syncController.sync(library);
                        if (success) {
                          await ref
                              .read(libraryControllerProvider.notifier)
                              .load();
                        }
                      },
                icon: const Icon(Icons.sync_rounded),
                label: Text(sync.syncing ? '同步中' : '立即同步'),
              ),
              OutlinedButton.icon(
                onPressed: account.loading || sync.syncing
                    ? null
                    : () => _pickAndUploadAvatar(context, controller),
                icon: const Icon(Icons.add_a_photo_outlined),
                label: const Text('更换头像'),
              ),
              OutlinedButton.icon(
                onPressed: account.loading || sync.syncing
                    ? null
                    : () => _showNameDialog(context, ref, account.displayName),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('修改名称'),
              ),
              OutlinedButton.icon(
                onPressed: account.loading || sync.syncing
                    ? null
                    : controller.signOut,
                icon: const Icon(Icons.logout_rounded),
                label: const Text('退出账号'),
              ),
            ],
      glassTint: glassTint,
    );
  }

  Future<void> _pickAndUploadAvatar(
    BuildContext context,
    AccountController controller,
  ) async {
    final picked = await FilePicker.pickFile(type: FileType.image);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (!context.mounted) return;
    final cropped = await ImageCropDialog.show(
      context,
      imageBytes: bytes,
      aspectRatio: 1,
      title: '裁切头像',
      hint: '拖动图片并缩放，保留想展示的正方形区域。',
    );
    if (cropped == null) return;
    await controller.uploadAvatar(cropped);
  }

  Future<void> _showAuthDialog(
    BuildContext context,
    WidgetRef ref, {
    required bool register,
  }) async {
    final identifier = TextEditingController();
    final username = TextEditingController();
    final password = TextEditingController();
    final confirmPassword = TextEditingController();
    final name = TextEditingController();
    var passwordVisible = false;
    var confirmPasswordVisible = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 24,
          ),
          scrollable: true,
          title: Text(register ? '注册 Sona' : '登录 Sona'),
          content: SizedBox(
            width: 410,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (register) ...[
                  TextField(
                    controller: username,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    maxLength: 24,
                    decoration: const InputDecoration(
                      labelText: '账号名',
                      helperText: '3–24 位：字母、数字或下划线；以字母开头',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: name,
                    textInputAction: TextInputAction.next,
                    maxLength: 30,
                    decoration: const InputDecoration(labelText: '显示名称（可选）'),
                  ),
                  const SizedBox(height: 10),
                ],
                if (!register) ...[
                  TextField(
                    controller: identifier,
                    keyboardType: TextInputType.text,
                    autocorrect: false,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: '账号名'),
                  ),
                  const SizedBox(height: 10),
                ],
                TextField(
                  controller: password,
                  obscureText: !passwordVisible,
                  enableSuggestions: false,
                  autocorrect: false,
                  autofillHints: register
                      ? const [AutofillHints.newPassword]
                      : const [AutofillHints.password],
                  textInputAction: register
                      ? TextInputAction.next
                      : TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: '密码',
                    helperText: '至少 8 位',
                    suffixIcon: IconButton(
                      tooltip: passwordVisible ? '隐藏密码' : '显示密码',
                      onPressed: () => setDialogState(
                        () => passwordVisible = !passwordVisible,
                      ),
                      icon: Icon(
                        passwordVisible
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                    ),
                  ),
                ),
                if (register) ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: confirmPassword,
                    obscureText: !confirmPasswordVisible,
                    enableSuggestions: false,
                    autocorrect: false,
                    autofillHints: const [AutofillHints.newPassword],
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => FocusScope.of(dialogContext).unfocus(),
                    decoration: InputDecoration(
                      labelText: '确认密码',
                      helperText: '请再输入一次密码',
                      suffixIcon: IconButton(
                        tooltip: confirmPasswordVisible ? '隐藏密码' : '显示密码',
                        onPressed: () => setDialogState(
                          () =>
                              confirmPasswordVisible = !confirmPasswordVisible,
                        ),
                        icon: Icon(
                          confirmPasswordVisible
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                final trimmedIdentifier = identifier.text.trim().toLowerCase();
                final normalizedUsername = username.text.trim().toLowerCase();
                final usernameValid = RegExp(r'^[a-z][a-z0-9_]{2,23}$')
                    .hasMatch(normalizedUsername);
                final identifierValid = RegExp(r'^[a-z][a-z0-9_]{2,23}$')
                    .hasMatch(trimmedIdentifier);
                if (password.text.length < 8 ||
                    (register && !usernameValid) ||
                    (!register && !identifierValid)) {
                  showLatestSnackBar(
                    context,
                    SnackBar(
                      content: Text(
                        register ? '账号名格式不正确，密码至少 8 位。' : '请输入正确的账号名，密码至少 8 位。',
                      ),
                    ),
                  );
                  return;
                }
                if (register && password.text != confirmPassword.text) {
                  showLatestSnackBar(
                    context,
                    const SnackBar(content: Text('两次输入的密码不一致，请重新确认。')),
                  );
                  return;
                }
                final controller = ref.read(accountControllerProvider.notifier);
                final success = register
                    ? await controller.signUp(
                        username: normalizedUsername,
                        password: password.text,
                        displayName: name.text.trim(),
                      )
                    : await controller.signIn(
                        identifier: trimmedIdentifier,
                        password: password.text,
                      );
                if (success && dialogContext.mounted) {
                  showLatestSnackBar(
                    context,
                    SnackBar(content: Text(register ? '账号创建成功，已登录。' : '登录成功。')),
                  );
                  Navigator.pop(dialogContext);
                } else if (dialogContext.mounted) {
                  final error = ref.read(accountControllerProvider).error;
                  showLatestSnackBar(
                    context,
                    SnackBar(
                      content: Text(error.isEmpty ? '操作未完成，请重试。' : error),
                    ),
                  );
                }
              },
              child: Text(register ? '创建账号' : '登录'),
            ),
          ],
        ),
      ),
    );
    identifier.dispose();
    username.dispose();
    password.dispose();
    confirmPassword.dispose();
    name.dispose();
  }

  Future<void> _showNameDialog(
    BuildContext context,
    WidgetRef ref,
    String current,
  ) async {
    final name = TextEditingController(text: current);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('修改显示名称'),
        content: TextField(
          controller: name,
          autofocus: true,
          maxLength: 30,
          decoration: const InputDecoration(labelText: '显示名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              await ref
                  .read(accountControllerProvider.notifier)
                  .updateDisplayName(name.text);
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    name.dispose();
  }
}

class _CloudLibraryPanel extends ConsumerStatefulWidget {
  const _CloudLibraryPanel({required this.glassTint});

  final Color glassTint;

  @override
  ConsumerState<_CloudLibraryPanel> createState() => _CloudLibraryPanelState();
}

enum _CloudLibraryView { tracks, artists }

enum _CloudMediaFilter { all, audio, video }

enum _CloudTrackSort { recent, title, artist, album, size }

class _CloudLibraryPanelState extends ConsumerState<_CloudLibraryPanel> {
  final _searchController = TextEditingController();
  final _trackScrollController = ScrollController();
  final _expandedArtists = <String>{};
  final _selectedCloudTrackIds = <String>{};

  var _view = _CloudLibraryView.tracks;
  var _filter = _CloudMediaFilter.all;
  var _sort = _CloudTrackSort.recent;
  var _selecting = false;
  var _deletingSelected = false;
  var _deleteCompleted = 0;
  var _deleteTotal = 0;
  String? _openingCloudTrackId;
  final _cloudPlaybackRequests = LatestRequestGate();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(cloudSyncControllerProvider.notifier).loadCloudTracks();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _trackScrollController.dispose();
    super.dispose();
  }

  Future<void> _confirmDelete(CloudTrackSummary track) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('从云端删除？'),
        content: Text(
          '“${track.title}”会从云空间和其他设备可同步内容中移除。\n\n'
          '本机文件不会删除；此后它也不会被自动重新上传。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除云副本'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await ref
          .read(cloudSyncControllerProvider.notifier)
          .deleteCloudTrack(track);
    }
  }

  void _setSelecting(bool value) {
    if (_deletingSelected) return;
    setState(() {
      _selecting = value;
      _selectedCloudTrackIds.clear();
      _deleteCompleted = 0;
      _deleteTotal = 0;
    });
  }

  void _toggleTrackSelection(CloudTrackSummary track) {
    if (_deletingSelected) return;
    setState(() {
      if (!_selectedCloudTrackIds.add(track.id)) {
        _selectedCloudTrackIds.remove(track.id);
      }
    });
  }

  void _toggleSelectAll(List<CloudTrackSummary> allTracks) {
    if (_deletingSelected) return;
    final allIds = allTracks.map((track) => track.id).toSet();
    final allSelected =
        allIds.isNotEmpty && allIds.every(_selectedCloudTrackIds.contains);
    setState(() {
      if (allSelected) {
        _selectedCloudTrackIds.removeAll(allIds);
      } else {
        // "Select all" deliberately means the complete cloud library, not
        // only the currently visible search/filter result. This makes the
        // mobile delete-all workflow predictable while the count keeps the
        // scope explicit before confirmation.
        _selectedCloudTrackIds.addAll(allIds);
      }
    });
  }

  Future<void> _confirmDeleteSelected(List<CloudTrackSummary> allTracks) async {
    if (_deletingSelected) return;
    final selected = allTracks
        .where((track) => _selectedCloudTrackIds.contains(track.id))
        .toList(growable: false);
    if (selected.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          context
              .tr('删除选中的 {count} 首云端歌曲？')
              .replaceAll('{count}', '${selected.length}'),
        ),
        content: Text(
          context.tr(
            '这些歌曲会从云空间和其他设备可同步内容中移除。\n\n'
            '本机文件不会删除；此后它们也不会被自动重新上传。此操作无法撤销。',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.tr('取消')),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.delete_outline_rounded),
            label: Text(
              context
                  .tr('删除 {count} 首云副本')
                  .replaceAll('{count}', '${selected.length}'),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _deletingSelected = true;
      _deleteCompleted = 0;
      _deleteTotal = selected.length;
    });
    final controller = ref.read(cloudSyncControllerProvider.notifier);
    var removed = 0;
    final failedIds = <String>{};
    for (var index = 0; index < selected.length; index += 1) {
      final track = selected[index];
      if (!mounted) return;
      final success = await controller.deleteCloudTrack(track);
      if (!mounted) return;
      if (success) {
        removed += 1;
        _selectedCloudTrackIds.remove(track.id);
      } else {
        failedIds.add(track.id);
      }
      final offline = ref.read(cloudSyncControllerProvider).offline;
      if (!success && offline) {
        failedIds.addAll(
          selected.skip(index + 1).map((remaining) => remaining.id),
        );
      }
      setState(() => _deleteCompleted = offline ? selected.length : index + 1);
      // One offline failure is enough evidence that the remaining requests
      // cannot succeed. Stop immediately instead of making a phone wait for
      // the same timeout once per selected cloud track.
      if (!success && offline) break;
    }
    if (!mounted) return;
    setState(() {
      _deletingSelected = false;
      _selectedCloudTrackIds
        ..clear()
        ..addAll(failedIds);
      _selecting = failedIds.isNotEmpty;
      _deleteCompleted = 0;
      _deleteTotal = 0;
    });
    showLatestSnackBar(
      context,
      SnackBar(
        content: Text(
          failedIds.isEmpty
              ? context
                    .tr('已从云端删除 {removed} 首歌曲，本机文件保持不变。')
                    .replaceAll('{removed}', '$removed')
              : context
                    .tr('已删除 {removed} 首，{failed} 首未能删除，请稍后重试。')
                    .replaceAll('{removed}', '$removed')
                    .replaceAll('{failed}', '${failedIds.length}'),
        ),
      ),
    );
  }

  Future<void> _playCloudTrack(
    CloudTrackSummary track,
    List<CloudTrackSummary> queueCandidates,
  ) async {
    final request = _cloudPlaybackRequests.begin();
    setState(() => _openingCloudTrackId = track.id);
    try {
      final cloud = ref.read(cloudSyncControllerProvider.notifier);
      final localTrack = await cloud.prepareCloudTrackForPlayback(track);
      if (!mounted || !_cloudPlaybackRequests.isCurrent(request)) return;
      if (localTrack == null) {
        showLatestSnackBar(
          context,
          const SnackBar(content: Text('云端文件暂时不可用，请稍后重试。')),
        );
        return;
      }
      await ref.read(libraryControllerProvider.notifier).load();
      if (!mounted || !_cloudPlaybackRequests.isCurrent(request)) return;
      final queue = await cloud.cachedCloudTracksForPlayback(queueCandidates);
      if (!mounted || !_cloudPlaybackRequests.isCurrent(request)) return;
      if (queue.every((item) => item.contentHash != localTrack.contentHash)) {
        queue.insert(0, localTrack);
      }
      await playTrack(ref, localTrack, queue, source: '云端资料库');
    } finally {
      if (mounted && _cloudPlaybackRequests.isCurrent(request)) {
        setState(() => _openingCloudTrackId = null);
      }
    }
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).ceil()} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _displayArtist(CloudTrackSummary track) {
    final artist = track.artist.trim();
    if (artist.isEmpty || artist.toLowerCase() == 'unknown artist') {
      return '未标注歌手';
    }
    return artist;
  }

  List<CloudTrackSummary> _visibleTracks(List<CloudTrackSummary> tracks) {
    final query = _searchController.text.trim().toLowerCase();
    final visible = tracks
        .where((track) {
          final matchesType = switch (_filter) {
            _CloudMediaFilter.all => true,
            _CloudMediaFilter.audio => track.mediaType != 'video',
            _CloudMediaFilter.video => track.mediaType == 'video',
          };
          if (!matchesType) return false;
          if (query.isEmpty) return true;
          return <String>[
            track.title,
            _displayArtist(track),
            track.album,
          ].join('\n').toLowerCase().contains(query);
        })
        .toList(growable: false);
    visible.sort(_compareTracks);
    return visible;
  }

  int _compareTracks(CloudTrackSummary first, CloudTrackSummary second) {
    int compareText(String a, String b) =>
        a.toLowerCase().compareTo(b.toLowerCase());

    final result = switch (_sort) {
      _CloudTrackSort.recent => (second.updatedAt ?? DateTime(0)).compareTo(
        first.updatedAt ?? DateTime(0),
      ),
      _CloudTrackSort.title => compareText(first.title, second.title),
      _CloudTrackSort.artist => compareText(
        _displayArtist(first),
        _displayArtist(second),
      ),
      _CloudTrackSort.album => compareText(first.album, second.album),
      _CloudTrackSort.size => second.fileSize.compareTo(first.fileSize),
    };
    if (result != 0 || _sort == _CloudTrackSort.recent) return result;
    return compareText(first.title, second.title);
  }

  Map<String, List<CloudTrackSummary>> _artistGroups(
    List<CloudTrackSummary> tracks,
  ) {
    final groups = <String, List<CloudTrackSummary>>{};
    for (final track in tracks) {
      groups.putIfAbsent(_displayArtist(track), () => []).add(track);
    }
    return groups;
  }

  String _resultDescription({
    required int visibleCount,
    required int totalCount,
  }) {
    final noun = _view == _CloudLibraryView.tracks ? '首曲目' : '位歌手';
    if (_searchController.text.trim().isEmpty &&
        _filter == _CloudMediaFilter.all) {
      return '共 $visibleCount $noun · 可搜索、筛选和排序';
    }
    return '找到 $visibleCount $noun（云端共 $totalCount 首）';
  }

  Widget _buildBrowser(
    BuildContext context,
    CloudSyncState sync,
    List<CloudTrackSummary> tracks,
  ) {
    final groups = _artistGroups(tracks);
    final groupEntries = groups.entries.toList()
      ..sort(
        (first, second) =>
            first.key.toLowerCase().compareTo(second.key.toLowerCase()),
      );
    final itemCount = _view == _CloudLibraryView.tracks
        ? tracks.length
        : groupEntries.length;
    final hasExpandedArtist =
        _view == _CloudLibraryView.artists &&
        groupEntries.any((group) => _expandedArtists.contains(group.key));
    final listHeight = hasExpandedArtist || itemCount > 3
        ? 350.0
        : itemCount * 70.0 + (itemCount > 1 ? (itemCount - 1) * 8.0 : 0);

    return SizedBox(
      height: listHeight,
      child: Scrollbar(
        controller: _trackScrollController,
        thumbVisibility: true,
        interactive: true,
        thickness: 5,
        radius: const Radius.circular(8),
        child: ListView.separated(
          controller: _trackScrollController,
          physics: const ClampingScrollPhysics(),
          // Keep every row clear of the desktop scrollbar. The thumb stays in
          // the outer gutter instead of covering the liquid-glass row.
          padding: const EdgeInsets.only(right: 16),
          itemCount: itemCount,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            if (_view == _CloudLibraryView.tracks) {
              final track = tracks[index];
              return _CloudTrackRow(
                track: track,
                removing: sync.removingCloudTrackId == track.id,
                opening: _openingCloudTrackId == track.id,
                selecting: _selecting,
                selected: _selectedCloudTrackIds.contains(track.id),
                selectionEnabled: !_deletingSelected,
                subtitle:
                    '${context.metadata(_displayArtist(track))} · ${_formatDuration(track.duration)} · ${_formatBytes(track.fileSize)}',
                onPlay: () => _playCloudTrack(track, tracks),
                onSelect: () => _toggleTrackSelection(track),
                onDelete: () => _confirmDelete(track),
              );
            }
            final group = groupEntries[index];
            final expanded = _expandedArtists.contains(group.key);
            return _CloudArtistGroup(
              artist: group.key,
              tracks: group.value,
              expanded: expanded,
              onToggle: () => setState(() {
                if (expanded) {
                  _expandedArtists.remove(group.key);
                } else {
                  _expandedArtists.add(group.key);
                }
              }),
              itemBuilder: (track) => _CloudTrackRow(
                track: track,
                removing: sync.removingCloudTrackId == track.id,
                opening: _openingCloudTrackId == track.id,
                selecting: _selecting,
                selected: _selectedCloudTrackIds.contains(track.id),
                selectionEnabled: !_deletingSelected,
                subtitle:
                    '${track.album.isEmpty ? context.tr('未标注专辑') : context.metadata(track.album)} · ${_formatDuration(track.duration)} · ${_formatBytes(track.fileSize)}',
                onPlay: () => _playCloudTrack(track, group.value),
                onSelect: () => _toggleTrackSelection(track),
                onDelete: () => _confirmDelete(track),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildControls(
    BuildContext context,
    List<CloudTrackSummary> allTracks,
  ) {
    final audioCount = allTracks
        .where((track) => track.mediaType != 'video')
        .length;
    final videoCount = allTracks.length - audioCount;
    final totalBytes = allTracks.fold<int>(
      0,
      (total, track) => total + track.fileSize,
    );
    final searchField = TextField(
      controller: _searchController,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.30),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 13,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.52)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: widget.glassTint, width: 1.25),
        ),
        hintText: '搜索歌名、歌手或专辑',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: _searchController.text.isEmpty
            ? null
            : IconButton(
                tooltip: '清除搜索',
                onPressed: () {
                  _searchController.clear();
                  setState(() {});
                },
                icon: const Icon(Icons.close_rounded),
              ),
      ),
    );
    final sortMenu = DropdownButtonFormField<_CloudTrackSort>(
      initialValue: _sort,
      isDense: true,
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.30),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 13,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.52)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: widget.glassTint, width: 1.25),
        ),
        prefixIcon: const Icon(Icons.sort_rounded),
      ),
      items: [
        DropdownMenuItem(
          value: _CloudTrackSort.recent,
          child: Text(context.tr('最近同步')),
        ),
        DropdownMenuItem(
          value: _CloudTrackSort.title,
          child: Text(context.tr('曲名 A–Z')),
        ),
        DropdownMenuItem(
          value: _CloudTrackSort.artist,
          child: Text(context.tr('歌手 A–Z')),
        ),
        DropdownMenuItem(
          value: _CloudTrackSort.album,
          child: Text(context.tr('专辑 A–Z')),
        ),
        DropdownMenuItem(
          value: _CloudTrackSort.size,
          child: Text(context.tr('文件大小')),
        ),
      ],
      onChanged: (value) {
        if (value != null) setState(() => _sort = value);
      },
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            _CloudLibraryMetric(
              icon: Icons.library_music_outlined,
              label: '云端曲目',
              value: '${allTracks.length} 首',
              tint: widget.glassTint,
            ),
            _CloudLibraryMetric(
              icon: Icons.music_note_rounded,
              label: '音乐',
              value: '$audioCount 首',
              tint: widget.glassTint,
            ),
            _CloudLibraryMetric(
              icon: Icons.movie_outlined,
              label: 'MV',
              value: '$videoCount 首',
              tint: widget.glassTint,
            ),
            _CloudLibraryMetric(
              icon: Icons.cloud_outlined,
              label: '已用空间',
              value: _formatBytes(totalBytes),
              tint: widget.glassTint,
            ),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: 230,
          child: Row(
            children: [
              Expanded(
                child: _CloudJellyChoice(
                  selected: _view == _CloudLibraryView.tracks,
                  icon: Icons.queue_music_rounded,
                  label: '曲目',
                  tint: widget.glassTint,
                  onTap: () => setState(() => _view = _CloudLibraryView.tracks),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _CloudJellyChoice(
                  selected: _view == _CloudLibraryView.artists,
                  icon: Icons.person_outline_rounded,
                  label: '按歌手',
                  tint: widget.glassTint,
                  onTap: () =>
                      setState(() => _view = _CloudLibraryView.artists),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _CloudJellyChoice(
              selected: _filter == _CloudMediaFilter.all,
              icon: Icons.library_music_outlined,
              label: '全部 ${allTracks.length}',
              tint: widget.glassTint,
              compact: true,
              onTap: () => setState(() => _filter = _CloudMediaFilter.all),
            ),
            _CloudJellyChoice(
              selected: _filter == _CloudMediaFilter.audio,
              icon: Icons.music_note_rounded,
              label: '音乐 $audioCount',
              tint: widget.glassTint,
              compact: true,
              onTap: () => setState(() => _filter = _CloudMediaFilter.audio),
            ),
            _CloudJellyChoice(
              selected: _filter == _CloudMediaFilter.video,
              icon: Icons.movie_outlined,
              label: 'MV $videoCount',
              tint: widget.glassTint,
              compact: true,
              onTap: () => setState(() => _filter = _CloudMediaFilter.video),
            ),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 620) {
              return Column(
                children: [
                  searchField,
                  const SizedBox(height: 10),
                  SizedBox(width: double.infinity, child: sortMenu),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: searchField),
                const SizedBox(width: 10),
                SizedBox(width: 172, child: sortMenu),
              ],
            );
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final sync = ref.watch(cloudSyncControllerProvider);
    final controller = ref.read(cloudSyncControllerProvider.notifier);
    final tracks = sync.cloudTracks;
    final visibleTracks = _visibleTracks(tracks);
    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selecting) _setSelecting(false);
      },
      child: _CloudPanel(
        icon: Icons.cloud_queue_outlined,
        title: '云端资料库',
        description: sync.offline
            ? '离线状态，无法连接至云端。本地曲库和播放仍可正常使用。'
            : sync.loadingCloudTracks
            ? '正在读取云端歌曲…'
            : '集中浏览和管理云端曲目。删除仅影响云副本，不会删除本机文件。',
        badge: sync.offline
            ? '离线'
            : (sync.loadingCloudTracks ? '读取中' : '${tracks.length} 首'),
        glassTint: widget.glassTint,
        actions: [
          OutlinedButton.icon(
            onPressed: sync.loadingCloudTracks
                ? null
                : controller.loadCloudTracks,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('刷新云内容'),
          ),
        ],
        content: sync.loadingCloudTracks && tracks.isEmpty
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: CircularProgressIndicator()),
              )
            : sync.offline && tracks.isEmpty
            ? const _CloudOfflineState()
            : tracks.isEmpty
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('云空间还没有歌曲。完成一次同步后，歌曲会显示在这里。'),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildControls(context, tracks),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _resultDescription(
                            visibleCount: _view == _CloudLibraryView.tracks
                                ? visibleTracks.length
                                : _artistGroups(visibleTracks).length,
                            totalCount: tracks.length,
                          ),
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (!_selecting)
                        TextButton.icon(
                          onPressed: () => _setSelecting(true),
                          icon: const Icon(Icons.checklist_rounded, size: 18),
                          label: Text(context.tr('批量管理')),
                        ),
                    ],
                  ),
                  if (_selecting) ...[
                    const SizedBox(height: 8),
                    _CloudBatchBar(
                      tint: widget.glassTint,
                      selected: _selectedCloudTrackIds
                          .where(
                            tracks.map((track) => track.id).toSet().contains,
                          )
                          .length,
                      total: tracks.length,
                      deleting: _deletingSelected,
                      completed: _deleteCompleted,
                      deleteTotal: _deleteTotal,
                      onSelectAll: () => _toggleSelectAll(tracks),
                      onDelete: () => _confirmDeleteSelected(tracks),
                      onClose: () => _setSelecting(false),
                    ),
                  ],
                  const SizedBox(height: 8),
                  if (visibleTracks.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: Text('没有匹配的云端曲目。')),
                    )
                  else
                    _buildBrowser(context, sync, visibleTracks),
                ],
              ),
      ),
    );
  }
}

class _CloudOfflineState extends StatelessWidget {
  const _CloudOfflineState();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
      ),
      child: const Row(
        children: [
          Icon(Icons.cloud_off_rounded, color: AppColors.accent),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              '网络不可用。离线状态下不会影响本地曲库、下载内容或正在播放的歌曲。',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _CloudLibraryMetric extends StatelessWidget {
  const _CloudLibraryMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.tint,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 112),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.46),
            tint.withValues(alpha: 0.14),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.58)),
        boxShadow: [
          BoxShadow(
            color: tint.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 16, color: AppColors.accent),
          ),
          const SizedBox(width: 7),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Shared glass interaction for cloud-library switches and filters. The
/// animated surface is deliberately restrained: it reads as a soft jelly press
/// on selection without making a dense library panel feel like a game UI.
class _CloudJellyChoice extends StatelessWidget {
  const _CloudJellyChoice({
    required this.selected,
    required this.icon,
    required this.label,
    required this.tint,
    required this.onTap,
    this.compact = false,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final Color tint;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? AppColors.ink : AppColors.textSecondary;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(compact ? 15 : 16),
        gradient: selected
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.alphaBlend(tint.withValues(alpha: 0.48), Colors.white),
                  Color.alphaBlend(tint.withValues(alpha: 0.28), Colors.white),
                ],
              )
            : LinearGradient(
                colors: [
                  Colors.white.withValues(alpha: 0.24),
                  Colors.white.withValues(alpha: 0.13),
                ],
              ),
        border: Border.all(
          color: selected
              ? tint.withValues(alpha: 0.56)
              : Colors.white.withValues(alpha: 0.46),
          width: selected ? 1.15 : 0.9,
        ),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: tint.withValues(alpha: 0.14),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(compact ? 15 : 16),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 11 : 10,
              vertical: compact ? 8 : 10,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: compact ? 16 : 17, color: foreground),
                SizedBox(width: compact ? 6 : 7),
                Text(
                  label,
                  style: TextStyle(
                    color: foreground,
                    fontSize: compact ? 13 : 14,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
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

class _CloudBatchBar extends StatelessWidget {
  const _CloudBatchBar({
    required this.tint,
    required this.selected,
    required this.total,
    required this.deleting,
    required this.completed,
    required this.deleteTotal,
    required this.onSelectAll,
    required this.onDelete,
    required this.onClose,
  });

  final Color tint;
  final int selected;
  final int total;
  final bool deleting;
  final int completed;
  final int deleteTotal;
  final VoidCallback onSelectAll;
  final VoidCallback onDelete;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final allSelected = total > 0 && selected == total;
    final partiallySelected = selected > 0 && selected < total;
    final status = deleting
        ? context
              .tr('正在删除 {completed} / {total} 首')
              .replaceAll('{completed}', '$completed')
              .replaceAll('{total}', '$deleteTotal')
        : context
              .tr('已选 {selected} / {total} 首')
              .replaceAll('{selected}', '$selected')
              .replaceAll('{total}', '$total');
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 7, 6, 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.43),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.72)),
        boxShadow: [
          BoxShadow(
            color: tint.withValues(alpha: 0.09),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Tooltip(
            message: context.tr(allSelected ? '取消全选' : '全选全部云端歌曲'),
            child: InkWell(
              onTap: deleting ? null : onSelectAll,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Checkbox(
                      value: allSelected,
                      tristate: partiallySelected,
                      activeColor: tint,
                      onChanged: deleting ? null : (_) => onSelectAll(),
                    ),
                    Text(
                      context.tr(allSelected ? '取消全选' : '全选'),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              status,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (deleting)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            FilledButton.icon(
              onPressed: selected == 0 ? null : onDelete,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFD6405D),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                minimumSize: const Size(0, 40),
              ),
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              label: Text(context.tr('删除')),
            ),
          IconButton(
            tooltip: context.tr('退出批量管理'),
            onPressed: deleting ? null : onClose,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}

class _CloudArtistGroup extends StatelessWidget {
  const _CloudArtistGroup({
    required this.artist,
    required this.tracks,
    required this.expanded,
    required this.onToggle,
    required this.itemBuilder,
  });

  final String artist;
  final List<CloudTrackSummary> tracks;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget Function(CloudTrackSummary track) itemBuilder;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: onToggle,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.11),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.person_outline_rounded,
                        color: AppColors.accent,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        context.metadata(artist),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    Text(
                      '${tracks.length} 首',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: AppColors.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Column(
                children: [
                  for (final track in tracks) ...[
                    const SizedBox(height: 6),
                    itemBuilder(track),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _CloudTrackRow extends StatelessWidget {
  const _CloudTrackRow({
    required this.track,
    required this.removing,
    required this.opening,
    required this.selecting,
    required this.selected,
    required this.selectionEnabled,
    required this.subtitle,
    required this.onPlay,
    required this.onSelect,
    required this.onDelete,
  });

  final CloudTrackSummary track;
  final bool removing;
  final bool opening;
  final bool selecting;
  final bool selected;
  final bool selectionEnabled;
  final String subtitle;
  final VoidCallback onPlay;
  final VoidCallback onSelect;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: 12, right: 6, top: 7, bottom: 7),
      decoration: BoxDecoration(
        color: selected
            ? Color.alphaBlend(
                AppColors.accent.withValues(alpha: 0.15),
                Colors.white.withValues(alpha: 0.32),
              )
            : Colors.white.withValues(alpha: 0.24),
        borderRadius: BorderRadius.circular(12),
        border: selected
            ? Border.all(color: AppColors.accent.withValues(alpha: 0.30))
            : null,
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: opening || removing || (selecting && !selectionEnabled)
            ? null
            : selecting
            ? onSelect
            : onPlay,
        onSecondaryTapDown: selecting || opening || removing
            ? null
            : (details) async {
                final overlay = Navigator.of(context).overlay;
                if (overlay == null) return;
                final overlayBox =
                    overlay.context.findRenderObject() as RenderBox;
                final action = await showMenu<String>(
                  context: context,
                  constraints: const BoxConstraints.tightFor(width: 142),
                  position: RelativeRect.fromRect(
                    Rect.fromLTWH(
                      details.globalPosition.dx,
                      details.globalPosition.dy,
                      1,
                      1,
                    ),
                    Offset.zero & overlayBox.size,
                  ),
                  items: [
                    PopupMenuItem<String>(
                      value: 'delete',
                      height: 42,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Row(
                        children: [
                          const Icon(Icons.delete_outline_rounded, size: 19),
                          const SizedBox(width: 8),
                          Text(context.tr('从云端删除')),
                        ],
                      ),
                    ),
                  ],
                );
                if (action == 'delete') onDelete();
              },
        child: Row(
          children: [
            if (selecting) ...[
              Checkbox(
                value: selected,
                activeColor: AppColors.accent,
                onChanged: selectionEnabled ? (_) => onSelect() : null,
              ),
              const SizedBox(width: 2),
            ],
            Icon(
              track.mediaType == 'video'
                  ? Icons.movie_outlined
                  : Icons.music_note_rounded,
              color: AppColors.accent,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.metadata(track.title),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.trackTitleStyle,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (!selecting)
              IconButton(
                tooltip: context.tr('从云端删除'),
                onPressed: removing || opening ? null : onDelete,
                icon: removing || opening
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.delete_outline_rounded),
              ),
          ],
        ),
      ),
    );
  }
}

class _CloudPanel extends StatelessWidget {
  const _CloudPanel({
    required this.icon,
    required this.title,
    required this.description,
    required this.badge,
    required this.actions,
    required this.glassTint,
    this.busy = false,
    this.message = '',
    this.isError = false,
    this.progress,
    this.avatarUrl,
    this.content,
  });

  final IconData icon;
  final String title;
  final String description;
  final String badge;
  final List<Widget> actions;
  final Color glassTint;
  final bool busy;
  final String message;
  final bool isError;
  final double? progress;
  final String? avatarUrl;
  final Widget? content;

  @override
  Widget build(BuildContext context) {
    return LiquidGlass(
      borderRadius: 18,
      blur: 22,
      tint: glassTint,
      // Account settings live on bright wallpapers. Keep this a light glass
      // surface so the content feels airy instead of turning the wallpaper
      // into a grey/black veil.
      dark: false,
      padding: const EdgeInsets.all(18),
      child: SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 45,
                  height: 45,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: avatarUrl == null
                      ? Icon(icon, color: AppColors.accent)
                      : Image.network(
                          avatarUrl!,
                          key: ValueKey(avatarUrl),
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              Icon(icon, color: AppColors.accent),
                        ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  badge,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            if (busy) ...[
              const SizedBox(height: 14),
              LinearProgressIndicator(value: progress),
            ],
            if (message.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                message,
                style: TextStyle(
                  color: isError
                      ? Colors.red.shade700
                      : AppColors.textSecondary,
                ),
              ),
            ],
            if (content != null) ...[const SizedBox(height: 14), content!],
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 14),
              Theme(
                data: Theme.of(context).copyWith(
                  outlinedButtonTheme: OutlinedButtonThemeData(
                    style: OutlinedButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.32),
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.46),
                      ),
                    ),
                  ),
                ),
                child: Wrap(spacing: 10, runSpacing: 8, children: actions),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
