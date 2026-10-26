import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../services/app_version.dart';
import '../../../services/archangeld_connection.dart';
import '../../../services/monitoring_service.dart';
import '../../../services/semver.dart';
import '../../../services/server_registry.dart';
import '../../../services/update_check_service.dart';
import '../../../services/wireguard_controller.dart';
import '../../../widgets/backend_update_dialog.dart';
import '../../shell/connection_state.dart';
import '../../ui.dart';
import '../home/home_logic.dart';
import 'diagnostics_report.dart';
import 'settings_parts.dart';

/// The name of the secure connection's network interface on this device.
/// (Mirrors the private name in `wireguard_controller.dart`.)
const _kInterfaceName = 'archangel';

/// About: an overview of this server (health, size, secure connection), the
/// Updates card, and the technical values tucked away behind a toggle.
class ArchangelOsSection extends StatelessWidget {
  const ArchangelOsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final backend = context.watch<ArchangeldConnection>();
    final registry = context.watch<ServerRegistry>();
    final monitoring = context.watch<MonitoringService>();
    final wireguard = context.watch<WireGuardController>();

    final metrics = monitoring.metrics;
    final paired = backend.isPaired;
    final serverName = registry.active?.name;
    final phase = deriveConnectionPhase(
      paired: paired,
      tunnel: wireguard.status,
      reachable: backend.reachable,
      healthFailures: backend.healthFailures,
    );
    final health = evaluateHealth(connected: monitoring.isConnected, metrics: metrics);
    final cfg = wireguard.config;
    final privateAddress = cfg?.interfaceAddress.split('/').first;
    final polled = monitoring.lastPolled;

    final healthBadge = switch (health.level) {
      HealthLevel.healthy => StatusBadge.ok(health.pill, icon: Icons.verified_user_outlined),
      HealthLevel.warning => StatusBadge.warning(health.pill),
      HealthLevel.unreachable => StatusBadge.error(health.pill, icon: Icons.cloud_off_outlined),
      HealthLevel.checking => StatusBadge.info(health.pill, icon: Icons.sync),
    };
    final connectionBadge = switch (phase) {
      ConnectionPhase.connected => const StatusBadge.ok('Encrypted', icon: Icons.lock_outline),
      ConnectionPhase.starting || ConnectionPhase.reaching => const StatusBadge.info('Connecting…', icon: Icons.sync),
      ConnectionPhase.serverNotResponding => const StatusBadge.warning('Not answering'),
      ConnectionPhase.offline => const StatusBadge.error('Not connected', icon: Icons.cloud_off_outlined),
      ConnectionPhase.notPaired => const StatusBadge.neutral('No server yet'),
    };

    return SettingsStack(
      children: [
        AxCard(
          padding: EdgeInsets.symmetric(horizontal: ax.space.xl, vertical: ax.space.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AxWordmark(size: 32),
              SizedBox(height: ax.space.xs),
              Text('Your private cloud, guarded 24/7.', style: ax.typo.caption.copyWith(color: c.textMuted)),
              SizedBox(height: ax.space.md),
              Wrap(
                spacing: ax.space.sm,
                runSpacing: ax.space.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  StatusBadge.neutral('App ${AppVersion.current}', icon: Icons.tag_rounded),
                  if (!paired) const StatusBadge.neutral('No server yet', icon: Icons.cloud_off_outlined),
                ],
              ),
            ],
          ),
        ),
        if (paired)
          SettingsCard(
            title: 'This server',
            intro: 'A quick look at the server you are using.',
            children: [
              AxListTile(
                leading: const AxTileIcon(Icons.dns_outlined),
                title: serverName ?? 'Your server',
                titleMono: true,
                subtitle: health.headline,
                controls: [healthBadge],
              ),
              if (metrics != null) ...[
                AxListTile(title: 'Running for', subtitle: plainUptime(metrics.uptimeSeconds)),
                AxListTile(title: 'Operating system', subtitle: plainOsName(metrics.host.os)),
                AxListTile(title: 'Size', subtitle: capacitySummary(metrics)),
              ] else
                const SettingsMessage('Details appear once your server answers.'),
            ],
          ),
        if (paired)
          SettingsCard(
            title: 'Secure connection',
            intro: 'Everything between this device and your server is encrypted.',
            children: [
              AxListTile(
                leading: const AxTileIcon(Icons.shield_outlined),
                title: 'Connection',
                subtitle: connectionText(phase, serverName: serverName),
                controls: [connectionBadge],
              ),
              if (privateAddress != null) AxListTile(title: 'Private address', subtitle: privateAddress, subtitleMono: true),
              AxListTile(
                title: polled == null ? 'Not checked yet' : 'Last checked ${plainAgo(DateTime.now().difference(polled))}',
                subtitle: 'Your server is checked about every few seconds.',
              ),
              _TechnicalDetails(
                rows: [
                  if (metrics != null) ...[
                    ('Computer name', metrics.host.hostname),
                    ('Kernel', metrics.host.kernel),
                    ('Architecture', metrics.host.arch),
                    ('Operating system (full)', metrics.host.os),
                  ],
                  ('Server address', backend.host ?? ''),
                  ('Server program version', backend.backendVersion ?? ''),
                  ('Connection endpoint', cfg?.peerEndpoint ?? ''),
                  ('Tunnel address', cfg?.interfaceAddress ?? ''),
                  ('Allowed addresses', cfg?.peerAllowedIps ?? ''),
                  ('Interface name', cfg == null ? '' : _kInterfaceName),
                  ('App connection port', registry.active?.appPort.toString() ?? ''),
                  ('Secure connection port', registry.active?.wgPort.toString() ?? ''),
                ],
              ),
            ],
          ),
        const UpdatesSection(),
      ],
    );
  }
}

/// A collapsed "Technical details" row that opens a list of raw values, each
/// with a copy button. Empty values are left out.
class _TechnicalDetails extends StatefulWidget {
  const _TechnicalDetails({required this.rows});

  final List<(String, String)> rows;

  @override
  State<_TechnicalDetails> createState() => _TechnicalDetailsState();
}

class _TechnicalDetailsState extends State<_TechnicalDetails> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final rows = widget.rows.where((r) => r.$2.isNotEmpty).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          expanded: _open,
          label: 'Technical details',
          excludeSemantics: true,
          onTap: () => setState(() => _open = !_open),
          child: InkWell(
            key: const ValueKey('technical-details-toggle'),
            onTap: () => setState(() => _open = !_open),
            child: Container(
              constraints: BoxConstraints(minHeight: axMinTarget(context)),
              padding: EdgeInsets.symmetric(horizontal: ax.space.lg, vertical: ax.space.sm),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Technical details', style: ax.typo.label.copyWith(color: c.text)),
                  ),
                  Icon(_open ? Icons.expand_less : Icons.expand_more, size: 20, color: c.textMuted),
                ],
              ),
            ),
          ),
        ),
        if (_open) ...[
          Divider(height: 1, thickness: 1, color: c.border),
          for (final r in rows) _TechRow(label: r.$1, value: r.$2),
          if (rows.isEmpty) const SettingsMessage('Nothing to show yet.'),
        ],
      ],
    );
  }
}

class _TechRow extends StatelessWidget {
  const _TechRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    return Padding(
      padding: EdgeInsets.only(left: ax.space.lg, right: ax.space.sm, top: ax.space.xs, bottom: ax.space.xs),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: ax.typo.caption.copyWith(color: c.textMuted)),
                Text(value, style: ax.typo.mono.copyWith(color: c.text)),
              ],
            ),
          ),
          AxIconButton(
            icon: Icons.copy_rounded,
            tooltip: 'Copy $label',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: value));
              showSnack(ScaffoldMessenger.maybeOf(context), 'Copied');
            },
          ),
        ],
      ),
    );
  }
}

/// The app and server-program versions, and checking for newer ones.
class UpdatesSection extends StatelessWidget {
  const UpdatesSection({super.key});

  @override
  Widget build(BuildContext context) {
    final updates = context.watch<UpdateCheckService>();
    final backend = context.watch<ArchangeldConnection>();
    final appUpdate = isUpdateAvailable(current: AppVersion.current, latest: updates.latestFrontend) ? updates.latestFrontend : null;
    final url = updates.releaseUrl;
    final serverVersion = backend.backendVersion;
    final serverUpdate = backend.isPaired && isUpdateAvailable(current: serverVersion, latest: updates.latestBackend)
        ? updates.latestBackend
        : null;
    final checked = updates.lastChecked;

    final String? serverSubtitle;
    final List<Widget> serverControls;
    if (serverVersion == null) {
      if (backend.backendChecking) {
        serverSubtitle = null;
        serverControls = const [StatusBadge.info('Checking…', icon: Icons.sync)];
      } else {
        serverSubtitle = "Can't check right now";
        serverControls = const [StatusBadge.neutral('Not answering', icon: Icons.cloud_off_outlined)];
      }
    } else {
      serverSubtitle = 'Version $serverVersion';
      serverControls = [
        if (serverUpdate == null)
          const StatusBadge.ok('Up to date', icon: Icons.check)
        else ...[
          StatusBadge.info('$serverUpdate ready'),
          if (updates.backendTag != null)
            AxButton(
              label: 'Update',
              small: true,
              onPressed: () => showBackendUpdateDialog(context, targetVersion: serverUpdate, releaseTag: updates.backendTag!),
            ),
        ],
      ];
    }

    final String result;
    if (updates.checking) {
      result = 'Checking for updates…';
    } else if (checked == null) {
      result = 'No check yet. Press "Check now".';
    } else if (appUpdate != null || serverUpdate != null) {
      result = 'An update is ready.';
    } else {
      result = "You're up to date.";
    }

    return SettingsCard(
      title: 'Updates',
      intro: 'Keep the app and your server on the latest version.',
      footnote: 'Every update is checked before it installs, and rolls itself back if anything goes wrong.',
      children: [
        AxListTile(
          leading: const AxTileIcon(Icons.download_outlined),
          title: 'Archangel OS app',
          subtitle: 'Version ${AppVersion.current}',
          controls: [
            if (appUpdate == null)
              const StatusBadge.ok('Up to date', icon: Icons.check)
            else ...[
              StatusBadge.info('$appUpdate ready'),
              if (url != null)
                AxButton(
                  label: 'Download',
                  small: true,
                  onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
                ),
            ],
          ],
        ),
        if (backend.isPaired)
          AxListTile(
            leading: const AxTileIcon(Icons.dns_outlined),
            title: 'Server program',
            subtitle: serverSubtitle,
            controls: serverControls,
          ),
        AxListTile(
          title: result,
          subtitle: checked == null ? null : 'Last checked ${formatSettingsDate(checked)}',
          controls: [
            AxButton.secondary(
              label: 'Check now',
              small: true,
              loading: updates.checking,
              onPressed: () => updates.checkForUpdates(force: true),
            ),
          ],
        ),
      ],
    );
  }
}
