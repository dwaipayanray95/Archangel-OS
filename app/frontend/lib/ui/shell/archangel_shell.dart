import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../data/app_state.dart';
import '../../services/archangeld_connection.dart';
import '../../services/admin_mode_service.dart';
import '../../services/containers_service.dart';
import '../../services/devices_service.dart';
import '../../services/devops_service.dart';
import '../../services/files_service.dart';
import '../../services/monitoring_service.dart';
import '../../services/server_registry.dart';
import '../../services/window_service.dart';
import '../../widgets/command_palette.dart';
import '../../widgets/notif_panel.dart';
import '../components/ax_glass.dart';
import '../components/ax_icon_button.dart';
import '../components/ax_wordmark.dart';
import '../theme.dart';
import 'desktop_mode.dart';
import 'desktop_prefs.dart';
import 'destinations.dart';
import 'more_page.dart';
import 'server_switcher.dart';
import 'sidebar.dart';
import 'status_strip.dart';

const _kOpenPalette = SingleActivator(LogicalKeyboardKey.keyK, meta: true);
const _kOpenPaletteCtrl = SingleActivator(LogicalKeyboardKey.keyK, control: true);
const _kToggleFullScreen = SingleActivator(LogicalKeyboardKey.f11);

/// Below this width the phone layout (bottom bar + More) is used.
const double kPhoneBreakpoint = 720;

/// At or above this width the sidebar shows labels next to the icons.
const double kExtendedRailBreakpoint = 1000;

/// Desktop mode needs at least this much room (tablets, phones held
/// sideways, computers).
const double kDesktopModeMinWidth = 900;

const _phoneTabs = <AxSection>[AxSection.home, AxSection.apps, AxSection.files, AxSection.terminal];

/// Whether [section] polls the monitoring stream / containers / services.
/// Home summarises all three, so it keeps them running (monitoring at a
/// slower rate than the Activity charts).
bool sectionUsesMonitoring(AxSection? s) => s == AxSection.home || s == AxSection.activity;
bool sectionUsesContainers(AxSection? s) => s == AxSection.home || s == AxSection.apps;
bool sectionUsesServices(AxSection? s) => s == AxSection.home || s == AxSection.services;

/// Root shell. Everything sits on the Halo wallpaper ([AxBackdrop]).
///
/// - Phone: wordmark + server pill, the connection strip, the destination,
///   and a floating glass bottom bar (Home, Apps, Files, Terminal, More).
/// - Tablet / computer, Simple layout: a glass sidebar, the connection strip
///   and one destination at a time.
/// - Tablet / computer, Desktop mode: windows, a dock and a launcher
///   ([DesktopModeView]).
///
/// Destinations are built the first time they are visited and then kept
/// alive (so scroll position and terminal sessions survive switching, and
/// moving between Simple and Desktop mode), but only the visible ones poll
/// the server. The command palette and notification panel are overlays.
class ArchangelShell extends StatefulWidget {
  const ArchangelShell({super.key});

  @override
  State<ArchangelShell> createState() => _ArchangelShellState();
}

class _ArchangelShellState extends State<ArchangelShell> {
  final Set<AxSection> _visited = {};
  final DesktopWindows _desk = DesktopWindows();

  /// One GlobalKey per destination (per server generation) so a destination
  /// keeps its state when it moves between the Simple layout and a window.
  final Map<AxSection, GlobalKey> _keys = {};
  AxSection? _lastSection;
  bool _showMore = false;

  /// Bumped when the app is re-pointed at another server; part of every
  /// destination's key so their per-server state (terminal tabs, current
  /// folder, selections) starts fresh.
  int _generation = 0;
  bool _hadServer = false;
  int _lastPairing = 0;
  String? _lastPollKey;
  late ArchangeldConnection _backend;

  @override
  void initState() {
    super.initState();
    _backend = context.read<ArchangeldConnection>();
    _hadServer = _backend.isPaired;
    _lastPairing = _backend.pairingGeneration;
    _backend.addListener(_onBackendChanged);
    _desk.addListener(_onDeskChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WindowService.setFullScreen(true);
    });
  }

  @override
  void dispose() {
    _backend.removeListener(_onBackendChanged);
    _desk.removeListener(_onDeskChanged);
    _desk.dispose();
    super.dispose();
  }

  void _onDeskChanged() {
    if (mounted) setState(() {});
  }

  Widget _destination(AxSection s) {
    final key = _keys.putIfAbsent(s, () => GlobalKey(debugLabel: 'dest-${s.name}-$_generation'));
    return KeyedSubtree(key: key, child: buildDestination(s));
  }

  void _onBackendChanged() {
    // Compare the pairing generation, not the host: two servers set up with
    // defaults share the same host:port.
    if (_backend.pairingGeneration == _lastPairing) return;
    _lastPairing = _backend.pairingGeneration;
    final hadServer = _hadServer;
    _hadServer = _backend.isPaired;
    if (!_backend.isPaired || !hadServer) return; // unpaired / first pairing: nothing stale to clear
    context.read<MonitoringService>().reset();
    context.read<ContainersService>().reset();
    context.read<DevopsService>().reset();
    context.read<FilesService>().reset();
    context.read<DevicesService>().reset();
    context.read<AdminModeService>().reset();
    setState(() {
      _generation++;
      _keys.clear();
      _showMore = false;
    });
    _lastPollKey = null; // re-apply polling for the new server
  }

  /// Applies visibility-driven polling for the sections on screen (one in
  /// the Simple layout, every open window in Desktop mode).
  ///
  /// [widget]: Desktop mode's health widget is showing, so monitoring keeps
  /// running (at Home's calm rate) even with no window open.
  void _syncPolling(Set<AxSection> visible, {bool widget = false}) {
    final names = visible.map((s) => s.name).toList()..sort();
    final key = '${names.join(',')}/$widget/$_generation';
    if (key == _lastPollKey) return;
    _lastPollKey = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final mon = context.read<MonitoringService>();
      mon.setActive(widget || visible.any(sectionUsesMonitoring));
      // Activity shows live charts; Home and the widget only need a summary.
      if (visible.contains(AxSection.activity)) {
        mon.setPollingRateMs(1000);
      } else if (widget || visible.contains(AxSection.home)) {
        mon.setPollingRateMs(5000);
      }
      context.read<ContainersService>().setActive(visible.any(sectionUsesContainers));
      context.read<DevopsService>().setActive(visible.any(sectionUsesServices));
    });
  }

  void _open(AxSection s) {
    setState(() => _showMore = false);
    context.read<AppState>().go(s);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final prefs = context.watch<DesktopPrefs>();

    final sectionChanged = app.section != _lastSection;
    if (sectionChanged) {
      _lastSection = app.section;
      _showMore = false;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final phone = constraints.maxWidth < kPhoneBreakpoint;
        final extended = constraints.maxWidth >= kExtendedRailBreakpoint;
        final desktopAllowed = !phone && constraints.maxWidth >= kDesktopModeMinWidth;
        final desktop = desktopAllowed && app.layout == AxLayout.desktop;
        final moreVisible = phone && _showMore;

        Set<AxSection> visible;
        if (desktop) {
          final r = prefs.reserve;
          _desk.fitTo(Size(constraints.maxWidth - r.horizontal, constraints.maxHeight - kDeskTopBarHeight - r.vertical));
          _desk.ensureDefaults(rightInset: prefs.showWidget ? kDeskWidgetWidth + 24 : 0);
          // Navigating from inside a screen (e.g. Home's quick actions)
          // opens or raises that window.
          if (sectionChanged && app.section != _desk.front) {
            final target = app.section;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && app.section == target && _desk.front != target) _desk.open(target);
            });
          }
          visible = _desk.visible;
        } else {
          visible = moreVisible ? <AxSection>{} : {app.section};
        }
        _visited.addAll(visible);
        _syncPolling(visible, widget: desktop && prefs.showWidget);

        final canExit = app.section == AxSection.home && !moreVisible && !app.paletteOpen && !app.notifOpen;

        final Widget main;
        if (desktop) {
          main = DesktopModeView(
            windows: _desk,
            buildContent: _destination,
            onFocus: (s) {
              if (app.section != s) app.go(s);
            },
            onSimpleLayout: () => app.layout = AxLayout.simple,
          );
        } else {
          final content = _Destinations(
            visited: _visited,
            current: app.section,
            builder: _destination,
            showMore: moreVisible,
            more: MorePage(onOpen: _open),
          );
          main =
              phone
                  ? _PhoneFrame(
                    showBack: axMoreSections.contains(app.section) && !moreVisible,
                    onBack: () => setState(() => _showMore = true),
                    child: content,
                  )
                  : Row(
                    children: [
                      AxSidebar(
                        extended: extended,
                        selected: app.section,
                        onSelect: _open,
                        onDesktopMode: desktopAllowed ? () => app.layout = AxLayout.desktop : null,
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            SafeArea(
                              bottom: false,
                              left: false,
                              child: Padding(
                                padding: EdgeInsets.fromLTRB(context.ax.space.lg, context.ax.space.md, context.ax.space.md, 0),
                                child: const StatusStrip(showServerName: false),
                              ),
                            ),
                            Expanded(child: content),
                          ],
                        ),
                      ),
                    ],
                  );
        }

        final Widget body = Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(onTap: app.closeNotif, behavior: HitTestBehavior.translucent, child: main),
            if (app.notifOpen) const NotifPanel(),
            if (app.paletteOpen) const Positioned.fill(child: CommandPalette()),
          ],
        );

        return CallbackShortcuts(
          bindings: {_kOpenPalette: app.openPalette, _kOpenPaletteCtrl: app.openPalette, _kToggleFullScreen: app.toggleFullScreen},
          child: Focus(
            autofocus: true,
            // Back: close overlay -> Home -> leave the app. (Dialogs and
            // pushed pages sit above this route and are popped first.)
            child: PopScope(
              canPop: canExit,
              onPopInvokedWithResult: (didPop, _) {
                if (didPop) return;
                if (app.paletteOpen) {
                  app.closePalette();
                } else if (app.notifOpen) {
                  app.closeNotif();
                } else {
                  setState(() => _showMore = false);
                  app.go(AxSection.home);
                }
              },
              child: AxBackdrop(
                child: Scaffold(
                  backgroundColor: Colors.transparent,
                  body: body,
                  bottomNavigationBar:
                      phone
                          ? _GlassNavBar(
                            child: NavigationBar(
                              selectedIndex: moreVisible || app.section.index >= _phoneTabs.length ? _phoneTabs.length : app.section.index,
                              onDestinationSelected: (i) {
                                if (i == _phoneTabs.length) {
                                  setState(() => _showMore = true);
                                  app.closeNotif();
                                } else {
                                  _open(_phoneTabs[i]);
                                }
                              },
                              destinations: [
                                for (final s in _phoneTabs)
                                  NavigationDestination(
                                    icon: Icon(axSectionIcons[s]),
                                    selectedIcon: Icon(axSectionSelectedIcons[s]),
                                    label: axSectionLabels[s]!,
                                  ),
                                const NavigationDestination(
                                  icon: Icon(Icons.more_horiz),
                                  selectedIcon: Icon(Icons.more_horiz),
                                  label: 'More',
                                ),
                              ],
                            ),
                          )
                          : null,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Phone header: the wordmark (or Back to More), the server pill, then the
/// connection strip, above the destination.
class _PhoneFrame extends StatelessWidget {
  const _PhoneFrame({required this.showBack, required this.onBack, required this.child});

  final bool showBack;
  final VoidCallback onBack;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    return Column(
      children: [
        SafeArea(
          bottom: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(ax.space.lg, ax.space.sm, ax.space.md, 0),
            child: Column(
              children: [
                Row(
                  children: [
                    if (showBack) AxIconButton(icon: Icons.arrow_back, tooltip: 'Back to More', onPressed: onBack) else const AxWordmark(),
                    SizedBox(width: ax.space.md),
                    const Expanded(child: Align(alignment: Alignment.centerRight, child: _ServerPill())),
                  ],
                ),
                SizedBox(height: ax.space.xs),
                const StatusStrip(showServerName: false),
              ],
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}

class _ServerPill extends StatelessWidget {
  const _ServerPill();

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final name = context.watch<ServerRegistry>().active?.name;
    if (name == null || name.isEmpty) return const ServerSwitcher(compact: true);
    return Semantics(
      button: true,
      label: 'Server: $name. Switch server',
      excludeSemantics: true,
      onTap: () => showServerSheet(context),
      child: Tooltip(
        message: 'Switch server',
        child: Material(
          color: c.glassStrong,
          shape: StadiumBorder(side: BorderSide(color: c.border)),
          child: InkWell(
            onTap: () => showServerSheet(context),
            customBorder: const StadiumBorder(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: axMinTarget(context) - 8, maxWidth: 200),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: ax.space.md),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.dns_outlined, size: 15, color: c.accent),
                    SizedBox(width: ax.space.xs + 2),
                    Flexible(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ax.typo.mono.copyWith(color: c.text, fontSize: 12.5),
                      ),
                    ),
                    Icon(Icons.expand_more, size: 16, color: c.textMuted),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The phone's floating frosted bottom bar.
class _GlassNavBar extends StatelessWidget {
  const _GlassNavBar({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    return SafeArea(
      top: false,
      minimum: EdgeInsets.only(bottom: ax.space.sm),
      child: Padding(
        padding: EdgeInsets.fromLTRB(ax.space.md, ax.space.xs, ax.space.md, ax.space.xs),
        child: AxGlass(strong: true, blur: true, shadow: true, radius: 24, child: child),
      ),
    );
  }
}

/// Lazily built, kept-alive destinations. Unvisited ones are not built at
/// all; the More page (phone) is the last stack entry.
class _Destinations extends StatelessWidget {
  const _Destinations({required this.visited, required this.current, required this.builder, required this.showMore, required this.more});

  final Set<AxSection> visited;
  final AxSection current;
  final Widget Function(AxSection) builder;
  final bool showMore;
  final Widget more;

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: showMore ? AxSection.values.length : current.index,
      children: [
        for (final s in AxSection.values)
          if (visited.contains(s)) builder(s) else const SizedBox.shrink(),
        more,
      ],
    );
  }
}
