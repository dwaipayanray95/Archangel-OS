import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../models/container_model.dart';
import '../../../services/containers_service.dart';
import '../../ui.dart';
import 'app_specs.dart';

/// Status badge for an app: icon + words, never colour alone.
Widget appStatusBadge(DockerContainerItem c) {
  if (c.running) return const StatusBadge.ok('Running');
  switch (c.state.toLowerCase()) {
    case 'paused':
      return const StatusBadge.warning('Paused');
    case 'restarting':
      return const StatusBadge.warning('Restarting');
    case 'dead':
      return const StatusBadge.error('Failed');
    default:
      return const StatusBadge.neutral('Stopped', icon: Icons.stop_circle_outlined);
  }
}

String appCpuText(DockerContainerItem c) => c.running ? '${c.cpu.toStringAsFixed(1)}%' : '—';
String appMemoryText(DockerContainerItem c) => c.running && c.memLabel.isNotEmpty ? c.memLabel : '—';

/// "3 running, 1 stopped" - counts in words. Empty server: "No apps yet".
String appCountsSummary(int running, int stopped) {
  if (running == 0 && stopped == 0) return 'No apps yet';
  final parts = <String>[if (running > 0) '$running running', if (stopped > 0) '$stopped stopped'];
  return parts.join(', ');
}

/// Opens the app's web page (a published port on the secure connection).
Future<void> openAppInBrowser(BuildContext context, Uri uri) async {
  final messenger = ScaffoldMessenger.of(context);
  var ok = false;
  try {
    ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    ok = false;
  }
  if (!ok) {
    messenger.showSnackBar(SnackBar(content: Text('Could not open $uri. Make sure the secure connection is on.')));
  }
}

void _toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

/// Starts, stops or restarts [c]. Stop and restart ask first. Returns true
/// when the server accepted the action. Failures show the server's message.
Future<bool> runAppAction(BuildContext context, ContainersService svc, DockerContainerItem c, String action) async {
  if (action == 'stop') {
    final yes = await showConfirmDialog(
      context,
      title: 'Stop ${c.name}?',
      message: 'The app will stop working until you start it again. Its data is kept.',
      confirmLabel: 'Stop app',
    );
    if (!yes || !context.mounted) return false;
  } else if (action == 'restart') {
    final yes = await showConfirmDialog(
      context,
      title: 'Restart ${c.name}?',
      message: 'The app will be briefly unavailable while it restarts.',
      confirmLabel: 'Restart app',
    );
    if (!yes || !context.mounted) return false;
  }
  final ok = await svc.triggerAction(c.id, action);
  if (!context.mounted) return ok;
  final verb = switch (action) {
    'start' => 'started',
    'stop' => 'stopped',
    'restart' => 'restarted',
    _ => 'updated',
  };
  _toast(context, ok ? '${c.name} $verb.' : (svc.lastActionMessage ?? 'Could not $action ${c.name}.'));
  return ok;
}

/// Removes [c] after the person types its name. Returns true when removed.
Future<bool> removeApp(BuildContext context, ContainersService svc, DockerContainerItem c) async {
  final yes = await showConfirmDialog(
    context,
    title: 'Remove ${c.name}?',
    message:
        'This deletes the app "${c.name}". Data saved in folders you shared with it is kept '
        'on your server. Anything stored only inside the app is lost.',
    confirmLabel: 'Remove app',
    danger: true,
    typeToConfirm: c.name,
  );
  if (!yes || !context.mounted) return false;
  final ok = await svc.removeContainer(c.id);
  if (!context.mounted) return ok;
  _toast(context, ok ? '${c.name} was removed.' : (svc.lastActionMessage ?? 'Could not remove ${c.name}.'));
  return ok;
}

/// "Open" link for [c] given the server's host:port, or null when it has no
/// published port.
Uri? appUriFor(DockerContainerItem c, String? serverHost) => c.running ? appOpenUri(serverHost, c.ports) : null;
