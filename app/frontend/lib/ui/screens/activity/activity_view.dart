import 'package:flutter/material.dart';

import '../../../models/system_metrics.dart';
import '../../components/status_badge.dart';
import '../../theme.dart';
import 'activity_logic.dart';
import 'activity_widgets.dart';

/// The rebuilt Activity view supporting wide (>= 720) and compact (< 720) layouts.
class ActivityView extends StatelessWidget {
  const ActivityView({super.key, required this.metrics, required this.processes, required this.totalProcesses, required this.isConnected});

  final SystemMetrics metrics;
  final List<LiveProcessInfo> processes;
  final int totalProcesses;
  final bool isConnected;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;

    final avgCpu = calculate10sAverage(metrics.cpu.history, metrics.cpu.usagePercent);
    final avgMem = calculate10sAverage(metrics.memory.history, metrics.memory.usagePercent);
    final statusInfo = calculateServerStatus(avgCpu, avgMem);

    final cpuMean = cpuMeaning(metrics.cpu.usagePercent);
    final memMean = memoryMeaning(metrics.memory.usagePercent);
    final diskUsagePct = metrics.disk.totalBytes > 0 ? (metrics.disk.usedBytes / metrics.disk.totalBytes) * 100 : metrics.disk.usagePercent;
    final diskMean = diskMeaning(diskUsagePct);
    final totalNet = metrics.network.rxBytesPerSec + metrics.network.txBytesPerSec;
    final netMean = networkMeaning(totalNet);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 720;
        final isFourAcross = constraints.maxWidth >= 960;

        return SingleChildScrollView(
          padding: EdgeInsets.all(isWide ? ax.space.xl : ax.space.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              _buildHeader(context, ax, c, isWide),
              SizedBox(height: ax.space.lg),

              // Status Card
              HeroStatusCard(info: statusInfo),
              SizedBox(height: ax.space.lg),

              // Measures
              if (isWide)
                _buildWideMeasures(ax, isFourAcross, cpuMean, memMean, diskMean, netMean, totalNet)
              else
                CompactMeasuresCard(metrics: metrics, cpuMeaning: cpuMean, memMeaning: memMean, diskMeaning: diskMean, netMeaning: netMean),
              SizedBox(height: ax.space.lg),

              // Server Info
              ServerInfoCard(metrics: metrics),
              SizedBox(height: ax.space.lg),

              // Busiest Programs
              BusiestProgramsCard(processes: processes, totalProcesses: totalProcesses, isWide: isWide),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, ArchangelTheme ax, AxPalette c, bool isWide) {
    final hostname = metrics.host.hostname.isEmpty ? 'server' : metrics.host.hostname;
    final subtitle = isWide ? 'Live from $hostname. Updates every 2 seconds.' : 'Live from $hostname';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Activity', style: ax.typo.headline.copyWith(color: c.text)),
              SizedBox(height: 2),
              Text(subtitle, style: ax.typo.body.copyWith(color: c.textMuted)),
            ],
          ),
        ),
        if (isWide && isConnected)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: StatusBadge.ok('Live', icon: Icons.circle),
          ),
      ],
    );
  }

  Widget _buildWideMeasures(
    ArchangelTheme ax,
    bool isFourAcross,
    MeaningInfo cpuMean,
    MeaningInfo memMean,
    MeaningInfo diskMean,
    MeaningInfo netMean,
    double totalNet,
  ) {
    final coresStr = metrics.cpu.cores.length == 1 ? '1 core' : '${metrics.cpu.cores.length} cores';
    final memSub = 'of ${formatBytes(metrics.memory.totalBytes)} · ${metrics.memory.usagePercent.round()}%';

    final diskRate = metrics.disk.readBytesPerSec >= metrics.disk.writeBytesPerSec && metrics.disk.readBytesPerSec > 1024
        ? 'reading ${formatRate(metrics.disk.readBytesPerSec)}'
        : metrics.disk.writeBytesPerSec > 1024
        ? 'writing ${formatRate(metrics.disk.writeBytesPerSec)}'
        : 'reading ${formatRate(metrics.disk.readBytesPerSec)}';
    final diskSub = 'of ${formatBytes(metrics.disk.totalBytes)} · ${metrics.disk.usagePercent.round()}% · $diskRate';
    final netSub = '↓ ${formatRate(metrics.network.rxBytesPerSec)} · ↑ ${formatRate(metrics.network.txBytesPerSec)}';

    final cards = [
      WideMeasureCard(
        label: 'CPU',
        value: '${metrics.cpu.usagePercent.round()}%',
        subLine: coresStr,
        meaning: cpuMean,
        chartValues: metrics.cpu.history,
        chartSemantics: 'CPU over the last minute',
        chartMaxY: 100.0,
      ),
      WideMeasureCard(
        label: 'Memory',
        value: formatBytes(metrics.memory.usedBytes),
        subLine: memSub,
        meaning: memMean,
        chartValues: metrics.memory.history,
        chartSemantics: 'Memory over the last minute',
        chartMaxY: 100.0,
      ),
      WideMeasureCard(
        label: 'Disk',
        value: formatBytes(metrics.disk.usedBytes),
        subLine: diskSub,
        meaning: diskMean,
        chartValues: metrics.disk.history,
        chartSemantics: 'Disk activity over the last minute',
        chartMaxY: null,
      ),
      WideMeasureCard(
        label: 'Network',
        value: formatRate(totalNet),
        subLine: netSub,
        meaning: netMean,
        chartValues: metrics.network.history,
        chartSemantics: 'Network over the last minute',
        chartMaxY: null,
      ),
    ];

    if (isFourAcross) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < cards.length; i++) ...[if (i > 0) SizedBox(width: ax.space.md), Expanded(child: cards[i])],
        ],
      );
    }

    // 2x2 grid between 720 and 960
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: cards[0]),
            SizedBox(width: ax.space.md),
            Expanded(child: cards[1]),
          ],
        ),
        SizedBox(height: ax.space.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: cards[2]),
            SizedBox(width: ax.space.md),
            Expanded(child: cards[3]),
          ],
        ),
      ],
    );
  }
}
