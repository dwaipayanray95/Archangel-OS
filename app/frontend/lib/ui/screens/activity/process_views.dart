import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/app_state.dart';
import '../../../models/system_metrics.dart';
import '../../../services/monitoring_service.dart';
import '../../ui.dart';
import 'activity_logic.dart';
import 'activity_widgets.dart';

/// Rows shown at once; search narrows the rest.
const kMaxProcessRows = 60;

/// Width at which the process list becomes a table.
const kProcessTableMinWidth = 720.0;

/// Explains what stopping a process can do, in plain words.
const kStopWarning = 'Programs you stop may lose unsaved work. System processes can make the server unstable.';

class ProcessesView extends StatefulWidget {
  const ProcessesView({super.key, required this.processes, required this.totalCount});
  final List<LiveProcessInfo> processes;
  final int totalCount;

  @override
  State<ProcessesView> createState() => _ProcessesViewState();
}

class _ProcessesViewState extends State<ProcessesView> {
  String _query = '';
  ProcessSort _sort = ProcessSort.cpu;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final all = widget.processes;
    final shown = filterAndSortProcesses(all, query: _query, sort: _sort);
    final rows = shown.take(kMaxProcessRows).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                decoration: const InputDecoration(
                  hintText: 'Search by name, user or ID',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                ),
              ),
            ),
            SizedBox(width: ax.space.sm),
            const HelpTip(
              title: 'Processes',
              message: 'A process is a program that is running on your server right now. '
                  'Your apps, the web server and the system itself are all made of processes. '
                  'Tap one to see details or to stop it.',
            ),
          ],
        ),
        SizedBox(height: ax.space.md),
        ScrollableSegments<ProcessSort>(
          values: ProcessSort.values,
          selected: _sort,
          label: (s) => switch (s) {
            ProcessSort.cpu => 'Busiest',
            ProcessSort.memory => 'Most memory',
            ProcessSort.name => 'Name',
          },
          onSelect: (s) => setState(() => _sort = s),
        ),
        SizedBox(height: ax.space.md),
        if (all.isEmpty)
          const EmptyState(
            icon: Icons.list_alt,
            title: 'No programs listed yet',
            message: 'The list will appear in a few seconds.',
          )
        else if (rows.isEmpty)
          EmptyState(icon: Icons.search_off, title: 'Nothing matches "$_query"', message: 'Try a different name or user.')
        else
          LayoutBuilder(
            builder: (context, box) => AxCard(
              padding: EdgeInsets.symmetric(vertical: ax.space.xs),
              child: box.maxWidth >= kProcessTableMinWidth ? _ProcessTable(rows: rows) : _ProcessList(rows: rows),
            ),
          ),
        if (rows.isNotEmpty) ...[
          SizedBox(height: ax.space.sm),
          Text(
            shown.length > rows.length
                ? 'Showing the first ${rows.length} of ${shown.length}. Use search to find others.'
                : 'Showing ${rows.length} of ${widget.totalCount > 0 ? widget.totalCount : all.length} programs.',
            style: ax.typo.caption.copyWith(color: c.textMuted),
          ),
        ],
      ],
    );
  }
}

class _ProcessList extends StatelessWidget {
  const _ProcessList({required this.rows});
  final List<LiveProcessInfo> rows;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    return Column(
      children: [
        for (final p in rows)
          AxListTile(
            key: ValueKey('proc-${p.pid}'),
            title: p.name.isEmpty ? 'Unnamed program' : p.name,
            subtitle: '${p.user.isEmpty ? 'unknown user' : p.user} · ID ${p.pid}',
            semanticsLabel: '${p.name}, user ${p.user}, ${p.cpu.toStringAsFixed(1)} percent processor, ${p.memoryLabel} memory. Opens details.',
            trailing: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('CPU ${p.cpu.toStringAsFixed(1)}%', style: ax.typo.label.copyWith(color: c.text)),
                Text(p.memoryLabel, style: ax.typo.caption.copyWith(color: c.textMuted)),
              ],
            ),
            onTap: () => showProcessDetails(context, p),
          ),
      ],
    );
  }
}

class _ProcessTable extends StatelessWidget {
  const _ProcessTable({required this.rows});
  final List<LiveProcessInfo> rows;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final head = ax.typo.label.copyWith(color: c.textMuted);
    Widget cell(int flex, Widget child) => Expanded(flex: flex, child: child);
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: ax.space.lg, vertical: ax.space.sm),
          child: Row(
            children: [
              cell(4, Text('Name', style: head)),
              cell(2, Text('User', style: head)),
              cell(1, Text('ID', style: head)),
              cell(2, Text('Status', style: head)),
              cell(1, Text('CPU', style: head, textAlign: TextAlign.end)),
              cell(2, Text('Memory', style: head, textAlign: TextAlign.end)),
              SizedBox(width: ax.space.xl),
            ],
          ),
        ),
        Divider(height: 1, color: c.border),
        for (final p in rows)
          InkWell(
            key: ValueKey('proc-${p.pid}'),
            onTap: () => showProcessDetails(context, p),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: axMinTarget(context)),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: ax.space.lg, vertical: ax.space.sm),
                child: Row(
                  children: [
                    cell(4, Text(p.name, style: ax.typo.label.copyWith(color: c.text), overflow: TextOverflow.ellipsis)),
                    cell(2, Text(p.user, style: ax.typo.body.copyWith(color: c.textMuted), overflow: TextOverflow.ellipsis)),
                    cell(1, Text('${p.pid}', style: ax.typo.body.copyWith(color: c.textMuted))),
                    cell(2, Text(processStateLabel(p.state), style: ax.typo.body.copyWith(color: c.textMuted), overflow: TextOverflow.ellipsis)),
                    cell(1, Text('${p.cpu.toStringAsFixed(1)}%', style: ax.typo.body.copyWith(color: c.text), textAlign: TextAlign.end)),
                    cell(2, Text(p.memoryLabel, style: ax.typo.body.copyWith(color: c.text), textAlign: TextAlign.end)),
                    SizedBox(width: ax.space.xl, child: Icon(Icons.chevron_right, size: 18, color: c.textMuted)),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Opens the details sheet for [p] with Stop / Force stop / Change priority.
Future<void> showProcessDetails(BuildContext context, LiveProcessInfo p) {
  final parent = context;
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      final ax = sheetContext.ax;
      final c = ax.colors;
      Widget fact(String k, String v) => Padding(
            padding: EdgeInsets.symmetric(vertical: ax.space.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 110, child: Text(k, style: ax.typo.body.copyWith(color: c.textMuted))),
                Expanded(child: Text(v, style: ax.typo.body.copyWith(color: c.text))),
              ],
            ),
          );
      return SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(ax.space.xl, 0, ax.space.xl, ax.space.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(header: true, child: Text(p.name.isEmpty ? 'Unnamed program' : p.name, style: ax.typo.title.copyWith(color: c.text))),
              SizedBox(height: ax.space.sm),
              fact('Status', processStateLabel(p.state)),
              fact('Run by', p.user.isEmpty ? 'unknown' : p.user),
              fact('Process ID', '${p.pid}'),
              fact('Processor', '${p.cpu.toStringAsFixed(1)}% busy'),
              fact('Memory', p.memoryLabel),
              SizedBox(height: ax.space.lg),
              Wrap(
                spacing: ax.space.sm,
                runSpacing: ax.space.sm,
                children: [
                  AxButton.secondary(
                    label: 'Stop process',
                    icon: Icons.stop_circle_outlined,
                    onPressed: () {
                      Navigator.of(sheetContext).pop();
                      stopProcess(parent, p, force: false);
                    },
                  ),
                  AxButton.danger(
                    label: 'Force stop',
                    icon: Icons.dangerous_outlined,
                    onPressed: () {
                      Navigator.of(sheetContext).pop();
                      stopProcess(parent, p, force: true);
                    },
                  ),
                  AxButton.secondary(
                    label: 'Change priority',
                    icon: Icons.tune,
                    onPressed: () {
                      Navigator.of(sheetContext).pop();
                      showPrioritySheet(parent, p);
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Confirms, then asks the server to stop [p] (SIGTERM, or SIGKILL when
/// [force]). Surfaces the server's own message on failure.
Future<void> stopProcess(BuildContext context, LiveProcessInfo p, {required bool force}) async {
  final mon = context.read<MonitoringService>();
  final app = context.read<AppState>();
  final messenger = ScaffoldMessenger.of(context);
  final name = p.name.isEmpty ? 'process ${p.pid}' : p.name;
  final ok = await showConfirmDialog(
    context,
    title: force ? 'Force stop "$name"?' : 'Stop "$name"?',
    message: force
        ? 'Force stop ends it immediately and gives it no chance to save or clean up. $kStopWarning'
        : 'This asks it to finish and close down properly. $kStopWarning',
    confirmLabel: force ? 'Force stop' : 'Stop process',
    danger: true,
  );
  if (!ok) return;
  final res = await mon.killProcess(p.pid, force: force);
  _report(messenger, app, res, success: force ? '"$name" was force stopped.' : '"$name" was asked to stop.');
}

/// Lets the user raise or lower how much attention [p] gets from the processor.
Future<void> showPrioritySheet(BuildContext context, LiveProcessInfo p) async {
  final mon = context.read<MonitoringService>();
  final app = context.read<AppState>();
  final messenger = ScaffoldMessenger.of(context);
  final nice = await showModalBottomSheet<int>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => PrioritySheet(processName: p.name.isEmpty ? 'process ${p.pid}' : p.name),
  );
  if (nice == null) return;
  final res = await mon.reniceProcess(p.pid, nice);
  _report(messenger, app, res, success: 'Priority changed: ${priorityLabel(nice)}.');
}

void _report(ScaffoldMessengerState messenger, AppState app, ProcessActionResult res, {required String success}) {
  messenger.showSnackBar(SnackBar(
    content: Text(res.success ? success : res.message),
    action: !res.success && res.message.toLowerCase().contains('admin')
        ? SnackBarAction(label: 'Open Settings', onPressed: () => app.go(AxSection.settings))
        : null,
  ));
}

/// The "Change priority" slider. Pops with the chosen nice value.
class PrioritySheet extends StatefulWidget {
  const PrioritySheet({super.key, required this.processName});
  final String processName;

  @override
  State<PrioritySheet> createState() => _PrioritySheetState();
}

class _PrioritySheetState extends State<PrioritySheet> {
  double _pos = sliderFromNice(0).toDouble();

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final nice = niceFromSlider(_pos);
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(ax.space.xl, 0, ax.space.xl, ax.space.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text('Change priority of ${widget.processName}', style: ax.typo.title.copyWith(color: c.text)),
                  ),
                ),
                const HelpTip(
                  title: 'Priority',
                  message: 'When the server is busy, priority decides which programs get the processor first. '
                      'Lower priority makes a program polite: it slows down so others stay fast. '
                      'Higher priority lets it work faster but can slow everything else. '
                      'Most programs should stay at Normal.',
                ),
              ],
            ),
            SizedBox(height: ax.space.md),
            Text(priorityLabel(nice), key: const Key('priority-label'), style: ax.typo.label.copyWith(color: c.text)),
            Text('Lower ↔ Higher priority', style: ax.typo.caption.copyWith(color: c.textMuted)),
            Slider(
              value: _pos,
              min: 0,
              max: kPrioritySteps.toDouble(),
              divisions: kPrioritySteps,
              label: priorityLabel(nice),
              semanticFormatterCallback: (v) => priorityLabel(niceFromSlider(v)),
              onChanged: (v) => setState(() => _pos = v),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Lower', style: ax.typo.caption.copyWith(color: c.textMuted)),
                Text('Higher', style: ax.typo.caption.copyWith(color: c.textMuted)),
              ],
            ),
            SizedBox(height: ax.space.lg),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: ax.space.sm,
              runSpacing: ax.space.sm,
              children: [
                AxButton.ghost(label: 'Cancel', onPressed: () => Navigator.of(context).pop()),
                AxButton(label: 'Apply', onPressed: () => Navigator.of(context).pop(nice)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
