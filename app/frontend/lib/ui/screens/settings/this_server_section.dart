import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../services/app_version.dart';
import '../../../services/archangeld_connection.dart';
import '../../../services/monitoring_service.dart';
import '../../../services/semver.dart';
import '../../../services/server_registry.dart';
import '../../../services/update_check_service.dart';
import '../../../services/wireguard_controller.dart';
import '../../../widgets/backend_update_dialog.dart';
import '../../../widgets/sync_server_config_dialog.dart';
import '../../shell/connection_state.dart';
import '../../shell/status_strip.dart' show ConnectionStatusLine;
import '../../ui.dart';
import 'settings_parts.dart';

/// The active server: its name, version (with Update), this app's version and
/// the secure connection to it.
class ThisServerSection extends StatelessWidget {
  const ThisServerSection({super.key});

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final backend = context.watch<ArchangeldConnection>();
    final updates = context.watch<UpdateCheckService>();
    final registry = context.watch<ServerRegistry>();
    final hostname = context.watch<MonitoringService>().metrics?.host.hostname ?? '';

    final serverVer = backend.isPaired
        ? (backend.backendVersion != null
            ? 'v${backend.backendVersion}'
            : (backend.backendChecking ? 'checking…' : (backend.backendVersionError ?? 'not answering')))
        : 'not paired';
    final serverUpdate =
        backend.isPaired && isUpdateAvailable(current: backend.backendVersion, latest: updates.latestBackend)
            ? updates.latestBackend
            : null;
    final appUpdate = isUpdateAvailable(current: AppVersion.current, latest: updates.latestFrontend) ? updates.latestFrontend : null;
    final canUpdate = serverUpdate != null && updates.backendTag != null;

    return SettingsSection(
      title: 'This server',
      explanation: 'The Archangel server you are connected to, and how this device reaches it.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KvRow('Name', registry.active?.name ?? 'No server'),
          if (backend.isPaired && hostname.isNotEmpty) KvRow('Computer name', hostname, mono: true),
          KvRow(
            'Archangel server',
            serverVer,
            trailing: serverUpdate == null
                ? null
                : Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: ax.space.sm,
                    children: [
                      StatusBadge.warning('v$serverUpdate available'),
                      if (canUpdate)
                        AxButton(
                          label: 'Update',
                          icon: Icons.system_update_alt,
                          onPressed: () => showBackendUpdateDialog(context, targetVersion: serverUpdate, releaseTag: updates.backendTag!),
                        ),
                    ],
                  ),
          ),
          KvRow(
            'This app',
            'v${AppVersion.current}',
            trailing: appUpdate == null ? null : StatusBadge.warning('v$appUpdate available'),
          ),
          SizedBox(height: ax.space.sm),
          const _SecureConnection(),
          if (backend.isPaired) ...[
            SizedBox(height: ax.space.lg),
            Text(
              'If something on the server stopped working after an update, you can re-apply its service and permission settings.',
              style: ax.typo.body.copyWith(color: ax.colors.textMuted),
            ),
            SizedBox(height: ax.space.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: AxButton.secondary(
                label: 'Repair server permissions',
                icon: Icons.build_outlined,
                onPressed: () => showSyncServerConfigDialog(context),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SecureConnection extends StatelessWidget {
  const _SecureConnection();

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final wg = context.watch<WireGuardController>();
    final backend = context.watch<ArchangeldConnection>();
    final registry = context.watch<ServerRegistry>();
    final phase = deriveConnectionPhase(
      paired: backend.isPaired,
      tunnel: wg.status,
      reachable: backend.reachable,
      healthFailures: backend.healthFailures,
    );
    final cfg = wg.config;
    final canToggle = wg.isPaired && wg.status != TunnelStatus.unsupported;
    final connected = wg.status == TunnelStatus.connected;
    final busy = wg.status == TunnelStatus.connecting || wg.status == TunnelStatus.disconnecting;

    return Container(
      padding: EdgeInsets.all(ax.space.md),
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(ax.radii.md),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('Secure connection', style: ax.typo.label.copyWith(color: c.text)),
              const HelpTip(
                title: 'Secure connection',
                message: 'Your server is only reachable through a private, encrypted tunnel (it uses WireGuard). '
                    'Archangel can start it for you, or you can run it with the WireGuard app - either way works.',
              ),
            ],
          ),
          ConnectionStatusLine(phase: phase, serverName: registry.active?.name),
          if (wg.lastError != null)
            Padding(
              padding: EdgeInsets.only(top: ax.space.sm),
              child: Text(wg.lastError!, style: ax.typo.caption.copyWith(color: c.danger)),
            ),
          if (cfg != null) ...[
            SizedBox(height: ax.space.sm),
            Text('Server address: ${cfg.peerEndpoint}', style: ax.typo.mono.copyWith(color: c.textMuted)),
          ],
          if (Platform.isMacOS && !wg.isMacosHelperInstalled) ...[
            SizedBox(height: ax.space.md),
            Text(
              'Archangel needs a one-time permission to control the secure connection without asking you every time.',
              style: ax.typo.body.copyWith(color: c.textMuted),
            ),
            SizedBox(height: ax.space.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: AxButton.secondary(
                label: wg.installingMacosHelper ? 'Authorizing…' : 'Allow seamless connection',
                icon: Icons.lock_open_outlined,
                loading: wg.installingMacosHelper,
                onPressed: () => wg.installMacosHelper(),
              ),
            ),
          ],
          SizedBox(height: ax.space.md),
          Wrap(
            spacing: ax.space.sm,
            runSpacing: ax.space.sm,
            children: [
              if (canToggle)
                AxButton(
                  label: connected ? 'Disconnect' : 'Connect',
                  icon: connected ? Icons.link_off : Icons.link,
                  loading: busy,
                  onPressed: connected ? wg.disconnect : wg.connect,
                ),
              if (cfg != null)
                AxButton.ghost(
                  label: 'Connection details',
                  icon: Icons.info_outline,
                  onPressed: () => _showDetails(context, cfg.toWgQuickConfig().replaceFirst(cfg.interfacePrivateKey, '••••••••••••••••')),
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _showDetails(BuildContext context, String config) {
    showDialog<void>(
      context: context,
      builder: (context) {
        final ax = context.ax;
        return AlertDialog(
          scrollable: true,
          title: Text('Connection details', style: ax.typo.title.copyWith(color: ax.colors.text)),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: SelectableText(config, style: ax.typo.mono.copyWith(color: ax.colors.text)),
          ),
          actions: [AxButton.ghost(label: 'Close', onPressed: () => Navigator.of(context).pop())],
        );
      },
    );
  }
}
