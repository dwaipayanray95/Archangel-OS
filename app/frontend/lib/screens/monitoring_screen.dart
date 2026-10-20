import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/app_state.dart';
import '../models/system_metrics.dart';
import '../services/archangeld_connection.dart';
import '../services/monitoring_service.dart';
import '../ui/screens/activity/activity_logic.dart';
import '../ui/screens/activity/activity_widgets.dart';
import '../ui/screens/activity/process_views.dart';
import '../ui/screens/home/home_logic.dart' show gbText, usageBadgeLabel, usageStatus, worstDiskPercent;
import '../ui/ui.dart';

enum ActivityTab { cpu, memory, disk, network, processes }

/// Activity: live charts of CPU, memory, disk and network, plus the list of
/// running programs ("processes") with safe ways to stop or slow them.
class MonitoringScreen extends StatefulWidget {
  const MonitoringScreen({super.key});

  @override
  State<MonitoringScreen> createState() => _MonitoringScreenState();
}

class _MonitoringScreenState extends State<MonitoringScreen> {
  ActivityTab _tab = ActivityTab.cpu;
  final LiveSamples _samples = LiveSamples();
  MonitoringService? _mon;
  DateTime? _lastSampled;

  @override
  void initState() {
    super.initState();
    _mon = context.read<MonitoringService>();
    _mon!.addListener(_onUpdate);
    _onUpdate();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final backend = context.read<ArchangeldConnection>();
      if (backend.isPaired) _mon!.start(backend);
    });
  }

  /// Adds one chart sample per new server reading (not per rebuild).
  void _onUpdate() {
    final m = _mon?.metrics;
    final at = _mon?.lastPolled;
    if (m == null || at == _lastSampled) return;
    _lastSampled = at;
    _samples.add(m);
  }

  @override
  void dispose() {
    _mon?.removeListener(_onUpdate);
    super.dispose();
  }

  void _retry() {
    final backend = context.read<ArchangeldConnection>();
    if (!backend.isPaired) return;
    _mon!.start(backend);
    _mon!.fetchSnapshot();
  }

  @override
  Widget build(BuildContext context) {
    final backend = context.watch<ArchangeldConnection>();
    final mon = context.watch<MonitoringService>();
    final app = context.read<AppState>();
    final ax = context.ax;

    if (!backend.isPaired) {
      return AxPage(
        title: 'Activity',
        child: EmptyState(
          icon: Icons.show_chart,
          title: 'No server connected yet',
          message: 'Connect a server to see how busy it is.',
          actionLabel: 'Open Settings',
          onAction: () => app.go(AxSection.settings),
        ),
      );
    }

    final metrics = mon.metrics;
    Widget body;
    if (_tab == ActivityTab.processes) {
      body =
          mon.processes.isEmpty && metrics == null
              ? _waiting(mon)
              : ProcessesView(processes: mon.processes, totalCount: mon.totalProcesses);
    } else if (metrics == null) {
      body = _waiting(mon);
    } else {
      body = switch (_tab) {
        ActivityTab.cpu => _CpuTab(metrics: metrics, samples: _samples),
        ActivityTab.memory => _MemoryTab(metrics: metrics, samples: _samples),
        ActivityTab.disk => _DiskTab(metrics: metrics, samples: _samples),
        ActivityTab.network => _NetworkTab(metrics: metrics, samples: _samples),
        ActivityTab.processes => const SizedBox.shrink(),
      };
    }

    return AxPage(
      title: 'Activity',
      subtitle: 'How busy your server is right now',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ScrollableSegments<ActivityTab>(
            values: ActivityTab.values,
            selected: _tab,
            label:
                (t) => switch (t) {
                  ActivityTab.cpu => 'CPU',
                  ActivityTab.memory => 'Memory',
                  ActivityTab.disk => 'Disk',
                  ActivityTab.network => 'Network',
                  ActivityTab.processes => 'Processes',
                },
            onSelect: (t) => setState(() => _tab = t),
          ),
          SizedBox(height: ax.space.lg),
          body,
        ],
      ),
    );
  }

  Widget _waiting(MonitoringService mon) {
    final failed = mon.status == MonitoringStatus.error || mon.status == MonitoringStatus.disconnected;
    return failed
        ? ErrorState(
          title: "Can't reach your server",
          message: 'Check that the secure connection is on and the server is running, then try again.',
          onRetry: _retry,
        )
        : LoadingState(message: 'Connecting to your server...', onRetry: _retry);
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.help});
  final String title;
  final Widget child;
  final Widget? help;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    return AxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Semantics(header: true, child: Text(title, style: ax.typo.title.copyWith(color: ax.colors.text)))),
              if (help != null) help!,
            ],
          ),
          SizedBox(height: ax.space.md),
          child,
        ],
      ),
    );
  }
}

class _Headline extends StatelessWidget {
  const _Headline({required this.value, required this.caption, required this.badge});
  final String value;
  final String caption;
  final Widget badge;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    return Wrap(
      spacing: ax.space.md,
      runSpacing: ax.space.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(value, style: ax.typo.headline.copyWith(color: c.text)),
        Text(caption, style: ax.typo.body.copyWith(color: c.textMuted)),
        badge,
      ],
    );
  }
}

class _Facts extends StatelessWidget {
  const _Facts(this.facts);
  final List<(String, String)> facts;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    return Wrap(
      spacing: ax.space.xl,
      runSpacing: ax.space.sm,
      children: [
        for (final (k, v) in facts)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [Text(k, style: ax.typo.caption.copyWith(color: c.textMuted)), Text(v, style: ax.typo.label.copyWith(color: c.text))],
          ),
      ],
    );
  }
}

class _CpuTab extends StatelessWidget {
  const _CpuTab({required this.metrics, required this.samples});
  final SystemMetrics metrics;
  final LiveSamples samples;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final cpu = metrics.cpu;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Section(
          title: 'Processor (CPU)',
          help: const HelpTip(
            title: 'CPU',
            message:
                'The CPU is the processor, the part of the server that does the work. '
                'Near 100% for a long time means the server is struggling to keep up.',
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Headline(
                value: '${cpu.usagePercent.round()}%',
                caption: 'busy',
                badge: StatusBadge(
                  label: usageBadgeLabel(cpu.usagePercent, high: 'Very busy', mid: 'Busy', ok: 'Fine'),
                  status: usageStatus(cpu.usagePercent),
                ),
              ),
              SizedBox(height: ax.space.md),
              LiveChart(
                series: [ChartSeries(label: 'CPU busy', values: List.of(samples.cpu), color: c.accent)],
                maxY: 100,
                formatY: (v) => '${v.round()}%',
                semanticsLabel: 'Chart of CPU use, now ${cpu.usagePercent.round()} percent',
              ),
            ],
          ),
        ),
        if (cpu.cores.isNotEmpty) ...[
          SizedBox(height: ax.space.lg),
          _Section(
            title: 'Each core',
            help: const HelpTip(
              title: 'Core',
              message: 'Modern processors have several cores that can each work on something at the same time.',
            ),
            child: LayoutBuilder(
              builder: (context, box) {
                final cols = box.maxWidth >= 700 ? 3 : (box.maxWidth >= 440 ? 2 : 1);
                final gap = ax.space.lg;
                final w = (box.maxWidth - gap * (cols - 1)) / cols;
                return Wrap(
                  spacing: gap,
                  runSpacing: ax.space.md,
                  children: [
                    for (final core in cpu.cores)
                      SizedBox(
                        width: w,
                        child: UsageBar(
                          percent: core.usagePercent,
                          label: 'Core ${core.id + 1}${core.speedLabel.isEmpty ? '' : ' · ${core.speedLabel}'}',
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}

class _MemoryTab extends StatelessWidget {
  const _MemoryTab({required this.metrics, required this.samples});
  final SystemMetrics metrics;
  final LiveSamples samples;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final m = metrics.memory;
    return _Section(
      title: 'Memory (RAM)',
      help: const HelpTip(
        title: 'Memory',
        message:
            'Memory (RAM) is the short-term workspace programs use while they run. '
            'When it fills up, the server slows down or programs may be stopped. '
            '"Cache" is memory the system borrows to speed things up and gives back when needed.',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Headline(
            value: '${gbText(m.usedGb)} of ${gbText(m.totalGb)} GB',
            caption: 'used',
            badge: StatusBadge(
              label: usageBadgeLabel(m.usagePercent, high: 'Almost full', mid: 'Getting full', ok: 'Fine'),
              status: usageStatus(m.usagePercent),
            ),
          ),
          SizedBox(height: ax.space.md),
          LiveChart(
            series: [ChartSeries(label: 'Memory used', values: List.of(samples.memory), color: c.info)],
            maxY: 100,
            formatY: (v) => '${v.round()}%',
            semanticsLabel: 'Chart of memory use, now ${m.usagePercent.round()} percent',
          ),
          SizedBox(height: ax.space.lg),
          _Facts([
            ('Available', '${gbText(m.availableGb)} GB'),
            ('Cache', '${gbText(m.cachedGb)} GB'),
            if (m.swapTotalBytes > 0) ('Extra memory on disk (swap)', '${gbText(m.swapUsedGb)} of ${gbText(m.swapTotalGb)} GB'),
          ]),
        ],
      ),
    );
  }
}

class _DiskTab extends StatelessWidget {
  const _DiskTab({required this.metrics, required this.samples});
  final SystemMetrics metrics;
  final LiveSamples samples;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final d = metrics.disk;
    final peak = [...samples.diskRead, ...samples.diskWrite, d.readBytesPerSec, d.writeBytesPerSec].fold<double>(0, math.max);
    final worst = worstDiskPercent(d);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Section(
          title: 'Disk speed',
          help: const HelpTip(
            title: 'Disk activity',
            message:
                'How fast data is being read from and written to the server\'s storage right now. '
                'Spikes are normal when apps start or save a lot of data.',
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Headline(
                value: formatRate(d.readBytesPerSec + d.writeBytesPerSec),
                caption: 'reading and writing',
                badge: StatusBadge(
                  label: usageBadgeLabel(worst, high: 'Almost full', mid: 'Getting full', ok: 'Plenty of space'),
                  status: usageStatus(worst),
                ),
              ),
              SizedBox(height: ax.space.md),
              LiveChart(
                series: [
                  ChartSeries(label: 'Reading', values: List.of(samples.diskRead), color: c.info),
                  ChartSeries(label: 'Writing', values: List.of(samples.diskWrite), color: c.warning),
                ],
                maxY: niceCeil(peak),
                formatY: formatRate,
                semanticsLabel: 'Chart of disk speed, now ${formatRate(d.readBytesPerSec + d.writeBytesPerSec)}',
              ),
            ],
          ),
        ),
        SizedBox(height: ax.space.lg),
        _Section(
          title: 'Storage space',
          child:
              d.mounts.isEmpty
                  ? UsageBar(percent: d.usagePercent, label: 'Disk · ${gbText(d.usedGb)} of ${gbText(d.totalGb)} GB used')
                  : Column(
                    children: [
                      for (final m in d.mounts.where((m) => m.totalBytes > 0))
                        Padding(
                          padding: EdgeInsets.only(bottom: ax.space.md),
                          child: UsageBar(
                            percent: m.usagePercent,
                            label: '${m.mountPoint} · ${gbText(m.usedGb)} of ${gbText(m.totalGb)} GB used',
                          ),
                        ),
                    ],
                  ),
        ),
      ],
    );
  }
}

class _NetworkTab extends StatelessWidget {
  const _NetworkTab({required this.metrics, required this.samples});
  final SystemMetrics metrics;
  final LiveSamples samples;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final n = metrics.network;
    final peak = [...samples.netIn, ...samples.netOut, n.rxBytesPerSec, n.txBytesPerSec].fold<double>(0, math.max);
    return _Section(
      title: 'Network traffic',
      help: const HelpTip(
        title: 'Network traffic',
        message:
            '"Coming in" is data your server receives (downloads, visitors\' requests). '
            '"Going out" is data it sends (pages, files, backups). The chart rescales to fit.',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Headline(
            value: formatRate(n.rxBytesPerSec + n.txBytesPerSec),
            caption: '${formatRate(n.rxBytesPerSec)} coming in · ${formatRate(n.txBytesPerSec)} going out',
            badge: const StatusBadge.info('Live', icon: Icons.sensors),
          ),
          SizedBox(height: ax.space.md),
          LiveChart(
            series: [
              ChartSeries(label: 'Coming in', values: List.of(samples.netIn), color: c.accent),
              ChartSeries(label: 'Going out', values: List.of(samples.netOut), color: c.warning),
            ],
            maxY: niceCeil(peak),
            formatY: formatRate,
            semanticsLabel: 'Chart of network traffic, now ${formatRate(n.rxBytesPerSec + n.txBytesPerSec)}',
          ),
          if (n.interfaces.isNotEmpty) ...[
            SizedBox(height: ax.space.lg),
            Text('By connection', style: ax.typo.label.copyWith(color: c.textMuted)),
            SizedBox(height: ax.space.xs),
            for (final i in n.interfaces)
              Padding(
                padding: EdgeInsets.symmetric(vertical: ax.space.xs),
                child: Row(
                  children: [
                    Expanded(child: Text(i.name, style: ax.typo.body.copyWith(color: c.text), overflow: TextOverflow.ellipsis)),
                    Flexible(
                      child: Text(
                        'in ${formatRate(i.rxBytesPerSec)} · out ${formatRate(i.txBytesPerSec)}',
                        style: ax.typo.caption.copyWith(color: c.textMuted),
                        textAlign: TextAlign.end,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
