import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/container_model.dart';
import '../../ui.dart';

/// Colour for a log level, from theme tokens. The level text is always shown
/// too, so meaning never depends on colour alone.
Color logLevelColor(AxPalette c, String level) {
  switch (level.toUpperCase()) {
    case 'ERROR':
    case 'ERR':
    case 'FATAL':
    case 'CRITICAL':
    case 'PANIC':
      return c.danger;
    case 'WARN':
    case 'WARNING':
      return c.warning;
    case 'DEBUG':
    case 'TRACE':
      return c.textSubtle;
    default:
      return c.info;
  }
}

/// Plain-text rendering of log lines, as copied to the clipboard.
String formatLogsForCopy(Iterable<DockerLogEntry> logs) =>
    logs.map((l) => [l.ts, l.level, if (l.source.isNotEmpty) '[${l.source}]', l.text].where((s) => s.isNotEmpty).join(' ')).join('\n');

/// Live log viewer: follows new lines unless paused; "Clear view" hides what
/// is shown so far without touching the app's real logs.
class AppLogView extends StatefulWidget {
  const AppLogView({super.key, required this.logs});

  final List<DockerLogEntry> logs;

  @override
  State<AppLogView> createState() => _AppLogViewState();
}

class _AppLogViewState extends State<AppLogView> {
  final _scroll = ScrollController();
  bool _paused = false;
  // The newest line when "Clear view" was pressed; everything up to and
  // including it is hidden. Identity based because the service trims old
  // lines from the front of its buffer.
  DockerLogEntry? _clearedAt;

  List<DockerLogEntry> get _visible {
    final all = widget.logs;
    final marker = _clearedAt;
    if (marker == null) return all;
    final i = all.lastIndexWhere((e) => identical(e, marker));
    return i < 0 ? all : all.sublist(i + 1);
  }

  @override
  void didUpdateWidget(covariant AppLogView old) {
    super.didUpdateWidget(old);
    if (!_paused && widget.logs.length != old.logs.length) _jumpToEnd();
  }

  void _jumpToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _copy() async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: formatLogsForCopy(_visible)));
    messenger.showSnackBar(const SnackBar(content: Text('Logs copied.')));
  }

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final lines = _visible;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: ax.space.sm,
          runSpacing: ax.space.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('Logs', style: ax.typo.title.copyWith(color: c.text)),
            AxButton.secondary(
              label: _paused ? 'Resume scrolling' : 'Pause scrolling',
              icon: _paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
              onPressed: () {
                setState(() => _paused = !_paused);
                if (!_paused) _jumpToEnd();
              },
            ),
            AxButton.secondary(
              label: 'Clear view',
              icon: Icons.cleaning_services_outlined,
              onPressed: widget.logs.isEmpty ? null : () => setState(() => _clearedAt = widget.logs.last),
            ),
            AxButton.secondary(label: 'Copy logs', icon: Icons.copy_rounded, onPressed: lines.isEmpty ? null : _copy),
          ],
        ),
        if (_clearedAt != null)
          Padding(
            padding: EdgeInsets.only(top: ax.space.xs),
            child: Text(
              'View cleared. Your app’s logs are untouched; new lines appear below.',
              style: ax.typo.caption.copyWith(color: c.textMuted),
            ),
          ),
        SizedBox(height: ax.space.sm),
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: c.surfaceAlt,
              borderRadius: BorderRadius.circular(ax.radii.md),
              border: Border.all(color: c.border),
            ),
            child:
                lines.isEmpty
                    ? Center(
                      child: Padding(
                        padding: EdgeInsets.all(ax.space.lg),
                        child: Text(
                          'No log lines yet. New output appears here as it happens.',
                          textAlign: TextAlign.center,
                          style: ax.typo.body.copyWith(color: c.textMuted),
                        ),
                      ),
                    )
                    : Scrollbar(
                      controller: _scroll,
                      child: ListView.builder(
                        controller: _scroll,
                        padding: EdgeInsets.all(ax.space.md),
                        itemCount: lines.length,
                        itemBuilder: (context, i) => _LogLine(entry: lines[i]),
                      ),
                    ),
          ),
        ),
      ],
    );
  }
}

class _LogLine extends StatelessWidget {
  const _LogLine({required this.entry});
  final DockerLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final level = logLevelColor(c, entry.level);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: SelectableText.rich(
        TextSpan(
          style: ax.typo.mono.copyWith(color: c.text),
          children: [
            if (entry.ts.isNotEmpty) TextSpan(text: '${entry.ts} ', style: TextStyle(color: c.textSubtle)),
            TextSpan(text: '${entry.level.toUpperCase()} ', style: TextStyle(color: level, fontWeight: FontWeight.w700)),
            TextSpan(text: entry.text),
          ],
        ),
      ),
    );
  }
}
