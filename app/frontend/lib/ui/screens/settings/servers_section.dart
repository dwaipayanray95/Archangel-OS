import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../screens/setup/setup_landing_screen.dart';
import '../../../services/archangeld_connection.dart';
import '../../../services/monitoring_service.dart';
import '../../../services/server_registry.dart';
import '../../../services/wireguard_controller.dart';
import '../../ui.dart';
import 'settings_parts.dart';

/// Every server this device knows: which one is in use, switch, rename,
/// remove (forget) and add another.
class ServersSection extends StatelessWidget {
  const ServersSection({super.key});

  Future<void> _switch(BuildContext context, ServerProfile p) async {
    final registry = context.read<ServerRegistry>();
    final wg = context.read<WireGuardController>();
    final backend = context.read<ArchangeldConnection>();
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await switchToServer(p.id, registry: registry, wg: wg, backend: backend);
    } catch (_) {
      showSnack(messenger, 'Could not switch to ${p.name}. Check your connection and try again.');
    }
  }

  Future<void> _rename(BuildContext context, ServerProfile p) async {
    final registry = context.read<ServerRegistry>();
    final name = await showDialog<String>(context: context, builder: (_) => _RenameDialog(initial: p.name));
    if (name != null && name.trim().isNotEmpty) await registry.rename(p.id, name);
  }

  Future<void> _remove(BuildContext context, ServerProfile p) async {
    final registry = context.read<ServerRegistry>();
    final wg = context.read<WireGuardController>();
    final backend = context.read<ArchangeldConnection>();
    final messenger = ScaffoldMessenger.maybeOf(context);
    final ok = await showConfirmDialog(
      context,
      title: 'Remove "${p.name}"?',
      message:
          'This only forgets the server on this device. The server itself keeps running and is not changed, '
          'and this device stays in its list of paired devices until you revoke it.',
      confirmLabel: 'Remove',
      danger: true,
    );
    if (!ok) return;
    try {
      if (registry.activeId == p.id) {
        await removeActiveServer(registry: registry, wg: wg, backend: backend);
      } else {
        await registry.remove(p.id);
      }
    } catch (_) {
      showSnack(messenger, 'Could not remove ${p.name} cleanly. Check the other server and try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final registry = context.watch<ServerRegistry>();
    final paired = context.watch<ArchangeldConnection>().isPaired;
    final hostname = paired ? (context.watch<MonitoringService>().metrics?.host.hostname ?? '') : '';
    return SettingsCard(
      title: 'Servers',
      actions: [
        AxButton.secondary(
          label: 'Add a server',
          icon: Icons.add,
          small: true,
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SetupLandingScreen(canCancel: true))),
        ),
      ],
      children: [
        if (registry.isEmpty) const SettingsMessage('No servers yet.'),
        for (final p in registry.profiles)
          _ServerRow(
            key: ValueKey('server-row-${p.id}'),
            profile: p,
            active: p.id == registry.activeId,
            computerName: p.id == registry.activeId ? hostname : '',
            onSwitch: () => _switch(context, p),
            onRename: () => _rename(context, p),
            onRemove: () => _remove(context, p),
          ),
      ],
    );
  }
}

enum _ServerMenu { rename, remove }

class _ServerRow extends StatelessWidget {
  const _ServerRow({
    super.key,
    required this.profile,
    required this.active,
    required this.computerName,
    required this.onSwitch,
    required this.onRename,
    required this.onRemove,
  });

  final ServerProfile profile;
  final bool active;

  /// The server's own computer name; empty when it isn't known.
  final String computerName;
  final VoidCallback onSwitch;
  final VoidCallback onRename;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return AxListTile(
      leading: const AxTileIcon(Icons.dns_outlined),
      title: profile.name,
      titleMono: true,
      subtitle: computerName.isEmpty ? profile.host : '${profile.host} · $computerName',
      subtitleMono: true,
      controls: [
        if (active)
          const StatusBadge.ok('In use', icon: Icons.check)
        else
          AxButton.secondary(label: 'Switch to it', small: true, semanticsLabel: 'Switch to ${profile.name}', onPressed: onSwitch),
        PopupMenuButton<_ServerMenu>(
          key: ValueKey('server-menu-${profile.id}'),
          tooltip: 'More for ${profile.name}',
          icon: const Icon(Icons.more_horiz),
          onSelected: (m) => m == _ServerMenu.rename ? onRename() : onRemove(),
          itemBuilder:
              (_) => const [
                PopupMenuItem(value: _ServerMenu.rename, child: Text('Rename')),
                PopupMenuItem(value: _ServerMenu.remove, child: Text('Remove')),
              ],
        ),
      ],
    );
  }
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initial});
  final String initial;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final v = _controller.text.trim();
    if (v.isNotEmpty) Navigator.of(context).pop(v);
  }

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    return AlertDialog(
      scrollable: true,
      title: Text('Rename server', style: ax.typo.title.copyWith(color: ax.colors.text)),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: TextField(
          controller: _controller,
          autofocus: true,
          maxLength: 40,
          onSubmitted: (_) => _submit(),
          decoration: const InputDecoration(labelText: 'Server name'),
        ),
      ),
      actions: [AxButton.ghost(label: 'Cancel', onPressed: () => Navigator.of(context).pop()), AxButton(label: 'Save', onPressed: _submit)],
    );
  }
}
