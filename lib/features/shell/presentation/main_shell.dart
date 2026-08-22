import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../../core/localization/sona_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/liquid_glass.dart';
import '../../account/application/account_controller.dart';
import '../../library/application/library_controller.dart';
import '../../library/data/library_database.dart';
import '../../library/presentation/pages/home_page.dart';
import '../../library/presentation/pages/library_page.dart';
import '../../library/presentation/pages/playlists_page.dart';
import '../../library/presentation/pages/rankings_page.dart';
import '../../player/application/video_playback_request.dart';
import '../../player/presentation/now_playing_bar.dart';
import '../../player/presentation/now_playing_page.dart';
import '../../settings/presentation/settings_page.dart';
import '../../settings/application/appearance_controller.dart';
import '../../settings/presentation/widgets/appearance_backdrop.dart';
import '../../settings/presentation/widgets/appearance_picker.dart';
import '../application/shell_navigation.dart';

@visibleForTesting
bool shouldUseCompactDesktopSidebar(double windowHeight) => windowHeight < 700;

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  var _playlistsExpanded = true;
  Set<int>? _pinnedPlaylistIds;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(() async {
      final raw = await ref
          .read(libraryDatabaseProvider)
          .getSetting('sidebar.pinned_playlists');
      if (!mounted || raw == null || raw.isEmpty) return;
      setState(
        () => _pinnedPlaylistIds = raw
            .split(',')
            .map(int.tryParse)
            .whereType<int>()
            .toSet(),
      );
    });
  }

  static const _pages = <Widget>[
    HomePage(),
    LibraryPage(),
    PlaylistsPage(),
    SettingsPage(),
    RankingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    final library = ref.watch(libraryControllerProvider);
    final appearance = ref.watch(appearanceControllerProvider);
    final selectedIndex = ref.watch(shellDestinationProvider);
    final libraryFilter = ref.watch(libraryFilterProvider);
    final selectionActive = ref.watch(librarySelectionActiveProvider);
    final settingsDetailOpen = ref.watch(settingsDetailOpenProvider);

    ref.listen<VideoPlaybackRequest?>(videoPlaybackRequestProvider, (
      previous,
      request,
    ) {
      if (request == null) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(videoPlaybackRequestProvider.notifier).state = null;
        Navigator.of(context).push(
          PageRouteBuilder<void>(
            transitionDuration: const Duration(milliseconds: 150),
            reverseTransitionDuration: const Duration(milliseconds: 120),
            pageBuilder: (_, animation, _) =>
                NowPlayingPage(autoplayRequest: request),
            // A full-screen fade forces every liquid-glass surface into an
            // extra composited opacity layer. A very small slide keeps the
            // navigation cue while staying on the cheaper transform path.
            transitionsBuilder: (_, animation, _, child) => SlideTransition(
              position:
                  Tween<Offset>(
                    begin: const Offset(0, 0.012),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                    ),
                  ),
              child: child,
            ),
          ),
        );
      });
    });

    // Sidebar entries are primary destinations, not browser-history actions.
    // Reset detail state even when the user taps the already selected item.
    void goToPrimaryDestination(int value) {
      ref.read(settingsDetailOpenProvider.notifier).state = false;
      ref.read(activePlaylistProvider.notifier).state = null;
      if (value == 1) {
        ref.read(libraryFilterProvider.notifier).state = LibraryFilter.all;
      }
      ref.read(shellDestinationProvider.notifier).state = value;
    }

    void goToLibraryFilter(LibraryFilter filter) {
      ref.read(settingsDetailOpenProvider.notifier).state = false;
      ref.read(activePlaylistProvider.notifier).state = null;
      ref.read(libraryFilterProvider.notifier).state = filter;
      ref.read(shellDestinationProvider.notifier).state = 1;
    }

    final useLightStatusIcons =
        !appearance.usesCustom && appearance.preset.prefersLightHomeForeground;
    final overlayStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: useLightStatusIcons
          ? Brightness.light
          : Brightness.dark,
      statusBarBrightness: useLightStatusIcons
          ? Brightness.dark
          : Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.dark,
      systemNavigationBarDividerColor: Colors.transparent,
      systemStatusBarContrastEnforced: false,
      systemNavigationBarContrastEnforced: false,
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final desktop = constraints.maxWidth >= 920;
          final scaffold = Scaffold(
            backgroundColor: Colors.transparent,
            body: Stack(
              children: [
                Positioned.fill(
                  child: AppearanceBackdrop(
                    appearance: appearance,
                    // Rankings is content-heavy too. Giving it the same
                    // vivid backdrop keeps bright themes from washing white.
                    vividContent: selectedIndex <= 4,
                  ),
                ),
                if (desktop)
                  Column(
                    children: [
                      if (defaultTargetPlatform == TargetPlatform.windows)
                        _DesktopWindowBar(appearance: appearance),
                      Expanded(
                        child: Row(
                          children: [
                            _DesktopSidebar(
                              appearance: appearance,
                              library: library,
                              selectedIndex: selectedIndex,
                              libraryFilter: libraryFilter,
                              onSelected: goToPrimaryDestination,
                              onFavorites: () =>
                                  goToLibraryFilter(LibraryFilter.favorites),
                              onRecent: () =>
                                  goToLibraryFilter(LibraryFilter.recent),
                              onVideos: () =>
                                  goToLibraryFilter(LibraryFilter.videos),
                              onRankings: () => goToPrimaryDestination(4),
                              onPlaylist: (playlistId) {
                                ref
                                        .read(activePlaylistProvider.notifier)
                                        .state =
                                    playlistId;
                                ref
                                        .read(shellDestinationProvider.notifier)
                                        .state =
                                    2;
                              },
                              playlistsExpanded: _playlistsExpanded,
                              pinnedPlaylistIds: _pinnedPlaylistIds,
                              onTogglePlaylists: () => setState(
                                () => _playlistsExpanded = !_playlistsExpanded,
                              ),
                              onConfigurePlaylists: () =>
                                  _configurePinnedPlaylists(library),
                              onAccount: () {
                                ref
                                        .read(activePlaylistProvider.notifier)
                                        .state =
                                    null;
                                ref
                                        .read(shellDestinationProvider.notifier)
                                        .state =
                                    3;
                                ref
                                    .read(
                                      settingsAccountRequestProvider.notifier,
                                    )
                                    .state++;
                              },
                            ),
                            Expanded(
                              child: Column(
                                children: [
                                  Expanded(
                                    child: _AnimatedPageStack(
                                      index: selectedIndex,
                                      children: _pages,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  const NowPlayingBar(compact: false),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                else
                  Column(
                    children: [
                      Expanded(
                        child: _AnimatedPageStack(
                          index: selectedIndex,
                          children: _pages,
                        ),
                      ),
                      // Keep a real strip of wallpaper between page surfaces
                      // and the compact player. Putting this spacing inside an
                      // individual page lets rounded translucent cards visually
                      // consume it, while a shell-level gap stays consistent on
                      // every mobile destination.
                      const SizedBox(height: 8),
                      const NowPlayingBar(compact: true),
                      _MobileBottomNavigation(
                        selectedIndex: selectedIndex > 3 ? 0 : selectedIndex,
                        accent: appearance.accent,
                        onSelected: goToPrimaryDestination,
                      ),
                      if (constraints.maxWidth < 0)
                        NavigationBar(
                          height: 56,
                          selectedIndex: selectedIndex > 3 ? 0 : selectedIndex,
                          onDestinationSelected: goToPrimaryDestination,
                          backgroundColor: Color.alphaBlend(
                            appearance.accent.withValues(alpha: 0.10),
                            Colors.white,
                          ),
                          indicatorColor: appearance.accent.withValues(
                            alpha: 0.23,
                          ),
                          labelBehavior:
                              NavigationDestinationLabelBehavior.alwaysShow,
                          labelTextStyle: const WidgetStatePropertyAll(
                            TextStyle(fontSize: 11, height: 1.05),
                          ),
                          destinations: [
                            NavigationDestination(
                              icon: const Icon(Icons.home_outlined),
                              selectedIcon: const Icon(Icons.home_rounded),
                              label: context.tr('首页'),
                            ),
                            NavigationDestination(
                              icon: const Icon(Icons.library_music_outlined),
                              selectedIcon: const Icon(
                                Icons.library_music_rounded,
                              ),
                              label: context.tr('曲库'),
                            ),
                            NavigationDestination(
                              icon: const Icon(Icons.queue_music_outlined),
                              selectedIcon: const Icon(
                                Icons.queue_music_rounded,
                              ),
                              label: context.tr('歌单'),
                            ),
                            NavigationDestination(
                              icon: const Icon(Icons.settings_outlined),
                              selectedIcon: const Icon(Icons.settings_rounded),
                              label: context.tr('设置'),
                            ),
                          ],
                        ),
                    ],
                  ),
                if (library.isImporting)
                  Positioned(
                    left: desktop ? 264 : 16,
                    right: 16,
                    top: 14,
                    child: _ImportProgress(state: library),
                  ),
              ],
            ),
          );
          if (desktop) return scaffold;
          return PopScope(
            canPop: canExitMobileShell(
              destination: selectedIndex,
              selectionActive: selectionActive,
            ),
            onPopInvokedWithResult: (didPop, _) {
              if (didPop || selectionActive) return;
              if (selectedIndex == 3 && settingsDetailOpen) {
                ref.read(settingsDetailOpenProvider.notifier).state = false;
                return;
              }
              if (selectedIndex == 0) return;
              ref.read(shellDestinationProvider.notifier).state = 0;
            },
            child: scaffold,
          );
        },
      ),
    );
  }

  Future<void> _configurePinnedPlaylists(LibraryState library) async {
    final selected = Set<int>.from(
      _pinnedPlaylistIds ?? library.playlists.take(5).map((item) => item.id),
    );
    final result = await showDialog<Set<int>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(context.tr('选择常用歌单')),
          content: SizedBox(
            width: 420,
            child: ListView(
              shrinkWrap: true,
              children: library.playlists
                  .map(
                    (playlist) => CheckboxListTile(
                      value: selected.contains(playlist.id),
                      title: Text(playlist.name),
                      subtitle: Text(
                        '${playlist.trackCount}${context.tr('首')}',
                      ),
                      onChanged: (_) => update(
                        () => selected.contains(playlist.id)
                            ? selected.remove(playlist.id)
                            : selected.add(playlist.id),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.tr('取消')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, selected),
              child: Text(context.tr('保存')),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    setState(() => _pinnedPlaylistIds = result);
    await ref
        .read(libraryDatabaseProvider)
        .setSetting('sidebar.pinned_playlists', result.join(','));
  }
}

class _AnimatedPageStack extends StatefulWidget {
  const _AnimatedPageStack({required this.index, required this.children});

  final int index;
  final List<Widget> children;

  @override
  State<_AnimatedPageStack> createState() => _AnimatedPageStackState();
}

class _AnimatedPageStackState extends State<_AnimatedPageStack>
    with SingleTickerProviderStateMixin {
  late int _currentIndex = widget.index;
  var _direction = 1.0;
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 160),
  )..value = 1;

  @override
  void didUpdateWidget(covariant _AnimatedPageStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_currentIndex == widget.index) return;
    _direction = widget.index > _currentIndex ? 1 : -1;
    _currentIndex = widget.index;
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final animationsDisabled =
            MediaQuery.maybeOf(context)?.disableAnimations ?? false;
        final progress = animationsDisabled
            ? 1.0
            : Curves.easeOutCubic.transform(_controller.value);
        // Rendering outgoing and incoming pages together doubles the cost of
        // BackdropFilter/LiquidGlass. A short one-page entrance still gives
        // navigation feedback without forcing two full-screen blur passes.
        return _SoftPageLayer(
          visible: true,
          interactive: progress > 0.72,
          horizontalOffset: _direction * 12 * (1 - progress),
          child: widget.children[_currentIndex],
        );
      },
    );
  }
}

class _SoftPageLayer extends StatelessWidget {
  const _SoftPageLayer({
    required this.visible,
    required this.interactive,
    required this.horizontalOffset,
    required this.child,
  });

  final bool visible;
  final bool interactive;
  final double horizontalOffset;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Offstage(
      offstage: !visible,
      child: TickerMode(
        enabled: visible,
        child: IgnorePointer(
          ignoring: !interactive,
          child: Transform.translate(
            offset: Offset(horizontalOffset, 0),
            // Opacity over an entire page creates a saveLayer and makes all
            // of its backdrop filters repaint together. Keep the subtle slide
            // but render the page directly.
            child: RepaintBoundary(child: child),
          ),
        ),
      ),
    );
  }
}

class _MobileBottomNavigation extends StatelessWidget {
  const _MobileBottomNavigation({
    required this.selectedIndex,
    required this.accent,
    required this.onSelected,
  });

  final int selectedIndex;
  final Color accent;
  final ValueChanged<int> onSelected;

  static const _items = <({String label, IconData icon, IconData selected})>[
    (label: '首页', icon: Icons.home_outlined, selected: Icons.home_rounded),
    (
      label: '曲库',
      icon: Icons.library_music_outlined,
      selected: Icons.library_music_rounded,
    ),
    (
      label: '歌单',
      icon: Icons.queue_music_outlined,
      selected: Icons.queue_music_rounded,
    ),
    (
      label: '设置',
      icon: Icons.settings_outlined,
      selected: Icons.settings_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
        child: SizedBox(
          height: 50,
          child: Material(
            color: Color.alphaBlend(
              accent.withValues(alpha: 0.08),
              Colors.white.withValues(alpha: 0.88),
            ),
            borderRadius: BorderRadius.circular(18),
            clipBehavior: Clip.antiAlias,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.outline),
              ),
              child: Row(
                children: [
                  for (var index = 0; index < _items.length; index++)
                    Expanded(
                      child: _MobileBottomNavigationItem(
                        item: _items[index],
                        selected: index == selectedIndex,
                        accent: accent,
                        onTap: () => onSelected(index),
                      ),
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

class _MobileBottomNavigationItem extends StatelessWidget {
  const _MobileBottomNavigationItem({
    required this.item,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final ({String label, IconData icon, IconData selected}) item;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // The selected dot is always a translucent tint on a light surface.
    // Keep text/icons dark even when the underlying theme accent is dark.
    final foreground = selected ? AppColors.ink : AppColors.textSecondary;
    return Semantics(
      selected: selected,
      button: true,
      label: context.tr(item.label),
      child: InkWell(
        onTap: onTap,
        splashFactory: NoSplash.splashFactory,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        focusColor: Colors.transparent,
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 5),
          padding: EdgeInsets.symmetric(horizontal: selected ? 4 : 0),
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: 0.07)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutBack,
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? accent.withValues(alpha: 0.22)
                      : Colors.transparent,
                  shape: BoxShape.circle,
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  switchInCurve: Curves.easeOutBack,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) => ScaleTransition(
                    scale: animation,
                    child: FadeTransition(opacity: animation, child: child),
                  ),
                  child: Icon(
                    selected ? item.selected : item.icon,
                    key: ValueKey(selected),
                    size: selected ? 22 : 21,
                    color: foreground,
                  ),
                ),
              ),
              const SizedBox(width: 5),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                style: TextStyle(
                  color: foreground,
                  fontSize: selected ? 12.3 : 12,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
                child: Text(context.tr(item.label)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DesktopWindowBar extends StatelessWidget {
  const _DesktopWindowBar({required this.appearance});

  final AppearanceState appearance;

  @override
  Widget build(BuildContext context) {
    // A wide Android screen (tablet, landscape, desktop mode) may use the
    // desktop content layout, but it must never receive Windows caption
    // controls. window_manager is initialized only on Windows as well.
    if (defaultTargetPlatform != TargetPlatform.windows) {
      return const SizedBox.shrink();
    }
    // The native caption buttons inherit this brightness.  Base this on the
    // actual theme colour instead of a per-preset foreground flag: a bright
    // wheat / ice theme gets a readable *tinted* light chrome, while a deep
    // theme keeps white controls over a version of its own accent colour.
    final lightChrome = appearance.accent.computeLuminance() > 0.27;
    final foreground = lightChrome
        ? Color.lerp(AppColors.textPrimary, appearance.accent, 0.16)!
        : Colors.white;
    final barColor = lightChrome
        ? Color.alphaBlend(
            appearance.accent.withValues(alpha: 0.28),
            Colors.white,
          ).withValues(alpha: 0.88)
        : Color.alphaBlend(
            appearance.accent.withValues(alpha: 0.24),
            const Color(0xFF0A1020),
          ).withValues(alpha: 0.88);
    final borderColor = lightChrome
        ? Colors.white.withValues(alpha: 0.78)
        : Colors.white.withValues(alpha: 0.28);

    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: barColor,
        border: Border(bottom: BorderSide(color: borderColor)),
      ),
      child: WindowCaption(
        backgroundColor: Colors.transparent,
        brightness: lightChrome ? Brightness.light : Brightness.dark,
        title: Row(
          children: [
            Image.asset(
              'assets/branding/sona_mark_cutout.png',
              width: 20,
              height: 20,
            ),
            const SizedBox(width: 8),
            Text(
              'Sona',
              style: TextStyle(
                color: foreground,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopSidebar extends ConsumerStatefulWidget {
  const _DesktopSidebar({
    required this.appearance,
    required this.library,
    required this.selectedIndex,
    required this.libraryFilter,
    required this.onSelected,
    required this.onFavorites,
    required this.onRecent,
    required this.onVideos,
    required this.onRankings,
    required this.onPlaylist,
    required this.playlistsExpanded,
    required this.pinnedPlaylistIds,
    required this.onTogglePlaylists,
    required this.onConfigurePlaylists,
    required this.onAccount,
  });

  final AppearanceState appearance;
  final LibraryState library;
  final int selectedIndex;
  final LibraryFilter libraryFilter;
  final ValueChanged<int> onSelected;
  final VoidCallback onFavorites;
  final VoidCallback onRecent;
  final VoidCallback onVideos;
  final VoidCallback onRankings;
  final ValueChanged<int> onPlaylist;
  final bool playlistsExpanded;
  final Set<int>? pinnedPlaylistIds;
  final VoidCallback onTogglePlaylists;
  final VoidCallback onConfigurePlaylists;
  final VoidCallback onAccount;

  @override
  ConsumerState<_DesktopSidebar> createState() => _DesktopSidebarState();
}

class _DesktopSidebarState extends ConsumerState<_DesktopSidebar> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appearance = widget.appearance;
    final library = widget.library;
    final selectedIndex = widget.selectedIndex;
    final libraryFilter = widget.libraryFilter;
    final onSelected = widget.onSelected;
    final onFavorites = widget.onFavorites;
    final onRecent = widget.onRecent;
    final onVideos = widget.onVideos;
    final onRankings = widget.onRankings;
    final onPlaylist = widget.onPlaylist;
    final playlistsExpanded = widget.playlistsExpanded;
    final pinnedPlaylistIds = widget.pinnedPlaylistIds;
    final onTogglePlaylists = widget.onTogglePlaylists;
    final onConfigurePlaylists = widget.onConfigurePlaylists;
    final onAccount = widget.onAccount;
    final compact = shouldUseCompactDesktopSidebar(
      MediaQuery.sizeOf(context).height,
    );
    final useLightForeground =
        !appearance.usesCustom && appearance.preset.prefersLightHomeForeground;
    final mutedForeground = useLightForeground
        ? Colors.white.withValues(alpha: 0.86)
        : AppColors.textSecondary;
    final account = ref.watch(accountControllerProvider);
    final signedIn = account.user != null;
    final accountName = account.displayName.isNotEmpty
        ? account.displayName
        : account.username.isNotEmpty
        ? account.username
        : context.tr('Sona 用户');
    return SizedBox(
      width: 248,
      child: LiquidGlass(
        borderRadius: 0,
        blur: 24,
        tint: appearance.accent,
        dark: useLightForeground,
        borderWidth: 0.8,
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              compact ? 10 : 16,
              20,
              compact ? 12 : 20,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  // Reserve a dedicated gutter between the navigation
                  // capsules and the scrollbar. Moving the whole scroll view
                  // also moved the capsules, so the thumb could still sit on
                  // top of a selected item on narrow layouts.
                  child: ScrollConfiguration(
                    // Flutter desktop automatically decorates scroll views
                    // with a scrollbar. This sidebar already owns a visible
                    // scrollbar with a reserved gutter, so allowing the
                    // platform decoration as well renders two parallel thumbs.
                    behavior: ScrollConfiguration.of(context)
                        .copyWith(scrollbars: false),
                    child: Scrollbar(
                      controller: _scrollController,
                      thumbVisibility: true,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 22),
                        child: SingleChildScrollView(
                          controller: _scrollController,
                          padding: EdgeInsets.zero,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                child: Text(
                                  context.tr('我的音乐'),
                                  style: TextStyle(
                                    color: mutedForeground,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.1,
                                  ),
                                ),
                              ),
                              SizedBox(height: compact ? 7 : 12),
                              _NavigationItem(
                                accent: appearance.accent,
                                lightForeground: useLightForeground,
                                icon: Icons.home_rounded,
                                label: context.tr('首页'),
                                selected: selectedIndex == 0,
                                onTap: () => onSelected(0),
                              ),
                              _NavigationItem(
                                accent: appearance.accent,
                                lightForeground: useLightForeground,
                                icon: Icons.library_music_rounded,
                                label: context.tr('本地曲库'),
                                selected:
                                    selectedIndex == 1 &&
                                    libraryFilter == LibraryFilter.all,
                                onTap: () => onSelected(1),
                              ),
                              _NavigationItem(
                                accent: appearance.accent,
                                lightForeground: useLightForeground,
                                icon: Icons.queue_music_rounded,
                                label: context.tr('我的歌单'),
                                selected: selectedIndex == 2,
                                onTap: () => onSelected(2),
                              ),
                              _NavigationItem(
                                accent: appearance.accent,
                                lightForeground: useLightForeground,
                                icon: Icons.favorite_rounded,
                                label:
                                    '${context.tr('我的收藏')} · ${library.tracks.where((item) => item.isFavorite).length}',
                                selected:
                                    selectedIndex == 1 &&
                                    libraryFilter == LibraryFilter.favorites,
                                onTap: onFavorites,
                              ),
                              _NavigationItem(
                                accent: appearance.accent,
                                lightForeground: useLightForeground,
                                icon: Icons.history_rounded,
                                label: context.tr('最近播放'),
                                selected:
                                    selectedIndex == 1 &&
                                    libraryFilter == LibraryFilter.recent,
                                onTap: onRecent,
                              ),
                              _NavigationItem(
                                accent: appearance.accent,
                                lightForeground: useLightForeground,
                                icon: Icons.ondemand_video_rounded,
                                label: context.tr('MV 专区'),
                                selected:
                                    selectedIndex == 1 &&
                                    libraryFilter == LibraryFilter.videos,
                                onTap: onVideos,
                              ),
                              _NavigationItem(
                                accent: appearance.accent,
                                lightForeground: useLightForeground,
                                icon: Icons.leaderboard_rounded,
                                label: context.tr('听歌排行'),
                                selected: selectedIndex == 4,
                                onTap: onRankings,
                              ),
                              if (library.playlists.isNotEmpty) ...[
                                const SizedBox(height: 16),
                                Padding(
                                  padding: const EdgeInsets.only(left: 12),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          context.tr('常用歌单'),
                                          style: TextStyle(
                                            color: mutedForeground,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: context.tr('选择常用歌单'),
                                        onPressed: onConfigurePlaylists,
                                        style: IconButton.styleFrom(
                                          foregroundColor: mutedForeground,
                                          backgroundColor: mutedForeground
                                              .withValues(alpha: 0.12),
                                          side: BorderSide(
                                            color: mutedForeground.withValues(
                                              alpha: 0.24,
                                            ),
                                          ),
                                          minimumSize: const Size.square(30),
                                          maximumSize: const Size.square(30),
                                          padding: EdgeInsets.zero,
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                        ),
                                        icon: const Icon(
                                          Icons.tune_rounded,
                                          size: 17,
                                        ),
                                      ),
                                      const SizedBox(width: 5),
                                      IconButton(
                                        tooltip: context.tr(
                                          playlistsExpanded ? '折叠' : '展开',
                                        ),
                                        onPressed: onTogglePlaylists,
                                        style: IconButton.styleFrom(
                                          foregroundColor: mutedForeground,
                                          backgroundColor: mutedForeground
                                              .withValues(alpha: 0.12),
                                          side: BorderSide(
                                            color: mutedForeground.withValues(
                                              alpha: 0.24,
                                            ),
                                          ),
                                          minimumSize: const Size.square(30),
                                          maximumSize: const Size.square(30),
                                          padding: EdgeInsets.zero,
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                        ),
                                        icon: Icon(
                                          playlistsExpanded
                                              ? Icons.expand_less_rounded
                                              : Icons.expand_more_rounded,
                                          size: 19,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (playlistsExpanded) ...[
                                  const SizedBox(height: 3),
                                  ...library.playlists
                                      .where(
                                        (playlist) => pinnedPlaylistIds == null
                                            ? true
                                            : pinnedPlaylistIds.contains(
                                                playlist.id,
                                              ),
                                      )
                                      .take(5)
                                      .map(
                                        (playlist) => _NavigationItem(
                                          accent: appearance.accent,
                                          lightForeground: useLightForeground,
                                          icon: Icons.music_note_rounded,
                                          label: playlist.name,
                                          selected: false,
                                          onTap: () => onPlaylist(playlist.id),
                                        ),
                                      ),
                                ],
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(height: compact ? 5 : 10),
                _NavigationItem(
                  accent: appearance.accent,
                  lightForeground: useLightForeground,
                  icon: Icons.palette_outlined,
                  label: context.tr('切换皮肤'),
                  selected: false,
                  onTap: _showAppearancePicker,
                ),
                _NavigationItem(
                  accent: appearance.accent,
                  lightForeground: useLightForeground,
                  icon: Icons.settings_rounded,
                  label: context.tr('设置'),
                  selected: selectedIndex == 3,
                  onTap: () => onSelected(3),
                ),
                SizedBox(height: compact ? 7 : 12),
                LiquidGlass(
                  borderRadius: 15,
                  blur: 16,
                  tint: appearance.accent,
                  // The account card intentionally has a brighter rim and a
                  // little more depth than the sidebar behind it, so it reads
                  // as a tappable identity card instead of a white sticker.
                  borderWidth: 1.25,
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(15),
                    child: InkWell(
                      onTap: onAccount,
                      borderRadius: BorderRadius.circular(15),
                      child: Padding(
                        padding: EdgeInsets.all(compact ? 10 : 13),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 17,
                              backgroundColor: appearance.accent,
                              backgroundImage:
                                  signedIn && account.avatarUrl != null
                                  ? NetworkImage(account.avatarUrl!)
                                  : null,
                              child: signedIn && account.avatarUrl != null
                                  ? null
                                  : const Icon(
                                      Icons.person_rounded,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    signedIn ? accountName : context.tr('本地模式'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: useLightForeground
                                          ? Colors.white
                                          : AppColors.textPrimary,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  if (!signedIn)
                                    Text(
                                      context.tr('前往设置连接云账号'),
                                      style: TextStyle(
                                        color: useLightForeground
                                            ? Colors.white.withValues(
                                                alpha: 0.76,
                                              )
                                            : AppColors.textSecondary,
                                        fontSize: 11,
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
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showAppearancePicker() async {
    final selection = await showModalBottomSheet<AppearancePickerSelection>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.20),
      sheetAnimationStyle: const AnimationStyle(
        duration: Duration(milliseconds: 160),
        reverseDuration: Duration(milliseconds: 120),
      ),
      builder: (sheetContext) => SafeArea(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: FractionallySizedBox(
            heightFactor: 0.84,
            widthFactor: 1,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final panelWidth = (constraints.maxWidth - 24).clamp(
                  0.0,
                  980.0,
                );
                return Align(
                  alignment: Alignment.bottomCenter,
                  child: SizedBox(
                    width: panelWidth,
                    height: constraints.maxHeight,
                    child: LiquidGlass(
                      borderRadius: 28,
                      // A high-sigma blur over 84% of a desktop window is
                      // extremely expensive while the sheet is moving. The
                      // glass tint, rim and shadow preserve the visual style
                      // without a live full-screen BackdropFilter.
                      blur: 0,
                      tint: widget.appearance.accent,
                      borderWidth: 1.2,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(22, 18, 22, 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        sheetContext.tr('播放器背景'),
                                        style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        sheetContext.tr(
                                          '选择一套皮肤，也可以导入并裁切自己的图片。',
                                        ),
                                        style: const TextStyle(
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: MaterialLocalizations.of(
                                    sheetContext,
                                  ).closeButtonTooltip,
                                  onPressed: () => Navigator.pop(sheetContext),
                                  icon: const Icon(Icons.close_rounded),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Expanded(
                              child: AppearancePicker(
                                scrollable: true,
                                onSelectionRequested: (selection) {
                                  Navigator.pop(sheetContext, selection);
                                },
                                onSelectionComplete: () {
                                  if (Navigator.of(sheetContext).canPop()) {
                                    Navigator.pop(sheetContext);
                                  }
                                },
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
        ),
      ),
    );
    if (!mounted || selection == null) return;
    final controller = ref.read(appearanceControllerProvider.notifier);
    final presetId = selection.presetId;
    if (presetId != null) {
      await controller.selectPreset(presetId);
      return;
    }
    final customBackground = selection.customBackground;
    if (customBackground != null) {
      await controller.selectCustomBackground(customBackground);
    }
  }
}

// Retained for mobile reuse once the compact shell is introduced.
// ignore: unused_element
class _Brand extends StatelessWidget {
  const _Brand({
    required this.accent,
    required this.foreground,
    required this.mutedForeground,
  });

  final Color accent;
  final Color foreground;
  final Color mutedForeground;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.42),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.72)),
          ),
          padding: const EdgeInsets.all(4),
          child: Image.asset(
            'assets/branding/sona_mark_cutout.png',
            filterQuality: FilterQuality.high,
          ),
        ),
        const SizedBox(width: 11),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sona',
              style: TextStyle(
                color: foreground,
                fontSize: 23,
                fontWeight: FontWeight.w800,
                height: 1.05,
              ),
            ),
            Text(
              context.tr('本地音乐空间'),
              style: TextStyle(
                color: mutedForeground,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _NavigationItem extends StatelessWidget {
  const _NavigationItem({
    required this.accent,
    required this.lightForeground,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final Color accent;
  final bool lightForeground;
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final compact = shouldUseCompactDesktopSidebar(
      MediaQuery.sizeOf(context).height,
    );
    final foreground = lightForeground ? Colors.white : AppColors.textPrimary;
    final mutedForeground = lightForeground
        ? Colors.white.withValues(alpha: 0.86)
        : AppColors.textSecondary;
    final displayLabel = label;
    return Padding(
      padding: EdgeInsets.only(bottom: compact ? 3 : 5),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.symmetric(
              horizontal: 13,
              vertical: compact ? 8 : 12,
            ),
            decoration: BoxDecoration(
              color: selected
                  ? accent.withValues(alpha: 0.16)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: selected
                    ? Colors.white.withValues(alpha: 0.55)
                    : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: selected ? accent : mutedForeground,
                  size: 21,
                ),
                const SizedBox(width: 12),
                Text(
                  displayLabel,
                  style: TextStyle(
                    color: selected ? foreground : mutedForeground,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
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

class _ImportProgress extends StatelessWidget {
  const _ImportProgress({required this.state});

  final LibraryState state;

  @override
  Widget build(BuildContext context) {
    final total = state.importTotal == 0 ? 1 : state.importTotal;
    return Material(
      color: AppColors.surfaceHigh,
      elevation: 12,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 13),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.outline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.library_add_rounded,
                  color: AppColors.mint,
                  size: 19,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    context
                        .tr('正在分析 {file}')
                        .replaceAll('{file}', state.importingFile),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(
                  '${state.importProgress}/${state.importTotal}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
            const SizedBox(height: 9),
            LinearProgressIndicator(
              value: state.importProgress / total,
              minHeight: 3,
              borderRadius: BorderRadius.circular(10),
              backgroundColor: AppColors.outline,
              color: AppColors.mint,
            ),
          ],
        ),
      ),
    );
  }
}
