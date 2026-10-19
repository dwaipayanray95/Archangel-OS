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
import '../../widgets/command_palette.dart';
import '../../widgets/notif_panel.dart';
import '../components/ax_icon_button.dart';
import '../theme.dart';
import 'destinations.dart';
import 'more_page.dart';
import 'server_switcher.dart';
import 'status_strip.dart';

const _kOpenPalette = SingleActivator(LogicalKeyboardKey.keyK, meta: true);
const _kOpenPaletteCtrl = SingleActivator(LogicalKeyboardKey.keyK, control: true);

/// Below this width the phone layout (bottom bar + More) is used.
const double kPhoneBreakpoint = 720;

/// At or above this width the rail shows labels next to the icons.
const double kExtendedRailBreakpoint = 1100;

const _phoneTabs = <AxSection>[AxSection.home, AxSection.apps, AxSection.files, AxSection.terminal];

/// Whether [section] polls the monitoring stream / containers / services.
/// Home summarises all three, so it keeps them running (monitoring at a
/// slower rate than the Activity charts).
bool sectionUsesMonitoring(AxSection? s) => s == AxSection.home || s == AxSection.activity;
bool sectionUsesContainers(AxSection? s) => s == AxSection.home || s == AxSection.apps;
bool sectionUsesServices(AxSection? s) => s == AxSection.home || s == AxSection.services;

/// Root shell: a compact status strip, the navigation (bottom bar on phones,
/// rail on larger screens) and the destinations.
///
/// Destinations are built the first time they are visited and then kept
/// alive (so scroll position and terminal sessions survive switching), but
/// only the visible one polls the server. The command palette and
/// notification panel are overlays on top.
class ArchangelShell extends StatefulWidget {
  const ArchangelShell({super.key});

  @override
  State<ArchangelShell> createState() => _ArchangelShellState();
}

class _ArchangelShellState extends State<ArchangelShell> {
  final Set<AxSection> _visited = {};
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
  }

  @override
  void dispose() {
    _backend.removeListener(_onBackendChanged);
    super.dispose();
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
      _showMore = false;
    });
    _lastPollKey = null; // re-apply polling for the new server
  }

  /// Applies visibility-driven polling for the currently visible section.
  void _syncPolling(AxSection? visible) {
    final key = '$visible/$_generation';
    if (key == _lastPollKey) return;
    _lastPollKey = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final mon = context.read<MonitoringService>();
      mon.setActive(sectionUsesMonitoring(visible));
      // Activity shows live charts; Home only needs a summary.
      if (visible == AxSection.activity) {
        mon.setPollingRateMs(1000);
      } else if (visible == AxSection.home) {
        mon.setPollingRateMs(5000);
      }
      context.read<ContainersService>().setActive(sectionUsesContainers(visible));
      context.read<DevopsService>().setActive(sectionUsesServices(visible));
    });
  }

  void _open(AxSection s) {
    setState(() => _showMore = false);
    context.read<AppState>().go(s);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    if (app.section != _lastSection) {
      _lastSection = app.section;
      _showMore = false;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final phone = constraints.maxWidth < kPhoneBreakpoint;
        final extended = constraints.maxWidth >= kExtendedRailBreakpoint;
        final moreVisible = phone && _showMore;
        final visible = moreVisible ? null : app.section;
        if (visible != null) _visited.add(visible);
        _syncPolling(visible);

        final canExit = app.section == AxSection.home && !moreVisible && !app.paletteOpen && !app.notifOpen;

        final content = _Destinations(
          visited: _visited,
          current: app.section,
          generation: _generation,
          showMore: moreVisible,
          more: MorePage(onOpen: _open),
        );

        final Widget body = Stack(
          fit: StackFit.expand,
          children: [
            Column(
              children: [
                SafeArea(
                  bottom: false,
                  left: !phone ? false : true,
                  child: StatusStrip(
                    showServerName: phone,
                    leading: phone && axMoreSections.contains(app.section) && !moreVisible
                        ? AxIconButton(
                            icon: Icons.arrow_back,
                            tooltip: 'Back to More',
                            onPressed: () => setState(() => _showMore = true),
                          )
                        : null,
                  ),
                ),
                Expanded(
                  child: Row(
                    children: [
                      if (!phone) _Rail(extended: extended, selected: app.section, onSelect: _open),
                      Expanded(
                        child: GestureDetector(
                          onTap: app.closeNotif,
                          behavior: HitTestBehavior.translucent,
                          child: content,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (app.notifOpen) const NotifPanel(),
            if (app.paletteOpen) const Positioned.fill(child: CommandPalette()),
          ],
        );

        return CallbackShortcuts(
          bindings: {
            _kOpenPalette: app.openPalette,
            _kOpenPaletteCtrl: app.openPalette,
          },
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
              child: Scaffold(
                backgroundColor: context.ax.colors.bg,
                body: body,
                bottomNavigationBar: phone
                    ? NavigationBar(
                        selectedIndex: moreVisible || app.section.index >= _phoneTabs.length
                            ? _phoneTabs.length
                            : app.section.index,
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
                      )
                    : null,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Lazily built, kept-alive destinations. Unvisited ones are not built at
/// all; the More page (phone) is the last stack entry.
class _Destinations extends StatelessWidget {
  const _Destinations({
    required this.visited,
    required this.current,
    required this.generation,
    required this.showMore,
    required this.more,
  });

  final Set<AxSection> visited;
  final AxSection current;
  final int generation;
  final bool showMore;
  final Widget more;

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: showMore ? AxSection.values.length : current.index,
      children: [
        for (final s in AxSection.values)
          if (visited.contains(s))
            KeyedSubtree(key: ValueKey('${s.name}-$generation'), child: buildDestination(s))
          else
            const SizedBox.shrink(),
        more,
      ],
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail({required this.extended, required this.selected, required this.onSelect});

  final bool extended;
  final AxSection selected;
  final void Function(AxSection) onSelect;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    return DecoratedBox(
      decoration: BoxDecoration(border: Border(right: BorderSide(color: c.border))),
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(
              child: NavigationRail(
                extended: extended,
                selectedIndex: selected.index,
                labelType: extended ? NavigationRailLabelType.none : NavigationRailLabelType.all,
                onDestinationSelected: (i) => onSelect(AxSection.values[i]),
                leading: Padding(
                  padding: EdgeInsets.only(bottom: ax.space.md, top: ax.space.sm),
                  child: Column(
                    children: [
                      if (extended)
                        Padding(
                          padding: EdgeInsets.only(bottom: ax.space.xs),
                          child: Text('Archangel', style: ax.typo.title.copyWith(color: c.text)),
                        ),
                      SizedBox(width: extended ? 220 : null, child: ServerSwitcher(compact: !extended)),
                    ],
                  ),
                ),
                destinations: [
                  for (final s in AxSection.values)
                    NavigationRailDestination(
                      icon: Icon(axSectionIcons[s]),
                      selectedIcon: Icon(axSectionSelectedIcons[s]),
                      label: Text(axSectionLabels[s]!),
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
