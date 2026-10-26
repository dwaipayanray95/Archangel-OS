import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../screens/setup/setup_landing_screen.dart';
import '../../services/archangeld_connection.dart';
import '../../services/server_registry.dart';
import '../../services/wireguard_controller.dart';
import '../theme.dart';
import '../components/ax_list_tile.dart';

/// Switches to [profile] and reports a failure in plain words.
Future<void> switchServerWithFeedback(BuildContext context, ServerProfile profile) async {
  final registry = context.read<ServerRegistry>();
  final wg = context.read<WireGuardController>();
  final backend = context.read<ArchangeldConnection>();
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await switchToServer(profile.id, registry: registry, wg: wg, backend: backend);
  } catch (e) {
    messenger?.showSnackBar(SnackBar(content: Text('Could not switch to ${profile.name}: $e')));
  }
}

void openAddServer(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SetupLandingScreen(canCancel: true)));
}

/// The list of servers with the active one checked, plus "Add a server".
/// Used inside the switcher sheet and the phone "More" page.
class ServerList extends StatelessWidget {
  const ServerList({super.key, this.onDone});

  /// Called after a choice is made (e.g. to close the sheet).
  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context) {
    final registry = context.watch<ServerRegistry>();
    final c = context.ax.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final p in registry.profiles)
          AxListTile(
            key: ValueKey('server-${p.id}'),
            title: p.name,
            subtitle: p.host,
            selected: p.id == registry.activeId,
            semanticsLabel: p.id == registry.activeId ? '${p.name}, current server' : 'Switch to ${p.name}',
            leading: Icon(
              p.id == registry.activeId ? Icons.check_circle : Icons.dns_outlined,
              color: p.id == registry.activeId ? c.accent : c.textMuted,
            ),
            onTap: () {
              onDone?.call();
              if (p.id != registry.activeId) switchServerWithFeedback(context, p);
            },
          ),
        AxListTile(
          title: 'Add a server',
          leading: Icon(Icons.add_circle_outline, color: c.accent),
          onTap: () {
            onDone?.call();
            openAddServer(context);
          },
        ),
      ],
    );
  }
}

Future<void> showServerSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(sheetContext.ax.space.lg, 0, sheetContext.ax.space.lg, sheetContext.ax.space.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text('Your servers', style: sheetContext.ax.typo.title.copyWith(color: sheetContext.ax.colors.text)),
            ),
            SizedBox(height: sheetContext.ax.space.sm),
            ServerList(onDone: () => Navigator.of(sheetContext).pop()),
          ],
        ),
      ),
    ),
  );
}

/// A button showing the active server's name that opens the server sheet.
class ServerSwitcher extends StatelessWidget {
  const ServerSwitcher({super.key, this.compact = false});

  /// Icon only (narrow rail).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final registry = context.watch<ServerRegistry>();
    final ax = context.ax;
    final c = ax.colors;
    final name = registry.active?.name ?? 'No server';
    final target = axMinTarget(context);
    return Semantics(
      button: true,
      label: 'Server: $name. Switch server',
      excludeSemantics: true,
      onTap: () => showServerSheet(context),
      child: Tooltip(
        message: 'Switch server',
        child: InkWell(
          onTap: () => showServerSheet(context),
          borderRadius: BorderRadius.circular(ax.radii.md),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: target, minWidth: target),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: ax.space.sm, vertical: ax.space.xs),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.dns_outlined, size: 20, color: c.accent),
                  if (!compact) ...[
                    SizedBox(width: ax.space.sm),
                    Flexible(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ax.typo.label.copyWith(color: c.text),
                      ),
                    ),
                    Icon(Icons.unfold_more, size: 18, color: c.textMuted),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
