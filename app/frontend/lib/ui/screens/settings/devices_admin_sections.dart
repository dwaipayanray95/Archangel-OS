import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../services/admin_mode_service.dart';
import '../../../services/archangeld_connection.dart';
import '../../../services/devices_service.dart';
import '../../../services/server_registry.dart';
import '../../../services/wireguard_controller.dart';
import '../../../widgets/sync_server_config_dialog.dart';
import '../../ui.dart';
import 'add_device_dialog.dart';
import 'settings_parts.dart';

/// Devices paired with the active server: list, remove, and add another.
class DevicesSection extends StatelessWidget {
  const DevicesSection({super.key});

  Future<void> _revoke(BuildContext context, PairedDevice device) async {
    final svc = context.read<DevicesService>();
    final backend = context.read<ArchangeldConnection>();
    final wg = context.read<WireGuardController>();
    final registry = context.read<ServerRegistry>();
    final messenger = ScaffoldMessenger.maybeOf(context);

    final confirmed =
        device.current
            ? await showConfirmDialog(
              context,
              title: 'Revoke "${device.name}"?',
              message:
                  'This is the device you are using. It will lose access to the server immediately, and this app will be unpaired. '
                  'You will need SSH access to the server to pair again.',
              confirmLabel: 'Revoke',
              danger: true,
              // Cutting your own connection needs the name typed.
              typeToConfirm: device.name,
            )
            : await showConfirmDialog(
              context,
              title: 'Remove ${device.name}?',
              message: "It won't be able to reach your server any more.",
              confirmLabel: 'Remove',
              danger: true,
            );
    if (!confirmed) return;

    final result = await svc.revoke(device, self: device.current);
    if (!result.success) {
      showSnack(messenger, result.message);
      return;
    }
    if (device.current) {
      // This device just lost access: forget the pairing locally as well.
      try {
        await removeActiveServer(registry: registry, wg: wg, backend: backend);
      } catch (_) {
        showSnack(messenger, 'Access was revoked, but the next server could not be opened. Pick a server to continue.');
        return;
      }
    }
    showSnack(messenger, device.current ? result.message : 'Revoked ${device.name}.');
  }

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<DevicesService>();
    return SettingsCard(
      title: 'Devices',
      actions: [
        AxIconButton(icon: Icons.refresh, tooltip: 'Refresh', onPressed: svc.loading ? null : svc.refresh),
        AxButton(label: 'Add a device', icon: Icons.qr_code_2, small: true, onPressed: () => showAddDeviceDialog(context)),
      ],
      footnote: 'Only devices listed here can reach your server. Removing one cuts it off straight away.',
      children: [
        if (svc.error != null) SettingsError(svc.error!, onRetry: svc.loading ? null : svc.refresh),
        if (svc.loading && !svc.loaded) const SettingsLoading(),
        if (svc.loaded && svc.devices.isEmpty) const SettingsMessage('No paired devices.'),
        for (final d in svc.devices) _DeviceRow(device: d, onRevoke: () => _revoke(context, d)),
      ],
    );
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({required this.device, required this.onRevoke});

  final PairedDevice device;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final muted = ax.colors.textMuted;
    final created = device.createdAt;
    final ip = device.tunnelIp;
    Widget? subtitle;
    if (created != null || ip != null) {
      subtitle = Text.rich(
        TextSpan(
          style: ax.typo.caption.copyWith(color: muted),
          children: [
            if (created != null) TextSpan(text: 'Paired ${formatSettingsDate(created)}'),
            if (created != null && ip != null) const TextSpan(text: ' · '),
            if (ip != null) TextSpan(text: ip, style: ax.typo.mono.copyWith(color: muted)),
          ],
        ),
      );
    }
    return AxListTile(
      leading: const AxTileIcon(Icons.devices_outlined),
      title: device.name,
      subtitleWidget: subtitle,
      controls: [
        if (device.current) const StatusBadge.accent('This device', icon: Icons.check),
        AxButton.ghost(label: 'Remove', small: true, semanticsLabel: 'Remove ${device.name}', onPressed: onRevoke),
      ],
    );
  }
}

/// Admin mode: whether the archangel user has passwordless sudo on the
/// server. The app can switch it off; switching it on needs SSH.
class AdminModeSection extends StatelessWidget {
  const AdminModeSection({super.key});

  Future<void> _toggle(BuildContext context, bool wantOn) async {
    final svc = context.read<AdminModeService>();
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (wantOn) {
      await showSyncServerConfigDialog(context, mode: SyncServerMode.enableAdminMode);
      await svc.refresh();
      return;
    }
    final ok = await showConfirmDialog(
      context,
      title: 'Turn off Admin mode?',
      message:
          'The terminal and Archangel will no longer be able to run commands as root. '
          'Actions that need root - starting or stopping services, rebooting, revoking devices - will be refused until you turn it back on, '
          'which needs your SSH key.',
      confirmLabel: 'Turn off',
      danger: true,
    );
    if (!ok) return;
    final result = await svc.disable();
    if (!result.success) {
      showSnack(messenger, result.message);
      await svc.refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final svc = context.watch<AdminModeService>();
    final enabled = svc.enabled;
    return AxCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Semantics(header: true, child: Text('Admin mode', style: ax.typo.title.copyWith(color: c.text)))),
              if (enabled != null)
                Semantics(
                  label: 'Admin mode',
                  toggled: enabled,
                  container: true,
                  excludeSemantics: true,
                  onTap: svc.loading ? null : () => _toggle(context, !enabled),
                  child: Switch(value: enabled, onChanged: svc.loading ? null : (v) => _toggle(context, v)),
                ),
            ],
          ),
          if (enabled != null) ...[
            SizedBox(height: ax.space.sm),
            Align(
              alignment: Alignment.centerLeft,
              child:
                  enabled
                      ? const StatusBadge.warning('Administrator commands allowed', icon: Icons.key_outlined)
                      : const StatusBadge.neutral('Administrator commands blocked', icon: Icons.lock_outline),
            ),
            SizedBox(height: ax.space.md),
            Text(
              'When this is on, the app and the terminal can run administrator commands (sudo). '
              'You need it to install software or change system settings.',
              style: ax.typo.body.copyWith(color: c.textMuted),
            ),
            SizedBox(height: ax.space.sm),
            Text(
              'Turn it off if you want a safety net against accidental changes. Your apps keep running either way.',
              style: ax.typo.body.copyWith(color: c.textMuted),
            ),
          ] else if (svc.error == null) ...[
            SizedBox(height: ax.space.md),
            const Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          ],
          if (svc.error != null) ...[
            SizedBox(height: ax.space.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline, size: 18, color: c.danger),
                SizedBox(width: ax.space.sm),
                Expanded(child: Text(svc.error!, style: ax.typo.body.copyWith(color: c.danger))),
              ],
            ),
            SizedBox(height: ax.space.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: AxButton.secondary(label: 'Retry', small: true, onPressed: svc.loading ? null : svc.refresh),
            ),
          ],
        ],
      ),
    );
  }
}
