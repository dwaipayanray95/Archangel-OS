import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/app_state.dart';
import '../models/container_model.dart';
import '../services/archangeld_connection.dart';
import '../services/containers_service.dart';
import '../ui/screens/apps/app_actions.dart';
import '../ui/screens/apps/app_specs.dart' show publishedPorts;
import '../ui/screens/apps/run_app_page.dart';
import '../ui/ui.dart';
import 'container_detail_screen.dart';

/// Apps: the Docker containers on the server, in plain words.
class ContainersScreen extends StatefulWidget {
  const ContainersScreen({super.key});

  @override
  State<ContainersScreen> createState() => _ContainersScreenState();
}

class _ContainersScreenState extends State<ContainersScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ContainersService>().init(context.read<ArchangeldConnection>());
    });
  }

  void _openDetail(DockerContainerItem c) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ContainerDetailScreen(container: c)));
  }

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<ContainersService>();
    final host = context.watch<ArchangeldConnection>().host;
    final overview = svc.overview;
    final containers = overview?.containers ?? const <DockerContainerItem>[];
    final running = overview?.runningCount ?? containers.where((c) => c.running).length;
    final stopped = overview?.stoppedCount ?? (containers.length - running);
    final dockerUp = overview?.dockerAvailable ?? true;

    final Widget body;
    if (overview == null) {
      body = LoadingState(message: 'Loading your apps...', onRetry: () => svc.fetchContainers());
    } else if (overview.engineVersion == 'disconnected') {
      body = ErrorState(
        title: 'Not connected to your server',
        message: 'Turn on the secure connection to see and manage your apps.',
        onRetry: () => svc.fetchContainers(),
      );
    } else if (!dockerUp) {
      body =
          svc.error != null && overview.engineVersion == 'unreachable'
              ? ErrorState(title: 'Could not reach your server', message: svc.error!, onRetry: () => svc.fetchContainers())
              : EmptyState(
                icon: Icons.sailing_outlined,
                title: 'Docker isn’t running',
                message:
                    'Apps run on Docker, which is switched off on this server right now. '
                    'You can start it in Services.',
                actionLabel: 'Go to Services',
                onAction: () => context.read<AppState>().go(AxSection.services),
              );
    } else if (containers.isEmpty) {
      body = EmptyState(
        icon: Icons.apps_rounded,
        title: 'No apps yet',
        message: 'Run your first app, for example a website, a notes tool or a password manager.',
        actionLabel: 'Run an app',
        onAction: () => RunAppPage.open(context, svc),
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (svc.error != null)
            Padding(padding: EdgeInsets.only(bottom: context.ax.space.lg), child: _Banner(message: 'Could not refresh: ${svc.error}')),
          _AppList(apps: containers, host: host, service: svc, onOpen: _openDetail),
        ],
      );
    }

    final showCounts = overview != null && dockerUp && overview.engineVersion != 'disconnected';
    final scrollBody = overview != null && dockerUp && containers.isNotEmpty && overview.engineVersion != 'disconnected';
    return AxPage(
      title: 'Apps',
      subtitle: showCounts ? appCountsSummary(running, stopped) : null,
      scrollable: scrollBody,
      actions: [
        if (dockerUp && overview != null && overview.engineVersion != 'disconnected')
          AxButton(label: 'Run an app', icon: Icons.add_rounded, onPressed: () => RunAppPage.open(context, svc)),
      ],
      child: body,
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    return Container(
      padding: EdgeInsets.all(ax.space.md),
      decoration: BoxDecoration(
        color: c.warningWash,
        borderRadius: BorderRadius.circular(ax.radii.md),
        border: Border.all(color: c.warning),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: c.warning),
          SizedBox(width: ax.space.sm),
          Expanded(child: Text(message, style: ax.typo.body.copyWith(color: c.text))),
        ],
      ),
    );
  }
}

/// Which apps the list shows.
enum _Filter { all, running, stopped }

/// The apps as one glass list: a single line per app on wide screens, a
/// stacked card-like row on phones. Status is always icon + words.
class _AppList extends StatefulWidget {
  const _AppList({required this.apps, required this.host, required this.service, required this.onOpen});

  final List<DockerContainerItem> apps;
  final String? host;
  final ContainersService service;
  final void Function(DockerContainerItem) onOpen;

  @override
  State<_AppList> createState() => _AppListState();
}

class _AppListState extends State<_AppList> {
  _Filter _filter = _Filter.all;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final running = widget.apps.where((a) => a.running).length;
    final stopped = widget.apps.length - running;
    final shown =
        widget.apps
            .where(
              (a) => switch (_filter) {
                _Filter.all => true,
                _Filter.running => a.running,
                _Filter.stopped => !a.running,
              },
            )
            .toList();
    return LayoutBuilder(
      builder: (context, box) {
        final wide = box.maxWidth >= 760;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: ax.space.sm,
              runSpacing: ax.space.sm,
              children: [
                _FilterChip(
                  label: 'All · ${widget.apps.length}',
                  selected: _filter == _Filter.all,
                  onTap: () => setState(() => _filter = _Filter.all),
                ),
                _FilterChip(
                  label: 'Running · $running',
                  selected: _filter == _Filter.running,
                  onTap: () => setState(() => _filter = _Filter.running),
                ),
                _FilterChip(
                  label: 'Stopped · $stopped',
                  selected: _filter == _Filter.stopped,
                  onTap: () => setState(() => _filter = _Filter.stopped),
                ),
              ],
            ),
            SizedBox(height: ax.space.md),
            AxCard(
              padding: EdgeInsets.zero,
              child:
                  shown.isEmpty
                      ? Padding(
                        padding: EdgeInsets.all(ax.space.lg),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline, color: c.textMuted),
                            SizedBox(width: ax.space.md),
                            Expanded(child: Text('No apps here.', style: ax.typo.body.copyWith(color: c.textMuted))),
                          ],
                        ),
                      )
                      : Column(
                        children: [
                          for (final (i, a) in shown.indexed) ...[
                            if (i > 0) Divider(height: 1, color: c.border),
                            wide
                                ? _WideRow(
                                  app: a,
                                  index: widget.apps.indexOf(a),
                                  host: widget.host,
                                  service: widget.service,
                                  onOpen: () => widget.onOpen(a),
                                )
                                : _NarrowRow(
                                  app: a,
                                  index: widget.apps.indexOf(a),
                                  host: widget.host,
                                  service: widget.service,
                                  onOpen: () => widget.onOpen(a),
                                ),
                          ],
                        ],
                      ),
            ),
            SizedBox(height: ax.space.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock_outline_rounded, size: 16, color: c.textMuted),
                SizedBox(width: ax.space.sm),
                Expanded(
                  child: Text(
                    'Private apps open only on your own devices, through the private connection. Public ones can be reached by anyone with the address.',
                    style: ax.typo.caption.copyWith(color: c.textMuted, fontSize: 12.5),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Show $label',
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: selected ? c.accentWash : c.glass,
        shape: StadiumBorder(side: BorderSide(color: selected ? c.accent : c.border)),
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 36),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: ax.space.md + 2),
              child: Center(
                widthFactor: 1,
                child: Text(
                  label,
                  style: ax.typo.caption.copyWith(color: selected ? c.accent : c.text, fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _portText(DockerContainerItem a) {
  final ports = publishedPorts(a.ports);
  if (ports.isEmpty) return 'No port';
  return ports.length == 1 ? 'Port ${ports.first}' : 'Ports ${ports.join(', ')}';
}

class _NarrowRow extends StatelessWidget {
  const _NarrowRow({required this.app, required this.index, required this.host, required this.service, required this.onOpen});

  final DockerContainerItem app;
  final int index;
  final String? host;
  final ContainersService service;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final open = appUriFor(app, host);
    return Semantics(
      container: true,
      label: 'App ${app.name}',
      child: Padding(
        padding: EdgeInsets.all(ax.space.md + 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AppTile(label: app.name, index: index, size: 40),
                SizedBox(width: ax.space.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(app.name, style: ax.typo.label.copyWith(color: c.text), overflow: TextOverflow.ellipsis),
                      Text(app.image, style: ax.typo.caption.copyWith(color: c.textMuted), overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                SizedBox(width: ax.space.sm),
                appStatusBadge(app),
              ],
            ),
            SizedBox(height: ax.space.sm),
            Padding(
              padding: const EdgeInsets.only(left: 52),
              child: Wrap(
                spacing: ax.space.lg,
                runSpacing: ax.space.xs,
                children: [
                  Text(_portText(app), style: ax.typo.mono.copyWith(color: c.textMuted, fontSize: 12)),
                  Text('CPU ${appCpuText(app)}', style: ax.typo.mono.copyWith(color: c.textMuted, fontSize: 12)),
                  Text('Memory ${appMemoryText(app)}', style: ax.typo.mono.copyWith(color: c.textMuted, fontSize: 12)),
                ],
              ),
            ),
            SizedBox(height: ax.space.md),
            Wrap(
              spacing: ax.space.xs,
              runSpacing: ax.space.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (open != null)
                  AxButton(label: 'Open', icon: Icons.open_in_new_rounded, onPressed: () => openAppInBrowser(context, open)),
                if (app.running)
                  AxButton.secondary(label: 'Stop', icon: Icons.stop_rounded, onPressed: () => runAppAction(context, service, app, 'stop'))
                else
                  AxButton.secondary(
                    label: 'Start',
                    icon: Icons.play_arrow_rounded,
                    onPressed: () => runAppAction(context, service, app, 'start'),
                  ),
                AxIconButton(
                  icon: Icons.restart_alt_rounded,
                  tooltip: 'Restart ${app.name}',
                  onPressed: () => runAppAction(context, service, app, 'restart'),
                ),
                AxIconButton(icon: Icons.notes_rounded, tooltip: 'Logs for ${app.name}', onPressed: onOpen),
                AxButton.ghost(label: 'Remove', icon: Icons.delete_outline_rounded, onPressed: () => removeApp(context, service, app)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _WideRow extends StatelessWidget {
  const _WideRow({required this.app, required this.index, required this.host, required this.service, required this.onOpen});

  final DockerContainerItem app;
  final int index;
  final String? host;
  final ContainersService service;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final open = appUriFor(app, host);
    final mono = ax.typo.mono.copyWith(color: c.textMuted, fontSize: 12.5);
    return InkWell(
      onTap: onOpen,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: ax.space.lg, vertical: ax.space.md),
        child: Row(
          children: [
            AppTile(label: app.name, index: index, size: 38),
            SizedBox(width: ax.space.md),
            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(app.name, style: ax.typo.label.copyWith(color: c.text), overflow: TextOverflow.ellipsis),
                  Text(app.image, style: ax.typo.caption.copyWith(color: c.textMuted), overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            SizedBox(width: 130, child: Align(alignment: Alignment.centerLeft, child: appStatusBadge(app))),
            SizedBox(width: 110, child: Text(_portText(app), style: mono, overflow: TextOverflow.ellipsis)),
            SizedBox(width: 70, child: Text(appCpuText(app), style: mono)),
            SizedBox(width: 90, child: Text(appMemoryText(app), style: mono, overflow: TextOverflow.ellipsis)),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (open != null) AxButton.ghost(label: 'Open', onPressed: () => openAppInBrowser(context, open)),
                AxIconButton(
                  icon: app.running ? Icons.stop_rounded : Icons.play_arrow_rounded,
                  tooltip: app.running ? 'Stop ${app.name}' : 'Start ${app.name}',
                  onPressed: () => runAppAction(context, service, app, app.running ? 'stop' : 'start'),
                ),
                AxIconButton(
                  icon: Icons.restart_alt_rounded,
                  tooltip: 'Restart ${app.name}',
                  onPressed: () => runAppAction(context, service, app, 'restart'),
                ),
                AxIconButton(icon: Icons.notes_rounded, tooltip: 'Logs for ${app.name}', onPressed: onOpen),
                AxIconButton(
                  icon: Icons.delete_outline_rounded,
                  tooltip: 'Remove ${app.name}',
                  color: c.danger,
                  onPressed: () => removeApp(context, service, app),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
