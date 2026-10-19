import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/app_state.dart';
import '../models/system_metrics.dart';
import '../services/archangeld_connection.dart';
import '../services/containers_service.dart';
import '../services/devops_service.dart';
import '../services/monitoring_service.dart';
import '../services/wireguard_controller.dart';
import '../theme/tokens.dart';
import '../widgets/ax_widgets.dart';
import '../widgets/sparkline.dart';

/// Shown (instead of "Waiting for…") once 10 s pass without any data.
const kStillNothingMessage = 'Still nothing from your server. Check the tunnel is connected (top bar) or open Settings.';
const kStaleAfter = Duration(seconds: 10);

enum HealthLevel { unreachable, checking, warning, healthy }

class HealthStatus {
  final HealthLevel level;
  final List<String> problems;
  const HealthStatus(this.level, [this.problems = const []]);

  bool get isHealthy => level == HealthLevel.healthy;

  String get headline => switch (level) {
        HealthLevel.unreachable => "Can't reach your server",
        HealthLevel.checking => 'Waiting for the first reading…',
        HealthLevel.warning => problems.join(' · '),
        HealthLevel.healthy => 'All systems nominal',
      };

  String? get hint => level == HealthLevel.unreachable ? 'Check the tunnel is connected (top bar) or open Settings.' : null;

  String get pill => switch (level) {
        HealthLevel.unreachable => 'Offline',
        HealthLevel.checking => 'Connecting',
        HealthLevel.warning => 'Needs attention',
        HealthLevel.healthy => 'Healthy',
      };
}

/// Healthy only when connected AND CPU, memory and every disk are under 90%.
HealthStatus evaluateHealth({required bool connected, required SystemMetrics? metrics}) {
  if (!connected) return const HealthStatus(HealthLevel.unreachable);
  if (metrics == null) return const HealthStatus(HealthLevel.checking);
  const limit = 90.0;
  final problems = <String>[];
  if (metrics.cpu.usagePercent >= limit) {
    problems.add('CPU is ${metrics.cpu.usagePercent.round()}% busy');
  }
  if (metrics.memory.usagePercent >= limit) {
    problems.add('Memory is ${metrics.memory.usagePercent.round()}% used');
  }
  final mounts = metrics.disk.mounts;
  if (mounts.isEmpty) {
    if (metrics.disk.usagePercent >= limit) problems.add('Disk is ${metrics.disk.usagePercent.round()}% full');
  } else {
    for (final m in mounts) {
      if (m.totalBytes > 0 && m.usagePercent >= limit) {
        problems.add('Disk ${m.mountPoint} is ${m.usagePercent.round()}% full');
      }
    }
  }
  return problems.isEmpty ? const HealthStatus(HealthLevel.healthy) : HealthStatus(HealthLevel.warning, problems);
}

class _Tile {
  final String label;
  final String value;
  final String unit;
  final String sub;
  final String delta;
  final Color deltaColor;
  final Color color;
  final IconData icon;
  final List<double> spark;
  final AxSection go;
  const _Tile(this.label, this.value, this.unit, this.sub, this.delta, this.deltaColor, this.color, this.icon, this.spark, this.go);
}

List<_Tile> _buildTiles(SystemMetrics? metrics, {bool stale = false}) {
  if (metrics == null) {
    final sub = stale ? 'No data' : 'Waiting for telemetry…';
    return [
      _Tile('CPU', '—', '%', sub, '', AxColors.fg3, AxColors.accent, Icons.memory, [0.0], AxSection.monitoring),
      _Tile('MEMORY', '—', 'GB', sub, '', AxColors.fg3, AxColors.info, Icons.developer_board, [0.0], AxSection.monitoring),
      _Tile('DISK', '—', 'GB', sub, '', AxColors.fg3, AxColors.fg, Icons.storage, [0.0], AxSection.monitoring),
      _Tile('NETWORK', '—', 'MB/s', sub, '', AxColors.fg3, AxColors.accent, Icons.swap_vert, [0.0], AxSection.monitoring),
    ];
  }

  final cpu = metrics.cpu;
  final mem = metrics.memory;
  final disk = metrics.disk;
  final net = metrics.network;

  final cpuSpark = cpu.history.isEmpty
      ? [cpu.usagePercent / 100.0]
      : cpu.history.map((v) => (v / 100.0).clamp(0.0, 1.0)).toList();

  final memSpark = mem.history.isEmpty
      ? [mem.usagePercent / 100.0]
      : mem.history.map((v) => (v / 100.0).clamp(0.0, 1.0)).toList();

  final diskSpark = disk.history.isEmpty
      ? [disk.totalMbPerSec > 0 ? (disk.totalMbPerSec / 100.0).clamp(0.0, 1.0) : 0.05]
      : disk.history.map((v) => (v / 100.0).clamp(0.0, 1.0)).toList();

  final netSpark = net.history.isEmpty
      ? [net.totalMbPerSec > 0 ? (net.totalMbPerSec / 10.0).clamp(0.0, 1.0) : 0.05]
      : net.history.map((v) => (v / 10.0).clamp(0.0, 1.0)).toList();

  return [
    _Tile(
      'CPU',
      cpu.usagePercent.toStringAsFixed(0),
      '%',
      '${cpu.cores.length} cores · ${cpu.cores.isNotEmpty && cpu.cores.first.speedLabel.isNotEmpty ? cpu.cores.first.speedLabel : "active"}',
      '',
      AxColors.accent,
      AxColors.accent,
      Icons.memory,
      cpuSpark,
      AxSection.monitoring,
    ),
    _Tile(
      'MEMORY',
      mem.usedGb.toStringAsFixed(1),
      'GB',
      '${mem.usedGb.toStringAsFixed(1)} of ${mem.totalGb.toStringAsFixed(1)} GB (${mem.usagePercent.toStringAsFixed(0)}%)',
      '',
      AxColors.warn,
      AxColors.info,
      Icons.developer_board,
      memSpark,
      AxSection.monitoring,
    ),
    _Tile(
      'DISK',
      disk.usedGb.toStringAsFixed(0),
      'GB',
      '${disk.freeGb.toStringAsFixed(0)} GB free · ${disk.usedGb.toStringAsFixed(0)} GB used',
      '',
      AxColors.fg3,
      AxColors.fg,
      Icons.storage,
      diskSpark,
      AxSection.monitoring,
    ),
    _Tile(
      'NETWORK',
      net.totalMbPerSec.toStringAsFixed(1),
      'MB/s',
      '${net.rxMbPerSec.toStringAsFixed(1)} in · ${net.txMbPerSec.toStringAsFixed(1)} out',
      '',
      AxColors.fg3,
      AxColors.accent,
      Icons.swap_vert,
      netSpark,
      AxSection.monitoring,
    ),
  ];
}

class OverviewScreen extends StatefulWidget {
  const OverviewScreen({super.key});

  @override
  State<OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenState extends State<OverviewScreen> {
  Timer? _ticker;
  final DateTime _openedAt = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final backend = context.read<ArchangeldConnection>();
      if (backend.isPaired) {
        context.read<MonitoringService>().start(backend);
        context.read<ContainersService>().init(backend);
        context.read<DevopsService>().init(backend);
      }
    });
    // Trigger lightweight refresh every second to update "polled Xs ago" accurately
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _formatAgo(MonitoringService mon, HealthStatus health) {
    if (health.level == HealthLevel.unreachable) {
      return mon.status == MonitoringStatus.connecting ? 'Connecting to your server…' : "${health.headline} · ${health.hint}";
    }
    if (health.level == HealthLevel.checking) return health.headline;
    final lastPolled = mon.lastPolled;
    final ago = lastPolled == null
        ? 'live stream'
        : (DateTime.now().difference(lastPolled).inSeconds <= 1 ? 'polled just now' : 'polled ${DateTime.now().difference(lastPolled).inSeconds}s ago');
    return '${health.headline} · $ago';
  }

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final mon = context.watch<MonitoringService>();
    final metrics = mon.metrics;
    final isConnected = mon.isConnected;
    final wide = MediaQuery.of(context).size.width >= 760;
    final health = evaluateHealth(connected: isConnected, metrics: metrics);
    final connecting = mon.status == MonitoringStatus.connecting;
    final stale = metrics == null && DateTime.now().difference(_openedAt) > kStaleAfter;
    final pillColor = switch (health.level) {
      HealthLevel.healthy => AxColors.accent,
      HealthLevel.warning => AxColors.warn,
      HealthLevel.checking => AxColors.warn,
      HealthLevel.unreachable => connecting ? AxColors.warn : AxColors.fg3,
    };

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Overview', style: AxTextStyles.h1),
                    const SizedBox(height: 3),
                    Text(
                      _formatAgo(mon, health),
                      style: AxTextStyles.mutedMono,
                    ),
                  ],
                ),
              ),
              if (wide)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                  decoration: BoxDecoration(
                    color: health.isHealthy ? AxColors.wash : AxColors.s2,
                    borderRadius: BorderRadius.circular(AxRadius.pill),
                    border: Border.all(
                      color: health.isHealthy ? AxColors.accent.withValues(alpha: 0.18) : AxColors.line,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      StatusDot(
                        color: pillColor,
                        size: 6,
                        pulse: health.isHealthy,
                      ),
                      const SizedBox(width: 7),
                      Text(
                        connecting && !isConnected ? 'Connecting' : health.pill,
                        style: AxTextStyles.sans.copyWith(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: pillColor,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          if (stale) ...[
            const SizedBox(height: 12),
            Text(kStillNothingMessage, style: AxTextStyles.sans.copyWith(fontSize: 12.5, color: AxColors.warn, height: 1.4)),
          ],
          const SizedBox(height: 17),
          LayoutBuilder(
            builder: (context, c) {
              final cols = c.maxWidth >= 900 ? 4 : (c.maxWidth >= 560 ? 2 : 1);
              final tiles = _buildTiles(metrics, stale: stale);
              return GridView.count(
                crossAxisCount: cols,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 11,
                crossAxisSpacing: 11,
                childAspectRatio: 1.9,
                children: [for (final t in tiles) _StatTile(t: t, onTap: () => app.go(t.go))],
              );
            },
          ),
          const SizedBox(height: 13),
          LayoutBuilder(
            builder: (context, c) {
              final narrow = c.maxWidth < 860;
              final feed = const _ActivityFeed();
              final side = const _IdentityAndActions();
              if (narrow) {
                return Column(children: [feed, const SizedBox(height: 11), side]);
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: feed),
                  const SizedBox(width: 11),
                  Expanded(flex: 2, child: side),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final _Tile t;
  final VoidCallback onTap;
  const _StatTile({required this.t, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return AxCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(t.icon, size: 14, color: AxColors.fg3),
              const SizedBox(width: 7),
              Text(t.label, style: AxTextStyles.label),
              const Spacer(),
              if (t.delta.isNotEmpty) Text(t.delta, style: AxTextStyles.mono.copyWith(fontSize: 10, color: t.deltaColor)),
            ],
          ),
          const SizedBox(height: 9),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(t.value, style: AxTextStyles.mono.copyWith(fontSize: 26, fontWeight: FontWeight.w500, letterSpacing: -0.4, color: t.color)),
              const SizedBox(width: 4),
              Text(t.unit, style: AxTextStyles.mono.copyWith(fontSize: 11, color: AxColors.fg3)),
            ],
          ),
          Text(t.sub, style: AxTextStyles.sans.copyWith(fontSize: 11, color: AxColors.fg2)),
          const SizedBox(height: 8),
          Expanded(child: Sparkline(values: t.spark, color: t.color)),
        ],
      ),
    );
  }
}

class _ActivityItem {
  final String actor;
  final String text;
  final String detail;
  final Color color;
  final String ago;
  final VoidCallback? onTap;

  const _ActivityItem({
    required this.actor,
    required this.text,
    required this.detail,
    required this.color,
    required this.ago,
    this.onTap,
  });
}

class _ActivityFeed extends StatelessWidget {
  const _ActivityFeed();

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final contSvc = context.watch<ContainersService>();
    final devSvc = context.watch<DevopsService>();
    final monSvc = context.watch<MonitoringService>();

    final items = <_ActivityItem>[];

    // Build real items from containers
    final containers = contSvc.overview?.containers ?? [];
    for (final c in containers.take(4)) {
      items.add(_ActivityItem(
        actor: c.name,
        text: c.running ? 'running' : 'stopped',
        detail: '${c.image} · ${c.uptime.isNotEmpty ? c.uptime : (c.running ? "active" : "inactive")}',
        color: c.running ? AxColors.accent : AxColors.warn,
        ago: c.ports.isNotEmpty && c.ports != '—' ? c.ports : (c.running ? 'live' : 'idle'),
        onTap: () => app.go(AxSection.containers),
      ));
    }

    // Build real items from devops services and deployments
    for (final s in devSvc.services.take(3)) {
      items.add(_ActivityItem(
        actor: s.name,
        text: s.status,
        detail: s.meta,
        color: s.ok ? AxColors.accent : AxColors.bad,
        ago: s.ok ? 'active' : 'warn',
        onTap: () => app.go(AxSection.devops),
      ));
    }

    for (final d in devSvc.deployments.take(2)) {
      items.add(_ActivityItem(
        actor: d.name,
        text: d.status,
        detail: d.meta,
        color: d.ok ? AxColors.info : AxColors.bad,
        ago: 'deploy',
        onTap: () => app.go(AxSection.devops),
      ));
    }

    // Fallback if no containers or services loaded yet
    if (items.isEmpty) {
      if (monSvc.isConnected) {
        items.add(_ActivityItem(
          actor: 'archangeld',
          text: 'metrics connected',
          detail: 'real-time telemetry link established',
          color: AxColors.accent,
          ago: 'live',
          onTap: () => app.go(AxSection.monitoring),
        ));
      } else {
        items.add(const _ActivityItem(
          actor: 'system',
          text: 'initializing services',
          detail: 'connecting to host background daemons',
          color: AxColors.fg3,
          ago: '—',
        ));
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: AxColors.s1,
        borderRadius: BorderRadius.circular(AxRadius.xl),
        border: Border.all(color: AxColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AxColors.line))),
            child: Row(
              children: [
                Text('Activity', style: AxTextStyles.sans.copyWith(fontSize: 12.5, fontWeight: FontWeight.w700)),
                const Spacer(),
                StatusDot(color: AxColors.accent, size: 5, pulse: monSvc.isConnected),
                const SizedBox(width: 5),
                Text('live', style: AxTextStyles.mono.copyWith(fontSize: 10, color: AxColors.fg3)),
              ],
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 420),
            child: ListView.builder(
              shrinkWrap: true,
              physics: const ClampingScrollPhysics(),
              itemCount: items.length,
              itemBuilder: (context, i) {
                final f = items[i];
                return InkWell(
                  onTap: f.onTap,
                  hoverColor: AxColors.s2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0x0BE8F0E6)))),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: Container(width: 6, height: 6, decoration: BoxDecoration(color: f.color, shape: BoxShape.circle)),
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              RichText(
                                text: TextSpan(
                                  style: AxTextStyles.sans.copyWith(fontSize: 12.5, height: 1.4),
                                  children: [
                                    TextSpan(text: '${f.actor} ', style: const TextStyle(fontWeight: FontWeight.w600)),
                                    TextSpan(text: f.text, style: const TextStyle(color: AxColors.fg2)),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(f.detail, style: AxTextStyles.mono.copyWith(fontSize: 10, color: AxColors.fg3), maxLines: 1, overflow: TextOverflow.ellipsis),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(f.ago, style: AxTextStyles.mono.copyWith(fontSize: 10, color: AxColors.fg3)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _IdentityAndActions extends StatelessWidget {
  const _IdentityAndActions();

  void _confirmReboot(BuildContext context) {
    final mon = context.read<MonitoringService>();

    showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          backgroundColor: AxColors.s1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AxRadius.lg),
            side: const BorderSide(color: AxColors.line),
          ),
          title: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: AxColors.warn, size: 22),
              const SizedBox(width: 8),
              Text('Reboot Host', style: AxTextStyles.sans.copyWith(fontSize: 16, fontWeight: FontWeight.w600)),
            ],
          ),
          content: Text(
            'Are you sure you want to reboot the remote server?\n\nActive connections and background tasks will be interrupted until the host boots back up.',
            style: AxTextStyles.sans.copyWith(fontSize: 13, color: AxColors.fg2, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: Text('Cancel', style: AxTextStyles.sans.copyWith(color: AxColors.fg3)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AxColors.bad,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AxRadius.sm)),
              ),
              onPressed: () async {
                Navigator.of(dialogCtx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Issuing reboot signal to server...')),
                );
                final res = await mon.rebootHost();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: res.success ? AxColors.s2 : AxColors.bad,
                      content: Text(
                        res.message,
                        style: TextStyle(color: res.success ? AxColors.accent : Colors.white),
                      ),
                    ),
                  );
                }
              },
              child: const Text('Reboot Server'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final backend = context.watch<ArchangeldConnection>();
    final wg = context.watch<WireGuardController>();
    final mon = context.watch<MonitoringService>();
    final metrics = mon.metrics;

    final hostname = (metrics?.host.hostname.isNotEmpty ?? false)
        ? metrics!.host.hostname
        : (backend.host?.isNotEmpty ?? false ? backend.host! : '—');

    final os = (metrics?.host.os.isNotEmpty ?? false)
        ? metrics!.host.os
        : '—';

    final kernel = (metrics?.host.kernel.isNotEmpty ?? false)
        ? metrics!.host.kernel
        : (metrics?.host.arch.isNotEmpty ?? false ? metrics!.host.arch : '—');

    final tunnelStatusText = wg.config != null
        ? '${wg.status.name} · ${wg.config!.interfaceAddress}'
        : 'disconnected';

    final uptime = metrics != null ? metrics.detailedUptimeLabel : '—';

    final identity = [
      ['Host', hostname],
      ['OS', os],
      ['Kernel', kernel],
      ['Tunnel', tunnelStatusText],
      ['Uptime', uptime],
      ['Backend', backend.backendVersion ?? '—'],
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AxCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.only(bottom: 11),
                margin: const EdgeInsets.only(bottom: 3),
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AxColors.line))),
                child: Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(color: AxColors.wash, borderRadius: BorderRadius.circular(10)),
                      child: const Icon(Icons.dns_outlined, size: 15, color: AxColors.accent),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(hostname, style: AxTextStyles.mono.copyWith(fontSize: 13, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
                          Text(
                            wg.config != null ? 'wireguard endpoint · ${wg.config!.serverAddress}' : 'remote host',
                            style: AxTextStyles.sans.copyWith(fontSize: 11, color: AxColors.fg3),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              for (final row in identity)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0x0BE8F0E6)))),
                  child: Row(
                    children: [
                      SizedBox(width: 78, child: Text(row[0], style: AxTextStyles.sans.copyWith(fontSize: 11, color: AxColors.fg3))),
                      Expanded(child: Text(row[1], style: AxTextStyles.mono.copyWith(fontSize: 11.5), overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 11),
        AxCard(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('QUICK ACTIONS', style: AxTextStyles.sans.copyWith(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1, color: AxColors.fg3)),
              const SizedBox(height: 9),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 7,
                crossAxisSpacing: 7,
                childAspectRatio: 2.6,
                children: [
                  _ActionButton(
                    label: 'Terminal',
                    icon: Icons.terminal_rounded,
                    color: AxColors.fg,
                    onTap: () => app.go(AxSection.terminal),
                  ),
                  _ActionButton(
                    label: 'DevOps',
                    icon: Icons.layers_outlined,
                    color: AxColors.fg,
                    onTap: () => app.go(AxSection.devops),
                  ),
                  _ActionButton(
                    label: 'Files',
                    icon: Icons.folder_outlined,
                    color: AxColors.fg,
                    onTap: () => app.go(AxSection.files),
                  ),
                  _ActionButton(
                    label: 'Reboot',
                    icon: Icons.restart_alt_rounded,
                    color: AxColors.warn,
                    onTap: () => _confirmReboot(context),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AxColors.s2,
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: AxColors.line),
          ),
          child: Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 8),
              Text(
                label,
                style: AxTextStyles.sans.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

