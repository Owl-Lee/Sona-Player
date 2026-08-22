import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as path_util;
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

import '../../../core/localization/sona_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/latest_snack_bar.dart';
import '../../../core/widgets/liquid_glass.dart';
import '../../account/presentation/account_sync_card.dart';
import '../../library/application/library_controller.dart';
import '../../library/data/library_backup_service.dart';
import '../../library/domain/library_backup.dart';
import '../application/appearance_controller.dart';
import '../application/language_controller.dart';
import '../application/release_update_service.dart';
import '../domain/release_update.dart';
import 'widgets/appearance_picker.dart';
import 'widgets/visual_effects_selector.dart';

enum _SettingsSection { root, appearance, account, language, storage, about }

/// The shell owns system-back and tab switching, while this page owns the
/// concrete secondary screen. Keeping only the depth public lets the shell
/// reset Settings without leaking its internal menu model.
final settingsDetailOpenProvider = StateProvider<bool>((ref) => false);

/// A shell-level request for the account subpage. The settings page keeps its
/// concrete route private, while callers can still open this destination
/// directly instead of first landing on the settings root.
final settingsAccountRequestProvider = StateProvider<int>((ref) => 0);

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  _SettingsSection _section = _SettingsSection.root;
  var _lastAccountRequest = 0;

  void _open(_SettingsSection section) {
    setState(() {
      _section = section;
    });
    ref.read(settingsDetailOpenProvider.notifier).state = true;
  }

  void _back() {
    setState(() {
      _section = _SettingsSection.root;
    });
    ref.read(settingsDetailOpenProvider.notifier).state = false;
  }

  @override
  Widget build(BuildContext context) {
    final accountRequest = ref.watch(settingsAccountRequestProvider);
    if (accountRequest != _lastAccountRequest) {
      _lastAccountRequest = accountRequest;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _open(_SettingsSection.account);
      });
    }
    ref.listen<bool>(settingsDetailOpenProvider, (previous, next) {
      if (!next && _section != _SettingsSection.root && mounted) {
        setState(() {
          _section = _SettingsSection.root;
        });
      }
    });
    final appearance = ref.watch(appearanceControllerProvider);
    final language = ref.watch(languageControllerProvider).language;
    final library = ref.watch(libraryControllerProvider);
    final lightForeground =
        !appearance.usesCustom && appearance.preset.prefersLightHomeForeground;
    final foreground = lightForeground ? Colors.white : AppColors.ink;

    return SafeArea(
      child: RepaintBoundary(
        child: switch (_section) {
          _SettingsSection.root => _SettingsRoot(
            foreground: foreground,
            lightForeground: lightForeground,
            appearanceName: appearance.usesCustom
                ? context.tr('我的背景')
                : context.tr(appearance.preset.name),
            language: language,
            onOpen: _open,
          ),
          _SettingsSection.appearance => _SettingsDetailPage(
            title: context.tr('外观与播放器'),
            foreground: foreground,
            lightForeground: lightForeground,
            onBack: _back,
            child: _SettingsPanel(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    context.tr('动态特效与性能'),
                    style: const TextStyle(
                      color: AppColors.ink,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    context.tr('可随设备性能切换特效强度；关闭动态特效不会改变壁纸和主题配色。'),
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 14),
                  VisualEffectsSelector(
                    labels: VisualEffectsLabels(
                      full: context.tr('完整特效'),
                      fullDescription: context.tr('保留完整环境动画、玻璃模糊和过渡效果'),
                      energySaver: context.tr('节能特效'),
                      energySaverDescription: context.tr('降低动画帧率、粒子数量和图片缓存占用'),
                      off: context.tr('关闭动态特效'),
                      offDescription: context.tr('保留静态主题，停用环境动画和实时液态毛玻璃模糊'),
                    ),
                  ),
                  const Divider(height: 34),
                  const AppearancePicker(),
                ],
              ),
            ),
          ),
          _SettingsSection.account => _SettingsDetailPage(
            title: context.tr('账号与云同步'),
            foreground: foreground,
            lightForeground: lightForeground,
            onBack: _back,
            child: const AccountSyncCard(),
          ),
          _SettingsSection.language => _SettingsDetailPage(
            title: context.tr('语言'),
            foreground: foreground,
            lightForeground: lightForeground,
            onBack: _back,
            child: const _LanguagePanel(),
          ),
          _SettingsSection.storage => _SettingsDetailPage(
            title: context.tr('存储与数据'),
            foreground: foreground,
            lightForeground: lightForeground,
            onBack: _back,
            child: _StoragePanel(databasePath: library.databasePath),
          ),
          _SettingsSection.about => _SettingsDetailPage(
            title: context.tr('关于'),
            foreground: foreground,
            lightForeground: lightForeground,
            onBack: _back,
            child: const _AboutPanel(),
          ),
        },
      ),
    );
  }
}

class _SettingsRoot extends StatelessWidget {
  const _SettingsRoot({
    required this.foreground,
    required this.lightForeground,
    required this.appearanceName,
    required this.language,
    required this.onOpen,
  });

  final Color foreground;
  final bool lightForeground;
  final String appearanceName;
  final AppLanguage language;
  final ValueChanged<_SettingsSection> onOpen;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth >= 1180
            ? 1040.0
            : double.infinity;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 26, 24, 36),
          child: Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('设置'),
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w900,
                      shadows: lightForeground
                          ? const [
                              Shadow(color: Colors.black38, blurRadius: 10),
                            ]
                          : null,
                    ),
                  ),
                  const SizedBox(height: 22),
                  _SettingsMenu(
                    children: [
                      _SettingsMenuRow(
                        icon: Icons.palette_outlined,
                        title: context.tr('外观与播放器'),
                        subtitle: appearanceName,
                        onTap: () => onOpen(_SettingsSection.appearance),
                      ),
                      _SettingsMenuRow(
                        icon: Icons.cloud_outlined,
                        title: context.tr('账号与云同步'),
                        subtitle: context.tr('登录、头像与跨设备同步'),
                        onTap: () => onOpen(_SettingsSection.account),
                      ),
                      _SettingsMenuRow(
                        icon: Icons.language_rounded,
                        title: context.tr('语言'),
                        subtitle: _languageName(context, language),
                        onTap: () => onOpen(_SettingsSection.language),
                      ),
                      _SettingsMenuRow(
                        icon: Icons.storage_rounded,
                        title: context.tr('存储与数据'),
                        subtitle: 'SQLite · ${context.tr('此设备')}',
                        onTap: () => onOpen(_SettingsSection.storage),
                      ),
                      _SettingsMenuRow(
                        icon: Icons.info_outline_rounded,
                        title: context.tr('关于'),
                        subtitle: 'Sona 0.5.0',
                        onTap: () => onOpen(_SettingsSection.about),
                        divider: false,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SettingsDetailPage extends StatelessWidget {
  const _SettingsDetailPage({
    required this.title,
    required this.foreground,
    required this.lightForeground,
    required this.onBack,
    required this.child,
  });

  final String title;
  final Color foreground;
  final bool lightForeground;
  final VoidCallback onBack;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Secondary settings pages should grow with the desktop window.  The
        // appearance grid in particular needs this width to add columns when
        // the window is maximised.
        const maxWidth = double.infinity;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 36),
          child: Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Material(
                        color: Colors.white.withValues(alpha: 0.22),
                        shape: const CircleBorder(),
                        child: IconButton(
                          tooltip: context.tr('返回设置'),
                          onPressed: onBack,
                          icon: Icon(
                            Icons.arrow_back_rounded,
                            color: foreground,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          title,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                color: foreground,
                                fontWeight: FontWeight.w900,
                                shadows: lightForeground
                                    ? const [
                                        Shadow(
                                          color: Colors.black38,
                                          blurRadius: 10,
                                        ),
                                      ]
                                    : null,
                              ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  child,
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SettingsMenu extends StatelessWidget {
  const _SettingsMenu({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return _SettingsPanel(
      padding: EdgeInsets.zero,
      child: Column(children: children),
    );
  }
}

class _SettingsMenuRow extends StatelessWidget {
  const _SettingsMenuRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.divider = true,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
              child: Row(
                children: [
                  Icon(icon, color: AppColors.textSecondary, size: 23),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: AppColors.ink,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
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
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (divider) const Divider(height: 1, indent: 56, endIndent: 16),
      ],
    );
  }
}

String _languageName(BuildContext context, AppLanguage language) =>
    switch (language) {
      AppLanguage.simplifiedChinese => context.tr('简体中文'),
      AppLanguage.traditionalChinese => context.tr('繁體中文'),
      AppLanguage.english => context.tr('英文'),
    };

class _LanguagePanel extends ConsumerWidget {
  const _LanguagePanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(languageControllerProvider).language;
    final accent = ref.watch(appearanceControllerProvider).accent;
    return _SettingsPanel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.tr('选择界面语言'),
            style: const TextStyle(
              color: AppColors.ink,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            context.tr('切换后立即应用，并在下次启动时保留。'),
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          for (final language in AppLanguage.values) ...[
            _LanguageChoice(
              language: language,
              selected: language == selected,
              accent: accent,
              onTap: () => ref
                  .read(languageControllerProvider.notifier)
                  .select(language),
            ),
            if (language != AppLanguage.values.last) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _LanguageChoice extends StatelessWidget {
  const _LanguageChoice({
    required this.language,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final AppLanguage language;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final sample = switch (language) {
      AppLanguage.simplifiedChinese => '简体中文',
      AppLanguage.traditionalChinese => '繁體中文',
      AppLanguage.english => 'English',
    };
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(17),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: 0.20)
                : Colors.white.withValues(alpha: 0.20),
            borderRadius: BorderRadius.circular(17),
            border: Border.all(
              color: selected
                  ? accent.withValues(alpha: 0.72)
                  : Colors.white.withValues(alpha: 0.72),
              width: selected ? 1.6 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.18),
                      blurRadius: 16,
                      offset: const Offset(0, 7),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: selected
                      ? accent.withValues(alpha: 0.88)
                      : Colors.white.withValues(alpha: 0.42),
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Text(
                  language == AppLanguage.english ? 'A' : '文',
                  style: TextStyle(
                    color: selected ? Colors.white : AppColors.ink,
                    fontWeight: FontWeight.w900,
                    fontSize: 17,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  sample,
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                child: selected
                    ? Icon(
                        Icons.check_circle_rounded,
                        key: const ValueKey('selected'),
                        color: accent,
                        size: 25,
                      )
                    : const Icon(
                        Icons.circle_outlined,
                        key: ValueKey('idle'),
                        color: AppColors.textSecondary,
                        size: 23,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsPanel extends ConsumerWidget {
  const _SettingsPanel({required this.child, required this.padding});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appearance = ref.watch(appearanceControllerProvider);
    return LiquidGlass(
      borderRadius: 22,
      blur: 18,
      tint: appearance.accent,
      child: Container(width: double.infinity, padding: padding, child: child),
    );
  }
}

class _StoragePanel extends ConsumerStatefulWidget {
  const _StoragePanel({required this.databasePath});

  final String databasePath;

  @override
  ConsumerState<_StoragePanel> createState() => _StoragePanelState();
}

class _StoragePanelState extends ConsumerState<_StoragePanel> {
  String _acoustIdKey = '';
  bool _backupBusy = false;
  List<File> _automaticBackups = const [];
  PendingLibraryRestoreStatus? _pendingRestore;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_loadRecognitionSettings);
    Future<void>.microtask(_refreshAutomaticBackups);
  }

  LibraryBackupService get _backupService =>
      ref.read(libraryBackupServiceProvider);

  Future<void> _refreshAutomaticBackups() async {
    try {
      final results = await Future.wait<Object?>([
        _backupService.automaticBackups(),
        _backupService.pendingRestoreStatus(),
      ]);
      if (mounted) {
        setState(() {
          _automaticBackups = results[0] as List<File>;
          _pendingRestore = results[1] as PendingLibraryRestoreStatus?;
        });
      }
    } catch (_) {
      // Automatic backup status is supplementary. Manual export and restore
      // remain available even when this summary cannot be read.
    }
  }

  Future<void> _cancelPendingRestore() async {
    if (_backupBusy) return;
    setState(() => _backupBusy = true);
    try {
      await _backupService.discardPendingRestore();
      if (!mounted) return;
      setState(() => _pendingRestore = null);
      showLatestSnackBar(
        context,
        SnackBar(content: Text(context.tr('恢复任务已取消，当前曲库未被修改。'))),
      );
    } on Object catch (error) {
      debugPrint('Sona could not discard the pending restore: $error');
      if (!mounted) return;
      showLatestSnackBar(
        context,
        SnackBar(content: Text(context.tr('取消恢复任务失败，请稍后重试。'))),
      );
    } finally {
      if (mounted) setState(() => _backupBusy = false);
    }
  }

  Future<void> _loadRecognitionSettings() async {
    final key = await ref
        .read(libraryControllerProvider.notifier)
        .getAcoustIdClientKey();
    if (mounted) setState(() => _acoustIdKey = key);
  }

  Future<void> _configureRecognition() async {
    final controller = TextEditingController(text: _acoustIdKey);
    final key = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('配置免费音频声纹')),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr(
                  '在 acoustid.org 注册一个非商业应用即可免费获得 Application API Key。'
                  '这里只保存应用 Key，不需要账户密码。',
                ),
              ),
              const SizedBox(height: 8),
              const SelectableText(
                'https://acoustid.org/new-application',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'AcoustID Application API Key',
                  hintText: context.tr('例如：xxxxxxxxxxx'),
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (value) => Navigator.pop(dialogContext, value),
              ),
            ],
          ),
        ),
        actions: [
          if (_acoustIdKey.isNotEmpty)
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, ''),
              child: Text(context.tr('清除 Key')),
            ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(context.tr('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: Text(context.tr('保存')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (key == null) return;
    final normalized = key.trim();
    if (normalized.isNotEmpty &&
        !RegExp(r'^[A-Za-z0-9_-]{6,80}$').hasMatch(normalized)) {
      if (!mounted) return;
      showLatestSnackBar(
        context,
        SnackBar(content: Text(context.tr('这个 Application API Key 格式不正确。'))),
      );
      return;
    }
    await ref
        .read(libraryControllerProvider.notifier)
        .setAcoustIdClientKey(normalized);
    if (!mounted) return;
    setState(() => _acoustIdKey = normalized);
    showLatestSnackBar(
      context,
      SnackBar(
        content: Text(context.tr(normalized.isEmpty ? '已关闭声纹联网查询' : '音频声纹已启用')),
      ),
    );
  }

  String _backupFileName() {
    final stamp = DateTime.now()
        .toUtc()
        .toIso8601String()
        .replaceAll(RegExp(r'[^0-9]'), '')
        .substring(0, 14);
    return 'Sona-library-$stamp.sonabackup';
  }

  Future<void> _exportCompleteBackup() async {
    if (_backupBusy) return;
    setState(() => _backupBusy = true);
    try {
      late final LibraryBackupManifest manifest;
      late final String displayName;
      if (Platform.isAndroid) {
        final result = await _backupService.exportBackupWithSystemPicker(
          suggestedFileName: _backupFileName(),
        );
        if (result == null) return;
        manifest = result.manifest;
        displayName = result.displayName;
      } else {
        final directory = await FilePicker.getDirectoryPath(
          dialogTitle: context.tr('选择完整备份保存位置'),
        );
        if (directory == null) return;
        final destination = path_util.join(directory, _backupFileName());
        final result = await _backupService.createBackup(
          destinationPath: destination,
        );
        manifest = result.manifest;
        displayName = result.path;
      }
      if (!mounted) return;
      await _showBackupResult(manifest, displayName);
    } on LibraryBackupException catch (error) {
      debugPrint('Sona complete backup export failed: ${error.message}');
      if (!mounted) return;
      showLatestSnackBar(
        context,
        SnackBar(content: Text(context.tr('创建完整备份失败，请稍后重试。'))),
      );
    } catch (_) {
      if (!mounted) return;
      showLatestSnackBar(
        context,
        SnackBar(content: Text(context.tr('创建完整备份失败，请稍后重试。'))),
      );
    } finally {
      if (mounted) setState(() => _backupBusy = false);
    }
  }

  Future<void> _showBackupResult(
    LibraryBackupManifest manifest,
    String displayName,
  ) {
    final missing = manifest.missingReferences.length;
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr(missing == 0 ? '完整备份已创建' : '备份已创建，但有文件缺失')),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SelectableText(
            '${context.tr('文件')}：$displayName\n'
            '${context.tr('条目')}：${manifest.entries.length}\n'
            '${context.tr('大小')}：${_readableBytes(manifest.totalBytes)}'
            '${missing == 0 ? '' : '\n${context.tr('缺失引用')}：$missing'}\n\n'
            '${context.tr('请将外部备份妥善保管；它可能包含歌曲、MV、封面和本地设置，且当前未加密。')}',
            style: const TextStyle(height: 1.5),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(context.tr('完成')),
          ),
        ],
      ),
    );
  }

  Future<void> _restoreCompleteBackup() async {
    if (_backupBusy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('从完整备份恢复？')),
        content: Text(
          context.tr('Sona 会先完整校验备份，在下次冷启动时替换曲库数据库并保留一份恢复前数据库。当前播放将在退出时停止。'),
          style: const TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.tr('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.tr('选择备份并校验')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _backupBusy = true);
    try {
      LibraryRestorePreparation? preparation;
      if (Platform.isAndroid) {
        preparation = await _backupService
            .pickAndStageRestoreWithSystemPicker();
      } else {
        final selection = await FilePicker.pickFile(
          dialogTitle: context.tr('选择 Sona 完整备份'),
          type: FileType.custom,
          allowedExtensions: const ['sonabackup'],
        );
        final selectedPath = selection?.path;
        if (selectedPath != null) {
          preparation = await _backupService.stageRestore(selectedPath);
        }
      }
      if (preparation == null || !mounted) return;
      await _showRestoreReady(preparation);
    } on LibraryBackupException catch (error) {
      debugPrint('Sona restore staging failed: ${error.message}');
      if (!mounted) return;
      showLatestSnackBar(
        context,
        SnackBar(content: Text(context.tr('备份校验或恢复准备失败。当前曲库没有被修改。'))),
      );
    } catch (_) {
      if (!mounted) return;
      showLatestSnackBar(
        context,
        SnackBar(content: Text(context.tr('备份校验或恢复准备失败。当前曲库没有被修改。'))),
      );
    } finally {
      if (mounted) setState(() => _backupBusy = false);
    }
  }

  Future<void> _restoreLatestAutomaticBackup() async {
    if (_backupBusy || _automaticBackups.isEmpty) return;
    final latest = _automaticBackups.first;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('恢复当前设备快照？')),
        content: Text(
          context.tr(
            '这会恢复最近一次自动保存的曲库数据库和托管图片。歌曲与 MV 不会从快照复制；只有当前设备上仍存在的媒体路径会被保留。Sona 会先完整校验，并在下次冷启动时应用。',
          ),
          style: const TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.tr('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.tr('校验并恢复')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _backupBusy = true);
    try {
      final preparation = await _backupService.stageAutomaticRestore(
        latest.path,
      );
      if (!mounted) return;
      await _showRestoreReady(preparation);
    } on LibraryBackupException catch (error) {
      debugPrint('Sona automatic snapshot restore failed: ${error.message}');
      if (!mounted) return;
      showLatestSnackBar(
        context,
        SnackBar(content: Text(context.tr('自动快照损坏或所需本机媒体已不存在。当前曲库没有被修改。'))),
      );
    } catch (error) {
      debugPrint('Sona automatic snapshot restore failed: $error');
      if (!mounted) return;
      showLatestSnackBar(
        context,
        SnackBar(content: Text(context.tr('自动快照损坏或所需本机媒体已不存在。当前曲库没有被修改。'))),
      );
    } finally {
      if (mounted) setState(() => _backupBusy = false);
    }
  }

  Future<void> _showRestoreReady(LibraryRestorePreparation preparation) async {
    final manifest = preparation.manifest;
    final action = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('备份校验通过')),
        content: Text(
          '${context.tr('备份版本')}：${manifest.appVersion}\n'
          '${context.tr('条目')}：${manifest.entries.length}\n'
          '${context.tr('大小')}：${_readableBytes(manifest.totalBytes)}\n\n'
          '${context.tr('恢复已安全排队。退出并重新打开 Sona 后生效。')}',
          style: const TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'discard'),
            child: Text(context.tr('取消此次恢复')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'later'),
            child: Text(context.tr('稍后退出')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, 'exit'),
            child: Text(context.tr('立即退出 Sona')),
          ),
        ],
      ),
    );
    if (action == 'discard') {
      try {
        await _backupService.discardPendingRestore();
        if (!mounted) return;
        showLatestSnackBar(
          context,
          SnackBar(content: Text(context.tr('已取消此次恢复。'))),
        );
      } on Object catch (error) {
        debugPrint('Sona could not discard the staged restore: $error');
        if (!mounted) return;
        showLatestSnackBar(
          context,
          SnackBar(content: Text(context.tr('取消恢复任务失败，请稍后重试。'))),
        );
      }
    } else if (action == 'exit') {
      if (Platform.isWindows) {
        await windowManager.close();
      } else {
        await SystemNavigator.pop();
      }
    }
  }

  String _readableBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
    return '${(mb / 1024).toStringAsFixed(2)} GB';
  }

  String _automaticBackupSummary(BuildContext context) {
    if (_automaticBackups.isEmpty) {
      return context.tr('轻量自动快照已开启；保存数据库和封面，不重复复制歌曲与 MV，默认保留最新 3 份。');
    }
    final latest = _automaticBackups.first;
    final modified = latest.lastModifiedSync().toLocal();
    final stamp =
        '${modified.year.toString().padLeft(4, '0')}-'
        '${modified.month.toString().padLeft(2, '0')}-'
        '${modified.day.toString().padLeft(2, '0')} '
        '${modified.hour.toString().padLeft(2, '0')}:'
        '${modified.minute.toString().padLeft(2, '0')}';
    return '${context.tr('自动备份')} ${_automaticBackups.length}/3 · '
        '${context.tr('最近')} $stamp · ${_readableBytes(latest.lengthSync())}';
  }

  @override
  Widget build(BuildContext context) {
    return _SettingsPanel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.lavender.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(
                  Icons.storage_rounded,
                  color: AppColors.lavender,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('此设备数据库'),
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 7),
                    SelectableText(
                      widget.databasePath.isEmpty
                          ? context.tr('正在读取数据库位置…')
                          : widget.databasePath,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const _Badge('SQLite'),
            ],
          ),
          const Divider(height: 34),
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.11),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(
                  Icons.fingerprint_rounded,
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('音频声纹识别'),
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _acoustIdKey.isEmpty
                          ? context.tr('未配置时仍可使用标签、文件名和 MusicBrainz 后备校准')
                          : context.tr('AcoustID 已配置 · 声纹不命中时自动回退公开曲库'),
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: _configureRecognition,
                icon: Icon(
                  _acoustIdKey.isEmpty
                      ? Icons.add_link_rounded
                      : Icons.check_circle_rounded,
                  size: 18,
                ),
                label: Text(
                  context.tr(_acoustIdKey.isEmpty ? '配置免费 Key' : '已启用'),
                ),
              ),
            ],
          ),
          const Divider(height: 34),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(
                  Icons.cloud_done_outlined,
                  color: AppColors.success,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('完整备份与恢复'),
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      context.tr('数据库、歌曲、MV、封面、自定义壁纸和本地设置会放进同一个可校验备份。'),
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _automaticBackupSummary(context),
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      context.tr('内部自动备份会随卸载或清除数据一起删除；跨设备或换签名前请导出完整备份到外部位置。'),
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_pendingRestore case final pending?) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: (pending.hasFailed ? Colors.orange : AppColors.accent)
                    .withValues(alpha: 0.11),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: (pending.hasFailed ? Colors.orange : AppColors.accent)
                      .withValues(alpha: 0.28),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    pending.hasFailed
                        ? Icons.warning_amber_rounded
                        : Icons.pending_actions_rounded,
                    color: pending.hasFailed
                        ? Colors.orange.shade800
                        : AppColors.accent,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.tr(
                            pending.hasFailed ? '上次恢复未能安全应用' : '有待处理的恢复',
                          ),
                          style: const TextStyle(
                            color: AppColors.ink,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          context.tr(
                            pending.hasFailed
                                ? 'Sona 已保留原曲库，下一次启动会再次尝试。你也可以取消这个恢复任务。'
                                : '恢复已排队，退出并重新打开 Sona 后应用。你可以在此取消。',
                          ),
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _backupBusy ? null : _cancelPendingRestore,
                    child: Text(context.tr('取消此次恢复')),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.tonalIcon(
                onPressed: _backupBusy ? null : _exportCompleteBackup,
                icon: _backupBusy
                    ? const SizedBox.square(
                        dimension: 17,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_alt_rounded, size: 19),
                label: Text(context.tr(_backupBusy ? '处理中…' : '导出完整备份')),
              ),
              OutlinedButton.icon(
                onPressed: _backupBusy ? null : _restoreCompleteBackup,
                icon: const Icon(
                  Icons.settings_backup_restore_rounded,
                  size: 19,
                ),
                label: Text(context.tr('从备份恢复')),
              ),
              OutlinedButton.icon(
                onPressed: _backupBusy || _automaticBackups.isEmpty
                    ? null
                    : _restoreLatestAutomaticBackup,
                icon: const Icon(Icons.history_rounded, size: 19),
                label: Text(context.tr('恢复当前设备快照')),
              ),
              IconButton.filledTonal(
                tooltip: context.tr('刷新自动备份状态'),
                onPressed: _backupBusy ? null : _refreshAutomaticBackups,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AboutPanel extends StatefulWidget {
  const _AboutPanel();

  @override
  State<_AboutPanel> createState() => _AboutPanelState();
}

class _AboutPanelState extends State<_AboutPanel> {
  static final Uri _website = Uri.parse('https://sona.yanbaoli.me/');
  static final Uri _repository = Uri.parse(
    'https://github.com/Owl-Lee/Sona-Player',
  );

  final _updates = ReleaseUpdateService();
  String _version = '—';
  String _buildNumber = '—';
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
  }

  Future<void> _loadPackageInfo() async {
    try {
      final package = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _version = package.version;
        _buildNumber = package.buildNumber;
      });
    } catch (_) {
      // The version remains an honest unknown marker on unsupported hosts.
    }
  }

  Future<void> _open(Uri uri) async {
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      showLatestSnackBar(
        context,
        SnackBar(content: Text(context.tr('无法打开链接，请稍后重试。'))),
      );
    }
  }

  Future<void> _checkForUpdates() async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      final current = _version == '—' ? '0.0.0' : _version;
      final update = await _updates.check(currentVersion: current);
      if (!mounted) return;
      if (update == null) {
        showLatestSnackBar(
          context,
          SnackBar(content: Text(context.tr('当前已是最新版本。'))),
        );
        return;
      }
      await _showUpdate(update);
    } catch (_) {
      if (!mounted) return;
      showLatestSnackBar(
        context,
        SnackBar(content: Text(context.tr('暂时无法检查更新，请确认网络后重试。'))),
      );
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _showUpdate(ReleaseUpdate update) async {
    final asset = update.assetForPlatform(
      windows: Platform.isWindows,
      android: Platform.isAndroid,
    );
    final notes = update.notes.trim();
    final displayNotes = notes.length > 1200
        ? '${notes.substring(0, 1200).trimRight()}…'
        : notes;
    final destination = asset?.downloadUrl ?? update.releasePage;
    final shouldOpen = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${context.tr('发现新版本')} ${update.version}'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${context.tr('当前版本')} $_version  →  ${update.version}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                if (displayNotes.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  SelectableText(
                    displayNotes,
                    style: const TextStyle(height: 1.45),
                  ),
                ],
                const SizedBox(height: 14),
                Text(
                  asset == null
                      ? context.tr('将打开发布页面，由你选择安装包。')
                      : context.tr('将打开当前设备对应的安装包下载。'),
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.tr('稍后再说')),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: Text(context.tr(asset == null ? '查看发布页' : '打开下载')),
          ),
        ],
      ),
    );
    if (shouldOpen == true && mounted) await _open(destination);
  }

  @override
  Widget build(BuildContext context) {
    return _SettingsPanel(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const CircleAvatar(
                radius: 25,
                backgroundColor: AppColors.accent,
                child: Icon(
                  Icons.graphic_eq_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Sona',
                      style: TextStyle(
                        color: AppColors.ink,
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${context.tr('版本')} $_version '
                      '(${context.tr('构建')} $_buildNumber) · Android / Windows',
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              const _Badge('Preview'),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.tonalIcon(
                onPressed: _checking ? null : _checkForUpdates,
                icon: _checking
                    ? const SizedBox.square(
                        dimension: 17,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.system_update_alt_rounded, size: 19),
                label: Text(context.tr(_checking ? '正在检查…' : '检查更新')),
              ),
              OutlinedButton.icon(
                onPressed: () => _open(_website),
                icon: const Icon(Icons.language_rounded, size: 19),
                label: Text(context.tr('产品网站')),
              ),
              OutlinedButton.icon(
                onPressed: () => _open(_repository),
                icon: const Icon(Icons.code_rounded, size: 19),
                label: const Text('GitHub'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.outline),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
