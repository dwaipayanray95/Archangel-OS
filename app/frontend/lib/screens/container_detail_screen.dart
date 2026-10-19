import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/app_state.dart';
import '../models/container_model.dart';
import '../services/containers_service.dart';
import '../theme/tokens.dart';
import '../widgets/ax_widgets.dart';

/// Container detail — hosts the reusable stdout/stderr log widget with real-time
/// WebSocket log streaming from archangeld.
class ContainerDetailScreen extends StatefulWidget {
  final DockerContainerItem container;
  const ContainerDetailScreen({super.key, required this.container});

  @override
  State<ContainerDetailScreen> createState() => _ContainerDetailScreenState();
}

class _ContainerDetailScreenState extends State<ContainerDetailScreen> {
  late DockerContainerItem _container;
  bool _actionLoading = false;
  ContainersService? _svc;

  @override
  void initState() {
    super.initState();
    _container = widget.container;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _svc = context.read<ContainersService>();
      _svc!.startLogStream(_container.id.isNotEmpty ? _container.id : _container.name);
    });
  }

  @override
  void dispose() {
    // Saved at start time rather than read from context here, since
    // context is unsafe to use once the widget is unmounting - this way
    // the stream is stopped regardless of how the screen was left
    // (back-arrow tap, system back gesture, or any other route pop).
    _svc?.stopLogStream();
    super.dispose();
  }

  Future<void> _handleAction(String action) async {
    setState(() => _actionLoading = true);
    final svc = context.read<ContainersService>();
    final ok = await svc.triggerAction(_container.id, action);
    if (!mounted) return;
    setState(() => _actionLoading = false);

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Container ${_container.name} action $action sent.')),
      );
      // Update local container state if found in updated overview
      final updated = svc.overview?.containers.firstWhere(
        (c) => c.id == _container.id,
        orElse: () => _container,
      );
      if (updated != null) {
        setState(() => _container = updated);
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(svc.lastActionMessage ?? 'Failed to $action container ${_container.name}')),
      );
    }
  }

  Future<void> _handleRemove() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AxColors.s1,
        title: Text('Remove Container?', style: AxTextStyles.h2),
        content: Text('Force remove container ${_container.name}? This will delete the instance.', style: AxTextStyles.sans),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel', style: AxTextStyles.sans.copyWith(color: AxColors.fg3)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Remove', style: AxTextStyles.sans.copyWith(color: AxColors.danger, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _actionLoading = true);
    final svc = context.read<ContainersService>();
    final ok = await svc.removeContainer(_container.id);
    if (!mounted) return;
    setState(() => _actionLoading = false);

    if (ok) {
      svc.stopLogStream();
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Container ${_container.name} removed.')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(svc.lastActionMessage ?? 'Failed to remove container ${_container.name}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<ContainersService>();
    final c = svc.overview?.containers.firstWhere(
          (item) => item.id == _container.id,
          orElse: () => _container,
        ) ??
        _container;

    final dot = c.running ? AxColors.accent : AxColors.fg3;
    final logs = svc.liveLogs;
    final stats = [
      ['CPU', '${c.cpu}%'],
      ['MEM', c.memLabel],
      ['PORTS', c.ports],
      ['ID', c.cid.isNotEmpty ? c.cid : (c.id.length > 12 ? c.id.substring(0, 12) : c.id)],
    ];

    return Scaffold(
      backgroundColor: AxColors.bg,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
            decoration: const BoxDecoration(color: AxColors.s1, border: Border(bottom: BorderSide(color: AxColors.line))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () {
                    svc.stopLogStream();
                    Navigator.of(context).pop();
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.chevron_left_rounded, size: 16, color: AxColors.fg3),
                      Text('Containers', style: AxTextStyles.sans.copyWith(fontSize: 11.5, fontWeight: FontWeight.w600, color: AxColors.fg3)),
                    ],
                  ),
                ),
                const SizedBox(height: 9),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 11,
                  runSpacing: 6,
                  children: [
                    StatusDot(color: dot, size: 8, pulse: c.running),
                    Text(c.name, style: AxTextStyles.mono.copyWith(fontSize: 17, fontWeight: FontWeight.w500)),
                    AxPill(text: c.running ? 'running' : 'stopped', color: dot),
                    Text(c.image, style: AxTextStyles.mono.copyWith(fontSize: 11, color: AxColors.fg3)),
                    if (_actionLoading) ...[
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AxColors.accent),
                      ),
                    ],
                    const Spacer(),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _DetailAction(
                          label: 'Restart',
                          icon: Icons.restart_alt_rounded,
                          onTap: () => _handleAction('restart'),
                        ),
                        const SizedBox(width: 6),
                        _DetailAction(
                          label: c.running ? 'Stop' : 'Start',
                          icon: c.running ? Icons.stop_rounded : Icons.play_arrow_rounded,
                          onTap: () => _handleAction(c.running ? 'stop' : 'start'),
                        ),
                        const SizedBox(width: 6),
                        _DetailAction(
                          label: 'Shell',
                          icon: Icons.terminal_rounded,
                          onTap: () {
                            final appState = context.read<AppState>();
                            svc.stopLogStream();
                            Navigator.of(context).pop();
                            appState.openTerminalWithCommand('docker exec -it ${c.name} sh');
                          },
                        ),
                        const SizedBox(width: 6),
                        _DetailAction(
                          label: 'Remove',
                          icon: Icons.delete_outline_rounded,
                          color: AxColors.danger,
                          onTap: _handleRemove,
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 13),
                LayoutBuilder(
                  builder: (context, cst) {
                    final cols = cst.maxWidth >= 500 ? 4 : 2;
                    return GridView.count(
                      crossAxisCount: cols,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 9,
                      crossAxisSpacing: 9,
                      childAspectRatio: 3.2,
                      children: stats.map((s) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                          decoration: BoxDecoration(color: AxColors.s2, borderRadius: BorderRadius.circular(AxRadius.md), border: Border.all(color: AxColors.line)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(s[0], style: AxTextStyles.label.copyWith(fontSize: 9.5)),
                              const SizedBox(height: 2),
                              Text(s[1], style: AxTextStyles.mono.copyWith(fontSize: 13.5, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
                            ],
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: LogPane(
                logs: logs,
                onClear: () {
                  // Re-trigger live logs reset
                  svc.startLogStream(_container.id.isNotEmpty ? _container.id : _container.name);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailAction extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color? color;
  final VoidCallback? onTap;

  const _DetailAction({
    required this.label,
    required this.icon,
    this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = color ?? AxColors.fg2;
    return InkWell(
      borderRadius: BorderRadius.circular(AxRadius.pill),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: AxColors.s2, borderRadius: BorderRadius.circular(AxRadius.pill), border: Border.all(color: AxColors.line)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 6),
            Text(label, style: AxTextStyles.sans.copyWith(fontSize: 11.5, fontWeight: FontWeight.w600, color: fg)),
          ],
        ),
      ),
    );
  }
}

/// The shared stdout/stderr streamed-log widget (reused by container detail,
/// and shaped for reuse by Terminal / "open in terminal" from Files).
class LogPane extends StatefulWidget {
  final List<DockerLogEntry> logs;
  final VoidCallback? onClear;

  const LogPane({super.key, required this.logs, this.onClear});

  @override
  State<LogPane> createState() => _LogPaneState();
}

class _LogPaneState extends State<LogPane> {
  final ScrollController _scrollController = ScrollController();
  bool _wrap = true;
  bool _followTail = true;

  @override
  void didUpdateWidget(covariant LogPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_followTail && widget.logs.length != oldWidget.logs.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: const Color(0xFF070807), borderRadius: BorderRadius.circular(14), border: Border.all(color: AxColors.line)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(color: AxColors.s1, border: Border(bottom: BorderSide(color: AxColors.line))),
            child: Row(
              children: [
                Text('STDOUT · STDERR', style: AxTextStyles.mono.copyWith(fontSize: 10.5, letterSpacing: 0.6, color: AxColors.fg3)),
                const Spacer(),
                GestureDetector(
                  onTap: () => setState(() => _followTail = !_followTail),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      StatusDot(
                        color: _followTail ? AxColors.accent : AxColors.fg3,
                        size: 5,
                        pulse: _followTail,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        _followTail ? 'following tail' : 'scroll paused',
                        style: AxTextStyles.mono.copyWith(
                          fontSize: 10,
                          color: _followTail ? AxColors.accent : AxColors.fg3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                AxGhostButton(
                  label: _wrap ? 'Wrap: On' : 'Wrap: Off',
                  onTap: () => setState(() => _wrap = !_wrap),
                ),
                const SizedBox(width: 6),
                AxGhostButton(
                  label: 'Clear',
                  onTap: widget.onClear,
                ),
              ],
            ),
          ),
          Expanded(
            child: widget.logs.isEmpty
                ? Center(
                    child: Text(
                      'No logs yet...',
                      style: AxTextStyles.mono.copyWith(fontSize: 11, color: AxColors.fg3),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(13, 10, 13, 14),
                    itemCount: widget.logs.length,
                    itemBuilder: (context, index) {
                      final l = widget.logs[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 1.5),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (l.ts.isNotEmpty) ...[
                              Text(l.ts, style: AxTextStyles.mono.copyWith(fontSize: 11.5, color: AxColors.fg3.withValues(alpha: 0.6))),
                              const SizedBox(width: 8),
                            ],
                            SizedBox(
                              width: 44,
                              child: Text(
                                l.level,
                                style: AxTextStyles.mono.copyWith(fontSize: 11.5, fontWeight: FontWeight.w500, color: _lvlColor(l.level)),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                l.source.isNotEmpty ? '${l.source}  ${l.text}' : l.text,
                                style: AxTextStyles.mono.copyWith(fontSize: 11.5),
                                softWrap: _wrap,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Color _lvlColor(String level) => switch (level.toUpperCase()) {
        'WARN' || 'WARNING' => AxColors.warn,
        'ERROR' || 'ERR' || 'STDERR' => AxColors.bad,
        _ => AxColors.fg2,
      };
}
