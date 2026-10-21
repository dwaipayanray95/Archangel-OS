import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../screens/setup/setup_landing_screen.dart';
import '../../../services/archangeld_connection.dart';
import '../../../services/monitoring_service.dart';
import '../../../services/server_registry.dart';
import '../../../services/wireguard_controller.dart';
import '../../shell/connection_state.dart';
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
    final ax = context.ax;
    final registry = context.watch<ServerRegistry>();
    final paired = context.watch<ArchangeldConnection>().isPaired;
    final hostname = paired ? (context.watch<MonitoringService>().metrics?.host.hostname ?? '') : '';
    final active = registry.active;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (active != null) ...[_ActiveConnectionCard(profile: active), SizedBox(height: ax.space.lg)],
        SettingsCard(
          title: 'Servers',
          actions: [
            AxButton.secondary(
              label: 'Add a server',
              icon: Icons.add,
              small: true,
              onPressed:
                  () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SetupLandingScreen(canCancel: true))),
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
        ),
      ],
    );
  }
}

class _ActiveConnectionCard extends StatefulWidget {
  const _ActiveConnectionCard({required this.profile});

  final ServerProfile profile;

  @override
  State<_ActiveConnectionCard> createState() => _ActiveConnectionCardState();
}

class _ActiveConnectionCardState extends State<_ActiveConnectionCard> {
  bool _testing = false;
  int? _pingLatencyMs;
  bool? _pingSuccess;
  bool _reconnecting = false;

  Future<void> _testConnection(BuildContext context) async {
    setState(() {
      _testing = true;
      _pingLatencyMs = null;
      _pingSuccess = null;
    });
    final backend = context.read<ArchangeldConnection>();
    final messenger = ScaffoldMessenger.maybeOf(context);
    final sw = Stopwatch()..start();
    try {
      await backend.checkReachable(timeout: const Duration(seconds: 5));
      sw.stop();
      if (!mounted) return;
      final ok = backend.reachable == true;
      setState(() {
        _pingLatencyMs = sw.elapsedMilliseconds;
        _pingSuccess = ok;
      });
      if (ok) {
        showSnack(messenger, 'Server is responding (${sw.elapsedMilliseconds}ms)');
      } else {
        showSnack(messenger, 'Server unreachable (${sw.elapsedMilliseconds}ms)');
      }
    } catch (_) {
      sw.stop();
      if (!mounted) return;
      setState(() {
        _pingLatencyMs = sw.elapsedMilliseconds;
        _pingSuccess = false;
      });
      showSnack(messenger, 'Connection test failed');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _reconnect(BuildContext context) async {
    setState(() => _reconnecting = true);
    final wg = context.read<WireGuardController>();
    final backend = context.read<ArchangeldConnection>();
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      if (wg.status == TunnelStatus.connected || wg.status == TunnelStatus.connecting) {
        await wg.disconnect();
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      if (wg.isPaired && wg.status != TunnelStatus.unsupported) {
        await wg.connect();
      }
      await backend.checkReachable();
      showSnack(messenger, 'Reconnected to ${widget.profile.name}');
    } catch (e) {
      showSnack(messenger, 'Could not reconnect: $e');
    } finally {
      if (mounted) setState(() => _reconnecting = false);
    }
  }

  Future<void> _connect(BuildContext context) async {
    final wg = context.read<WireGuardController>();
    final backend = context.read<ArchangeldConnection>();
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      if (wg.isPaired && wg.status != TunnelStatus.unsupported) {
        await wg.connect();
      }
      await backend.checkReachable();
    } catch (e) {
      showSnack(messenger, 'Could not connect: $e');
    }
  }

  Future<void> _disconnect(BuildContext context) async {
    final wg = context.read<WireGuardController>();
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await wg.disconnect();
    } catch (e) {
      showSnack(messenger, 'Could not disconnect: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final wg = context.watch<WireGuardController>();
    final backend = context.watch<ArchangeldConnection>();
    final metrics = context.watch<MonitoringService>().metrics;

    final phase = deriveConnectionPhase(
      paired: backend.isPaired,
      tunnel: wg.status,
      reachable: backend.reachable,
      healthFailures: backend.healthFailures,
    );

    final isConnected = phase == ConnectionPhase.connected;
    final isOffline = phase == ConnectionPhase.offline;

    final phaseBadge = switch (phase) {
      ConnectionPhase.connected => const StatusBadge.ok('Online', icon: Icons.check_circle_outline),
      ConnectionPhase.starting || ConnectionPhase.reaching => const StatusBadge.info('Connecting…', icon: Icons.sync),
      ConnectionPhase.serverNotResponding => const StatusBadge.warning('Unresponsive', icon: Icons.warning_amber_rounded),
      ConnectionPhase.offline => const StatusBadge.error('Offline', icon: Icons.cloud_off_outlined),
      ConnectionPhase.notPaired => const StatusBadge.neutral('Not paired'),
    };

    final pingBadgeText =
        _pingLatencyMs != null ? (_pingSuccess == true ? 'Ping: ${_pingLatencyMs}ms' : 'Timeout (${_pingLatencyMs}ms)') : null;

    final tunnelIp = wg.config?.interfaceAddress ?? 'Not assigned';
    final peerEndpoint = wg.config?.peerEndpoint ?? widget.profile.host;
    final daemonVersion = backend.backendVersion != null ? 'v${backend.backendVersion}' : 'Checking…';
    final hostDesc = metrics?.host.hostname != null ? '${widget.profile.host} · ${metrics!.host.hostname}' : widget.profile.host;

    return SettingsCard(
      title: 'Active Connection',
      actions: [phaseBadge],
      children: [
        AxListTile(
          leading: const AxTileIcon(Icons.dns_rounded),
          title: 'Active: ${widget.profile.name}',
          titleMono: true,
          subtitle: hostDesc,
          subtitleMono: true,
          controls: [
            if (pingBadgeText != null)
              _pingSuccess == true
                  ? StatusBadge.ok(pingBadgeText, icon: Icons.speed_rounded)
                  : StatusBadge.error(pingBadgeText, icon: Icons.speed_rounded),
            phaseBadge,
          ],
        ),
        AxListTile(
          leading: const AxTileIcon(Icons.bolt_rounded),
          title: 'Connection controls',
          subtitle:
              _reconnecting
                  ? 'Reconnecting to ${widget.profile.name}…'
                  : (_testing
                      ? 'Testing server response time…'
                      : (_pingLatencyMs != null
                          ? (_pingSuccess == true
                              ? 'Server responding · ${_pingLatencyMs}ms latency'
                              : 'Server unreachable · ${_pingLatencyMs}ms')
                          : 'Manage tunnel connection, reconnect, or ping server.')),
          controls: [
            if (isOffline)
              AxButton(
                key: const ValueKey('active-conn-connect-btn'),
                label: 'Connect',
                icon: Icons.power_settings_new_rounded,
                small: true,
                onPressed: () => _connect(context),
              ),
            AxButton.secondary(
              key: const ValueKey('active-conn-reconnect-btn'),
              label: 'Reconnect',
              icon: Icons.sync_rounded,
              small: true,
              loading: _reconnecting,
              onPressed: _reconnecting ? null : () => _reconnect(context),
            ),
            if (isConnected || wg.status == TunnelStatus.connected || wg.status == TunnelStatus.connecting)
              AxButton.ghost(
                key: const ValueKey('active-conn-disconnect-btn'),
                label: 'Disconnect',
                icon: Icons.power_off_rounded,
                small: true,
                onPressed: () => _disconnect(context),
              ),
            AxButton.secondary(
              key: const ValueKey('active-conn-test-btn'),
              label: _testing ? 'Testing…' : 'Test connection',
              icon: Icons.speed_rounded,
              small: true,
              loading: _testing,
              onPressed: _testing ? null : () => _testConnection(context),
            ),
          ],
        ),
        AxListTile(
          leading: const AxTileIcon(Icons.shield_outlined),
          title: 'WireGuard tunnel',
          subtitle: 'Status: ${wg.status.name} · IP: $tunnelIp · Endpoint: $peerEndpoint',
          subtitleMono: true,
          controls: [
            wg.status == TunnelStatus.connected
                ? const StatusBadge.ok('Mesh active', icon: Icons.hub_outlined)
                : (wg.status == TunnelStatus.connecting || wg.status == TunnelStatus.disconnecting
                    ? StatusBadge.info(wg.status.name, icon: Icons.sync)
                    : StatusBadge.neutral(wg.status.name, icon: Icons.circle_outlined)),
          ],
        ),
        AxListTile(
          leading: const AxTileIcon(Icons.memory_rounded),
          title: 'Daemon API (archangeld)',
          subtitle: 'http://${backend.host ?? widget.profile.host} · $daemonVersion',
          subtitleMono: true,
          controls: [
            backend.reachable == true
                ? const StatusBadge.ok('Healthy', icon: Icons.check)
                : (backend.reachable == false
                    ? const StatusBadge.error('Unreachable', icon: Icons.error_outline)
                    : const StatusBadge.neutral('Checking…', icon: Icons.sync)),
          ],
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
