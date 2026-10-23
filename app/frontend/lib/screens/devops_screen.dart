import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/app_state.dart';
import '../models/devops_model.dart';
import '../services/archangeld_connection.dart';
import '../services/devops_service.dart';
import '../ui/screens/services/services_logic.dart';
import '../ui/screens/services/services_widgets.dart';
import '../ui/ui.dart';

/// Services: background services, scheduled tasks, web addresses and deployments
/// in plain language, rebuilt in the Halo design.
class DevopsScreen extends StatefulWidget {
  const DevopsScreen({super.key});

  /// Resets the remembered tab to [ServicesTab.background] (useful for tests).
  @visibleForTesting
  static void resetTab() {
    _DevopsScreenState._lastTab = ServicesTab.background;
  }

  @override
  State<DevopsScreen> createState() => _DevopsScreenState();
}

class _DevopsScreenState extends State<DevopsScreen> {
  // Remember the last tab for the session
  static ServicesTab _lastTab = ServicesTab.background;

  late ServicesTab _tab;
  DevopsService? _svc;
  final Set<String> _busyRows = {};
  final Set<String> _runningScheduled = {};
  final Set<String> _testingWeb = {};
  final Map<String, (bool ok, String message)> _webResults = {};

  @override
  void initState() {
    super.initState();
    _tab = _lastTab;
    _svc = context.read<DevopsService>();
    _svc?.setActive(true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _svc?.init(context.read<ArchangeldConnection>());
    });
  }

  @override
  void dispose() {
    _svc?.setActive(false);
    super.dispose();
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _handleServiceAction(DevRowModel row, String action) async {
    final svc = context.read<DevopsService>();
    if (action == 'Stop') {
      final yes = await showConfirmDialog(
        context,
        title: 'Stop ${row.name}?',
        message: 'Anything that needs it stops working until you start it again.',
        confirmLabel: 'Stop',
        danger: true,
      );
      if (!yes || !mounted) return;
    } else if (action == 'Restart') {
      final yes = await showConfirmDialog(
        context,
        title: 'Restart ${row.name}?',
        message: 'It goes offline for a few seconds, then comes back on its own.',
        confirmLabel: 'Restart',
        danger: false,
      );
      if (!yes || !mounted) return;
    }

    setState(() => _busyRows.add(row.name));
    try {
      final ok = await svc.triggerServiceAction(row.name, action);
      if (!mounted) return;
      if (ok) {
        final past = switch (action) {
          'Start' => 'started',
          'Stop' => 'stopped',
          _ => 'restarted',
        };
        _toast('${row.name} $past.');
      } else {
        _toast(svc.lastActionMessage ?? 'Could not ${action.toLowerCase()} ${row.name}.');
      }
    } finally {
      if (mounted) setState(() => _busyRows.remove(row.name));
    }
  }

  Future<void> _runScheduled(DevRowModel row) async {
    final svc = context.read<DevopsService>();
    setState(() => _runningScheduled.add(row.name));
    try {
      final ok = await svc.triggerScheduled(row.name);
      if (!mounted) return;
      if (ok) {
        _toast('${row.name} started');
      } else {
        _toast(svc.lastActionMessage ?? 'Could not run ${row.name}.');
      }
    } finally {
      if (mounted) setState(() => _runningScheduled.remove(row.name));
    }
  }

  Future<void> _testAddress(DevRowModel row) async {
    final svc = context.read<DevopsService>();
    setState(() => _testingWeb.add(row.name));
    try {
      final result = await svc.testProxy(row.name);
      if (!mounted) return;
      final isFailure =
          result != null &&
          (result.toLowerCase().contains('error') || result.toLowerCase().contains('failed') || result.toLowerCase().contains('refused'));
      if (isFailure) {
        _webResults[row.name] = (false, "Didn't work: $result");
      } else {
        _webResults[row.name] = (true, 'Works. The address answered with a secure connection.');
      }
    } finally {
      if (mounted) setState(() => _testingWeb.remove(row.name));
    }
  }

  Future<void> _viewDeployment(DevRowModel row, bool isWide) async {
    final svc = context.read<DevopsService>();
    final content = await svc.getDeploymentContent(row.name);
    if (!mounted) return;
    showDeploymentContent(context, name: row.name, content: content ?? '', isWide: isWide);
  }

  Future<void> _removeDeployment(DevRowModel row) async {
    final svc = context.read<DevopsService>();
    final yes = await showConfirmDialog(
      context,
      title: 'Remove ${row.name}?',
      message: "This deletes the saved setup from your server. It can't be undone. Type ${row.name} to confirm.",
      confirmLabel: 'Remove',
      danger: true,
      typeToConfirm: row.name,
    );
    if (!yes || !mounted) return;

    final ok = await svc.deleteDeployment(row.name);
    if (!mounted) return;
    if (ok) {
      _toast('${row.name} removed');
      svc.fetchAll();
    } else {
      _toast(svc.lastActionMessage ?? 'Could not remove ${row.name}.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final backend = context.watch<ArchangeldConnection>();
    final svc = context.watch<DevopsService>();
    final app = context.read<AppState>();
    final ax = context.ax;
    final c = ax.colors;

    if (!backend.isPaired) {
      return AxPage(
        title: 'Services',
        child: EmptyState(
          icon: Icons.miscellaneous_services_outlined,
          title: 'No server connected yet',
          message: 'Connect a server to view and manage background services.',
          actionLabel: 'Open Settings',
          onAction: () => app.go(AxSection.settings),
        ),
      );
    }

    final counts = {
      ServicesTab.background: svc.services.length,
      ServicesTab.scheduled: svc.scheduled.length,
      ServicesTab.web: svc.proxy.length,
      ServicesTab.deployments: svc.deployments.length,
    };

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 720;

        Widget content = SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.all(isWide ? ax.space.xl : ax.space.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              _buildHeader(ax, c, svc, isWide),
              SizedBox(height: ax.space.lg),

              // Pill Tabs
              ServicesPillTabs(
                currentTab: _tab,
                counts: counts,
                onSelect:
                    (t) => setState(() {
                      _tab = t;
                      _lastTab = t;
                    }),
              ),
              SizedBox(height: ax.space.lg),

              // Tab Content
              _buildTabBody(ax, c, svc, isWide),
            ],
          ),
        );

        if (!isWide) {
          content = RefreshIndicator(onRefresh: () => svc.fetchAll(), child: content);
        }

        return content;
      },
    );
  }

  Widget _buildHeader(ArchangelTheme ax, AxPalette c, DevopsService svc, bool isWide) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Services', style: ax.typo.headline.copyWith(color: c.text)),
              SizedBox(height: 2),
              Text('The helpers that keep your server running in the background.', style: ax.typo.body.copyWith(color: c.textMuted)),
            ],
          ),
        ),
        if (isWide)
          AxButton.secondary(label: 'Refresh', icon: Icons.refresh_rounded, loading: svc.loading, onPressed: () => svc.fetchAll()),
      ],
    );
  }

  Widget _buildTabBody(ArchangelTheme ax, AxPalette c, DevopsService svc, bool isWide) {
    // 1. Group Error State
    final failed = switch (_tab) {
      ServicesTab.background => svc.servicesFailed,
      ServicesTab.scheduled => svc.scheduledFailed,
      ServicesTab.web => svc.proxyFailed,
      ServicesTab.deployments => svc.deploymentsFailed,
    };

    if (failed) {
      return GroupErrorView(groupNameLower: _tab.groupNameLower, onRetry: () => svc.fetchAll());
    }

    // 2. Initial Loading State (4 skeleton rows)
    if (svc.loading && !svc.hasLoaded) {
      return const ServicesLoadingSkeleton();
    }

    // 3. Data Rows
    final rows = switch (_tab) {
      ServicesTab.background => svc.services,
      ServicesTab.scheduled => svc.scheduled,
      ServicesTab.web => svc.proxy,
      ServicesTab.deployments => svc.deployments,
    };

    final introWidget =
        isWide
            ? Padding(
              padding: EdgeInsets.all(ax.space.md),
              child: Row(
                children: [
                  Icon(Icons.tune_outlined, size: 20, color: c.accent),
                  SizedBox(width: ax.space.sm),
                  Expanded(child: Text(_tab.intro, style: ax.typo.body.copyWith(color: c.text))),
                ],
              ),
            )
            : null;

    final listContent =
        rows.isEmpty
            ? Padding(
              padding: EdgeInsets.symmetric(vertical: ax.space.xxl, horizontal: ax.space.lg),
              child: Center(child: Text(_tab.emptyText, style: ax.typo.body.copyWith(color: c.textMuted))),
            )
            : Column(children: [for (final row in rows) _buildRow(ax, c, row, isWide)]);

    if (isWide) {
      return AxCard(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (introWidget != null) ...[introWidget, Divider(height: 1, color: c.border.withValues(alpha: 0.5))],
            listContent,
          ],
        ),
      );
    }

    // Compact layout: intro text above the card
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: ax.space.xs, vertical: ax.space.xs),
          child: Text(_tab.intro, style: ax.typo.body.copyWith(color: c.textMuted)),
        ),
        SizedBox(height: ax.space.sm),
        AxCard(padding: EdgeInsets.zero, child: listContent),
      ],
    );
  }

  Widget _buildRow(ArchangelTheme ax, AxPalette c, DevRowModel row, bool isWide) {
    final actions = _buildActionsForRow(ax, c, row, isWide);
    final inlineResult = _buildInlineResult(ax, c, row.name);

    if (isWide) {
      return WideServiceRow(row: row, actions: actions, inlineResult: inlineResult);
    }
    return CompactServiceRow(row: row, actions: actions, inlineResult: inlineResult);
  }

  Widget? _buildInlineResult(ArchangelTheme ax, AxPalette c, String name) {
    if (_tab != ServicesTab.web) return null;
    final res = _webResults[name];
    if (res == null) return null;

    final (ok, message) = res;
    final color = ok ? c.success : c.danger;
    final icon = ok ? Icons.check_circle_outline : Icons.error_outline;

    return Semantics(
      container: true,
      liveRegion: true,
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          SizedBox(width: ax.space.xs + 2),
          Expanded(child: Text(message, style: ax.typo.caption.copyWith(color: color, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  List<Widget> _buildActionsForRow(ArchangelTheme ax, AxPalette c, DevRowModel row, bool isWide) {
    final isRowBusy = _busyRows.contains(row.name);

    switch (_tab) {
      case ServicesTab.background:
        final btns = <Widget>[];
        final actions = row.actions;

        if (row.ok) {
          // Running: ghost Restart + Stop
          if (actions.contains('Restart')) {
            btns.add(
              AxButton.ghost(
                label: 'Restart',
                loading: isRowBusy,
                onPressed: isRowBusy ? null : () => _handleServiceAction(row, 'Restart'),
              ),
            );
          }
          if (actions.contains('Stop')) {
            if (btns.isNotEmpty) btns.add(SizedBox(width: ax.space.xs));
            btns.add(AxButton(label: 'Stop', loading: isRowBusy, onPressed: isRowBusy ? null : () => _handleServiceAction(row, 'Stop')));
          }
        } else {
          // Stopped / Failed: primary Start
          if (actions.contains('Start')) {
            btns.add(AxButton(label: 'Start', loading: isRowBusy, onPressed: isRowBusy ? null : () => _handleServiceAction(row, 'Start')));
          }
        }
        return btns;

      case ServicesTab.scheduled:
        final isRunning = _runningScheduled.contains(row.name);
        return [
          AxButton(label: isRunning ? 'Running…' : 'Run now', loading: isRunning, onPressed: isRunning ? null : () => _runScheduled(row)),
        ];

      case ServicesTab.web:
        final isTesting = _testingWeb.contains(row.name);
        final tested = _webResults.containsKey(row.name);
        return [AxButton(label: tested ? 'Test again' : 'Test', loading: isTesting, onPressed: isTesting ? null : () => _testAddress(row))];

      case ServicesTab.deployments:
        return [
          AxButton.secondary(label: 'View', onPressed: () => _viewDeployment(row, isWide)),
          SizedBox(width: ax.space.xs),
          AxButton.danger(label: 'Remove', onPressed: () => _removeDeployment(row)),
        ];
    }
  }
}
