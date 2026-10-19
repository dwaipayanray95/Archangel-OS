import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/app_state.dart';
import '../services/admin_mode_service.dart';
import '../services/app_version.dart';
import '../services/archangeld_connection.dart';
import '../services/devices_service.dart';
import '../services/monitoring_service.dart';
import '../services/semver.dart';
import '../services/ssh_credentials.dart';
import '../services/tunnel_config.dart';
import '../services/update_check_service.dart';
import '../services/wireguard_controller.dart';
import '../theme/tokens.dart';
import '../widgets/ax_widgets.dart';
import '../widgets/backend_update_dialog.dart';
import '../widgets/manage_ssh_key_dialog.dart';
import '../widgets/pairing_dialog.dart';
import '../widgets/passphrase_prompt_dialog.dart';
import '../widgets/sync_server_config_dialog.dart';
import '../widgets/uninstall_dialog.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  /// The backend host the devices/Admin-mode services were last pointed at,
  /// so they (re)load when pairing changes while this screen is open.
  String? _servicesHost;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<UpdateCheckService>().checkForUpdates();
    });
  }

  void _syncBackendServices(ArchangeldConnection backend) {
    final host = backend.isPaired ? backend.host : null;
    if (host == _servicesHost) return;
    _servicesHost = host;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<DevicesService>().init(backend);
      context.read<AdminModeService>().init(backend);
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final backend = context.watch<ArchangeldConnection>();
    final updates = context.watch<UpdateCheckService>();
    final devices = context.watch<DevicesService>();
    final hostname = context.watch<MonitoringService>().metrics?.host.hostname ?? '';
    _syncBackendServices(backend);
    final ver = AppVersion.current;
    final backendVer = backend.isPaired
        ? (backend.backendVersion != null
            ? 'v${backend.backendVersion}'
            : (backend.backendChecking ? 'checking…' : (backend.backendVersionError ?? 'offline')))
        : 'not paired';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Settings', style: AxTextStyles.h1),
          const SizedBox(height: 3),
          Text(
            backend.isPaired && devices.loaded
                ? 'Archangel v${AppVersion.archangel} · ${devices.devices.length} paired ${devices.devices.length == 1 ? 'device' : 'devices'}'
                : 'Archangel v${AppVersion.archangel}',
            style: AxTextStyles.mutedMono,
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, c) {
              final narrow = c.maxWidth < 700;
              final left = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _TunnelCard(),
                  const SizedBox(height: 11),
                  const _BackendCard(),
                  if (backend.isPaired) ...[
                    const SizedBox(height: 11),
                    const _DevicesCard(),
                  ],
                ],
              );
              final right = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AxCard(
                    padding: const EdgeInsets.all(15),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Appearance', style: AxTextStyles.sans.copyWith(fontSize: 12.5, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 11),
                        Text('Accent', style: AxTextStyles.sans.copyWith(fontSize: 11, color: AxColors.fg3)),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            for (final c in AxColors.accentOptions)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: GestureDetector(
                                  onTap: () => app.accent = c,
                                  child: AnimatedContainer(
                                    duration: AxMotion.base,
                                    width: 30,
                                    height: 30,
                                    decoration: BoxDecoration(
                                      color: c,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: app.accent == c ? AxColors.fg : Colors.transparent, width: 2),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 11),
                  AxCard(
                    padding: const EdgeInsets.all(15),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text('About', style: AxTextStyles.sans.copyWith(fontSize: 12.5, fontWeight: FontWeight.w700)),
                            const Spacer(),
                            GestureDetector(
                              onTap: updates.checking ? null : () => updates.checkForUpdates(force: true),
                              child: Padding(
                                padding: const EdgeInsets.all(2),
                                child: updates.checking
                                    ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5))
                                    : Icon(Icons.refresh, size: 14, color: AxColors.fg3),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _KvRow(
                          'Archangel version',
                          'v${AppVersion.archangel}',
                          divider: false,
                          updateAvailable: isUpdateAvailable(current: AppVersion.archangel, latest: updates.latestArchangel)
                              ? updates.latestArchangel
                              : null,
                        ),
                        _KvRow(
                          'App version',
                          'v$ver',
                          divider: false,
                          updateAvailable: isUpdateAvailable(current: ver, latest: updates.latestFrontend)
                              ? updates.latestFrontend
                              : null,
                        ),
                        _KvRow(
                          'Backend version',
                          backendVer,
                          divider: false,
                          updateAvailable: backend.isPaired && isUpdateAvailable(current: backend.backendVersion, latest: updates.latestBackend)
                              ? updates.latestBackend
                              : null,
                          onUpdateTap: (backend.isPaired && updates.latestBackend != null && updates.backendTag != null)
                              ? () => showBackendUpdateDialog(context, targetVersion: updates.latestBackend!, releaseTag: updates.backendTag!)
                              : null,
                        ),
                        if (backend.isPaired && hostname.isNotEmpty) _KvRow('Host', hostname, divider: false),
                      ],
                    ),
                  ),
                  if (backend.isPaired) ...[
                    const SizedBox(height: 11),
                    const _AdminModeCard(),
                    const SizedBox(height: 11),
                    AxCard(
                      padding: const EdgeInsets.all(15),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('SSH key & Server Config', style: AxTextStyles.sans.copyWith(fontSize: 12.5, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 8),
                          Text(
                            'Manage the remembered SSH key (protected by a passphrase), or synchronize the server service unit and permissions to the latest release.',
                            style: AxTextStyles.sans.copyWith(fontSize: 11.5, color: AxColors.fg3, height: 1.4),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              OutlinedButton(
                                onPressed: () => showManageSshKeyDialog(context),
                                child: const Text('Manage SSH key'),
                              ),
                              OutlinedButton(
                                onPressed: () => _changePassphrase(context),
                                child: const Text('Change passphrase'),
                              ),
                              FilledButton.tonalIcon(
                                icon: const Icon(Icons.sync_rounded, size: 14),
                                label: const Text('Sync server permissions'),
                                onPressed: () => showSyncServerConfigDialog(context),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 11),
                    AxCard(
                      padding: const EdgeInsets.all(15),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Danger zone', style: AxTextStyles.sans.copyWith(fontSize: 12.5, fontWeight: FontWeight.w700, color: AxColors.bad)),
                          const SizedBox(height: 8),
                          Text(
                            'Stops and removes archangeld and WireGuard from the paired server entirely.',
                            style: AxTextStyles.sans.copyWith(fontSize: 11.5, color: AxColors.fg3, height: 1.4),
                          ),
                          const SizedBox(height: 10),
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(foregroundColor: AxColors.bad, side: BorderSide(color: AxColors.bad)),
                            onPressed: () => showUninstallDialog(context),
                            child: const Text('Uninstall backend'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              );

              if (narrow) return Column(children: [left, const SizedBox(height: 11), right]);
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [Expanded(child: left), const SizedBox(width: 11), Expanded(child: right)],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _KvRow extends StatelessWidget {
  final String k;
  final String v;
  final bool divider;

  /// The newer version string, if this row's component is behind what
  /// GitHub's latest release manifest reports - renders a small
  /// tappable badge linking to the release page. Null when up to date
  /// or when there's no update info to compare against yet.
  final String? updateAvailable;

  /// If set, tapping the badge calls this instead of opening the GitHub
  /// release page - used for the Backend row, whose "update" is
  /// something this app can actually do (see BackendUpdateDialog),
  /// unlike the Archangel/App rows which are just informational.
  final VoidCallback? onUpdateTap;

  const _KvRow(this.k, this.v, {this.divider = true, this.updateAvailable, this.onUpdateTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: divider ? const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0x0AE8F0E6)))) : null,
      child: Row(
        children: [
          SizedBox(width: 132, child: Text(k, style: AxTextStyles.sans.copyWith(fontSize: 11, color: AxColors.fg3))),
          Expanded(child: Text(v, style: AxTextStyles.mono.copyWith(fontSize: 11.5), overflow: TextOverflow.ellipsis)),
          if (updateAvailable != null) _UpdateBadge(newerVersion: updateAvailable!, onTap: onUpdateTap, actionLabel: onUpdateTap != null ? 'update' : null),
        ],
      ),
    );
  }
}

class _UpdateBadge extends StatelessWidget {
  final String newerVersion;
  final VoidCallback? onTap;
  final String? actionLabel;
  const _UpdateBadge({required this.newerVersion, this.onTap, this.actionLabel});

  @override
  Widget build(BuildContext context) {
    final releaseUrl = context.watch<UpdateCheckService>().releaseUrl;
    final tapHandler = onTap ?? (releaseUrl == null ? null : () => launchUrl(Uri.parse(releaseUrl), mode: LaunchMode.externalApplication));
    return GestureDetector(
      onTap: tapHandler,
      child: Container(
        margin: const EdgeInsets.only(left: 6),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: AxColors.warn.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(AxRadius.pill)),
        child: Text(
          actionLabel != null ? 'v$newerVersion - $actionLabel' : 'v$newerVersion available',
          style: AxTextStyles.mono.copyWith(fontSize: 9.5, fontWeight: FontWeight.w600, color: AxColors.warn),
        ),
      ),
    );
  }
}

/// Yes/no confirmation in the app's dialog style. Returns false if dismissed.
Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = true,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: AxColors.s2,
      title: Text(title, style: AxTextStyles.sans.copyWith(fontSize: 15, fontWeight: FontWeight.w700)),
      content: SizedBox(
        width: 400,
        child: Text(message, style: AxTextStyles.sans.copyWith(fontSize: 12, color: AxColors.fg2, height: 1.5)),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        FilledButton(
          style: destructive ? FilledButton.styleFrom(backgroundColor: AxColors.bad, foregroundColor: Colors.white) : null,
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

void _snack(ScaffoldMessengerState messenger, String message) {
  messenger.showSnackBar(SnackBar(content: Text(message)));
}

/// "Change passphrase" for the saved SSH key: asks for the current and a new
/// passphrase, then re-encrypts the saved key.
Future<void> _changePassphrase(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  if (!await hasSavedSshCredentials()) {
    _snack(messenger, 'No SSH key is saved yet - use "Manage SSH key" to save one.');
    return;
  }
  if (!context.mounted) return;
  final result = await promptToChangePassphrase(context);
  if (result == null) return;
  try {
    await changeSshCredentialsPassphrase(result.$1, result.$2);
    _snack(messenger, 'Passphrase changed.');
  } on WrongPassphraseException {
    _snack(messenger, 'The current passphrase is incorrect.');
  } catch (e) {
    _snack(messenger, 'Could not change the passphrase: $e');
  }
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _formatDate(DateTime d) {
  final l = d.toLocal();
  return '${_months[l.month - 1]} ${l.day}, ${l.year}';
}

/// Paired devices as reported by the backend, with per-device revoke.
class _DevicesCard extends StatelessWidget {
  const _DevicesCard();

  Future<void> _revoke(BuildContext context, PairedDevice device) async {
    final svc = context.read<DevicesService>();
    final backend = context.read<ArchangeldConnection>();
    final wg = context.read<WireGuardController>();
    final messenger = ScaffoldMessenger.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _RevokeDeviceDialog(device: device),
    );
    if (confirmed != true) return;

    final result = await svc.revoke(device, self: device.current);
    if (!result.success) {
      _snack(messenger, result.message);
      return;
    }
    if (device.current) {
      // This device just lost access: forget the pairing locally as well.
      await backend.unpair();
      await wg.unpair();
    }
    _snack(messenger, device.current ? result.message : 'Revoked ${device.name}.');
  }

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<DevicesService>();
    return AxCard(
      padding: const EdgeInsets.all(15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Devices', style: AxTextStyles.sans.copyWith(fontSize: 12.5, fontWeight: FontWeight.w700)),
              const Spacer(),
              GestureDetector(
                onTap: svc.loading ? null : svc.refresh,
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: svc.loading
                      ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5))
                      : Icon(Icons.refresh, size: 14, color: AxColors.fg3),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('Devices paired with this server. Revoking one cuts its access immediately.',
              style: AxTextStyles.sans.copyWith(fontSize: 11.5, color: AxColors.fg2)),
          const SizedBox(height: 11),
          if (svc.error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(svc.error!, style: AxTextStyles.mono.copyWith(fontSize: 10.5, color: AxColors.bad)),
            ),
          if (svc.loaded && svc.devices.isEmpty)
            Text('No paired devices.', style: AxTextStyles.sans.copyWith(fontSize: 11.5, color: AxColors.fg3)),
          for (final d in svc.devices) _DeviceRow(device: d, onRevoke: () => _revoke(context, d)),
        ],
      ),
    );
  }
}

class _DeviceRow extends StatelessWidget {
  final PairedDevice device;
  final VoidCallback onRevoke;
  const _DeviceRow({required this.device, required this.onRevoke});

  @override
  Widget build(BuildContext context) {
    final meta = [
      if (device.createdAt != null) 'paired ${_formatDate(device.createdAt!)}',
      if (device.tunnelIp != null) device.tunnelIp!,
    ].join(' · ');
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(color: AxColors.s2, borderRadius: BorderRadius.circular(11), border: Border.all(color: AxColors.line)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(device.name, style: AxTextStyles.sans.copyWith(fontSize: 12, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                    ),
                    if (device.current) ...[
                      const SizedBox(width: 7),
                      AxPill(text: 'This device', color: AxColors.accent),
                    ],
                  ],
                ),
                if (meta.isNotEmpty) Text(meta, style: AxTextStyles.mono.copyWith(fontSize: 10.5, color: AxColors.fg3)),
              ],
            ),
          ),
          AxGhostButton(label: 'Revoke', color: AxColors.bad, onTap: onRevoke),
        ],
      ),
    );
  }
}

/// Confirms revoking a device. For the device in use, the user must also
/// type its name - it cuts their own connection to the server.
class _RevokeDeviceDialog extends StatefulWidget {
  final PairedDevice device;
  const _RevokeDeviceDialog({required this.device});

  @override
  State<_RevokeDeviceDialog> createState() => _RevokeDeviceDialogState();
}

class _RevokeDeviceDialogState extends State<_RevokeDeviceDialog> {
  final _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final device = widget.device;
    final canRevoke = !device.current || _nameController.text.trim() == device.name;
    return AlertDialog(
      backgroundColor: AxColors.s2,
      title: Text('Revoke "${device.name}"?', style: AxTextStyles.sans.copyWith(fontSize: 15, fontWeight: FontWeight.w700)),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              device.current
                  ? 'This is the device you are using. It will lose access to the server immediately, and this app will be unpaired. '
                      'You will need SSH access to the server to pair again.'
                  : 'This device will lose access to the server immediately. It will need to be paired again to reconnect.',
              style: AxTextStyles.sans.copyWith(fontSize: 12, color: AxColors.fg2, height: 1.5),
            ),
            if (device.current) ...[
              const SizedBox(height: 12),
              Text('Type "${device.name}" to confirm', style: AxTextStyles.sans.copyWith(fontSize: 11, color: AxColors.fg3)),
              const SizedBox(height: 4),
              TextField(
                controller: _nameController,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                style: AxTextStyles.mono.copyWith(fontSize: 12),
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: AxColors.s1,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: AxColors.line)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: AxColors.line)),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AxColors.bad, foregroundColor: Colors.white),
          onPressed: canRevoke ? () => Navigator.of(context).pop(true) : null,
          child: const Text('Revoke'),
        ),
      ],
    );
  }
}

/// Admin mode: whether the archangel user has passwordless sudo on the
/// server. The app can switch it off; switching it on needs SSH.
class _AdminModeCard extends StatelessWidget {
  const _AdminModeCard();

  Future<void> _toggle(BuildContext context, bool wantOn) async {
    final svc = context.read<AdminModeService>();
    final messenger = ScaffoldMessenger.of(context);
    if (wantOn) {
      await showSyncServerConfigDialog(context, mode: SyncServerMode.enableAdminMode);
      await svc.refresh();
      return;
    }
    final ok = await _confirm(
      context,
      title: 'Turn off Admin mode?',
      message: 'The terminal and Archangel will no longer be able to run commands as root. '
          'Actions that need root - starting or stopping services, rebooting, revoking devices - will be refused until you turn it back on, '
          'which needs your SSH key.',
      confirmLabel: 'Turn off',
    );
    if (!ok) return;
    final result = await svc.disable();
    if (!result.success) {
      _snack(messenger, result.message);
      await svc.refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<AdminModeService>();
    final enabled = svc.enabled;
    final known = enabled != null;
    return AxCard(
      padding: const EdgeInsets.all(15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Admin mode', style: AxTextStyles.sans.copyWith(fontSize: 12.5, fontWeight: FontWeight.w700)),
              const Spacer(),
              if (known) AxPill(text: enabled ? 'on' : 'off', color: enabled ? AxColors.accent : AxColors.fg3),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Admin mode lets the terminal and Archangel run commands as root (sudo). '
            'Turn it off for a safer, limited mode. Turning it back on needs your SSH key.',
            style: AxTextStyles.sans.copyWith(fontSize: 11.5, color: AxColors.fg3, height: 1.4),
          ),
          const SizedBox(height: 10),
          if (known)
            Row(
              children: [
                Switch(value: enabled, onChanged: svc.loading ? null : (v) => _toggle(context, v)),
                const SizedBox(width: 6),
                Text(enabled ? 'Enabled' : 'Disabled', style: AxTextStyles.sans.copyWith(fontSize: 11.5, color: AxColors.fg2)),
              ],
            )
          else if (svc.error == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.5)),
            ),
          if (svc.error != null) ...[
            Text(svc.error!, style: AxTextStyles.mono.copyWith(fontSize: 10.5, color: AxColors.bad)),
            const SizedBox(height: 8),
            AxGhostButton(label: 'Retry', onTap: svc.loading ? null : svc.refresh),
          ],
        ],
      ),
    );
  }
}

class _FilledPill extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const _FilledPill({required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
      decoration: BoxDecoration(color: AxColors.wash, borderRadius: BorderRadius.circular(AxRadius.pill), border: Border.all(color: AxColors.accent.withValues(alpha: 0.22))),
      child: Text(label, style: AxTextStyles.sans.copyWith(fontSize: 11.5, fontWeight: FontWeight.w700, color: AxColors.accent)),
    );
    return onTap == null ? pill : GestureDetector(onTap: onTap, child: pill);
  }
}

/// The Tunnel card on Settings: real WireGuard state (via
/// [WireGuardController]), pair/unpair, connect/disconnect, view config.
/// Real archangeld host/token pairing (host:port + auth token, stored in
/// the local app-state file — see local_kv_store.dart) — same connection
/// the Terminal screen uses.
class _BackendCard extends StatelessWidget {
  const _BackendCard();

  @override
  Widget build(BuildContext context) {
    final backend = context.watch<ArchangeldConnection>();
    return AxCard(
      padding: const EdgeInsets.all(15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Backend', style: AxTextStyles.sans.copyWith(fontSize: 12.5, fontWeight: FontWeight.w700)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
                decoration: BoxDecoration(
                  color: (backend.isPaired ? AxColors.accent : AxColors.fg3).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AxRadius.pill),
                ),
                child: Text(
                  backend.isPaired ? 'paired' : 'not paired',
                  style: AxTextStyles.mono.copyWith(fontSize: 10, fontWeight: FontWeight.w500, color: backend.isPaired ? AxColors.accent : AxColors.fg3),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (backend.isPaired) ...[
            _KvRow('Host', backend.host!),
            const SizedBox(height: 12),
            AxGhostButton(
              label: 'Unpair',
              color: AxColors.bad,
              onTap: () async {
                final ok = await _confirm(
                  context,
                  title: 'Unpair from this backend?',
                  message: 'This app will forget the backend address and token, so you will need to pair again to use the terminal, files, containers and monitoring. '
                      'The server itself is not changed, and this device stays in its paired-devices list until you revoke it.',
                  confirmLabel: 'Unpair',
                );
                if (ok) await backend.unpair();
              },
            ),
          ] else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Pair from the Terminal screen, or paste host + token there once archangeld prints them.',
                style: AxTextStyles.sans.copyWith(fontSize: 11.5, color: AxColors.fg2),
              ),
            ),
        ],
      ),
    );
  }
}

class _TunnelCard extends StatelessWidget {
  const _TunnelCard();

  @override
  Widget build(BuildContext context) {
    final wg = context.watch<WireGuardController>();
    final statusColor = switch (wg.status) {
      TunnelStatus.connected => AxColors.accent,
      TunnelStatus.connecting || TunnelStatus.disconnecting => AxColors.warn,
      TunnelStatus.error || TunnelStatus.unsupported => AxColors.bad,
      TunnelStatus.disconnected => AxColors.fg3,
    };
    final statusLabel = switch (wg.status) {
      TunnelStatus.connected => 'wg0 up',
      TunnelStatus.connecting => 'connecting…',
      TunnelStatus.disconnecting => 'disconnecting…',
      TunnelStatus.error => 'error',
      TunnelStatus.unsupported => 'unsupported here',
      TunnelStatus.disconnected => 'wg0 down',
    };

    final cfg = wg.config;
    final rows = cfg == null
        ? const <List<String>>[]
        : [
            ['Interface', cfg.interfaceAddress],
            ['Endpoint', cfg.peerEndpoint],
            ['Allowed IPs', cfg.peerAllowedIps],
            if (cfg.interfaceDns != null) ['DNS', cfg.interfaceDns!],
          ];

    return AxCard(
      padding: const EdgeInsets.all(15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('Tunnel', style: AxTextStyles.sans.copyWith(fontSize: 12.5, fontWeight: FontWeight.w700)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
                decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(AxRadius.pill)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    StatusDot(color: statusColor, size: 5, pulse: wg.status == TunnelStatus.connected),
                    const SizedBox(width: 6),
                    Text(statusLabel, style: AxTextStyles.mono.copyWith(fontSize: 10, fontWeight: FontWeight.w500, color: statusColor)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (cfg == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('No device paired yet.', style: AxTextStyles.sans.copyWith(fontSize: 11.5, color: AxColors.fg2)),
            )
          else
            for (final r in rows) _KvRow(r[0], r[1]),
          if (wg.lastError != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(wg.lastError!, style: AxTextStyles.mono.copyWith(fontSize: 10.5, color: AxColors.bad)),
            ),
          if (Platform.isMacOS && !wg.isMacosHelperInstalled) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: AxColors.s2,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: AxColors.accent.withValues(alpha: 0.28)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.shield_outlined, size: 14, color: AxColors.accent),
                      const SizedBox(width: 6),
                      Text(
                        'Seamless WireGuard Tunnel',
                        style: AxTextStyles.sans.copyWith(fontSize: 11.5, fontWeight: FontWeight.w700, color: AxColors.fg),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Archangel needs a one-time permission to control the VPN tunnel seamlessly without prompting you every time.',
                    style: AxTextStyles.sans.copyWith(fontSize: 11, color: AxColors.fg2, height: 1.4),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.tonalIcon(
                    onPressed: wg.installingMacosHelper ? null : () => wg.installMacosHelper(),
                    icon: wg.installingMacosHelper
                        ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5))
                        : const Icon(Icons.lock_open_rounded, size: 13),
                    label: Text(
                      wg.installingMacosHelper ? 'Authorizing…' : 'Enable Seamless Tunnel',
                      style: AxTextStyles.sans.copyWith(fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              if (cfg == null)
                _FilledPill(label: 'Pair device', onTap: () => showPairingDialog(context))
              else ...[
                _FilledPill(
                  label: wg.status == TunnelStatus.connected ? 'Disconnect' : 'Reconnect',
                  onTap: wg.status == TunnelStatus.connected ? wg.disconnect : wg.connect,
                ),
                const SizedBox(width: 7),
                AxGhostButton(label: 'View config', onTap: () => _showConfigDialog(context, cfg)),
                const SizedBox(width: 7),
                AxGhostButton(
                  label: 'Unpair',
                  color: AxColors.bad,
                  onTap: () async {
                    final ok = await _confirm(
                      context,
                      title: 'Remove the tunnel from this device?',
                      message: 'The WireGuard tunnel config is deleted from this device, so it can no longer reach the server until you pair again.',
                      confirmLabel: 'Unpair',
                    );
                    if (ok) await wg.unpair();
                  },
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  void _showConfigDialog(BuildContext context, TunnelConfig cfg) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AxColors.s2,
        title: Text('Tunnel config', style: AxTextStyles.sans.copyWith(fontSize: 15, fontWeight: FontWeight.w700)),
        content: SelectableText(
          cfg.toWgQuickConfig().replaceFirst(cfg.interfacePrivateKey, '••••••••••••••••••••••••••••••••••••••••••'),
          style: AxTextStyles.mono.copyWith(fontSize: 12, height: 1.6),
        ),
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))],
      ),
    );
  }

}
