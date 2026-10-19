import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../screens/setup/setup_landing_screen.dart';
import '../../../services/archangeld_connection.dart';
import '../../../services/server_registry.dart';
import '../../../services/wireguard_controller.dart';
import '../../ui.dart';
import 'settings_parts.dart';

/// Every server this device knows: which one is active, switch, rename,
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
      message: 'This only forgets the server on this device. The server itself keeps running and is not changed, '
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
    final ax = context.ax;
    final registry = context.watch<ServerRegistry>();
    return SettingsSection(
      title: 'Servers',
      explanation: 'The servers this device can manage. One is active at a time.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (registry.isEmpty)
            Padding(
              padding: EdgeInsets.only(bottom: ax.space.sm),
              child: Text('No servers yet.', style: ax.typo.body.copyWith(color: ax.colors.textMuted)),
            ),
          for (final p in registry.profiles)
            _ServerRow(
              key: ValueKey('server-row-${p.id}'),
              profile: p,
              active: p.id == registry.activeId,
              onSwitch: () => _switch(context, p),
              onRename: () => _rename(context, p),
              onRemove: () => _remove(context, p),
            ),
          SizedBox(height: ax.space.xs),
          Align(
            alignment: Alignment.centerLeft,
            child: AxButton.secondary(
              label: 'Add a server',
              icon: Icons.add,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const SetupLandingScreen(canCancel: true)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ServerRow extends StatelessWidget {
  const _ServerRow({
    super.key,
    required this.profile,
    required this.active,
    required this.onSwitch,
    required this.onRename,
    required this.onRemove,
  });

  final ServerProfile profile;
  final bool active;
  final VoidCallback onSwitch;
  final VoidCallback onRename;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    return Container(
      margin: EdgeInsets.only(bottom: ax.space.sm),
      padding: EdgeInsets.all(ax.space.md),
      decoration: BoxDecoration(
        color: active ? c.accentWash : c.surfaceAlt,
        borderRadius: BorderRadius.circular(ax.radii.md),
        border: Border.all(color: active ? c.accent : c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: ax.space.sm,
            runSpacing: ax.space.xs,
            children: [
              Text(profile.name, style: ax.typo.label.copyWith(color: c.text)),
              if (active) const StatusBadge.ok('Active'),
            ],
          ),
          SizedBox(height: ax.space.xs),
          Text(profile.host, style: ax.typo.mono.copyWith(color: c.textMuted)),
          SizedBox(height: ax.space.sm),
          Wrap(
            spacing: ax.space.sm,
            runSpacing: ax.space.xs,
            children: [
              if (!active) AxButton(label: 'Switch', semanticsLabel: 'Switch to ${profile.name}', onPressed: onSwitch),
              AxButton.ghost(label: 'Rename', semanticsLabel: 'Rename ${profile.name}', onPressed: onRename),
              AxButton.ghost(label: 'Remove', semanticsLabel: 'Remove ${profile.name}', onPressed: onRemove),
            ],
          ),
        ],
      ),
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
      actions: [
        AxButton.ghost(label: 'Cancel', onPressed: () => Navigator.of(context).pop()),
        AxButton(label: 'Save', onPressed: _submit),
      ],
    );
  }
}
