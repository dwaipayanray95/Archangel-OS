import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/app_state.dart';
import '../models/container_model.dart';
import '../services/archangeld_connection.dart';
import '../services/containers_service.dart';
import '../ui/screens/apps/app_actions.dart';
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
    final wide = MediaQuery.sizeOf(context).width >= 900;

    final Widget body;
    if (overview == null) {
      body = LoadingState(
        message: 'Loading your apps...',
        onRetry: () => svc.fetchContainers(),
      );
    } else if (overview.engineVersion == 'disconnected') {
      body = ErrorState(
        title: 'Not connected to your server',
        message: 'Turn on the secure connection to see and manage your apps.',
        onRetry: () => svc.fetchContainers(),
      );
    } else if (!dockerUp) {
      body = svc.error != null && overview.engineVersion == 'unreachable'
          ? ErrorState(
              title: 'Could not reach your server',
              message: svc.error!,
              onRetry: () => svc.fetchContainers(),
            )
          : EmptyState(
              icon: Icons.sailing_outlined,
              title: 'Docker isn’t running',
              message: 'Apps run on Docker, which is switched off on this server right now. '
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
            Padding(
              padding: EdgeInsets.only(bottom: context.ax.space.lg),
              child: _Banner(message: 'Could not refresh: ${svc.error}'),
            ),
          if (wide)
            _AppsTable(apps: containers, host: host, service: svc, onOpen: _openDetail)
          else
            for (final a in containers)
              Padding(
                padding: EdgeInsets.only(bottom: context.ax.space.md),
                child: _AppCard(app: a, host: host, service: svc, onOpen: () => _openDetail(a)),
              ),
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
          AxButton(
            label: 'Run an app',
            icon: Icons.add_rounded,
            onPressed: () => RunAppPage.open(context, svc),
          ),
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

class _AppCard extends StatelessWidget {
  const _AppCard({required this.app, required this.host, required this.service, required this.onOpen});

  final DockerContainerItem app;
  final String? host;
  final ContainersService service;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final open = appUriFor(app, host);
    return AxCard(
      onTap: onOpen,
      semanticsLabel: 'App ${app.name}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(app.name, style: ax.typo.title.copyWith(color: c.text), overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(app.image, style: ax.typo.caption.copyWith(color: c.textMuted), overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              SizedBox(width: ax.space.sm),
              appStatusBadge(app),
            ],
          ),
          SizedBox(height: ax.space.md),
          Wrap(
            spacing: ax.space.xl,
            runSpacing: ax.space.xs,
            children: [
              Text('CPU ${appCpuText(app)}', style: ax.typo.body.copyWith(color: c.textMuted)),
              Text('Memory ${appMemoryText(app)}', style: ax.typo.body.copyWith(color: c.textMuted)),
            ],
          ),
          SizedBox(height: ax.space.md),
          Wrap(
            spacing: ax.space.sm,
            runSpacing: ax.space.sm,
            children: [
              if (open != null)
                AxButton(label: 'Open', icon: Icons.open_in_new_rounded, onPressed: () => openAppInBrowser(context, open)),
              if (app.running)
                AxButton.secondary(label: 'Stop', icon: Icons.stop_rounded, onPressed: () => runAppAction(context, service, app, 'stop'))
              else
                AxButton.secondary(label: 'Start', icon: Icons.play_arrow_rounded, onPressed: () => runAppAction(context, service, app, 'start')),
              AxButton.secondary(label: 'Restart', icon: Icons.restart_alt_rounded, onPressed: () => runAppAction(context, service, app, 'restart')),
              AxButton.secondary(label: 'Logs', icon: Icons.notes_rounded, onPressed: onOpen),
              AxButton.ghost(label: 'Remove', icon: Icons.delete_outline_rounded, onPressed: () => removeApp(context, service, app)),
            ],
          ),
        ],
      ),
    );
  }
}

class _AppsTable extends StatelessWidget {
  const _AppsTable({required this.apps, required this.host, required this.service, required this.onOpen});

  final List<DockerContainerItem> apps;
  final String? host;
  final ContainersService service;
  final void Function(DockerContainerItem) onOpen;

  static const _statusW = 130.0;
  static const _numW = 90.0;
  static const _memW = 110.0;
  static const _actionsW = 310.0;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    Widget head(String t) => Text(t, style: ax.typo.caption.copyWith(color: c.textMuted, fontWeight: FontWeight.w700));
    return AxCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: ax.space.lg, vertical: ax.space.md),
            child: Row(
              children: [
                Expanded(flex: 3, child: head('Name')),
                Expanded(flex: 3, child: head('Image')),
                SizedBox(width: _statusW, child: head('Status')),
                SizedBox(width: _numW, child: head('CPU')),
                SizedBox(width: _memW, child: head('Memory')),
                const SizedBox(width: _actionsW),
              ],
            ),
          ),
          for (final a in apps) ...[
            Divider(color: c.border),
            _row(context, a),
          ],
        ],
      ),
    );
  }

  Widget _row(BuildContext context, DockerContainerItem a) {
    final ax = context.ax;
    final c = ax.colors;
    final open = appUriFor(a, host);
    return InkWell(
      onTap: () => onOpen(a),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: ax.space.lg, vertical: ax.space.sm),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Text(a.name, style: ax.typo.label.copyWith(color: c.text), overflow: TextOverflow.ellipsis),
            ),
            Expanded(
              flex: 3,
              child: Text(a.image, style: ax.typo.body.copyWith(color: c.textMuted), overflow: TextOverflow.ellipsis),
            ),
            SizedBox(width: _statusW, child: Align(alignment: Alignment.centerLeft, child: appStatusBadge(a))),
            SizedBox(width: _numW, child: Text(appCpuText(a), style: ax.typo.body.copyWith(color: c.text))),
            SizedBox(width: _memW, child: Text(appMemoryText(a), style: ax.typo.body.copyWith(color: c.text), overflow: TextOverflow.ellipsis)),
            SizedBox(
              width: _actionsW,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (open != null)
                    AxButton.ghost(label: 'Open', onPressed: () => openAppInBrowser(context, open)),
                  AxIconButton(
                    icon: a.running ? Icons.stop_rounded : Icons.play_arrow_rounded,
                    tooltip: a.running ? 'Stop ${a.name}' : 'Start ${a.name}',
                    onPressed: () => runAppAction(context, service, a, a.running ? 'stop' : 'start'),
                  ),
                  AxIconButton(
                    icon: Icons.restart_alt_rounded,
                    tooltip: 'Restart ${a.name}',
                    onPressed: () => runAppAction(context, service, a, 'restart'),
                  ),
                  AxIconButton(icon: Icons.notes_rounded, tooltip: 'Logs for ${a.name}', onPressed: () => onOpen(a)),
                  AxIconButton(
                    icon: Icons.delete_outline_rounded,
                    tooltip: 'Remove ${a.name}',
                    color: c.danger,
                    onPressed: () => removeApp(context, service, a),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
