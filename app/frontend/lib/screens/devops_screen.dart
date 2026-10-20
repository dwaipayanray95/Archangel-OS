import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/app_state.dart';
import '../models/devops_model.dart';
import '../services/archangeld_connection.dart';
import '../services/devops_service.dart';
import '../ui/screens/services/script_editor_page.dart';
import '../ui/screens/services/services_logic.dart';
import '../ui/screens/services/services_widgets.dart';
import '../ui/ui.dart';

/// Services: background services, scheduled tasks, web addresses and scripts
/// on the server, in plain words.
class DevopsScreen extends StatefulWidget {
  const DevopsScreen({super.key});

  @override
  State<DevopsScreen> createState() => _DevopsScreenState();
}

class _DevopsScreenState extends State<DevopsScreen> {
  ServicesTab _tab = ServicesTab.services;

  // Server refusal being shown prominently (null = none).
  String? _refusal;
  bool _refusalIsAdmin = false;

  // Names of rows with an action in flight, and web-address test results.
  final _busy = <String>{};
  final _testing = <String>{};
  final _testResults = <String, String?>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<DevopsService>().init(context.read<ArchangeldConnection>());
    });
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _showRefusal(DevopsService svc, String fallback) {
    final msg = svc.lastActionMessage ?? fallback;
    setState(() {
      _refusal = msg;
      _refusalIsAdmin = isAdminModeRefusal(msg, svc.lastActionStatus);
    });
  }

  Future<void> _guard(String key, Future<void> Function() job) async {
    if (_busy.contains(key)) return;
    setState(() => _busy.add(key));
    try {
      await job();
    } finally {
      if (mounted) setState(() => _busy.remove(key));
    }
  }

  Future<void> _serviceAction(DevRowModel row, String action) async {
    final svc = context.read<DevopsService>();
    if (action == 'Stop') {
      final yes = await showConfirmDialog(
        context,
        title: 'Stop ${row.name}?',
        message: 'Anything that depends on this service stops working until you start it again.',
        confirmLabel: 'Stop service',
      );
      if (!yes || !mounted) return;
    } else if (action == 'Restart') {
      final yes = await showConfirmDialog(
        context,
        title: 'Restart ${row.name}?',
        message: 'The service is briefly unavailable while it restarts.',
        confirmLabel: 'Restart service',
      );
      if (!yes || !mounted) return;
    }
    await _guard('svc:${row.name}', () async {
      final ok = await svc.triggerServiceAction(row.name, action);
      if (!mounted) return;
      if (ok) {
        setState(() => _refusal = null);
        final past = switch (action) {
          'Start' => 'started',
          'Stop' => 'stopped',
          _ => 'restarted',
        };
        _toast('${row.name} $past.');
      } else {
        _showRefusal(svc, 'Could not ${action.toLowerCase()} ${row.name}.');
      }
    });
  }

  Future<void> _runTimer(DevRowModel row) async {
    final svc = context.read<DevopsService>();
    await _guard('timer:${row.name}', () async {
      final ok = await svc.triggerScheduled(row.name);
      if (!mounted) return;
      if (ok) {
        setState(() => _refusal = null);
        _toast('${row.name} is running now.');
      } else {
        _showRefusal(svc, 'Could not run ${row.name}.');
      }
    });
  }

  Future<void> _testAddress(DevRowModel row) async {
    final svc = context.read<DevopsService>();
    setState(() {
      _testing.add(row.name);
      _testResults.remove(row.name);
    });
    final res = await svc.testProxy(row.name);
    if (!mounted) return;
    setState(() {
      _testing.remove(row.name);
      _testResults[row.name] = res;
    });
  }

  Future<void> _runScript(DevRowModel row) async {
    final svc = context.read<DevopsService>();
    final yes = await showConfirmDialog(
      context,
      title: 'Run ${row.name}?',
      message: 'This runs the script on your server as the archangel user.',
      confirmLabel: 'Run script',
    );
    if (!yes || !mounted) return;
    Map<String, String>? res;
    await _guard('script:${row.name}', () async {
      res = await svc.runDeployment(row.name);
    });
    final result = res;
    if (!mounted || result == null) return;
    final ok = result['ok'] == 'true';
    final message = result['message'] ?? '';
    if (!ok && (result['output'] ?? '').isEmpty && isAdminModeRefusal(message, null)) {
      setState(() {
        _refusal = message;
        _refusalIsAdmin = true;
      });
      return;
    }
    setState(() => _refusal = null);
    await showRunOutputSheet(context, scriptName: row.name, ok: ok, message: message, output: result['output'] ?? '');
  }

  Future<void> _editScript(DevRowModel row) async {
    final svc = context.read<DevopsService>();
    await _guard('script:${row.name}', () async {
      final content = await svc.getDeploymentContent(row.name);
      if (!mounted) return;
      if (content == null) {
        _toast('Could not open ${row.name}. Check your connection and try again.');
        return;
      }
      final saved = await ScriptEditorPage.open(context, svc, scriptName: row.name, initialContent: content);
      if (saved && mounted) _toast('${row.name} saved.');
    });
  }

  Future<void> _newScript() async {
    final svc = context.read<DevopsService>();
    final saved = await ScriptEditorPage.open(context, svc);
    if (saved && mounted) _toast('Script saved.');
  }

  Future<void> _deleteScript(DevRowModel row) async {
    final svc = context.read<DevopsService>();
    final yes = await showConfirmDialog(
      context,
      title: 'Delete ${row.name}?',
      message: 'The script is removed from your server. This can’t be undone.',
      confirmLabel: 'Delete script',
      danger: true,
    );
    if (!yes || !mounted) return;
    await _guard('script:${row.name}', () async {
      final ok = await svc.deleteDeployment(row.name);
      if (!mounted) return;
      if (ok) {
        setState(() => _refusal = null);
        _toast('${row.name} was deleted.');
      } else {
        _showRefusal(svc, 'Could not delete ${row.name}.');
      }
    });
  }

  void _openLogs(DevRowModel row) {
    context.read<AppState>().openTerminalWithCommand('journalctl -u ${row.name} -n 50 --no-pager');
  }

  List<DevRowModel> _rowsFor(DevopsService svc) => switch (_tab) {
    ServicesTab.services => svc.services,
    ServicesTab.timers => svc.scheduled,
    ServicesTab.web => svc.proxy,
    ServicesTab.scripts => svc.deployments,
  };

  List<RowAction> _actionsFor(DevRowModel row) {
    switch (_tab) {
      case ServicesTab.services:
        final busy = _busy.contains('svc:${row.name}');
        return [
          if (!row.ok)
            RowAction(
              label: 'Start',
              icon: Icons.play_arrow_rounded,
              kind: AxButtonKind.primary,
              loading: busy,
              onPressed: () => _serviceAction(row, 'Start'),
            ),
          RowAction(label: 'Restart', icon: Icons.restart_alt_rounded, onPressed: busy ? null : () => _serviceAction(row, 'Restart')),
          if (row.ok) RowAction(label: 'Stop', icon: Icons.stop_rounded, onPressed: busy ? null : () => _serviceAction(row, 'Stop')),
          RowAction(label: 'Logs', icon: Icons.notes_rounded, onPressed: () => _openLogs(row)),
        ];
      case ServicesTab.timers:
        return [
          RowAction(
            label: 'Run now',
            icon: Icons.play_arrow_rounded,
            loading: _busy.contains('timer:${row.name}'),
            onPressed: () => _runTimer(row),
          ),
        ];
      case ServicesTab.web:
        return [
          RowAction(
            label: 'Test',
            icon: Icons.network_check_rounded,
            loading: _testing.contains(row.name),
            onPressed: () => _testAddress(row),
          ),
        ];
      case ServicesTab.scripts:
        final busy = _busy.contains('script:${row.name}');
        return [
          RowAction(
            label: 'Run',
            icon: Icons.play_arrow_rounded,
            kind: AxButtonKind.primary,
            loading: busy,
            onPressed: busy ? null : () => _runScript(row),
          ),
          RowAction(label: 'Edit', icon: Icons.edit_outlined, onPressed: busy ? null : () => _editScript(row)),
          RowAction(label: 'Delete', icon: Icons.delete_outline_rounded, onPressed: busy ? null : () => _deleteScript(row)),
        ];
    }
  }

  Widget _intro() {
    switch (_tab) {
      case ServicesTab.services:
        return const TabIntro(
          text: 'Programs that keep running on your server, like your web server.',
          helpTitle: 'Background services',
          helpText:
              'A background service is a program that starts with your server and keeps running without anyone '
              'logged in. Linux calls them “systemd services”. Stopping one switches that program off until you start it again.',
        );
      case ServicesTab.timers:
        return const TabIntro(
          text: 'Jobs your server runs on a schedule, like a nightly backup.',
          helpTitle: 'Scheduled tasks',
          helpText:
              'A scheduled task runs by itself at set times, for example every night. Linux calls these “systemd timers”. '
              '“Run now” starts the job straight away without changing its schedule.',
        );
      case ServicesTab.web:
        return const TabIntro(
          text: 'Website names that point to apps on your server.',
          helpTitle: 'Web addresses',
          helpText:
              'A web address (like notes.example.com) is sent to the right app on your server by a helper called Caddy, '
              'a “reverse proxy”. “Test” checks that the address answers.',
        );
      case ServicesTab.scripts:
        return const TabIntro(
          text: 'Saved sets of commands you can run on your server with one tap.',
          helpTitle: 'Scripts',
          helpText:
              'A script is a text file of commands, for example to update an app. Scripts run on your server as the '
              '“archangel” user, so only run ones you trust.',
        );
    }
  }

  ({IconData icon, String title, String message}) _emptyText() => switch (_tab) {
    ServicesTab.services => (
      icon: Icons.settings_suggest_outlined,
      title: 'No background services found',
      message: 'Programs that run in the background on your server will show up here.',
    ),
    ServicesTab.timers => (
      icon: Icons.schedule_rounded,
      title: 'No scheduled tasks',
      message: 'Jobs that run on a schedule on your server will show up here.',
    ),
    ServicesTab.web => (
      icon: Icons.language_rounded,
      title: 'No web addresses yet',
      message: 'When an app on your server is given a website name, it will show up here.',
    ),
    ServicesTab.scripts => (
      icon: Icons.terminal_rounded,
      title: 'No scripts yet',
      message: 'Save a set of commands as a script and run it whenever you like.',
    ),
  };

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<DevopsService>();
    final conn = context.watch<ArchangeldConnection>();
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final ax = context.ax;

    final actions = [
      if (_tab == ServicesTab.scripts && conn.isPaired) AxButton(label: 'New script', icon: Icons.add_rounded, onPressed: _newScript),
    ];

    final Widget body;
    var scroll = true;
    final rows = _rowsFor(svc);
    if (!conn.isPaired) {
      scroll = false;
      body = EmptyState(
        icon: Icons.link_off_rounded,
        title: 'Not connected to a server',
        message: 'Connect this device to your server to see and manage its services.',
        actionLabel: 'Open Settings',
        onAction: () => context.read<AppState>().go(AxSection.settings),
      );
    } else if (!svc.hasLoaded) {
      scroll = false;
      body = LoadingState(message: 'Loading your services...', onRetry: svc.fetchAll);
    } else {
      final children = <Widget>[
        ServicesTabBar(selected: _tab, onSelected: (t) => setState(() => _tab = t)),
        SizedBox(height: ax.space.md),
        _intro(),
        SizedBox(height: ax.space.md),
        if (_refusal != null) ...[
          RefusalBanner(
            title: _refusalIsAdmin ? 'Admin mode is off' : 'That wasn’t allowed',
            message: _refusal!,
            onDismiss: () => setState(() => _refusal = null),
            onOpenSettings: _refusalIsAdmin ? () => context.read<AppState>().go(AxSection.settings) : null,
          ),
          SizedBox(height: ax.space.md),
        ],
        if (svc.error != null && rows.isNotEmpty) ...[
          InfoBanner(message: 'Could not refresh everything. What you see may be out of date.'),
          SizedBox(height: ax.space.md),
        ],
      ];
      if (rows.isEmpty && svc.error != null) {
        children.add(
          ErrorState(
            title: 'Could not load this list',
            message: 'Your server did not answer. Check that the secure connection is on, then try again.',
            onRetry: svc.fetchAll,
          ),
        );
      } else if (rows.isEmpty) {
        final e = _emptyText();
        children.add(
          EmptyState(
            icon: e.icon,
            title: e.title,
            message: e.message,
            actionLabel: _tab == ServicesTab.scripts ? 'New script' : null,
            onAction: _tab == ServicesTab.scripts ? _newScript : null,
          ),
        );
      } else {
        children.add(_list(rows, wide));
      }
      body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
    }

    return AxPage(title: 'Services', subtitle: 'What is running on your server', scrollable: scroll, actions: actions, child: body);
  }

  Widget _list(List<DevRowModel> rows, bool wide) {
    final ax = context.ax;
    final c = ax.colors;
    Widget row(DevRowModel r) => ServiceRow(
      key: ValueKey('${_tab.name}:${r.name}'),
      name: r.name,
      details: rowDetails(r),
      badge: rowBadge(_tab, r),
      actions: _actionsFor(r),
      wide: wide,
      footer:
          _tab == ServicesTab.web && (_testing.contains(r.name) || _testResults.containsKey(r.name))
              ? TestResultLine(testing: _testing.contains(r.name), result: _testResults[r.name])
              : null,
    );
    if (wide) {
      return AxCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            ServiceTableHeader(detailsLabel: _tab == ServicesTab.web ? 'Goes to' : 'Details'),
            for (final r in rows) ...[Divider(height: 1, color: c.border), row(r)],
          ],
        ),
      );
    }
    return Column(children: [for (final r in rows) Padding(padding: EdgeInsets.only(bottom: ax.space.md), child: row(r))]);
  }
}
