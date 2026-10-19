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

/// Devices paired with the active server: list, revoke, and add another.
class DevicesSection extends StatelessWidget {
  const DevicesSection({super.key});

  Future<void> _revoke(BuildContext context, PairedDevice device) async {
    final svc = context.read<DevicesService>();
    final backend = context.read<ArchangeldConnection>();
    final wg = context.read<WireGuardController>();
    final registry = context.read<ServerRegistry>();
    final messenger = ScaffoldMessenger.maybeOf(context);

    final confirmed = await showConfirmDialog(
      context,
      title: 'Revoke "${device.name}"?',
      message: device.current
          ? 'This is the device you are using. It will lose access to the server immediately, and this app will be unpaired. '
              'You will need SSH access to the server to pair again.'
          : 'This device will lose access to the server immediately. It will need to be paired again to reconnect.',
      confirmLabel: 'Revoke',
      danger: true,
      // Cutting your own connection needs the name typed.
      typeToConfirm: device.current ? device.name : null,
    );
    if (!confirmed) return;

    final result = await svc.revoke(device, self: device.current);
    if (!result.success) {
      showSnack(messenger, result.message);
      return;
    }
    if (device.current) {
      // This device just lost access: forget the pairing locally as well.
      await removeActiveServer(registry: registry, wg: wg, backend: backend);
    }
    showSnack(messenger, device.current ? result.message : 'Revoked ${device.name}.');
  }

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final svc = context.watch<DevicesService>();
    return SettingsSection(
      title: 'Devices',
      explanation: 'The phones and computers that can use this server. Revoking one cuts its access immediately.',
      trailing: AxIconButton(
        icon: Icons.refresh,
        tooltip: 'Refresh devices',
        onPressed: svc.loading ? null : svc.refresh,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (svc.error != null)
            Padding(
              padding: EdgeInsets.only(bottom: ax.space.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline, size: 18, color: c.danger),
                  SizedBox(width: ax.space.sm),
                  Expanded(child: Text(svc.error!, style: ax.typo.body.copyWith(color: c.danger))),
                ],
              ),
            ),
          if (svc.loading && !svc.loaded)
            Padding(
              padding: EdgeInsets.only(bottom: ax.space.sm),
              child: const Align(alignment: Alignment.centerLeft, child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
            ),
          if (svc.loaded && svc.devices.isEmpty)
            Padding(
              padding: EdgeInsets.only(bottom: ax.space.sm),
              child: Text('No paired devices.', style: ax.typo.body.copyWith(color: c.textMuted)),
            ),
          for (final d in svc.devices) _DeviceRow(device: d, onRevoke: () => _revoke(context, d)),
          SizedBox(height: ax.space.xs),
          Align(
            alignment: Alignment.centerLeft,
            child: AxButton(label: 'Add a device', icon: Icons.add, onPressed: () => showAddDeviceDialog(context)),
          ),
        ],
      ),
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
    final c = ax.colors;
    final meta = [
      if (device.createdAt != null) 'paired ${formatSettingsDate(device.createdAt!)}',
      if (device.tunnelIp != null) device.tunnelIp!,
    ].join(' · ');
    return Container(
      margin: EdgeInsets.only(bottom: ax.space.sm),
      padding: EdgeInsets.all(ax.space.md),
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(ax.radii.md),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: ax.space.sm,
                  runSpacing: ax.space.xs,
                  children: [
                    Text(device.name, style: ax.typo.label.copyWith(color: c.text)),
                    if (device.current) const StatusBadge.info('This device'),
                  ],
                ),
                if (meta.isNotEmpty) Text(meta, style: ax.typo.caption.copyWith(color: c.textMuted)),
              ],
            ),
          ),
          AxButton.ghost(label: 'Revoke', semanticsLabel: 'Revoke ${device.name}', onPressed: onRevoke),
        ],
      ),
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
      message: 'The terminal and Archangel will no longer be able to run commands as root. '
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
    return SettingsSection(
      title: 'Admin mode',
      explanation: 'Lets the terminal and Archangel run commands as the server\'s administrator. Turn it off for a safer, limited mode.',
      help: const HelpTip(
        title: 'Admin mode',
        message: 'Admin mode gives Archangel permission to run commands with full control of the server (this is called "sudo" or "root"). '
            'You need it to start and stop services, reboot, or add a device. '
            'Switching it off is instant; switching it back on needs your SSH key.',
      ),
      trailing: enabled == null ? null : (enabled ? const StatusBadge.ok('On') : const StatusBadge.neutral('Off')),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (enabled != null)
            MergeSemantics(
              child: SwitchListTile(
                value: enabled,
                onChanged: svc.loading ? null : (v) => _toggle(context, v),
                contentPadding: EdgeInsets.zero,
                title: Text(enabled ? 'Admin mode is on' : 'Admin mode is off', style: ax.typo.body.copyWith(color: c.text)),
              ),
            )
          else if (svc.error == null)
            const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
          if (svc.error != null) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline, size: 18, color: c.danger),
                SizedBox(width: ax.space.sm),
                Expanded(child: Text(svc.error!, style: ax.typo.body.copyWith(color: c.danger))),
              ],
            ),
            SizedBox(height: ax.space.sm),
            AxButton.secondary(label: 'Retry', onPressed: svc.loading ? null : svc.refresh),
          ],
        ],
      ),
    );
  }
}
