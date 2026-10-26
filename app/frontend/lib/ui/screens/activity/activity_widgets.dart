import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/system_metrics.dart';
import '../../../services/admin_mode_service.dart';
import '../../../services/monitoring_service.dart';
import '../../components/ax_button.dart';
import '../../components/ax_card.dart';
import '../../components/confirm_dialog.dart';
import '../../components/status_badge.dart';
import '../../theme.dart';
import 'activity_logic.dart';

/// A sparkline chart with an accent line and gradient area fill.
/// No axes or grid lines, strictly adhering to the Halo design spec.
class SparklineChart extends StatelessWidget {
  const SparklineChart({super.key, required this.values, required this.semanticsLabel, this.maxY, this.height = 56});

  final List<double> values;
  final String semanticsLabel;
  final double? maxY;
  final double height;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final accent = ax.colors.accent;

    return Semantics(
      label: semanticsLabel,
      image: true,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(painter: _SparklinePainter(values: values, accent: accent, forcedMaxY: maxY)),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  const _SparklinePainter({required this.values, required this.accent, this.forcedMaxY});

  final List<double> values;
  final Color accent;
  final double? forcedMaxY;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    if (values.length < 2) {
      // Draw a calm baseline if fewer than 2 points
      final p =
          Paint()
            ..color = accent.withValues(alpha: 0.3)
            ..strokeWidth = 1.5
            ..style = PaintingStyle.stroke;
      canvas.drawLine(Offset(0, size.height * 0.75), Offset(size.width, size.height * 0.75), p);
      return;
    }

    double maxVal = forcedMaxY ?? 0.0;
    if (maxVal <= 0) {
      for (final v in values) {
        if (v > maxVal) maxVal = v;
      }
      if (maxVal <= 0) maxVal = 1.0;
    }

    final double stepX = size.width / (values.length - 1);
    final linePath = Path();
    final areaPath = Path();

    double getY(double val) {
      final norm = (val / maxVal).clamp(0.0, 1.0);
      return size.height - (norm * (size.height - 4)) - 2;
    }

    linePath.moveTo(0, getY(values.first));
    areaPath.moveTo(0, size.height);
    areaPath.lineTo(0, getY(values.first));

    for (int i = 1; i < values.length; i++) {
      final x = i * stepX;
      final y = getY(values[i]);
      linePath.lineTo(x, y);
      areaPath.lineTo(x, y);
    }

    areaPath.lineTo(size.width, size.height);
    areaPath.close();

    final fillPaint =
        Paint()
          ..color = accent.withValues(alpha: 0.14)
          ..style = PaintingStyle.fill;
    canvas.drawPath(areaPath, fillPaint);

    final strokePaint =
        Paint()
          ..color = accent
          ..strokeWidth = 2.0
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke;
    canvas.drawPath(linePath, strokePaint);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) {
    return oldDelegate.values != values || oldDelegate.accent != accent || oldDelegate.forcedMaxY != forcedMaxY;
  }
}

/// The Hero Status Card showing overall calm/busy/struggling state.
class HeroStatusCard extends StatelessWidget {
  const HeroStatusCard({super.key, required this.info});

  final ServerStatusInfo info;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;

    final (Color fg, Color bg) = switch (info.status) {
      AxStatus.ok => (c.success, c.successWash),
      AxStatus.warning => (c.warning, c.warningWash),
      AxStatus.error => (c.danger, c.dangerWash),
      _ => (c.accent, c.accentWash),
    };

    return AxCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(ax.radii.md),
              border: Border.all(color: fg.withValues(alpha: 0.3)),
            ),
            child: Icon(info.icon, color: fg, size: 24),
          ),
          SizedBox(width: ax.space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(info.title, style: ax.typo.title.copyWith(color: c.text)),
                SizedBox(height: ax.space.xs),
                Text(info.line, style: ax.typo.body.copyWith(color: c.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Wide layout card for a single system measure (CPU, Memory, Disk, Network).
class WideMeasureCard extends StatelessWidget {
  const WideMeasureCard({
    super.key,
    required this.label,
    required this.value,
    required this.subLine,
    required this.meaning,
    required this.chartValues,
    required this.chartSemantics,
    this.chartMaxY,
  });

  final String label;
  final String value;
  final String subLine;
  final MeaningInfo meaning;
  final List<double> chartValues;
  final String chartSemantics;
  final double? chartMaxY;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;

    return AxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: ax.typo.label.copyWith(color: c.textMuted)),
              Text(value, style: ax.typo.mono.copyWith(fontWeight: FontWeight.w700, fontSize: 16, color: c.text)),
            ],
          ),
          SizedBox(height: ax.space.sm),
          SparklineChart(values: chartValues, semanticsLabel: chartSemantics, maxY: chartMaxY, height: 52),
          SizedBox(height: ax.space.sm),
          Row(children: [StatusBadge(label: meaning.label, status: meaning.status, icon: meaning.icon)]),
          SizedBox(height: ax.space.xs),
          Text(subLine, style: ax.typo.caption.copyWith(color: c.textMuted), maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

/// Compact layout card grouping all 4 measures into a single card with expandable charts.
class CompactMeasuresCard extends StatefulWidget {
  const CompactMeasuresCard({
    super.key,
    required this.metrics,
    required this.cpuMeaning,
    required this.memMeaning,
    required this.diskMeaning,
    required this.netMeaning,
  });

  final SystemMetrics metrics;
  final MeaningInfo cpuMeaning;
  final MeaningInfo memMeaning;
  final MeaningInfo diskMeaning;
  final MeaningInfo netMeaning;

  @override
  State<CompactMeasuresCard> createState() => _CompactMeasuresCardState();
}

class _CompactMeasuresCardState extends State<CompactMeasuresCard> {
  int? _expandedIndex;

  void _toggle(int index) {
    setState(() {
      _expandedIndex = _expandedIndex == index ? null : index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final m = widget.metrics;

    final totalNet = m.network.rxBytesPerSec + m.network.txBytesPerSec;
    final diskUsagePct = m.disk.totalBytes > 0 ? (m.disk.usedBytes / m.disk.totalBytes) * 100 : m.disk.usagePercent;

    final items = [
      (
        label: 'CPU',
        meaning: widget.cpuMeaning,
        value: '${m.cpu.usagePercent.round()}%',
        chartValues: m.cpu.history,
        chartSemantics: 'CPU over the last minute',
        chartMaxY: 100.0,
      ),
      (
        label: 'Memory',
        meaning: widget.memMeaning,
        value: formatBytes(m.memory.usedBytes),
        chartValues: m.memory.history,
        chartSemantics: 'Memory over the last minute',
        chartMaxY: 100.0,
      ),
      (
        label: 'Disk',
        meaning: widget.diskMeaning,
        value: '${diskUsagePct.round()}%',
        chartValues: m.disk.history,
        chartSemantics: 'Disk activity over the last minute',
        chartMaxY: null,
      ),
      (
        label: 'Network',
        meaning: widget.netMeaning,
        value: formatRate(totalNet),
        chartValues: m.network.history,
        chartSemantics: 'Network over the last minute',
        chartMaxY: null,
      ),
    ];

    return AxCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (int i = 0; i < items.length; i++) ...[
            if (i > 0) Divider(height: 1, color: c.border.withValues(alpha: 0.5)),
            InkWell(
              onTap: () => _toggle(i),
              borderRadius: BorderRadius.vertical(
                top: i == 0 ? Radius.circular(ax.radii.md) : Radius.zero,
                bottom: i == items.length - 1 && _expandedIndex != i ? Radius.circular(ax.radii.md) : Radius.zero,
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: ax.space.md, vertical: ax.space.sm + 2),
                child: Row(
                  children: [
                    Text(items[i].label, style: ax.typo.label.copyWith(color: c.text)),
                    SizedBox(width: ax.space.sm),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: StatusBadge(label: items[i].meaning.label, status: items[i].meaning.status, icon: items[i].meaning.icon),
                        ),
                      ),
                    ),
                    SizedBox(width: ax.space.xs),
                    Text(items[i].value, style: ax.typo.mono.copyWith(fontWeight: FontWeight.w600, color: c.text)),
                    SizedBox(width: 2),
                    Icon(_expandedIndex == i ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, size: 18, color: c.textMuted),
                  ],
                ),
              ),
            ),
            if (_expandedIndex == i)
              Padding(
                padding: EdgeInsets.fromLTRB(ax.space.md, 0, ax.space.md, ax.space.sm),
                child: SparklineChart(
                  values: items[i].chartValues,
                  semanticsLabel: items[i].chartSemantics,
                  maxY: items[i].chartMaxY,
                  height: 64,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Server info card with Name, System, Up for in IBM Plex Mono.
class ServerInfoCard extends StatelessWidget {
  const ServerInfoCard({super.key, required this.metrics});

  final SystemMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;

    final systemStr = '${metrics.host.os} · ${metrics.host.arch}';
    final uptimeStr = formatUptimeLong(metrics.uptimeSeconds);

    return AxCard(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 450;
          if (isNarrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _infoRow(ax, c, 'Name', metrics.host.hostname),
                SizedBox(height: ax.space.xs),
                _infoRow(ax, c, 'System', systemStr),
                SizedBox(height: ax.space.xs),
                _infoRow(ax, c, 'Up for', uptimeStr),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: _infoColumn(ax, c, 'Name', metrics.host.hostname)),
              Expanded(child: _infoColumn(ax, c, 'System', systemStr)),
              Expanded(child: _infoColumn(ax, c, 'Up for', uptimeStr)),
            ],
          );
        },
      ),
    );
  }

  Widget _infoColumn(ArchangelTheme ax, AxPalette c, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: ax.typo.caption.copyWith(color: c.textMuted)),
        SizedBox(height: 2),
        Text(value, style: ax.typo.mono.copyWith(fontWeight: FontWeight.w600, color: c.text)),
      ],
    );
  }

  Widget _infoRow(ArchangelTheme ax, AxPalette c, String label, String value) {
    return Row(
      children: [
        Text(label, style: ax.typo.caption.copyWith(color: c.textMuted)),
        SizedBox(width: ax.space.sm),
        Expanded(
          child: Text(
            value,
            style: ax.typo.mono.copyWith(fontWeight: FontWeight.w600, color: c.text),
            textAlign: TextAlign.end,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// Shown on every Stop and Force stop confirmation.
const String kStopWarning = 'Programs you stop may lose unsaved work. System processes can make the server unstable.';

/// Busiest programs card with search, CPU/Memory sort, wide table / compact rows,
/// and confirmed actions.
class BusiestProgramsCard extends StatefulWidget {
  const BusiestProgramsCard({super.key, required this.processes, required this.totalProcesses, required this.isWide});

  final List<LiveProcessInfo> processes;
  final int totalProcesses;
  final bool isWide;

  @override
  State<BusiestProgramsCard> createState() => _BusiestProgramsCardState();
}

class _BusiestProgramsCardState extends State<BusiestProgramsCard> {
  String _query = '';
  bool _sortByMemory = false; // default CPU descending

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _stopProcess(LiveProcessInfo proc, {bool force = false}) async {
    final mon = context.read<MonitoringService>();
    final title = force ? 'Force stop ${proc.name}?' : 'Stop ${proc.name}?';
    final body =
        force
            ? "Use this only if Stop didn't work. It ends the program at once, so anything it hadn't saved is lost."
            : "This asks it to close. Whatever it's doing stops, and apps that rely on it may stop working until it runs again.";
    final confirmLabel = force ? 'Force stop' : 'Stop';

    final critical = isCriticalProcess(proc.pid, proc.name);
    final message = [if (critical) 'Stopping this can cut you off from your server.', body, kStopWarning].join(' ');

    final confirmed = await showConfirmDialog(
      context,
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      danger: true,
      typeToConfirm: critical ? proc.name : null,
    );

    if (!confirmed || !mounted) return;

    final result = await mon.killProcess(proc.pid, force: force);
    if (!mounted) return;

    if (result.success) {
      _toast('${proc.name} stopped');
    } else {
      _toast(result.message);
    }
  }

  Future<void> _changePriority(LiveProcessInfo proc) async {
    final mon = context.read<MonitoringService>();
    final adminMode = context.read<AdminModeService>();
    final isAdmin = adminMode.enabled == true;

    final chosen = await showDialog<int>(
      context: context,
      builder: (context) => ChangePriorityDialog(procName: proc.name, isAdmin: isAdmin),
    );

    if (chosen == null || !mounted) return;

    final result = await mon.reniceProcess(proc.pid, chosen);
    if (!mounted) return;

    if (result.success) {
      _toast('Priority changed');
    } else {
      _toast(result.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;

    final shown = filterAndSortPrograms(widget.processes, query: _query, sortByMemory: _sortByMemory);

    return AxCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(ax.space.md, ax.space.md, ax.space.md, ax.space.sm),
            child:
                widget.isWide
                    ? Row(
                      children: [
                        Expanded(child: Text('Busiest programs', style: ax.typo.title.copyWith(color: c.text))),
                        SizedBox(width: ax.space.sm),
                        _searchAndSortRow(ax, c, isExpanded: false),
                      ],
                    )
                    : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Busiest programs', style: ax.typo.title.copyWith(color: c.text)),
                        SizedBox(height: ax.space.sm),
                        _searchAndSortRow(ax, c, isExpanded: true),
                      ],
                    ),
          ),
          Divider(height: 1, color: c.border.withValues(alpha: 0.5)),
          if (_query.trim().isNotEmpty && shown.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: ax.space.md, vertical: ax.space.xl),
              child: Center(child: Text('Nothing matches "$_query"', style: ax.typo.body.copyWith(color: c.textMuted))),
            )
          else if (widget.isWide)
            _buildWideTable(ax, c, shown)
          else
            _buildCompactRows(ax, c, shown),
          Divider(height: 1, color: c.border.withValues(alpha: 0.5)),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: ax.space.md, vertical: ax.space.sm),
            child: Text(
              'Showing the ${shown.length} busiest of ${widget.totalProcesses} programs.',
              style: ax.typo.caption.copyWith(color: c.textMuted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchAndSortRow(ArchangelTheme ax, AxPalette c, {required bool isExpanded}) {
    final searchField = SizedBox(
      width: isExpanded ? null : 170,
      height: 36,
      child: TextField(
        onChanged: (v) => setState(() => _query = v),
        style: ax.typo.body.copyWith(fontSize: 13),
        decoration: InputDecoration(
          hintText: 'Search programs',
          hintStyle: ax.typo.caption.copyWith(color: c.textMuted),
          prefixIcon: Icon(Icons.search, size: 16, color: c.textMuted),
          contentPadding: EdgeInsets.zero,
          isDense: true,
          filled: true,
          fillColor: c.surfaceAlt,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(ax.radii.sm), borderSide: BorderSide(color: c.border)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(ax.radii.sm), borderSide: BorderSide(color: c.border)),
        ),
      ),
    );

    final sortButtons = Container(
      height: 36,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(ax.radii.sm), border: Border.all(color: c.border)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _sortButton(ax, c, label: 'CPU', selected: !_sortByMemory, onSelect: () => setState(() => _sortByMemory = false)),
          _sortButton(ax, c, label: 'Memory', selected: _sortByMemory, onSelect: () => setState(() => _sortByMemory = true)),
        ],
      ),
    );

    return Row(
      mainAxisSize: isExpanded ? MainAxisSize.max : MainAxisSize.min,
      children: [if (isExpanded) Expanded(child: searchField) else searchField, SizedBox(width: ax.space.sm), sortButtons],
    );
  }

  Widget _sortButton(ArchangelTheme ax, AxPalette c, {required String label, required bool selected, required VoidCallback onSelect}) {
    return Material(
      key: ValueKey('sort-${label.toLowerCase()}'),
      color: selected ? c.accentWash : Colors.transparent,
      borderRadius: BorderRadius.circular(ax.radii.sm - 2),
      child: InkWell(
        onTap: onSelect,
        borderRadius: BorderRadius.circular(ax.radii.sm - 2),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Text(
            label,
            style: ax.typo.caption.copyWith(
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? c.accent : c.textMuted,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWideTable(ArchangelTheme ax, AxPalette c, List<LiveProcessInfo> shown) {
    return Column(
      children: [
        // Table Header
        Padding(
          padding: EdgeInsets.symmetric(horizontal: ax.space.md, vertical: ax.space.xs + 2),
          child: Row(
            children: [
              Expanded(flex: 3, child: Text('Program', style: ax.typo.caption.copyWith(color: c.textMuted, fontWeight: FontWeight.w600))),
              Expanded(flex: 2, child: Text('Run by', style: ax.typo.caption.copyWith(color: c.textMuted, fontWeight: FontWeight.w600))),
              Expanded(
                flex: 2,
                child: Text(
                  !_sortByMemory ? 'CPU ↓' : 'CPU',
                  style: ax.typo.caption.copyWith(color: c.textMuted, fontWeight: FontWeight.w600),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  _sortByMemory ? 'Memory ↓' : 'Memory',
                  style: ax.typo.caption.copyWith(color: c.textMuted, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 40),
            ],
          ),
        ),
        Divider(height: 1, color: c.border.withValues(alpha: 0.3)),
        for (final p in shown) ...[
          Padding(
            padding: EdgeInsets.symmetric(horizontal: ax.space.md, vertical: 4),
            child: Row(
              children: [
                Expanded(flex: 3, child: Text(p.name, style: ax.typo.mono.copyWith(color: c.text, fontWeight: FontWeight.w600))),
                Expanded(flex: 2, child: Text(p.user, style: ax.typo.caption.copyWith(color: c.textMuted))),
                Expanded(flex: 2, child: Text('${p.cpu.toStringAsFixed(1)}%', style: ax.typo.mono.copyWith(color: c.text))),
                Expanded(flex: 2, child: Text(p.memoryLabel, style: ax.typo.mono.copyWith(color: c.text))),
                _processMenu(ax, c, p),
              ],
            ),
          ),
          Divider(height: 1, color: c.border.withValues(alpha: 0.15)),
        ],
      ],
    );
  }

  Widget _buildCompactRows(ArchangelTheme ax, AxPalette c, List<LiveProcessInfo> shown) {
    return Column(
      children: [
        for (final p in shown) ...[
          Padding(
            padding: EdgeInsets.symmetric(horizontal: ax.space.md, vertical: ax.space.xs),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.name, style: ax.typo.mono.copyWith(color: c.text, fontWeight: FontWeight.w600)),
                      SizedBox(height: 2),
                      Text(
                        '${p.cpu.toStringAsFixed(1)}% CPU · ${p.memoryLabel} · ${p.user}',
                        style: ax.typo.caption.copyWith(color: c.textMuted),
                      ),
                    ],
                  ),
                ),
                _processMenu(ax, c, p),
              ],
            ),
          ),
          Divider(height: 1, color: c.border.withValues(alpha: 0.2)),
        ],
      ],
    );
  }

  Widget _processMenu(ArchangelTheme ax, AxPalette c, LiveProcessInfo p) {
    return PopupMenuButton<String>(
      tooltip: 'More for ${p.name}',
      icon: Icon(Icons.more_horiz, size: 18, color: c.textMuted),
      onSelected: (val) {
        if (val == 'stop') _stopProcess(p, force: false);
        if (val == 'force_stop') _stopProcess(p, force: true);
        if (val == 'priority') _changePriority(p);
      },
      itemBuilder:
          (context) => [
            PopupMenuItem(value: 'stop', child: Text('Stop', style: ax.typo.body.copyWith(color: c.text))),
            PopupMenuItem(value: 'force_stop', child: Text('Force stop', style: ax.typo.body.copyWith(color: c.danger))),
            const PopupMenuDivider(),
            PopupMenuItem(
              value: 'priority',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Change priority…', style: ax.typo.body.copyWith(color: c.text)),
                  Text('Advanced', style: ax.typo.caption.copyWith(color: c.textMuted)),
                ],
              ),
            ),
          ],
    );
  }
}

/// Dialog for changing process priority.
class ChangePriorityDialog extends StatefulWidget {
  const ChangePriorityDialog({super.key, required this.procName, required this.isAdmin});

  final String procName;
  final bool isAdmin;

  @override
  State<ChangePriorityDialog> createState() => _ChangePriorityDialogState();
}

class _ChangePriorityDialogState extends State<ChangePriorityDialog> {
  int _selected = 0; // Normal

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;

    return AlertDialog(
      title: const Text('Change priority'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Lower priority lets other programs go first when the server is busy. Most people never need this.',
            style: ax.typo.body.copyWith(color: c.textMuted),
          ),
          SizedBox(height: ax.space.lg),
          Row(
            children: [
              _priorityOption(ax, c, label: 'Lower', value: 10, enabled: true),
              SizedBox(width: ax.space.xs),
              _priorityOption(ax, c, label: 'Normal', value: 0, enabled: true),
              SizedBox(width: ax.space.xs),
              _priorityOption(ax, c, label: 'Higher', value: -5, enabled: widget.isAdmin),
            ],
          ),
          SizedBox(height: ax.space.sm),
          Row(
            children: [
              Icon(Icons.lock_outline, size: 14, color: c.textMuted),
              SizedBox(width: ax.space.xs),
              Text('Higher needs Admin mode.', style: ax.typo.caption.copyWith(color: c.textMuted)),
            ],
          ),
        ],
      ),
      actions: [
        AxButton.ghost(label: 'Cancel', onPressed: () => Navigator.pop(context)),
        AxButton(label: 'Apply', onPressed: () => Navigator.pop(context, _selected)),
      ],
    );
  }

  Widget _priorityOption(ArchangelTheme ax, AxPalette c, {required String label, required int value, required bool enabled}) {
    final isChosen = _selected == value;
    return Expanded(
      child: Material(
        color:
            !enabled
                ? c.surfaceAlt.withValues(alpha: 0.5)
                : isChosen
                ? c.accentWash
                : c.surfaceAlt,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ax.radii.sm),
          side: BorderSide(color: isChosen ? c.accent : c.border),
        ),
        child: InkWell(
          onTap: enabled ? () => setState(() => _selected = value) : null,
          borderRadius: BorderRadius.circular(ax.radii.sm),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Center(
              child: Text(
                label,
                style: ax.typo.label.copyWith(
                  color:
                      !enabled
                          ? c.textMuted.withValues(alpha: 0.5)
                          : isChosen
                          ? c.accent
                          : c.text,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
