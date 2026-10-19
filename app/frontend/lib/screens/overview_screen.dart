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
import '../widgets/sparkline.dart';

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
        child: failed && mon.status != MonitoringStatus.connecting
            ? ErrorState(
                title: "Can't reach your server",
                message: 'Check that the secure connection is on and that the server is running, then try again.',
                onRetry: _retry,
                helpTitle: 'Why can\'t I reach it?',
                helpText: 'Your devices talk to the server through a private "secure connection". If it is switched off, '
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

    return AxPage(
      title: 'Home',
      subtitle: metrics.host.hostname.isNotEmpty ? metrics.host.hostname : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _HealthHero(health: health),
          SizedBox(height: context.ax.space.lg),
          _MetricCards(metrics: metrics, uptimeKey: mon.lastPolled, onOpenActivity: () => app.go(AxSection.activity)),
          SizedBox(height: context.ax.space.xl),
          _SectionTitle('Needs attention'),
          _AttentionList(items: attention, onOpen: (i) => app.go(i.target)),
          SizedBox(height: context.ax.space.xl),
          _SectionTitle('Quick actions'),
          const _QuickActions(),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    return Padding(
      padding: EdgeInsets.only(bottom: ax.space.sm),
      child: Semantics(header: true, child: Text(text, style: ax.typo.title.copyWith(color: ax.colors.text))),
    );
  }
}

class _HealthHero extends StatelessWidget {
  const _HealthHero({required this.health});
  final HealthStatus health;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final (IconData icon, Color color, AxStatus status) = switch (health.level) {
      HealthLevel.healthy => (Icons.check_circle_outline, c.success, AxStatus.ok),
      HealthLevel.warning => (Icons.warning_amber_rounded, c.warning, AxStatus.warning),
      HealthLevel.unreachable => (Icons.cloud_off_outlined, c.danger, AxStatus.error),
      HealthLevel.checking => (Icons.hourglass_empty, c.textMuted, AxStatus.neutral),
    };
    return AxCard(
      semanticsLabel: 'Server health: ${health.headline}',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 40, color: color),
          SizedBox(width: ax.space.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(health.headline, style: ax.typo.headline.copyWith(color: c.text)),
                SizedBox(height: ax.space.xs),
                Text(health.detail, style: ax.typo.body.copyWith(color: c.textMuted)),
                SizedBox(height: ax.space.sm),
                StatusBadge(label: health.pill, status: status),
              ],
            ),
          ),
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
    final c = ax.colors;
    final cpu = metrics.cpu.usagePercent;
    final mem = metrics.memory;
    final disk = metrics.disk;
    final diskPct = worstDiskPercent(disk);

    List<double> norm(List<double> h, double now) =>
        h.isEmpty ? [now / 100, now / 100] : h.map((v) => (v / 100).clamp(0.0, 1.0)).toList();

    final cards = <Widget>[
      _MetricCard(
        icon: Icons.memory,
        label: 'CPU',
        value: '${cpu.round()}%',
        detail: metrics.cpu.cores.isEmpty ? 'How hard the processor is working' : 'Processor, ${metrics.cpu.cores.length} cores',
        badge: StatusBadge(label: usageBadgeLabel(cpu, high: 'Very busy', mid: 'Busy', ok: 'Fine'), status: usageStatus(cpu)),
        spark: norm(metrics.cpu.history, cpu),
        sparkColor: c.accent,
        onTap: onOpenActivity,
        semantics: 'CPU ${cpu.round()} percent busy',
      ),
      _MetricCard(
        icon: Icons.developer_board,
        label: 'Memory',
        value: '${gbText(mem.usedGb)} of ${gbText(mem.totalGb)} GB',
        detail: 'Memory in use (${mem.usagePercent.round()}%)',
        badge: StatusBadge(
            label: usageBadgeLabel(mem.usagePercent, high: 'Almost full', mid: 'Getting full', ok: 'Fine'),
            status: usageStatus(mem.usagePercent)),
        spark: norm(mem.history, mem.usagePercent),
        sparkColor: c.info,
        onTap: onOpenActivity,
        semantics: 'Memory ${gbText(mem.usedGb)} of ${gbText(mem.totalGb)} gigabytes used',
      ),
      _MetricCard(
        icon: Icons.storage,
        label: 'Disk',
        value: '${diskPct.round()}% full',
        detail: disk.totalBytes > 0 ? '${gbText(disk.freeGb)} GB free of ${gbText(disk.totalGb)} GB' : 'Storage space',
        badge: StatusBadge(
            label: usageBadgeLabel(diskPct, high: 'Almost full', mid: 'Getting full', ok: 'Plenty of space'),
            status: usageStatus(diskPct)),
        spark: null,
        sparkColor: c.accent,
        onTap: onOpenActivity,
        semantics: 'Disk ${diskPct.round()} percent full',
      ),
      _UptimeCard(uptimeSeconds: metrics.uptimeSeconds, receivedAt: uptimeKey),
    ];

    return LayoutBuilder(builder: (context, box) {
      final cols = box.maxWidth >= 900 ? 4 : (box.maxWidth >= 560 ? 2 : 1);
      final gap = ax.space.md;
      final w = (box.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [for (final card in cards) SizedBox(width: w, child: card)],
      );
    });
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.detail,
    required this.badge,
    required this.spark,
    required this.sparkColor,
    required this.onTap,
    required this.semantics,
  });

  final IconData icon;
  final String label;
  final String value;
  final String detail;
  final Widget badge;
  final List<double>? spark;
  final Color sparkColor;
  final VoidCallback onTap;
  final String semantics;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    return AxCard(
      onTap: onTap,
      semanticsLabel: '$semantics. Opens Activity.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: c.textMuted),
              SizedBox(width: ax.space.sm),
              Expanded(child: Text(label, style: ax.typo.label.copyWith(color: c.textMuted))),
            ],
          ),
          SizedBox(height: ax.space.sm),
          Text(value, style: ax.typo.headline.copyWith(color: c.text)),
          Text(detail, style: ax.typo.caption.copyWith(color: c.textMuted)),
          SizedBox(height: ax.space.sm),
          badge,
          if (spark != null) ...[
            SizedBox(height: ax.space.md),
            SizedBox(height: 36, child: Sparkline(values: spark!, color: sparkColor)),
          ],
        ],
      ),
    );
  }
}

class _UptimeCard extends StatelessWidget {
  const _UptimeCard({required this.uptimeSeconds, required this.receivedAt});
  final int uptimeSeconds;
  final DateTime? receivedAt;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    return AxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.schedule, size: 18, color: c.textMuted),
              SizedBox(width: ax.space.sm),
              Expanded(child: Text('Uptime', style: ax.typo.label.copyWith(color: c.textMuted))),
              const HelpTip(
                title: 'Uptime',
                message: 'How long the server has been running since it was last restarted. '
                    'A long uptime is normal and usually a good sign.',
              ),
            ],
          ),
          SizedBox(height: ax.space.sm),
          UptimeText(uptimeSeconds: uptimeSeconds, receivedAt: receivedAt, style: ax.typo.headline.copyWith(color: c.text)),
          Text('Running since the last restart', style: ax.typo.caption.copyWith(color: c.textMuted)),
          SizedBox(height: ax.space.sm),
          uptimeSeconds > 0 ? const StatusBadge.ok('Up and running') : const StatusBadge.neutral('Unknown'),
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

class _AttentionList extends StatelessWidget {
  const _AttentionList({required this.items, required this.onOpen});
  final List<AttentionItem> items;
  final void Function(AttentionItem) onOpen;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    if (items.isEmpty) {
      return AxCard(
        child: Row(
          children: [
            Icon(Icons.check_circle_outline, color: c.success),
            SizedBox(width: ax.space.md),
            Expanded(child: Text('Nothing needs your attention right now.', style: ax.typo.body.copyWith(color: c.text))),
          ],
        ),
      );
    }
    return AxCard(
      padding: EdgeInsets.symmetric(vertical: ax.space.xs),
      child: Column(
        children: [
          for (final i in items)
            AxListTile(
              key: ValueKey(i.id),
              title: i.title,
              subtitle: i.detail,
              semanticsLabel: '${i.title}. ${i.detail} ${i.actionLabel}.',
              leading: Icon(StatusBadge.defaultIcon(i.status), color: _statusColor(c, i.status)),
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
      message: "Everything stops for about a minute; you'll reconnect automatically. "
          'Apps and services start again by themselves once the server is back.',
      confirmLabel: 'Reboot server',
      danger: true,
    );
    if (!ok) return;
    messenger.showSnackBar(const SnackBar(content: Text('Restarting your server...')));
    final res = await mon.rebootHost();
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text(res.success ? 'Reboot started. Your server will be back in about a minute.' : res.message),
      action: !res.success && res.message.toLowerCase().contains('admin')
          ? SnackBarAction(label: 'Open Settings', onPressed: () => app.go(AxSection.settings))
          : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final ax = context.ax;
    return Wrap(
      spacing: ax.space.md,
      runSpacing: ax.space.md,
      children: [
        AxButton.secondary(label: 'Open terminal', icon: Icons.terminal_rounded, onPressed: () => app.go(AxSection.terminal)),
        AxButton.secondary(label: 'Run an app', icon: Icons.apps_rounded, onPressed: () => app.go(AxSection.apps)),
        AxButton.secondary(label: 'Browse files', icon: Icons.folder_outlined, onPressed: () => app.go(AxSection.files)),
        AxButton.danger(label: 'Reboot server', icon: Icons.restart_alt_rounded, onPressed: () => _reboot(context)),
      ],
    );
  }
}
