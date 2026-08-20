import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/sona_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/latest_snack_bar.dart';
import '../../../core/widgets/liquid_glass.dart';
import '../../account/presentation/account_sync_card.dart';
import '../../library/application/library_controller.dart';
import '../application/appearance_controller.dart';
import '../application/language_controller.dart';
import 'widgets/appearance_picker.dart';

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
                : appearance.preset.name,
            language: language,
            onOpen: _open,
          ),
          _SettingsSection.appearance => _SettingsDetailPage(
            title: context.tr('外观与播放器'),
            foreground: foreground,
            lightForeground: lightForeground,
            onBack: _back,
            child: const _SettingsPanel(
              padding: EdgeInsets.all(16),
              child: AppearancePicker(),
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
                        subtitle: 'Sona 0.4.26',
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

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_loadRecognitionSettings);
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
        title: const Text('配置免费音频声纹'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '在 acoustid.org 注册一个非商业应用即可免费获得 Application API Key。'
                '这里只保存应用 Key，不需要账户密码。',
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
                decoration: const InputDecoration(
                  labelText: 'AcoustID Application API Key',
                  hintText: '例如：xxxxxxxxxxx',
                  border: OutlineInputBorder(),
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
              child: const Text('清除 Key'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('保存'),
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
        const SnackBar(content: Text('这个 Application API Key 格式不正确。')),
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
      SnackBar(content: Text(normalized.isEmpty ? '已关闭声纹联网查询' : '音频声纹已启用')),
    );
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
        ],
      ),
    );
  }
}

class _AboutPanel extends StatelessWidget {
  const _AboutPanel();

  @override
  Widget build(BuildContext context) {
    return _SettingsPanel(
      padding: const EdgeInsets.all(20),
      child: Row(
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
                  context.tr('版本 0.4.26 · Android / Windows'),
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const _Badge('Beta'),
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
