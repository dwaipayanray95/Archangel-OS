import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../models/system_metrics.dart';
import '../../../services/app_version.dart';
import '../../../services/archangeld_connection.dart';
import '../../../services/monitoring_service.dart';
import '../../../services/server_registry.dart';
import '../../../services/update_check_service.dart';
import '../../../services/wireguard_controller.dart';
import '../../../widgets/backend_update_dialog.dart';
import '../../shell/connection_state.dart';
import '../../ui.dart';
import '../activity/activity_logic.dart' show formatBytes;
import '../home/home_logic.dart';
import 'diagnostics_report.dart';
import 'settings_parts.dart';

/// The name of the secure connection's network interface on this device.
/// (Mirrors the private name in `wireguard_controller.dart`.)
const _kInterfaceName = 'archangel';

/// About: an overview of this server (health, size, secure connection), the
/// Archangel OS banner with build number, Changelog and Updates buttons, and
/// the technical values tucked away behind a toggle.
class ArchangelOsSection extends StatefulWidget {
  const ArchangelOsSection({super.key});

  @override
  State<ArchangelOsSection> createState() => _ArchangelOsSectionState();
}

class _ArchangelOsSectionState extends State<ArchangelOsSection> {
  bool _showUpdatesPage = false;

  @override
  Widget build(BuildContext context) {
    if (_showUpdatesPage) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) setState(() => _showUpdatesPage = false);
        },
        child: UpdatesPage(onBack: () => setState(() => _showUpdatesPage = false)),
      );
    }

    final ax = context.ax;
    final c = ax.colors;
    final backend = context.watch<ArchangeldConnection>();
    final registry = context.watch<ServerRegistry>();
    final monitoring = context.watch<MonitoringService>();
    final wireguard = context.watch<WireGuardController>();
    final updates = context.watch<UpdateCheckService>();

    final metrics = monitoring.metrics;
    final paired = backend.isPaired;
    final serverName = registry.active?.name;
    final updateAvailable = updates.updateAvailable(serverVersion: backend.backendVersion);
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
          padding: EdgeInsets.symmetric(horizontal: ax.space.xl, vertical: ax.space.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AxWordmark(size: 34),
              SizedBox(height: ax.space.xs),
              Text('Your private cloud, guarded 24/7.', style: ax.typo.body.copyWith(color: c.textMuted)),
              SizedBox(height: ax.space.md),
              Wrap(
                spacing: ax.space.sm,
                runSpacing: ax.space.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  StatusBadge.neutral('(v${AppVersion.current} build ${AppVersion.build})', icon: Icons.tag_rounded),
                  if (paired)
                    const StatusBadge.ok('Guarded 24/7', icon: Icons.verified_user_outlined)
                  else
                    const StatusBadge.neutral('No server yet', icon: Icons.cloud_off_outlined),
                  if (updateAvailable && updates.latestVersion != null)
                    StatusBadge.info('Update ready: v${updates.latestVersion}', icon: Icons.download_rounded),
                ],
              ),
              SizedBox(height: ax.space.lg),
              Wrap(
                spacing: ax.space.sm,
                runSpacing: ax.space.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  AxButton(
                    key: const ValueKey('about-updates-btn'),
                    label: 'Updates',
                    icon: Icons.sync_rounded,
                    small: true,
                    kind: updateAvailable ? AxButtonKind.primary : AxButtonKind.secondary,
                    onPressed: () => setState(() => _showUpdatesPage = true),
                  ),
                  AxButton.ghost(
                    key: const ValueKey('about-changelog-btn'),
                    label: 'Changelog',
                    icon: Icons.article_outlined,
                    small: true,
                    onPressed: () => _showChangelogDialog(context, updates),
                  ),
                  AxButton.ghost(
                    key: const ValueKey('about-license-btn'),
                    label: 'License',
                    icon: Icons.policy_outlined,
                    small: true,
                    onPressed: () => _showLicenseDialog(context),
                  ),
                  AxButton.ghost(
                    key: const ValueKey('about-github-btn'),
                    label: 'GitHub',
                    icon: Icons.open_in_new,
                    small: true,
                    onPressed: () => launchUrl(Uri.parse('https://github.com/$kGithubRepoSlug'), mode: LaunchMode.externalApplication),
                  ),
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
        if (paired && metrics != null)
          SettingsCard(
            title: 'Storage & disk',
            intro: 'Capacity and disk usage on your server.',
            children: [
              _DiskGraphic(disk: metrics.disk),
              for (final m in metrics.disk.mounts) _MountRow(mount: m),
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

/// The one Archangel OS version, and checking for a newer one on a dedicated
/// Updates page opened from the Archangel banner card.
///
/// Automatically checks for fresh updates from GitHub upon opening.
/// There is a single version for the app and the server program. One
/// "Update" button does whatever is needed: update the server first when it
/// is behind, then open the download for the app when that is behind too.
class UpdatesPage extends StatefulWidget {
  const UpdatesPage({super.key, this.onBack});

  final VoidCallback? onBack;

  @override
  State<UpdatesPage> createState() => _UpdatesPageState();
}

class _UpdatesPageState extends State<UpdatesPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<UpdateCheckService>().checkForUpdates(force: true);
      }
    });
  }

  Future<void> _update(BuildContext context) async {
    final updates = context.read<UpdateCheckService>();
    final backend = context.read<ArchangeldConnection>();
    final latest = updates.latestVersion;
    if (latest == null) return;
    final url = updates.releaseUrl;

    if (backend.isPaired && updates.serverBehind(backend.backendVersion)) {
      await showBackendUpdateDialog(context, targetVersion: latest, releaseTag: updates.releaseTag ?? 'v$latest');
      // Only go on to the app once the server really is up to date (the
      // dialog refreshes the server's version when it finishes).
      if (updates.serverBehind(backend.backendVersion)) return;
    }
    if (updates.appBehind && url != null) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final updates = context.watch<UpdateCheckService>();
    final backend = context.watch<ArchangeldConnection>();
    final serverVersion = backend.backendVersion;
    final paired = backend.isPaired;
    final latest = updates.latestVersion;
    final appBehind = updates.appBehind;
    final serverBehind = paired && updates.serverBehind(serverVersion);
    final available = (appBehind || serverBehind) && latest != null;
    final checked = updates.lastChecked;

    // "App 0.8.0 · Server 0.7.0", only when they differ.
    final String? differ = paired && serverVersion != null && serverVersion != AppVersion.current
        ? 'App ${AppVersion.current} · Server $serverVersion'
        : null;

    final String result;
    if (updates.checking) {
      result = 'Checking for updates…';
    } else if (checked == null) {
      result = 'No check yet. Press "Check now".';
    } else if (available) {
      result = 'An update is ready.';
    } else {
      result = "You're up to date.";
    }

    return SettingsStack(
      children: [
        if (widget.onBack != null)
          Align(
            alignment: Alignment.centerLeft,
            child: AxButton.ghost(label: 'Back to About', icon: Icons.chevron_left, onPressed: widget.onBack),
          ),
        SettingsCard(
          title: 'Updates',
          intro: 'The app and your server share one version.',
          footnote: 'Every update is checked before it installs, and rolls itself back if anything goes wrong.',
          children: [
            AxListTile(
              leading: const AxTileIcon(Icons.download_outlined),
              title: 'Archangel OS ${AppVersion.full}',
              subtitle: differ,
              controls: [
                if (!available)
                  const StatusBadge.ok('Up to date', icon: Icons.check)
                else ...[
                  StatusBadge.info('Update available — $latest'),
                  AxButton(label: 'Update', small: true, onPressed: () => _update(context)),
                ],
              ],
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
        ),
        if (available && updates.releaseNotes != null && updates.releaseNotes!.trim().isNotEmpty)
          SettingsCard(
            title: updates.releaseName ?? 'What\'s new in v$latest',
            intro: 'Release notes from GitHub for this version.',
            children: [
              Padding(
                padding: EdgeInsets.all(ax.space.md),
                child: Container(
                  padding: EdgeInsets.all(ax.space.md),
                  decoration: BoxDecoration(
                    color: c.surfaceAlt,
                    borderRadius: BorderRadius.circular(ax.radii.sm),
                    border: Border.all(color: c.border),
                  ),
                  child: SelectableText(updates.releaseNotes!.trim(), style: ax.typo.body.copyWith(color: c.text, height: 1.45)),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

/// Kept for compatibility.
typedef UpdatesSection = UpdatesPage;

/// Visual graphic bar and statistics for server storage & disk usage.
class _DiskGraphic extends StatelessWidget {
  const _DiskGraphic({required this.disk});

  final DiskMetrics disk;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final pct = disk.usagePercent.clamp(0.0, 100.0);
    final isWarn = pct >= 80;
    final isCrit = pct >= 90;
    final barColor = isCrit ? c.danger : (isWarn ? c.warning : c.accent);
    final badge = isCrit
        ? StatusBadge.error('Critical (${pct.round()}%)')
        : (isWarn ? StatusBadge.warning('Getting full (${pct.round()}%)') : StatusBadge.ok('${pct.round()}% used'));

    final totalStr = formatBytes(disk.totalBytes);
    final usedStr = formatBytes(disk.usedBytes);
    final freeBytes = disk.freeBytes > 0 ? disk.freeBytes : (disk.totalBytes > disk.usedBytes ? disk.totalBytes - disk.usedBytes : 0);
    final freeStr = formatBytes(freeBytes);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: ax.space.lg, vertical: ax.space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('$usedStr used of $totalStr', style: ax.typo.label.copyWith(color: c.text)),
              ),
              badge,
            ],
          ),
          SizedBox(height: ax.space.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(ax.radii.pill),
            child: Container(
              height: 12,
              color: c.surfaceHigh,
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: (pct / 100.0).clamp(0.02, 1.0),
                  child: Container(
                    decoration: BoxDecoration(color: barColor, borderRadius: BorderRadius.circular(ax.radii.pill)),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(height: ax.space.sm),
          Wrap(
            spacing: ax.space.md,
            runSpacing: ax.space.xs,
            children: [
              Text('Free: $freeStr', style: ax.typo.caption.copyWith(color: c.textMuted)),
              Text('Total: $totalStr', style: ax.typo.caption.copyWith(color: c.textMuted)),
              if (disk.totalMbPerSec > 0.05)
                Text(
                  'Activity: ${disk.readMbPerSec.toStringAsFixed(1)} MB/s read · ${disk.writeMbPerSec.toStringAsFixed(1)} MB/s write',
                  style: ax.typo.caption.copyWith(color: c.textMuted),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MountRow extends StatelessWidget {
  const _MountRow({required this.mount});

  final MountMetric mount;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final pct = mount.usagePercent.clamp(0.0, 100.0);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: ax.space.lg, vertical: ax.space.xs),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(mount.mountPoint, style: ax.typo.mono.copyWith(color: c.text)),
                if (mount.device.isNotEmpty) Text(mount.device, style: ax.typo.caption.copyWith(color: c.textMuted)),
              ],
            ),
          ),
          SizedBox(width: ax.space.sm),
          Text(
            '${formatBytes(mount.usedBytes)} / ${formatBytes(mount.totalBytes)} (${pct.round()}%)',
            style: ax.typo.caption.copyWith(color: c.textMuted),
          ),
        ],
      ),
    );
  }
}

void _showLicenseDialog(BuildContext context) {
  final ax = context.ax;
  final c = ax.colors;
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: c.surface,
      scrollable: true,
      title: Row(
        children: [
          Icon(Icons.policy_outlined, size: 22, color: c.accent),
          SizedBox(width: ax.space.sm),
          Text('License', style: ax.typo.title.copyWith(color: c.text)),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: EdgeInsets.all(ax.space.md),
              decoration: BoxDecoration(
                color: c.surfaceAlt,
                borderRadius: BorderRadius.circular(ax.radii.sm),
                border: Border.all(color: c.border),
              ),
              child: SelectableText(_kLicenseText, style: ax.typo.caption.copyWith(color: c.text, height: 1.45)),
            ),
          ],
        ),
      ),
      actions: [
        AxButton.secondary(
          label: 'Open-source notices',
          icon: Icons.description_outlined,
          small: true,
          onPressed: () => showLicensePage(context: context, applicationName: 'Archangel OS', applicationVersion: AppVersion.full),
        ),
        AxButton.ghost(label: 'Close', small: true, onPressed: () => Navigator.of(ctx).pop()),
      ],
    ),
  );
}

void _showChangelogDialog(BuildContext context, UpdateCheckService updates) {
  final ax = context.ax;
  final c = ax.colors;
  final notes = updates.releaseNotes?.trim();
  final hasNotes = notes != null && notes.isNotEmpty;

  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: c.surface,
      scrollable: true,
      title: Row(
        children: [
          Icon(Icons.article_outlined, size: 22, color: c.accent),
          SizedBox(width: ax.space.sm),
          Text('Changelog', style: ax.typo.title.copyWith(color: c.text)),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Archangel OS ${AppVersion.full}', style: ax.typo.label.copyWith(color: c.text)),
            SizedBox(height: ax.space.xs),
            Text(
              hasNotes
                  ? (updates.releaseName ?? 'Latest release notes:')
                  : 'For a complete release history and detailed commit logs, visit the official releases on GitHub.',
              style: ax.typo.body.copyWith(color: c.textMuted),
            ),
            if (hasNotes) ...[
              SizedBox(height: ax.space.sm),
              Container(
                padding: EdgeInsets.all(ax.space.md),
                decoration: BoxDecoration(
                  color: c.surfaceAlt,
                  borderRadius: BorderRadius.circular(ax.radii.sm),
                  border: Border.all(color: c.border),
                ),
                child: SelectableText(notes, style: ax.typo.caption.copyWith(color: c.text, height: 1.45)),
              ),
            ],
          ],
        ),
      ),
      actions: [
        AxButton.secondary(
          label: 'View all releases on GitHub',
          icon: Icons.open_in_new,
          small: true,
          onPressed: () => launchUrl(
            Uri.parse(updates.releaseUrl ?? 'https://github.com/$kGithubRepoSlug/releases'),
            mode: LaunchMode.externalApplication,
          ),
        ),
        AxButton.ghost(label: 'Close', small: true, onPressed: () => Navigator.of(ctx).pop()),
      ],
    ),
  );
}

const _kLicenseText = '''The Awesome License v1 (TALv1)
Copyright (c) 2026 dwaipayanray95
Contact: https://github.com/dwaipayanray95

THE VIBE (PREAMBLE)
This code is meant to be shared, learned from, and built upon. You are free to use it to create amazing things. However, if you are turning a profit from my hard work, it is only fair that we share the success or keep the open-source ecosystem thriving.

THE RULES (PERMISSIONS & CONDITIONS)
1. Free for Open & Non-Profit Use:
   You may use, copy, modify, merge, publish, and distribute the Software freely for personal, educational, or open-source projects where no revenue is generated.

2. The Commercial Catch:
   If you use this Software in a revenue-generating project or within a for-profit entity, you must choose ONE of:
   • Option A (Pay It Forward): Release the entire source code of your project publicly under an OSI-approved open source license.
   • Option B (Pay the Piper): Contact the author to negotiate a commercial license, revenue cut, or flat fee before deployment.

3. Credit Where It's Due (Attribution):
   You must provide clear, public credit to the original author (for example, in an "About" page, "Credits" screen, or README).

4. No Trademark Rights:
   No trademark, branding, or endorsement rights are granted beyond plain attribution.

5. Termination:
   Rights terminate automatically upon failure to comply with commercial conditions.

THE BEERWARE CLAUSE
As long as you retain this notice, you can do whatever you want with this stuff, subject strictly to the rules above. If you like my work and use my work, you owe me a beer whenever we meet.''';
