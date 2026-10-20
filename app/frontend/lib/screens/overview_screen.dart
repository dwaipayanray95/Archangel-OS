import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/app_state.dart';
import '../models/system_metrics.dart';
import '../services/archangeld_connection.dart';
import '../services/containers_service.dart';
import '../services/devops_service.dart';
import '../services/monitoring_service.dart';
import '../services/update_check_service.dart';
import '../ui/screens/home/home_logic.dart';
import '../ui/ui.dart';
import '../ui/screens/settings/add_device_dialog.dart';

export '../ui/screens/home/home_logic.dart' show HealthLevel, HealthStatus, evaluateHealth, AttentionItem, buildAttentionItems;

/// Kept for callers that referenced the old constants.
const kStillNothingMessage = 'Still nothing from your server. Check the tunnel is connected (top bar) or open Settings.';
const kStaleAfter = Duration(seconds: 10);

/// Home: the health of the server in plain words, what needs attention, and
/// the things people most often want to do.
class OverviewScreen extends StatefulWidget {
  const OverviewScreen({super.key});

  @override
  State<OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenState extends State<OverviewScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final backend = context.read<ArchangeldConnection>();
      if (backend.isPaired) {
        context.read<MonitoringService>().start(backend);
        context.read<ContainersService>().init(backend);
        context.read<DevopsService>().init(backend);
      }
    });
  }

  void _retry() {
    final backend = context.read<ArchangeldConnection>();
    if (!backend.isPaired) return;
    context.read<MonitoringService>().start(backend);
    context.read<MonitoringService>().fetchSnapshot();
    context.read<ContainersService>().init(backend);
    context.read<DevopsService>().init(backend);
  }

  @override
  Widget build(BuildContext context) {
    final backend = context.watch<ArchangeldConnection>();
    final mon = context.watch<MonitoringService>();
    final app = context.read<AppState>();

    if (!backend.isPaired) {
      return AxPage(
        title: 'Home',
        child: EmptyState(
          icon: Icons.dns_outlined,
          title: 'No server connected yet',
          message: 'Set up or pair a server and its health will show up here.',
          actionLabel: 'Open Settings',
          onAction: () => app.go(AxSection.settings),
        ),
      );
    }

    final metrics = mon.metrics;
    if (metrics == null) {
      final failed = mon.status == MonitoringStatus.error || mon.status == MonitoringStatus.disconnected;
      return AxPage(
        title: 'Home',
        child:
            failed && mon.status != MonitoringStatus.connecting
                ? ErrorState(
                  title: "Can't reach your server",
                  message: 'Check that the secure connection is on and that the server is running, then try again.',
                  onRetry: _retry,
                  helpTitle: 'Why can\'t I reach it?',
                  helpText:
                      'Your devices talk to the server through a private "secure connection". If it is switched off, '
                      'or the server itself is turned off or restarting, nothing can load. Open Settings to check the connection.',
                )
                : LoadingState(message: 'Connecting to your server...', onRetry: _retry),
      );
    }

    final health = evaluateHealth(connected: mon.isConnected, metrics: metrics);
    final containers = context.watch<ContainersService>();
    final devops = context.watch<DevopsService>();
    final updates = context.watch<UpdateCheckService>();
    final attention = buildAttentionItems(
      containers: containers.overview?.dockerAvailable == true ? containers.overview!.containers : const [],
      services: devops.services,
      metrics: metrics,
      backendVersion: backend.backendVersion,
      latestBackend: updates.latestBackend,
    );

    final running = containers.overview?.dockerAvailable == true ? containers.overview!.containers.where((c) => c.running).length : null;
    final host = metrics.host.hostname;

    return AxPage(
      title: 'Home',
      subtitle: host.isNotEmpty ? host : null,
      child: LayoutBuilder(
        builder: (context, box) {
          final wide = box.maxWidth >= 760;
          final ax = context.ax;
          final attentionCard = _AttentionCard(items: attention, onOpen: (i) => app.go(i.target));
          const actionsCard = _QuickActions();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _HealthHero(health: health, running: running, attention: attention.length),
              SizedBox(height: ax.space.md),
              _MetricCards(metrics: metrics, uptimeKey: mon.lastPolled, onOpenActivity: () => app.go(AxSection.activity)),
              SizedBox(height: ax.space.md),
              if (wide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: attentionCard),
                    SizedBox(width: ax.space.md),
                    const Expanded(flex: 2, child: actionsCard),
                  ],
                )
              else ...[
                attentionCard,
                SizedBox(height: ax.space.md),
                actionsCard,
              ],
            ],
          );
        },
      ),
    );
  }
}

String _greeting(DateTime now) {
  final h = now.hour;
  return h < 12 ? 'Good morning' : (h < 17 ? 'Good afternoon' : 'Good evening');
}

/// The one plain-English sentence about the server, with a short follow-up
/// and a status pill (icon + words).
class _HealthHero extends StatelessWidget {
  const _HealthHero({required this.health, required this.running, required this.attention});
  final HealthStatus health;
  final int? running;
  final int attention;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final status = switch (health.level) {
      HealthLevel.healthy => AxStatus.ok,
      HealthLevel.warning => AxStatus.warning,
      HealthLevel.unreachable => AxStatus.error,
      HealthLevel.checking => AxStatus.neutral,
    };
    final apps = running == null ? null : (running == 1 ? '1 app is running.' : '$running apps are running.');
    final tail =
        attention == 0
            ? 'Nothing needs you right now.'
            : (attention == 1 ? 'One thing could use a look.' : '$attention things could use a look.');
    final detail = health.level == HealthLevel.healthy ? [if (apps != null) apps, tail].join(' ') : health.detail;
    return AxCard(
      semanticsLabel: 'Server health: ${health.headline}. $detail',
      padding: EdgeInsets.all(ax.space.lg + 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_greeting(DateTime.now()), style: ax.typo.caption.copyWith(color: c.textMuted, fontSize: 12.5)),
          SizedBox(height: ax.space.sm),
          Text(health.headline, style: ax.typo.display.copyWith(color: c.text)),
          SizedBox(height: ax.space.sm),
          Text(detail, style: ax.typo.body.copyWith(color: c.textMuted)),
          SizedBox(height: ax.space.md),
          StatusBadge(label: health.pill, status: status),
        ],
      ),
    );
  }
}

class _MetricCards extends StatelessWidget {
  const _MetricCards({required this.metrics, required this.uptimeKey, required this.onOpenActivity});
  final SystemMetrics metrics;
  final DateTime? uptimeKey;
  final VoidCallback onOpenActivity;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final cpu = metrics.cpu.usagePercent;
    final mem = metrics.memory;
    final disk = metrics.disk;
    final diskPct = worstDiskPercent(disk);

    final cards = <Widget>[
      _MetricCard(
        icon: Icons.memory,
        label: 'CPU',
        value: Text('${cpu.round()}%'),
        percent: cpu,
        note: usageBadgeLabel(cpu, high: 'Very busy', mid: 'Busy', ok: 'Calm'),
        status: usageStatus(cpu),
        onTap: onOpenActivity,
        semantics: 'CPU ${cpu.round()} percent busy',
      ),
      _MetricCard(
        icon: Icons.developer_board,
        label: 'Memory',
        value: Text('${gbText(mem.usedGb)} of ${gbText(mem.totalGb)} GB'),
        percent: mem.usagePercent,
        note: usageBadgeLabel(mem.usagePercent, high: 'Almost full', mid: 'Getting full', ok: 'Plenty free'),
        status: usageStatus(mem.usagePercent),
        onTap: onOpenActivity,
        semantics: 'Memory ${gbText(mem.usedGb)} of ${gbText(mem.totalGb)} gigabytes used',
      ),
      _MetricCard(
        icon: Icons.storage,
        label: 'Disk',
        value: Text('${diskPct.round()}% full'),
        percent: diskPct,
        note:
            disk.totalBytes > 0
                ? '${gbText(disk.freeGb)} GB free · ${usageBadgeLabel(diskPct, high: 'almost full', mid: 'getting full', ok: 'room to spare')}'
                : usageBadgeLabel(diskPct, high: 'Almost full', mid: 'Getting full', ok: 'Room to spare'),
        status: usageStatus(diskPct),
        onTap: onOpenActivity,
        semantics: 'Disk ${diskPct.round()} percent full',
      ),
      _MetricCard(
        icon: Icons.schedule,
        label: 'Uptime',
        value: UptimeText(uptimeSeconds: metrics.uptimeSeconds, receivedAt: uptimeKey),
        note: metrics.uptimeSeconds > 0 ? 'Since the last restart' : 'Unknown',
        status: metrics.uptimeSeconds > 0 ? AxStatus.ok : AxStatus.neutral,
        help: const HelpTip(
          title: 'Uptime',
          message:
              'How long the server has been running since it was last restarted. '
              'A long uptime is normal and usually a good sign.',
        ),
        semantics: 'Uptime',
      ),
    ];

    return LayoutBuilder(
      builder: (context, box) {
        final cols = box.maxWidth >= 720 ? 4 : (box.maxWidth >= 300 ? 2 : 1);
        final gap = ax.space.md;
        final w = (box.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(spacing: gap, runSpacing: gap, children: [for (final card in cards) SizedBox(width: w, child: card)]);
      },
    );
  }
}

/// A metric: label, a big monospace number, a usage bar and a one-word
/// note that always carries an icon (never colour alone).
class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.note,
    required this.status,
    required this.semantics,
    this.percent,
    this.onTap,
    this.help,
  });

  final IconData icon;
  final String label;
  final Widget value;
  final double? percent;
  final String note;
  final AxStatus status;
  final VoidCallback? onTap;
  final Widget? help;
  final String semantics;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final (Color tone, IconData? noteIcon) = switch (status) {
      AxStatus.ok => (c.textMuted, null),
      AxStatus.neutral => (c.textMuted, null),
      AxStatus.info => (c.info, Icons.info_outline),
      AxStatus.warning => (c.warning, Icons.warning_amber_rounded),
      AxStatus.error => (c.danger, Icons.error_outline),
    };
    final barColor = switch (status) {
      AxStatus.warning => c.warning,
      AxStatus.error => c.danger,
      _ => c.accent,
    };
    return AxCard(
      onTap: onTap,
      padding: EdgeInsets.all(ax.space.md + 2),
      semanticsLabel: onTap == null ? null : '$semantics. $note. Opens Activity.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: c.textMuted),
              SizedBox(width: ax.space.xs + 2),
              Expanded(child: Text(label, style: ax.typo.caption.copyWith(color: c.textMuted, fontSize: 12.5))),
              if (help != null) help!,
            ],
          ),
          SizedBox(height: ax.space.sm),
          DefaultTextStyle.merge(
            style: ax.typo.metric.copyWith(color: c.text, fontSize: 21),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            child: value,
          ),
          SizedBox(height: ax.space.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 5,
              child:
                  percent == null
                      ? const SizedBox.shrink()
                      : LinearProgressIndicator(value: (percent! / 100).clamp(0.0, 1.0), backgroundColor: c.border, color: barColor),
            ),
          ),
          SizedBox(height: ax.space.sm),
          Row(
            children: [
              if (noteIcon != null) ...[Icon(noteIcon, size: 13, color: tone), const SizedBox(width: 4)],
              Expanded(child: Text(note, maxLines: 1, overflow: TextOverflow.ellipsis, style: ax.typo.caption.copyWith(color: tone))),
            ],
          ),
        ],
      ),
    );
  }
}

/// The only ticking part of Home: counts uptime up once a second between
/// server readings. Rebuilds only itself.
class UptimeText extends StatefulWidget {
  const UptimeText({super.key, required this.uptimeSeconds, required this.receivedAt, this.style});
  final int uptimeSeconds;
  final DateTime? receivedAt;
  final TextStyle? style;

  @override
  State<UptimeText> createState() => _UptimeTextState();
}

class _UptimeTextState extends State<UptimeText> {
  Timer? _timer;
  late DateTime _base = widget.receivedAt ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(UptimeText old) {
    super.didUpdateWidget(old);
    if (old.uptimeSeconds != widget.uptimeSeconds || old.receivedAt != widget.receivedAt) {
      _base = widget.receivedAt ?? DateTime.now();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = widget.uptimeSeconds <= 0 ? 0 : DateTime.now().difference(_base).inSeconds.clamp(0, 86400);
    return Text(formatUptime(widget.uptimeSeconds + elapsed), style: widget.style);
  }
}

class _CardTitle extends StatelessWidget {
  const _CardTitle(this.text, {this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    return Padding(
      padding: EdgeInsets.fromLTRB(ax.space.lg, ax.space.md + 2, ax.space.md, ax.space.xs),
      child: Row(
        children: [
          Expanded(child: Semantics(header: true, child: Text(text, style: ax.typo.title.copyWith(color: ax.colors.text)))),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _AttentionCard extends StatelessWidget {
  const _AttentionCard({required this.items, required this.onOpen});
  final List<AttentionItem> items;
  final void Function(AttentionItem) onOpen;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    return AxCard(
      padding: EdgeInsets.only(bottom: ax.space.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CardTitle(
            'Needs attention',
            trailing:
                items.isEmpty
                    ? const StatusBadge.ok('All clear')
                    : StatusBadge.warning(items.length == 1 ? '1 to review' : '${items.length} to review'),
          ),
          if (items.isEmpty)
            Padding(
              padding: EdgeInsets.fromLTRB(ax.space.lg, ax.space.sm, ax.space.lg, ax.space.sm),
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline, color: c.success),
                  SizedBox(width: ax.space.md),
                  Expanded(child: Text('Nothing needs your attention right now.', style: ax.typo.body.copyWith(color: c.text))),
                ],
              ),
            )
          else
            for (final i in items)
              AxListTile(
                key: ValueKey(i.id),
                title: i.title,
                subtitle: i.detail,
                semanticsLabel: '${i.title}. ${i.detail} ${i.actionLabel}.',
                leading: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(color: _wash(c, i.status), borderRadius: BorderRadius.circular(ax.radii.sm + 2)),
                  child: Icon(StatusBadge.defaultIcon(i.status), size: 20, color: _statusColor(c, i.status)),
                ),
                trailing: Icon(Icons.chevron_right, color: c.textMuted),
                onTap: () => onOpen(i),
              ),
        ],
      ),
    );
  }

  Color _statusColor(AxPalette c, AxStatus s) => switch (s) {
    AxStatus.ok => c.success,
    AxStatus.warning => c.warning,
    AxStatus.error => c.danger,
    AxStatus.info => c.info,
    AxStatus.neutral => c.textMuted,
  };

  Color _wash(AxPalette c, AxStatus s) => switch (s) {
    AxStatus.ok => c.successWash,
    AxStatus.warning => c.warningWash,
    AxStatus.error => c.dangerWash,
    AxStatus.info => c.infoWash,
    AxStatus.neutral => c.surfaceHigh,
  };
}

class _QuickActions extends StatelessWidget {
  const _QuickActions();

  Future<void> _reboot(BuildContext context) async {
    final mon = context.read<MonitoringService>();
    final app = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showConfirmDialog(
      context,
      title: 'Reboot the server?',
      message:
          "Everything stops for about a minute; you'll reconnect automatically. "
          'Apps and services start again by themselves once the server is back.',
      confirmLabel: 'Reboot server',
      danger: true,
    );
    if (!ok) return;
    messenger.showSnackBar(const SnackBar(content: Text('Restarting your server...')));
    final res = await mon.rebootHost();
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(res.success ? 'Reboot started. Your server will be back in about a minute.' : res.message),
        action:
            !res.success && res.message.toLowerCase().contains('admin')
                ? SnackBarAction(label: 'Open Settings', onPressed: () => app.go(AxSection.settings))
                : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final ax = context.ax;
    final actions = <(IconData, String, VoidCallback, bool)>[
      (Icons.play_arrow_rounded, 'Run an app', () => app.go(AxSection.apps), false),
      (Icons.terminal_rounded, 'Open terminal', () => app.go(AxSection.terminal), false),
      (Icons.folder_outlined, 'Browse files', () => app.go(AxSection.files), false),
      (Icons.qr_code_2, 'Add a device', () => showAddDeviceDialog(context), false),
      (Icons.show_chart_rounded, 'See activity', () => app.go(AxSection.activity), false),
      (Icons.restart_alt_rounded, 'Reboot server', () => _reboot(context), true),
    ];
    return AxCard(
      padding: EdgeInsets.only(bottom: ax.space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _CardTitle('Quick actions'),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: ax.space.md),
            child: LayoutBuilder(
              builder: (context, box) {
                final cols = box.maxWidth >= 300 ? 2 : 1;
                final gap = ax.space.sm;
                final w = (box.maxWidth - gap * (cols - 1)) / cols;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final (icon, label, onTap, danger) in actions)
                      SizedBox(width: w, child: _ActionTile(icon: icon, label: label, onTap: onTap, danger: danger)),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.icon, required this.label, required this.onTap, this.danger = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final fg = danger ? c.danger : c.accent;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: c.glassStrong,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ax.radii.md), side: BorderSide(color: c.border)),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(ax.radii.md),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: axMinTarget(context) + 2),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: ax.space.md, vertical: ax.space.sm),
              child: Row(
                children: [
                  Icon(icon, size: 19, color: fg),
                  SizedBox(width: ax.space.sm + 2),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 2,
                      style: ax.typo.body.copyWith(color: danger ? c.danger : c.text, fontWeight: FontWeight.w500),
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
