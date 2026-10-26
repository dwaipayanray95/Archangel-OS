import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../data/app_state.dart';
import '../../../services/admin_mode_service.dart';
import '../../../services/app_version.dart';
import '../../../services/archangeld_connection.dart';
import '../../../services/monitoring_service.dart';
import '../../../services/semver.dart';
import '../../../services/server_registry.dart';
import '../../../services/ssh_credentials.dart';
import '../../../services/update_check_service.dart';
import '../../../services/wireguard_controller.dart';
import '../../../widgets/backend_update_dialog.dart';
import '../../../widgets/manage_ssh_key_dialog.dart';
import '../../../widgets/passphrase_prompt_dialog.dart';
import '../../../widgets/sync_server_config_dialog.dart';
import '../../../widgets/uninstall_dialog.dart';
import '../../shell/archangel_shell.dart' show kDesktopModeMinWidth;
import '../../shell/connection_state.dart';
import '../../shell/desktop_customize.dart';
import '../../shell/desktop_prefs.dart';
import '../../ui.dart';
import 'settings_parts.dart';

/// The saved SSH key and the secure connection to the server, plus repairs.
class SecuritySection extends StatefulWidget {
  const SecuritySection({super.key});

  @override
  State<SecuritySection> createState() => _SecuritySectionState();
}

class _SecuritySectionState extends State<SecuritySection> {
  /// Whether an SSH key is saved on this device; null until it has been checked.
  bool? _keySaved;

  @override
  void initState() {
    super.initState();
    _checkKey();
  }

  Future<void> _checkKey() async {
    bool saved;
    try {
      saved = await hasSavedSshCredentials();
    } catch (_) {
      saved = false;
    }
    if (mounted) setState(() => _keySaved = saved);
  }

  /// "Change passphrase" for the saved SSH key: asks for the current and a new
  /// passphrase, then re-encrypts the saved key.
  Future<void> _changePassphrase() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (!await hasSavedSshCredentials()) {
      showSnack(messenger, 'No SSH key is saved yet. Use "Add a key" to save one.');
      return;
    }
    if (!mounted) return;
    final result = await promptToChangePassphrase(context);
    if (result == null) return;
    try {
      await changeSshCredentialsPassphrase(result.$1, result.$2);
      showSnack(messenger, 'Passphrase changed.');
    } on WrongPassphraseException {
      showSnack(messenger, 'The current passphrase is incorrect.');
    } catch (e) {
      showSnack(messenger, 'Could not change the passphrase: $e');
    }
  }

  Future<void> _manageKey() async {
    await showManageSshKeyDialog(context);
    await _checkKey();
  }

  Future<void> _forget() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (!await hasSavedSshCredentials()) {
      showSnack(messenger, 'No SSH key is saved on this device.');
      return;
    }
    if (!mounted) return;
    final ok = await showConfirmDialog(
      context,
      title: 'Forget the saved SSH key?',
      message:
          'The key is deleted from this device. The next time you update or repair your server you will have to enter it again. Your server is not changed.',
      confirmLabel: 'Forget key',
      danger: true,
    );
    if (!ok) return;
    await clearSavedSshCredentials();
    showSnack(messenger, 'Saved SSH key forgotten.');
    await _checkKey();
  }

  Widget _keyControl() {
    if (_keySaved == false) {
      return AxButton.secondary(label: 'Add a key', small: true, onPressed: _manageKey);
    }
    return MenuAnchor(
      menuChildren: [
        MenuItemButton(onPressed: _changePassphrase, child: const Text('Change passphrase')),
        MenuItemButton(onPressed: _manageKey, child: const Text('Replace key')),
        MenuItemButton(onPressed: _forget, child: const Text('Forget key')),
      ],
      builder:
          (context, controller, _) => AxButton.secondary(
            label: 'Manage',
            icon: Icons.arrow_drop_down,
            small: true,
            onPressed: () => controller.isOpen ? controller.close() : controller.open(),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final wg = context.watch<WireGuardController>();
    final backend = context.watch<ArchangeldConnection>();
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
    final muted = ax.typo.caption.copyWith(color: c.textMuted);

    return SettingsCard(
      children: [
        AxListTile(
          leading: const AxTileIcon(Icons.vpn_key_outlined),
          title: 'SSH key',
          subtitle:
              _keySaved == null
                  ? null
                  : (_keySaved!
                      ? 'Stored on this device, protected by your passphrase. It never leaves this device.'
                      : 'No key saved yet.'),
          controls: [_keyControl()],
        ),
        AxListTile(
          leading: const AxTileIcon(Icons.shield_outlined),
          title: 'Secure connection',
          subtitleWidget:
              cfg == null && wg.lastError == null
                  ? null
                  : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (cfg != null)
                        Text.rich(
                          TextSpan(
                            style: muted,
                            children: [
                              const TextSpan(text: 'Server address '),
                              TextSpan(text: cfg.peerEndpoint, style: ax.typo.mono.copyWith(color: c.textMuted)),
                            ],
                          ),
                        ),
                      if (wg.lastError != null) Text(wg.lastError!, style: ax.typo.caption.copyWith(color: c.danger)),
                    ],
                  ),
          controls: [
            phase == ConnectionPhase.connected
                ? const StatusBadge.ok('Encrypted', icon: Icons.lock_outline)
                : const StatusBadge.error('Not connected', icon: Icons.cloud_off_outlined),
            if (canToggle)
              AxButton.secondary(
                label: connected ? 'Disconnect' : 'Connect',
                small: true,
                loading: busy,
                onPressed: connected ? wg.disconnect : wg.connect,
              ),
            if (cfg != null)
              AxButton.ghost(
                label: 'Details',
                small: true,
                onPressed: () => _showDetails(context, cfg.toWgQuickConfig().replaceFirst(cfg.interfacePrivateKey, '••••••••••••••••')),
              ),
          ],
        ),
        if (Platform.isMacOS && !wg.isMacosHelperInstalled)
          AxListTile(
            leading: const AxTileIcon(Icons.lock_open_outlined),
            title: 'Allow seamless connection',
            subtitle: 'Archangel needs a one-time permission to control the secure connection without asking you every time.',
            controls: [
              AxButton.secondary(
                label: wg.installingMacosHelper ? 'Authorizing…' : 'Allow',
                small: true,
                loading: wg.installingMacosHelper,
                onPressed: () => wg.installMacosHelper(),
              ),
            ],
          ),
        if (backend.isPaired)
          AxListTile(
            leading: const AxTileIcon(Icons.build_outlined),
            title: 'Repair server permissions',
            subtitle: "Fixes Archangel's own files on the server if something stops working.",
            controls: [AxButton.secondary(label: 'Repair', small: true, onPressed: () => showSyncServerConfigDialog(context))],
          ),
      ],
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

/// Theme, accent colour, layout, the desktop and the start-up animation,
/// remembered on this device.
class AppearanceSection extends StatelessWidget {
  const AppearanceSection({super.key});

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final app = context.watch<AppState>();
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Phones always use the bottom bar, so the layout choice only shows where
    // Desktop mode is possible. It follows the screen, not the window.
    final desktopPossible = MediaQuery.sizeOf(context).width >= kDesktopModeMinWidth;
    DesktopPrefs? prefs;
    try {
      prefs = Provider.of<DesktopPrefs>(context);
    } catch (_) {
      prefs = null;
    }
    final p = prefs;
    return SettingsCard(
      children: [
        AxListTile(
          title: 'Theme',
          subtitle: 'Pearl is light, Dawn is dark. Auto follows your device.',
          controls: [
            SegmentedButton<ThemeMode>(
              key: const ValueKey('theme-choice'),
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: ThemeMode.system, label: Text('Auto')),
                ButtonSegment(value: ThemeMode.light, label: Text('Pearl')),
                ButtonSegment(value: ThemeMode.dark, label: Text('Dawn')),
              ],
              selected: {app.themeMode},
              onSelectionChanged: (s) => app.themeMode = s.first,
            ),
          ],
        ),
        AxListTile(
          title: 'Accent colour',
          subtitle: 'The highlight colour.',
          controls: [
            for (final a in AxAccent.values)
              ChoiceChip(
                key: ValueKey('accent-${a.name}'),
                label: Text(a.label),
                avatar: CircleAvatar(backgroundColor: dark ? a.dark : a.light, radius: 8),
                selected: app.accentChoice == a,
                onSelected: (_) => app.accentChoice = a,
              ),
          ],
        ),
        AxListTile(
          title: 'UI scale',
          subtitle: 'Make interface elements more compact and elegant, or standard size.',
          controls: [
            SegmentedButton<AxUiScale>(
              key: const ValueKey('ui-scale-choice'),
              showSelectedIcon: false,
              segments: [for (final s in AxUiScale.values) ButtonSegment(value: s, label: Text(s.label))],
              selected: {app.uiScale},
              onSelectionChanged: (s) => app.uiScale = s.first,
            ),
          ],
        ),
        if (desktopPossible)
          AxListTile(
            title: 'Layout',
            subtitle: 'Desktop mode (the default) gives you windows and a dock. Simple keeps one screen at a time.',
            controls: [
              SegmentedButton<AxLayout>(
                key: const ValueKey('layout-choice'),
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: AxLayout.desktop, label: Text('Desktop mode')),
                  ButtonSegment(value: AxLayout.simple, label: Text('Simple')),
                ],
                selected: {app.layout},
                onSelectionChanged: (s) => app.layout = s.first,
              ),
            ],
          ),
        if (desktopPossible)
          AxListTile(
            title: 'Window mode',
            subtitle: 'Run Archangel full screen like a game, or inside a standard window (F11 to toggle anytime).',
            controls: [
              SegmentedButton<bool>(
                key: const ValueKey('fullscreen-choice'),
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: true, label: Text('Full screen')),
                  ButtonSegment(value: false, label: Text('Windowed')),
                ],
                selected: {app.fullScreen},
                onSelectionChanged: (s) => app.fullScreen = s.first,
              ),
            ],
          ),
        if (desktopPossible && app.layout == AxLayout.desktop) ...[
          if (p != null) ...[
            AxListTile(
              title: 'Wallpaper',
              subtitle: 'Desktop backdrop. Halo dynamically follows Pearl and Dawn.',
              subtitleWidget: Padding(
                padding: EdgeInsets.only(top: ax.space.sm),
                child: Wrap(
                  spacing: ax.space.sm,
                  runSpacing: ax.space.sm,
                  children: [
                    for (final w in DeskWallpaper.values)
                      DeskWallpaperSwatch(wallpaper: w, selected: p.wallpaper == w, onTap: () => p.wallpaper = w),
                  ],
                ),
              ),
            ),
            AxListTile(
              title: 'Dock position',
              subtitle: 'Position of the application dock on your screen.',
              controls: [
                SegmentedButton<DockPosition>(
                  key: const ValueKey('settings-dock-position'),
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: DockPosition.left, label: Text('Left')),
                    ButtonSegment(value: DockPosition.bottom, label: Text('Bottom')),
                    ButtonSegment(value: DockPosition.right, label: Text('Right')),
                  ],
                  selected: {p.dockPosition},
                  onSelectionChanged: (v) => p.dockPosition = v.first,
                ),
              ],
            ),
            AxListTile(
              title: 'Dock size',
              subtitle: 'Icon dimensions and button padding of the dock.',
              controls: [
                SegmentedButton<DockSize>(
                  key: const ValueKey('settings-dock-size'),
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: DockSize.small, label: Text('Small')),
                    ButtonSegment(value: DockSize.medium, label: Text('Medium')),
                    ButtonSegment(value: DockSize.large, label: Text('Large')),
                  ],
                  selected: {p.dockSize},
                  onSelectionChanged: (v) => p.dockSize = v.first,
                ),
              ],
            ),
            AxListTile(
              title: 'Hide dock automatically',
              subtitle: 'The dock hides out of view and reappears when pointing at the edge.',
              controls: [Switch(key: const ValueKey('settings-dock-autohide'), value: p.autoHide, onChanged: (v) => p.autoHide = v)],
            ),
            AxListTile(
              title: 'Health widget',
              subtitle: 'Show real-time CPU, RAM and disk usage stats on the desktop.',
              controls: [
                Switch(key: const ValueKey('settings-show-health-widget'), value: p.showWidget, onChanged: (v) => p.showWidget = v),
              ],
            ),
            AxListTile(
              title: 'Wallpaper wordmark',
              subtitle: 'Display the Archangel OS wordmark in the center of the desktop.',
              controls: [
                Switch(
                  key: const ValueKey('settings-wallpaper-wordmark'),
                  value: p.showWallpaperWordmark,
                  onChanged: (v) => p.showWallpaperWordmark = v,
                ),
              ],
            ),
          ],
          AxListTile(
            title: 'Desktop',
            subtitle: "Wallpaper, dock position and size, what's in the dock, the health widget.",
            controls: [AxButton.secondary(label: 'Customize', small: true, onPressed: () => showDesktopCustomize(context))],
          ),
        ],
      ],
    );
  }
}

String _formatUptime(int seconds) {
  if (seconds <= 0) return 'Just started';
  final days = seconds ~/ 86400;
  final hours = (seconds % 86400) ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  final parts = <String>[];
  if (days > 0) parts.add('${days}d');
  if (hours > 0 || days > 0) parts.add('${hours}h');
  parts.add('${minutes}m');
  return parts.join(' ');
}

String _generateDiagnosticReport(BuildContext context) {
  final app = context.read<AppState>();
  final backend = context.read<ArchangeldConnection>();
  final registry = context.read<ServerRegistry>();
  final monitoring = context.read<MonitoringService>();
  final wireguard = context.read<WireGuardController>();
  final admin = context.read<AdminModeService>();

  final buf = StringBuffer();
  buf.writeln('=== Archangel OS Unified Diagnostic Snapshot ===');
  buf.writeln('Generated: ${DateTime.now().toUtc().toIso8601String()}');
  buf.writeln();

  buf.writeln('--- Client & OS Platform ---');
  buf.writeln('Archangel OS Version: ${AppVersion.current}');
  buf.writeln('Build Protocol Target: ${AppVersion.archangel}');
  buf.writeln('Operating System: ${Platform.operatingSystem} (${Platform.operatingSystemVersion})');
  buf.writeln('Dart Runtime: ${Platform.version.split(' ').first}');
  buf.writeln('Display Scaling: ${app.uiScale.label}');
  buf.writeln('Window Layout: ${app.layout.name}');
  buf.writeln('Window Mode: ${app.fullScreen ? "Full screen" : "Windowed"}');
  buf.writeln();

  buf.writeln('--- Server Node Connection ---');
  buf.writeln('Paired: ${backend.isPaired}');
  buf.writeln('Active Server Name: ${registry.active?.name ?? "None"}');
  buf.writeln('Active Host Address: ${backend.host ?? "None"}');
  buf.writeln('Server Engine Version: ${backend.backendVersion ?? "Unavailable"}');
  buf.writeln('Pairing Generation: ${backend.pairingGeneration}');
  buf.writeln('Session Admin Mode: ${admin.enabled == true}');
  buf.writeln();

  buf.writeln('--- Host Hardware & Engine Metrics ---');
  final m = monitoring.metrics;
  if (m != null) {
    buf.writeln('Server Hostname: ${m.host.hostname}');
    buf.writeln('Server OS: ${m.host.os} (${m.host.kernel}) [${m.host.arch}]');
    buf.writeln('Server Uptime: ${_formatUptime(m.uptimeSeconds)} (${m.uptimeSeconds}s)');
    buf.writeln('CPU Cores: ${m.cpu.cores.length} cores');
    buf.writeln('CPU Utilization: ${m.cpu.usagePercent.toStringAsFixed(1)}%');
    buf.writeln(
      'Memory Utilization: ${m.memory.usedGb.toStringAsFixed(2)} GB / ${m.memory.totalGb.toStringAsFixed(2)} GB (${m.memory.usagePercent.toStringAsFixed(1)}%)',
    );
    buf.writeln(
      'Disk Space: ${m.disk.usedGb.toStringAsFixed(2)} GB / ${m.disk.totalGb.toStringAsFixed(2)} GB (${m.disk.usagePercent.toStringAsFixed(1)}%)',
    );
    buf.writeln('Network Bandwidth: ${m.network.totalMbPerSec.toStringAsFixed(2)} MB/s');
  } else {
    buf.writeln('Metrics Status: ${monitoring.status.name}');
    if (monitoring.error != null) buf.writeln('Metrics Error: ${monitoring.error}');
  }
  buf.writeln();

  buf.writeln('--- WireGuard Mesh Network ---');
  buf.writeln('Tunnel Configured: ${wireguard.isPaired}');
  buf.writeln('Tunnel Status: ${wireguard.status.name}');
  if (wireguard.config != null) {
    buf.writeln('Device Tunnel IP: ${wireguard.config!.interfaceAddress}');
    buf.writeln('Peer Endpoint: ${wireguard.config!.peerEndpoint}');
  }
  if (wireguard.lastError != null) {
    buf.writeln('Tunnel Error: ${wireguard.lastError}');
  }
  buf.writeln();

  buf.writeln('=== End of Diagnostic Snapshot ===');
  return buf.toString();
}

void _copyDiagnostics(BuildContext context, String report) {
  Clipboard.setData(ClipboardData(text: report));
  showSnack(ScaffoldMessenger.maybeOf(context), 'Diagnostic report copied to clipboard');
}

void _showDiagnosticDialog(BuildContext context, String report) {
  final ax = context.ax;
  final c = ax.colors;
  showDialog<void>(
    context: context,
    builder:
        (ctx) => AlertDialog(
          backgroundColor: c.surface,
          title: Text('System Diagnostic Report', style: ax.typo.title.copyWith(color: c.text)),
          content: SizedBox(
            width: 640,
            height: 400,
            child: SingleChildScrollView(
              child: Container(
                padding: EdgeInsets.all(ax.space.md),
                decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(8), border: Border.all(color: c.border)),
                child: SelectableText(report, style: ax.typo.mono.copyWith(fontSize: 12, color: c.text, height: 1.4)),
              ),
            ),
          ),
          actions: [
            AxButton.secondary(label: 'Close', small: true, onPressed: () => Navigator.of(ctx).pop()),
            AxButton(
              label: 'Copy to clipboard',
              small: true,
              icon: Icons.copy_rounded,
              onPressed: () {
                Clipboard.setData(ClipboardData(text: report));
                Navigator.of(ctx).pop();
                showSnack(ScaffoldMessenger.maybeOf(context), 'Diagnostic report copied to clipboard');
              },
            ),
          ],
        ),
  );
}

/// System information about the OS, host, server engine, updates, and developer diagnostics.
class ArchangelOsSection extends StatelessWidget {
  const ArchangelOsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final app = context.watch<AppState>();
    final backend = context.watch<ArchangeldConnection>();
    final registry = context.watch<ServerRegistry>();
    final monitoring = context.watch<MonitoringService>();
    final wireguard = context.watch<WireGuardController>();
    final admin = context.watch<AdminModeService>();

    final metrics = monitoring.metrics;
    final isPaired = backend.isPaired;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Hero Wordmark & Branding Banner
        AxCard(
          padding: EdgeInsets.symmetric(horizontal: ax.space.xl, vertical: ax.space.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AxWordmark(size: 32),
              SizedBox(height: ax.space.xs),
              Text('Sovereign personal cloud system', style: ax.typo.caption.copyWith(color: c.textMuted)),
              SizedBox(height: ax.space.md),
              Wrap(
                spacing: ax.space.sm,
                runSpacing: ax.space.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  StatusBadge.ok('v${AppVersion.current}', icon: Icons.verified_outlined),
                  if (isPaired)
                    StatusBadge.info(registry.active?.name ?? 'Server node connected', icon: Icons.cloud_done_outlined)
                  else
                    const StatusBadge.neutral('No server paired', icon: Icons.cloud_off_outlined),
                  if (wireguard.status == TunnelStatus.connected) const StatusBadge.ok('Mesh active', icon: Icons.hub_outlined),
                ],
              ),
            ],
          ),
        ),
        SizedBox(height: ax.space.lg),

        // System & Platform Details
        SettingsCard(
          title: 'System Information',
          children: [
            AxListTile(
              title: 'Archangel OS',
              subtitle: 'Version ${AppVersion.current} • Build protocol v${AppVersion.archangel}',
              controls: const [StatusBadge.info('Release', icon: Icons.tag_rounded)],
            ),
            AxListTile(
              title: 'Host platform',
              subtitle: '${Platform.operatingSystem} (${Platform.operatingSystemVersion})',
              subtitleMono: true,
              controls: [
                Text(Platform.isMacOS ? 'macOS App' : Platform.operatingSystem, style: ax.typo.caption.copyWith(color: c.textMuted)),
              ],
            ),
            AxListTile(
              title: 'Display & window configuration',
              subtitle:
                  'Scale: ${app.uiScale.label} • Layout: ${app.layout == AxLayout.desktop ? "Desktop mode" : "Simple"} • Mode: ${app.fullScreen ? "Full screen" : "Windowed"}',
            ),
          ],
        ),
        SizedBox(height: ax.space.lg),

        // Active Server Node & Cloud Infrastructure
        if (isPaired) ...[
          SettingsCard(
            title: 'Active Server Node',
            children: [
              AxListTile(
                title: registry.active?.name ?? 'Server',
                subtitle: backend.host ?? 'No active host',
                subtitleMono: true,
                controls: [if (admin.enabled == true) const StatusBadge.accent('Admin mode') else const StatusBadge.ok('Paired')],
              ),
              AxListTile(
                title: 'Server engine (archangeld)',
                subtitle: backend.backendVersion != null ? 'archangeld v${backend.backendVersion}' : 'Checking version…',
                controls: [
                  if (backend.backendVersion != null)
                    const StatusBadge.ok('Healthy', icon: Icons.check)
                  else
                    const StatusBadge.neutral('Connecting', icon: Icons.sync),
                ],
              ),
              if (metrics != null) ...[
                AxListTile(
                  title: 'Server OS & kernel',
                  subtitle: '${metrics.host.os} • ${metrics.host.kernel} (${metrics.host.arch})',
                  subtitleMono: true,
                ),
                AxListTile(title: 'Server uptime', subtitle: _formatUptime(metrics.uptimeSeconds), subtitleMono: true),
                AxListTile(
                  title: 'Host hardware & load',
                  subtitle:
                      'CPU: ${metrics.cpu.usagePercent.toStringAsFixed(1)}% (${metrics.cpu.cores.length} cores) • RAM: ${metrics.memory.usedGb.toStringAsFixed(1)} / ${metrics.memory.totalGb.toStringAsFixed(1)} GB (${metrics.memory.usagePercent.toStringAsFixed(0)}%) • Disk: ${metrics.disk.usedGb.toStringAsFixed(1)} / ${metrics.disk.totalGb.toStringAsFixed(1)} GB',
                ),
              ],
              AxListTile(
                title: 'WireGuard mesh tunnel',
                subtitle:
                    wireguard.isPaired
                        ? 'Device IP: ${wireguard.config?.interfaceAddress ?? "Configured"} • Endpoint: ${wireguard.config?.peerEndpoint ?? "Connected"}'
                        : 'Tunnel inactive',
                subtitleMono: true,
                controls: [
                  if (wireguard.status == TunnelStatus.connected)
                    const StatusBadge.ok('Connected')
                  else if (wireguard.isPaired)
                    StatusBadge.info(wireguard.status.name)
                  else
                    const StatusBadge.neutral('Disabled'),
                ],
              ),
            ],
          ),
          SizedBox(height: ax.space.lg),
        ],

        // Software Updates
        const UpdatesSection(),
        SizedBox(height: ax.space.lg),

        // Developer Options & Diagnostics
        SettingsCard(
          title: 'Developer Options & Diagnostics',
          footnote:
              'Unified diagnostic reports include local runtime metrics and connectivity metadata without secret keys or credentials.',
          children: [
            AxListTile(
              title: 'System diagnostic report',
              subtitle: 'Unified snapshot of host OS, engine versions, server metrics, and tunnel state.',
              controls: [
                AxButton.secondary(
                  label: 'View report',
                  small: true,
                  onPressed: () => _showDiagnosticDialog(context, _generateDiagnosticReport(context)),
                ),
                AxButton(
                  label: 'Copy report',
                  small: true,
                  icon: Icons.copy_rounded,
                  onPressed: () => _copyDiagnostics(context, _generateDiagnosticReport(context)),
                ),
              ],
            ),
            AxListTile(
              title: 'Start-up boot animation',
              subtitle: 'Test and replay the Archangel OS start-up experience.',
              controls: [
                AxButton.secondary(label: 'Replay first launch', small: true, onPressed: () => app.replayBoot(BootKind.first)),
                AxButton.secondary(label: 'Replay later launch', small: true, onPressed: () => app.replayBoot(BootKind.short)),
              ],
            ),
            AxListTile(
              title: 'UI display scaling reset',
              subtitle: 'Current scale: ${app.uiScale.label} (default: 80%)',
              controls: [AxButton.secondary(label: 'Reset to 80%', small: true, onPressed: () => app.uiScale = AxUiScale.default80)],
            ),
          ],
        ),
      ],
    );
  }
}

/// The app and server-program versions, and checking for newer ones.
class UpdatesSection extends StatelessWidget {
  const UpdatesSection({super.key});

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final updates = context.watch<UpdateCheckService>();
    final backend = context.watch<ArchangeldConnection>();
    final appUpdate = isUpdateAvailable(current: AppVersion.current, latest: updates.latestFrontend) ? updates.latestFrontend : null;
    final url = updates.releaseUrl;
    final serverVersion = backend.backendVersion;
    final serverUpdate =
        backend.isPaired && isUpdateAvailable(current: serverVersion, latest: updates.latestBackend) ? updates.latestBackend : null;
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsCard(
          title: 'Software Updates',
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
          ],
        ),
        SizedBox(height: ax.space.md),
        Wrap(
          spacing: ax.space.md,
          runSpacing: ax.space.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            AxButton.ghost(
              label: 'Check now',
              small: true,
              loading: updates.checking,
              onPressed: () => updates.checkForUpdates(force: true),
            ),
            if (checked != null) Text('Last checked ${formatSettingsDate(checked)}', style: ax.typo.caption.copyWith(color: c.textMuted)),
          ],
        ),
        SizedBox(height: ax.space.sm),
        Text(
          'Every update is checked before it installs, and rolls itself back if anything goes wrong.',
          style: ax.typo.caption.copyWith(color: c.textMuted),
        ),
      ],
    );
  }
}

/// System maintenance, local cache & data reset, and danger zone actions.
class SystemSection extends StatelessWidget {
  const SystemSection({super.key});

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final backend = context.watch<ArchangeldConnection>();
    final paired = backend.isPaired;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsCard(
          title: 'Storage & Cache',
          children: [
            AxListTile(
              title: 'Clear application cache',
              subtitle: 'Purge local image cache, preview caches, and temporary files on this device.',
              controls: [AxButton.secondary(label: 'Clear cache', small: true, onPressed: () => _clearCache(context))],
            ),
            AxListTile(
              title: 'Reset app settings',
              subtitle: 'Restore display scaling, theme mode, and desktop layout to defaults.',
              controls: [AxButton.secondary(label: 'Reset settings', small: true, onPressed: () => _resetAppSettings(context))],
            ),
          ],
        ),
        SizedBox(height: ax.space.lg),
        SettingsCard(
          title: 'Danger Zone',
          danger: true,
          children: [
            AxListTile(
              title: 'Restart server',
              subtitle: 'Your apps stop for about a minute, then start again.',
              controls: [AxButton.secondary(label: 'Restart', small: true, onPressed: paired ? () => _restart(context) : null)],
            ),
            AxListTile(
              title: 'Forget this server',
              subtitle: 'Removes it from this device only. Nothing on the server changes.',
              controls: [AxButton.danger(label: 'Forget', small: true, onPressed: paired ? () => _forget(context) : null)],
            ),
            AxListTile(
              title: 'Remove Archangel from this server',
              subtitle: 'Uninstalls Archangel and its secure connection. Your apps and files stay.',
              controls: [AxButton.danger(label: 'Remove', small: true, onPressed: paired ? () => showUninstallDialog(context) : null)],
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _clearCache(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    try {
      // Only Archangel's own subfolder. The temp directory itself is shared
      // with every other app on Linux (/tmp) and Windows (%TEMP%), so it must
      // never be emptied wholesale.
      final appTemp = Directory('${(await getTemporaryDirectory()).path}${Platform.pathSeparator}archangel');
      if (await appTemp.exists()) await appTemp.delete(recursive: true);
    } catch (_) {}
    showSnack(messenger, 'Application cache cleared');
  }

  Future<void> _resetAppSettings(BuildContext context) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Reset app settings to defaults?',
      message:
          'This will reset display scaling, theme mode, accent colour, and window preferences on this device. '
          'Your server connection and cloud files will not be changed.',
      confirmLabel: 'Reset settings',
      danger: true,
    );
    if (!ok) return;
    if (!context.mounted) return;

    final app = context.read<AppState>();
    app.uiScale = AxUiScale.default80;
    app.themeMode = ThemeMode.system;
    app.accentChoice = AxAccent.halo;
    app.layout = AxLayout.desktop;
    app.fullScreen = true;
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    showSnack(ScaffoldMessenger.maybeOf(context), 'Settings reset to defaults');
  }

  Future<void> _restart(BuildContext context) async {
    final monitoring = context.read<MonitoringService>();
    final messenger = ScaffoldMessenger.maybeOf(context);
    final ok = await showConfirmDialog(
      context,
      title: 'Restart your server?',
      message: 'Your apps stop for about a minute, then start again. This app reconnects by itself.',
      confirmLabel: 'Restart',
    );
    if (!ok) return;
    final result = await monitoring.rebootHost();
    showSnack(
      messenger,
      result.success ? 'Restarting. Your server will be back in about a minute.' : "Couldn't restart: ${result.message}",
    );
  }

  Future<void> _forget(BuildContext context) async {
    final registry = context.read<ServerRegistry>();
    final wg = context.read<WireGuardController>();
    final backend = context.read<ArchangeldConnection>();
    final name = registry.active?.name;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final ok = await showConfirmDialog(
      context,
      title: name == null ? 'Unpair from this server?' : 'Unpair from "$name"?',
      message:
          'This app will forget the server address and its key, so you will need to pair again to use the terminal, files, apps and activity. '
          'The server itself is not changed, and this device stays in its list of paired devices until you revoke it.',
      confirmLabel: 'Unpair',
      danger: true,
    );
    if (!ok) return;
    try {
      await removeActiveServer(registry: registry, wg: wg, backend: backend);
    } catch (_) {
      showSnack(messenger, 'Could not switch to the next server. This device was unpaired; pair again or pick a server.');
    }
  }
}

typedef DangerZoneSection = SystemSection;
