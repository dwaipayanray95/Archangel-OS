import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/system_metrics.dart';
import '../services/archangeld_connection.dart';
import '../services/monitoring_service.dart';
import '../theme/tokens.dart';
import '../widgets/ax_widgets.dart';
import '../widgets/sparkline.dart';
import 'overview_screen.dart' show kStaleAfter, kStillNothingMessage;

enum _MonTab { cpu, memory, disk, network, processes }

class MonitoringScreen extends StatefulWidget {
  const MonitoringScreen({super.key});

  @override
  State<MonitoringScreen> createState() => _MonitoringScreenState();
}

class _MonitoringScreenState extends State<MonitoringScreen> {
  _MonTab _tab = _MonTab.cpu;
  String _procQuery = '';
  final DateTime _openedAt = DateTime.now();
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final backend = context.read<ArchangeldConnection>();
      context.read<MonitoringService>().start(backend);
    });
    // Re-render so the "still nothing" message can appear after 10 s.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && context.read<MonitoringService>().metrics == null) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mon = context.watch<MonitoringService>();
    final metrics = mon.metrics;
    final stale = metrics == null && DateTime.now().difference(_openedAt) > kStaleAfter;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Monitoring', style: AxTextStyles.h1),
              const Spacer(),
              if (mon.isConnected)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: AxColors.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AxRadius.pill),
                    border: Border.all(color: AxColors.accent.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const StatusDot(color: AxColors.accent, size: 5),
                      const SizedBox(width: 6),
                      Text('LIVE ${(mon.pollingRateMs / 1000.0).toStringAsFixed(mon.pollingRateMs % 1000 == 0 ? 0 : 1)}s', style: AxTextStyles.mono.copyWith(fontSize: 10.5, color: AxColors.accent)),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            mon.isConnected
                ? 'archangeld · streaming live over WireGuard'
                : (mon.status == MonitoringStatus.connecting ? 'Connecting to your server…' : "Can't reach your server"),
            style: AxTextStyles.mutedMono,
          ),
          if (metrics == null) ...[
            const SizedBox(height: 6),
            Text(
              stale ? kStillNothingMessage : 'Waiting for telemetry…',
              style: AxTextStyles.sans.copyWith(fontSize: 12.5, color: stale ? AxColors.warn : AxColors.fg3, height: 1.4),
            ),
          ],
          const SizedBox(height: 15),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              AxSegmented<_MonTab>(
                values: _MonTab.values,
                selected: _tab,
                label: (t) => switch (t) {
                  _MonTab.cpu => 'CPU',
                  _MonTab.memory => 'Memory',
                  _MonTab.disk => 'Disk',
                  _MonTab.network => 'Network',
                  _MonTab.processes => 'Processes',
                },
                onSelect: (t) => setState(() => _tab = t),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_tab == _MonTab.processes)
            _ProcessTable(
              query: _procQuery,
              onQuery: (v) => setState(() => _procQuery = v),
              liveProcs: mon.processes,
              totalCount: mon.totalProcesses,
            )
          else
            _ChartCard(
              tab: _tab,
              metrics: metrics,
            ),
        ],
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  final _MonTab tab;
  final SystemMetrics? metrics;
  const _ChartCard({required this.tab, this.metrics});

  @override
  Widget build(BuildContext context) {
    final (title, now, unit, values, stats, breakdown) = switch (tab) {
      _MonTab.cpu => _buildCpuData(metrics?.cpu),
      _MonTab.memory => _buildMemoryData(metrics?.memory),
      _MonTab.disk => _buildDiskData(metrics?.disk),
      _MonTab.network => _buildNetworkData(metrics?.network),
      _MonTab.processes => ('', '', '', <double>[], <List<String>>[], <List<dynamic>>[]),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AxCard(
          padding: const EdgeInsets.fromLTRB(15, 14, 15, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: AxTextStyles.sans.copyWith(fontSize: 12.5, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 3),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(now, style: AxTextStyles.mono.copyWith(fontSize: 25, fontWeight: FontWeight.w500, color: AxColors.accent)),
                            const SizedBox(width: 6),
                            Text(unit, style: AxTextStyles.mono.copyWith(fontSize: 11.5, color: AxColors.fg3)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  for (final s in stats)
                    Padding(
                      padding: const EdgeInsets.only(left: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(s[0], style: AxTextStyles.label),
                          const SizedBox(height: 2),
                          Text(s[1], style: AxTextStyles.mono.copyWith(fontSize: 13, fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(height: 150, child: Sparkline(values: values, color: AxColors.accent)),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [Text('Live (since you opened this screen)', style: AxTextStyles.mono.copyWith(fontSize: 9.5, color: AxColors.fg3))],
              ),
            ],
          ),
        ),
        const SizedBox(height: 11),
        if (tab == _MonTab.memory && metrics?.memory != null)
          _buildMemoryUnifiedCard(metrics!.memory)
        else
          LayoutBuilder(
            builder: (context, c) {
              final cols = c.maxWidth >= 700 ? 4 : 2;
              return GridView.count(
                crossAxisCount: cols,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 11,
                crossAxisSpacing: 11,
                childAspectRatio: 2.6,
                children: [
                  for (final b in breakdown)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
                      decoration: BoxDecoration(color: AxColors.s1, borderRadius: BorderRadius.circular(13), border: Border.all(color: AxColors.line)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(b[0] as String, style: AxTextStyles.mono.copyWith(fontSize: 11, color: AxColors.fg2)),
                              if (b.length > 3 && (b[3] as String).isNotEmpty)
                                Text(b[3] as String, style: AxTextStyles.mono.copyWith(fontSize: 10, color: AxColors.fg3)),
                              Text('${((b[1] as double) * 100).round()}%', style: AxTextStyles.mono.copyWith(fontSize: 12, fontWeight: FontWeight.w500)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          AxMeter(value: (b[1] as double).clamp(0.0, 1.0), color: b[2] as Color),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }

  Widget _buildMemoryUnifiedCard(MemoryMetrics mem) {
    final total = mem.totalGb > 0 ? mem.totalGb : 1.0;
    final appRatio = (mem.appUsedGb / total).clamp(0.0, 1.0);
    final cacheRatio = (mem.cachedGb / total).clamp(0.0, 1.0);
    final freeRatio = (mem.freeGb / total).clamp(0.0, 1.0);
    final swapTotal = mem.swapTotalGb > 0 ? mem.swapTotalGb : 1.0;
    final swapRatio = (mem.swapUsedGb / swapTotal).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: AxColors.s1,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: AxColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('PHYSICAL RAM DISTRIBUTION', style: AxTextStyles.label),
              Text('${mem.totalGb.toStringAsFixed(1)} GB TOTAL', style: AxTextStyles.mono.copyWith(fontSize: 11, color: AxColors.fg3)),
            ],
          ),
          const SizedBox(height: 12),
          AxSegmentMeter(
            height: 10,
            segments: [
              (appRatio, AxColors.accent),
              (cacheRatio, AxColors.info),
              (freeRatio, AxColors.fg3.withValues(alpha: 0.35)),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 20,
            runSpacing: 10,
            children: [
              _buildMemLegend('Apps & System', '${mem.appUsedGb.toStringAsFixed(1)} GB (${(appRatio * 100).round()}%)', AxColors.accent),
              _buildMemLegend('Cache & Buffers', '${mem.cachedGb.toStringAsFixed(1)} GB (${(cacheRatio * 100).round()}%)', AxColors.info),
              _buildMemLegend('Free Memory', '${mem.freeGb.toStringAsFixed(1)} GB (${(freeRatio * 100).round()}%)', AxColors.fg3.withValues(alpha: 0.7)),
              if (mem.swapTotalGb > 0)
                _buildMemLegend('Swap Used', '${mem.swapUsedGb.toStringAsFixed(1)} / ${mem.swapTotalGb.toStringAsFixed(1)} GB (${(swapRatio * 100).round()}%)', AxColors.warn),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMemLegend(String title, String value, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(title, style: AxTextStyles.mono.copyWith(fontSize: 11, color: AxColors.fg2)),
        const SizedBox(width: 5),
        Text(value, style: AxTextStyles.mono.copyWith(fontSize: 11, fontWeight: FontWeight.w600, color: AxColors.fg)),
      ],
    );
  }

  (String, String, String, List<double>, List<List<String>>, List<List<dynamic>>) _buildCpuData(CPUMetrics? cpu) {
    if (cpu == null) {
      return (
        'CPU utilization', '—', '%',
        const [0.0],
        const [['MIN', '—'], ['AVG', '—'], ['MAX', '—']],
        const <List<dynamic>>[],
      );
    }

    final hist = cpu.history.isEmpty
        ? [cpu.usagePercent / 100.0]
        : cpu.history.map((v) => (v / 100.0).clamp(0.0, 1.0)).toList();

    final minVal = (cpu.history.isEmpty ? cpu.usagePercent : cpu.history.reduce((a, b) => a < b ? a : b)).round();
    final maxVal = (cpu.history.isEmpty ? cpu.usagePercent : cpu.history.reduce((a, b) => a > b ? a : b)).round();
    final avgVal = cpu.history.isEmpty ? cpu.usagePercent.round() : (cpu.history.reduce((a, b) => a + b) / cpu.history.length).round();

    final breakdown = cpu.cores.map((c) {
      final ratio = (c.usagePercent / 100.0).clamp(0.0, 1.0);
      final col = ratio > 0.8 ? AxColors.bad : (ratio > 0.4 ? AxColors.warn : AxColors.accent);
      return ['core ${c.id}', ratio, col, c.speedLabel];
    }).toList();

    return (
      'CPU utilization',
      cpu.usagePercent.toStringAsFixed(1),
      '%',
      hist,
      [['MIN', '$minVal%'], ['AVG', '$avgVal%'], ['MAX', '$maxVal%']],
      breakdown,
    );
  }

  (String, String, String, List<double>, List<List<String>>, List<List<dynamic>>) _buildMemoryData(MemoryMetrics? mem) {
    if (mem == null) {
      return (
        'Memory usage', '—', 'GB',
        const [0.0],
        const [['TOTAL', '—'], ['AVAIL', '—'], ['SWAP', '—']],
        const <List<dynamic>>[],
      );
    }

    final hist = mem.history.isEmpty
        ? [mem.usagePercent / 100.0]
        : mem.history.map((v) => (v / 100.0).clamp(0.0, 1.0)).toList();

    final total = mem.totalGb > 0 ? mem.totalGb : 1.0;
    final appRatio = (mem.appUsedGb / total).clamp(0.0, 1.0);
    final cacheRatio = (mem.cachedGb / total).clamp(0.0, 1.0);
    final freeRatio = (mem.freeGb / total).clamp(0.0, 1.0);
    final swapTotal = mem.swapTotalGb > 0 ? mem.swapTotalGb : 1.0;
    final swapRatio = (mem.swapUsedGb / swapTotal).clamp(0.0, 1.0);

    final breakdown = [
      ['Apps & System', appRatio, AxColors.accent, '${mem.appUsedGb.toStringAsFixed(1)} GB'],
      ['Cache & Buffers', cacheRatio, AxColors.info, '${mem.cachedGb.toStringAsFixed(1)} GB'],
      ['Free', freeRatio, AxColors.fg3, '${mem.freeGb.toStringAsFixed(1)} GB'],
      ['Swap', swapRatio, AxColors.warn, '${mem.swapUsedGb.toStringAsFixed(1)} / ${mem.swapTotalGb.toStringAsFixed(1)} GB'],
    ];

    return (
      'Memory usage',
      mem.usedGb.toStringAsFixed(1),
      'GB',
      hist,
      [
        ['TOTAL', '${mem.totalGb.toStringAsFixed(1)} GB'],
        ['USED', '${mem.usedGb.toStringAsFixed(1)} GB (${mem.usagePercent.round()}%)'],
        ['AVAIL', '${mem.availableGb.toStringAsFixed(1)} GB'],
      ],
      breakdown,
    );
  }

  (String, String, String, List<double>, List<List<String>>, List<List<dynamic>>) _buildDiskData(DiskMetrics? disk) {
    if (disk == null) {
      return (
        'Disk throughput', '—', 'MB/s',
        const [0.0],
        const [['MIN', '—'], ['AVG', '—'], ['MAX', '—']],
        const <List<dynamic>>[],
      );
    }

    final hist = disk.history.isEmpty
        ? [disk.totalMbPerSec > 0 ? (disk.totalMbPerSec / 100.0).clamp(0.0, 1.0) : 0.05]
        : disk.history.map((v) => (v / 100.0).clamp(0.0, 1.0)).toList();

    final breakdown = disk.mounts.map((m) {
      final r = (m.usagePercent / 100.0).clamp(0.0, 1.0);
      return [
        m.mountPoint,
        r,
        r > 0.85 ? AxColors.bad : AxColors.accent,
        '${m.availableGb.toStringAsFixed(0)} GB avail · ${m.usedGb.toStringAsFixed(0)} GB used',
      ];
    }).toList();

    return (
      'Disk throughput',
      disk.totalMbPerSec.toStringAsFixed(1),
      'MB/s',
      hist,
      [
        ['USED', '${disk.usedGb.toStringAsFixed(0)} GB (${disk.usagePercent.round()}%)'],
        ['AVAIL', '${disk.availableGb.toStringAsFixed(0)} GB'],
        ['FREE', '${disk.freeGb.toStringAsFixed(0)} GB'],
        ['READ', '${disk.readMbPerSec.toStringAsFixed(1)} M/s'],
        ['WRITE', '${disk.writeMbPerSec.toStringAsFixed(1)} M/s'],
      ],
      breakdown.isEmpty ? [['/', 0.0, AxColors.accent, '— avail · — used']] : breakdown,
    );
  }

  (String, String, String, List<double>, List<List<String>>, List<List<dynamic>>) _buildNetworkData(NetworkMetrics? net) {
    if (net == null) {
      return (
        'Network throughput', '—', 'MB/s',
        const [0.0],
        const [['MIN', '—'], ['AVG', '—'], ['MAX', '—']],
        const <List<dynamic>>[],
      );
    }

    final hist = net.history.isEmpty
        ? [net.totalMbPerSec > 0 ? (net.totalMbPerSec / 10.0).clamp(0.0, 1.0) : 0.05]
        : net.history.map((v) => (v / 10.0).clamp(0.0, 1.0)).toList();

    final breakdown = net.interfaces.map((i) {
      final totalMb = i.rxMbPerSec + i.txMbPerSec;
      final ratio = (totalMb / (net.totalMbPerSec > 0 ? net.totalMbPerSec : 1.0)).clamp(0.0, 1.0);
      return [i.name, ratio, AxColors.accent];
    }).toList();

    return (
      'Network throughput',
      net.totalMbPerSec.toStringAsFixed(1),
      'MB/s',
      hist,
      [['RX', '${net.rxMbPerSec.toStringAsFixed(1)} M/s'], ['TX', '${net.txMbPerSec.toStringAsFixed(1)} M/s'], ['TOTAL', '${net.totalMbPerSec.toStringAsFixed(1)} M/s']],
      breakdown.isEmpty ? [['eth0', 0.0, AxColors.accent]] : breakdown,
    );
  }
}

enum _ProcSortCol { pid, name, user, cpu, mem }

class _ProcessTable extends StatefulWidget {
  final String query;
  final ValueChanged<String> onQuery;
  final List<LiveProcessInfo> liveProcs;
  final int totalCount;

  const _ProcessTable({
    required this.query,
    required this.onQuery,
    this.liveProcs = const [],
    this.totalCount = 0,
  });

  @override
  State<_ProcessTable> createState() => _ProcessTableState();
}

class _ProcessTableState extends State<_ProcessTable> {
  _ProcSortCol _sortCol = _ProcSortCol.cpu;
  bool _sortAsc = false;

  void _onSort(_ProcSortCol col) {
    setState(() {
      if (_sortCol == col) {
        _sortAsc = !_sortAsc;
      } else {
        _sortCol = col;
        _sortAsc = (col == _ProcSortCol.name || col == _ProcSortCol.user || col == _ProcSortCol.pid);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final procsSource = widget.liveProcs;

    final filtered = (widget.query.isEmpty
        ? procsSource
        : procsSource.where((p) =>
            p.name.toLowerCase().contains(widget.query.toLowerCase()) ||
            p.user.toLowerCase().contains(widget.query.toLowerCase()) ||
            p.pid.toString().contains(widget.query)).toList())
      ..sort((a, b) {
        int cmp = 0;
        switch (_sortCol) {
          case _ProcSortCol.pid:
            cmp = a.pid.compareTo(b.pid);
          case _ProcSortCol.name:
            cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
          case _ProcSortCol.user:
            cmp = a.user.toLowerCase().compareTo(b.user.toLowerCase());
          case _ProcSortCol.cpu:
            cmp = a.cpu.compareTo(b.cpu);
          case _ProcSortCol.mem:
            if (a.rssBytes > 0 || b.rssBytes > 0) {
              cmp = a.rssBytes.compareTo(b.rssBytes);
            } else {
              cmp = a.mem.compareTo(b.mem);
            }
        }
        return _sortAsc ? cmp : -cmp;
      });

    final displayCount = widget.totalCount > 0 ? widget.totalCount : filtered.length;

    return Container(
      decoration: BoxDecoration(color: AxColors.s1, borderRadius: BorderRadius.circular(AxRadius.xl), border: Border.all(color: AxColors.line)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AxColors.line))),
            child: Row(
              children: [
                Container(
                  constraints: const BoxConstraints(maxWidth: 260),
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 2),
                  decoration: BoxDecoration(color: AxColors.s2, borderRadius: BorderRadius.circular(AxRadius.pill), border: Border.all(color: AxColors.line)),
                  child: Row(
                    children: [
                      const Icon(Icons.search, size: 12, color: AxColors.fg3),
                      const SizedBox(width: 7),
                      Expanded(
                        child: TextField(
                          onChanged: widget.onQuery,
                          style: AxTextStyles.mono.copyWith(fontSize: 11.5),
                          decoration: const InputDecoration(border: InputBorder.none, isDense: true, hintText: 'filter by name, pid or user'),
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Text('$displayCount processes', style: AxTextStyles.mono.copyWith(fontSize: 10.5, color: AxColors.fg3)),
              ],
            ),
          ),
          if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
              child: Center(
                child: Column(
                  children: [
                    const Icon(Icons.developer_board_off_outlined, size: 28, color: AxColors.fg3),
                    const SizedBox(height: 10),
                    Text(
                      widget.liveProcs.isEmpty
                          ? 'Waiting for process list…'
                          : 'No processes match "${widget.query}"',
                      style: AxTextStyles.mono.copyWith(fontSize: 12, color: AxColors.fg3),
                    ),
                  ],
                ),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: 700,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      color: AxColors.s2,
                      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 68,
                            child: _SortableColHead(
                              text: 'PID',
                              active: _sortCol == _ProcSortCol.pid,
                              asc: _sortAsc,
                              onTap: () => _onSort(_ProcSortCol.pid),
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: _SortableColHead(
                              text: 'NAME',
                              active: _sortCol == _ProcSortCol.name,
                              asc: _sortAsc,
                              onTap: () => _onSort(_ProcSortCol.name),
                            ),
                          ),
                          SizedBox(
                            width: 78,
                            child: _SortableColHead(
                              text: 'USER',
                              active: _sortCol == _ProcSortCol.user,
                              asc: _sortAsc,
                              onTap: () => _onSort(_ProcSortCol.user),
                            ),
                          ),
                          SizedBox(
                            width: 78,
                            child: _SortableColHead(
                              text: 'CPU%',
                              alignEnd: true,
                              active: _sortCol == _ProcSortCol.cpu,
                              asc: _sortAsc,
                              onTap: () => _onSort(_ProcSortCol.cpu),
                            ),
                          ),
                          SizedBox(
                            width: 110,
                            child: _SortableColHead(
                              text: 'MEM',
                              alignEnd: true,
                              active: _sortCol == _ProcSortCol.mem,
                              asc: _sortAsc,
                              onTap: () => _onSort(_ProcSortCol.mem),
                            ),
                          ),
                          const SizedBox(width: 96, child: _ColHead('', alignEnd: true)),
                        ],
                      ),
                    ),
                    for (final p in filtered)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0x0BE8F0E6)))),
                        child: Row(
                          children: [
                            SizedBox(width: 68, child: Text('${p.pid}', style: AxTextStyles.mono.copyWith(fontSize: 11.5, color: AxColors.fg3))),
                            Expanded(
                              flex: 3,
                              child: Row(
                                children: [
                                  Container(width: 5, height: 5, decoration: BoxDecoration(color: p.state == 'R' ? AxColors.accent : AxColors.fg3, shape: BoxShape.circle)),
                                  const SizedBox(width: 7),
                                  Expanded(child: Text(p.name, style: AxTextStyles.mono.copyWith(fontSize: 11.5), overflow: TextOverflow.ellipsis)),
                                ],
                              ),
                            ),
                            SizedBox(width: 78, child: Text(p.user, style: AxTextStyles.mono.copyWith(fontSize: 11, color: AxColors.fg2))),
                            SizedBox(width: 78, child: Text('${p.cpu.toStringAsFixed(1)}%', textAlign: TextAlign.right, style: AxTextStyles.mono.copyWith(fontSize: 11.5, color: p.cpu > 5 ? AxColors.warn : AxColors.fg))),
                            SizedBox(
                              width: 110,
                              child: Text(
                                p.rssBytes > 0
                                    ? '${p.memoryLabel} (${p.mem.toStringAsFixed(1)}%)'
                                    : '${p.mem.toStringAsFixed(1)}%',
                                textAlign: TextAlign.right,
                                style: AxTextStyles.mono.copyWith(fontSize: 11.5, color: AxColors.fg2),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          SizedBox(
                            width: 96,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                AxGhostButton(
                                  label: 'renice',
                                  onTap: () => _showReniceDialog(context, p),
                                ),
                                const SizedBox(width: 5),
                                AxGhostButton(
                                  label: 'kill',
                                  color: AxColors.bad,
                                  borderColor: const Color(0x4CE5806B),
                                  onTap: () => _showKillDialog(context, p),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showKillDialog(BuildContext context, LiveProcessInfo proc) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AxColors.s1,
        title: Text('Kill Process', style: AxTextStyles.h2),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Are you sure you want to terminate this process?', style: AxTextStyles.sans),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AxColors.s2,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AxColors.line),
              ),
              child: Row(
                children: [
                  Text('PID ${proc.pid}', style: AxTextStyles.mono.copyWith(color: AxColors.accent, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 10),
                  Expanded(child: Text(proc.name, style: AxTextStyles.mono, overflow: TextOverflow.ellipsis)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: AxTextStyles.sans.copyWith(color: AxColors.fg3)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AxColors.bad),
            onPressed: () async {
              Navigator.pop(ctx);
              final res = await context.read<MonitoringService>().killProcess(proc.pid);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(res.message),
                    backgroundColor: res.success ? AxColors.s2 : AxColors.bad,
                  ),
                );
              }
            },
            child: const Text('Kill Process', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showReniceDialog(BuildContext context, LiveProcessInfo proc) {
    int selectedPrio = 0;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          backgroundColor: AxColors.s1,
          title: Text('Renice Process', style: AxTextStyles.h2),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Adjust scheduling priority for PID ${proc.pid} (${proc.name}):', style: AxTextStyles.sans),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Priority (niceness):', style: AxTextStyles.label),
                  Text('$selectedPrio', style: AxTextStyles.mono.copyWith(fontSize: 16, color: AxColors.accent, fontWeight: FontWeight.bold)),
                ],
              ),
              Slider(
                value: selectedPrio.toDouble(),
                min: -20,
                max: 19,
                divisions: 39,
                activeColor: AxColors.accent,
                onChanged: (val) => setDlgState(() => selectedPrio = val.round()),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('-20 (Highest)', style: AxTextStyles.mono.copyWith(fontSize: 10, color: AxColors.warn)),
                  Text('0 (Normal)', style: AxTextStyles.mono.copyWith(fontSize: 10, color: AxColors.fg3)),
                  Text('+19 (Lowest)', style: AxTextStyles.mono.copyWith(fontSize: 10, color: AxColors.accent)),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: AxTextStyles.sans.copyWith(color: AxColors.fg3)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AxColors.accent),
              onPressed: () async {
                Navigator.pop(ctx);
                final res = await context.read<MonitoringService>().reniceProcess(proc.pid, selectedPrio);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(res.message),
                      backgroundColor: res.success ? AxColors.s2 : AxColors.bad,
                    ),
                  );
                }
              },
              child: const Text('Apply', style: TextStyle(color: Colors.black)),
            ),
          ],
        ),
      ),
    );
  }
}

class _ColHead extends StatelessWidget {
  final String text;
  final bool alignEnd;
  const _ColHead(this.text, {this.alignEnd = false});

  @override
  Widget build(BuildContext context) {
    return Text(text, textAlign: alignEnd ? TextAlign.right : TextAlign.left, style: AxTextStyles.label);
  }
}

class _SortableColHead extends StatelessWidget {
  final String text;
  final bool alignEnd;
  final bool active;
  final bool asc;
  final VoidCallback onTap;

  const _SortableColHead({
    required this.text,
    this.alignEnd = false,
    required this.active,
    required this.asc,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: alignEnd ? MainAxisAlignment.end : MainAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              style: AxTextStyles.label.copyWith(
                color: active ? AxColors.accent : AxColors.fg3,
                fontWeight: active ? FontWeight.bold : FontWeight.w600,
              ),
            ),
            if (active) ...[
              const SizedBox(width: 3),
              Icon(
                asc ? Icons.arrow_upward : Icons.arrow_downward,
                size: 11,
                color: AxColors.accent,
              ),
            ],
          ],
        ),
      ),
    );
  }
}


