import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/app_state.dart';
import '../models/container_model.dart';
import '../services/archangeld_connection.dart';
import '../services/containers_service.dart';
import '../ui/screens/apps/app_actions.dart';
import '../ui/screens/apps/log_view.dart';
import '../ui/ui.dart';

/// One app: status, details, actions and its live logs. A pushed page with a
/// real back button.
class ContainerDetailScreen extends StatefulWidget {
  final DockerContainerItem container;
  const ContainerDetailScreen({super.key, required this.container});

  @override
  State<ContainerDetailScreen> createState() => _ContainerDetailScreenState();
}

class _ContainerDetailScreenState extends State<ContainerDetailScreen> {
  late DockerContainerItem _container;
  bool _busy = false;
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
    // Saved at start time: context is unsafe to use while unmounting, and the
    // stream must stop however the page is left (back button, gesture, pop).
    _svc?.stopLogStream();
    super.dispose();
  }

  DockerContainerItem _current(ContainersService svc) {
    final list = svc.overview?.containers ?? const <DockerContainerItem>[];
    for (final item in list) {
      if (item.id == _container.id) return item;
    }
    return _container;
  }

  Future<void> _act(ContainersService svc, DockerContainerItem c, String action) async {
    setState(() => _busy = true);
    await runAppAction(context, svc, c, action);
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _remove(ContainersService svc, DockerContainerItem c) async {
    final removed = await removeApp(context, svc, c);
    if (removed && mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<ContainersService>();
    final host = context.watch<ArchangeldConnection>().host;
    final ax = context.ax;
    final c = ax.colors;
    final item = _current(svc);
    final open = appUriFor(item, host);
    final shortId = item.cid.isNotEmpty ? item.cid : (item.id.length > 12 ? item.id.substring(0, 12) : item.id);

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        surfaceTintColor: Colors.transparent,
        foregroundColor: c.text,
        leading: const BackButton(),
        title: Text(
          item.name,
          style: ax.typo.title.copyWith(color: c.text),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: LayoutBuilder(
        builder: (context, box) {
          final pad = AxPage.paddingFor(box.maxWidth);
          final logHeight = (box.maxHeight * 0.6).clamp(320.0, 900.0);
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(pad, ax.space.sm, pad, pad),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AxCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: ax.space.md,
                            runSpacing: ax.space.sm,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              appStatusBadge(item),
                              Text(item.image, style: ax.typo.mono.copyWith(color: c.textMuted)),
                            ],
                          ),
                          SizedBox(height: ax.space.lg),
                          Wrap(
                            spacing: ax.space.xl,
                            runSpacing: ax.space.md,
                            children: [
                              _Fact(label: 'CPU', value: appCpuText(item)),
                              _Fact(label: 'Memory', value: appMemoryText(item)),
                              _Fact(label: 'Ports', value: item.ports),
                              _Fact(label: 'Running for', value: item.uptime),
                              _Fact(label: 'ID', value: shortId),
                            ],
                          ),
                          SizedBox(height: ax.space.lg),
                          Wrap(
                            spacing: ax.space.sm,
                            runSpacing: ax.space.sm,
                            children: [
                              if (open != null)
                                AxButton(label: 'Open', icon: Icons.open_in_new_rounded, onPressed: () => openAppInBrowser(context, open)),
                              if (item.running)
                                AxButton.secondary(
                                  label: 'Stop',
                                  icon: Icons.stop_rounded,
                                  loading: _busy,
                                  onPressed: _busy ? null : () => _act(svc, item, 'stop'),
                                )
                              else
                                AxButton(
                                  label: 'Start',
                                  icon: Icons.play_arrow_rounded,
                                  loading: _busy,
                                  onPressed: _busy ? null : () => _act(svc, item, 'start'),
                                ),
                              AxButton.secondary(
                                label: 'Restart',
                                icon: Icons.restart_alt_rounded,
                                onPressed: _busy ? null : () => _act(svc, item, 'restart'),
                              ),
                              if (item.running)
                                AxButton.secondary(
                                  label: 'Open a shell inside',
                                  icon: Icons.terminal_rounded,
                                  onPressed: () {
                                    final app = context.read<AppState>();
                                    svc.stopLogStream();
                                    Navigator.of(context).pop();
                                    app.openTerminalWithCommand('docker exec -it ${item.name} sh');
                                  },
                                ),
                              AxButton.danger(
                                label: 'Remove',
                                icon: Icons.delete_outline_rounded,
                                onPressed: _busy ? null : () => _remove(svc, item),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: ax.space.lg),
                    SizedBox(
                      height: logHeight,
                      child: AppLogView(logs: svc.liveLogs),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: ax.typo.caption.copyWith(color: c.textMuted)),
        const SizedBox(height: 2),
        Text(value, style: ax.typo.label.copyWith(color: c.text)),
      ],
    );
  }
}
