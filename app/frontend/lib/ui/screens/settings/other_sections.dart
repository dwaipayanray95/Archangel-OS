import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../data/app_state.dart';
import '../../../services/admin_mode_service.dart';
import '../../../services/archangeld_connection.dart';
import '../../../services/monitoring_service.dart';
import '../../../services/server_registry.dart';
import '../../../services/ssh_credentials.dart';
import '../../../services/build_config.dart';
import '../../../services/wireguard_controller.dart';
import '../../../widgets/manage_ssh_key_dialog.dart';
import '../../../widgets/passphrase_prompt_dialog.dart';
import '../../../widgets/sync_server_config_dialog.dart';
import '../../../widgets/uninstall_dialog.dart';
import '../../shell/archangel_shell.dart' show kDesktopModeMinWidth;
import '../../shell/connection_state.dart';
import '../../shell/desktop_customize.dart';
import '../../shell/desktop_prefs.dart';
import '../../ui.dart';
import '../home/home_logic.dart';
import 'diagnostics_report.dart';
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
      builder: (context, controller, _) => AxButton.secondary(
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
      title: 'Security',
      intro: 'The key and the secure connection that keep your server private.',
      children: [
        const SettingsGroupLabel('Your key'),
        AxListTile(
          leading: const AxTileIcon(Icons.vpn_key_outlined),
          title: 'SSH key',
          subtitle: _keySaved == null
              ? null
              : (_keySaved! ? 'Stored on this device, protected by your passphrase. It never leaves this device.' : 'No key saved yet.'),
          controls: [_keyControl()],
        ),
        const SettingsGroupLabel('Connection'),
        AxListTile(
          leading: const AxTileIcon(Icons.shield_outlined),
          title: 'Secure connection',
          subtitleWidget: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(connectionText(phase, serverName: context.watch<ServerRegistry>().active?.name), style: muted),
              if (cfg != null)
                Text.rich(
                  TextSpan(
                    style: muted,
                    children: [
                      const TextSpan(text: 'Private address '),
                      TextSpan(
                        text: cfg.interfaceAddress.split('/').first,
                        style: ax.typo.mono.copyWith(color: c.textMuted),
                      ),
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
        if (backend.isPaired) const SettingsGroupLabel('Repairs'),
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
    return SettingsStack(
      children: [
        SettingsCard(
          title: 'Look',
          intro: 'Colours and size of the app on this device.',
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
              subtitle: 'Make everything a little smaller or larger.',
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
          ],
        ),
        if (desktopPossible)
          SettingsCard(
            title: 'Windows and layout',
            intro: 'How Archangel arranges its screens on this device.',
            children: [
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
              AxListTile(
                title: 'Window mode',
                subtitle: 'Fill the whole screen, or use a normal window. Press F11 to switch any time.',
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
            ],
          ),
        if (desktopPossible && app.layout == AxLayout.desktop)
          SettingsCard(
            title: 'Desktop',
            intro: 'What you see on the desktop and in the dock.',
            children: [
              if (p != null) ...[
                AxListTile(
                  title: 'Wallpaper',
                  subtitle: 'The picture behind your windows. Halo follows Pearl and Dawn.',
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
                  subtitle: 'Where the dock of apps sits on your screen.',
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
                  subtitle: 'How big the dock icons are.',
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
                  title: 'Hide the dock automatically',
                  subtitle: 'The dock slides away and comes back when you point at the edge.',
                  controls: [Switch(key: const ValueKey('settings-dock-autohide'), value: p.autoHide, onChanged: (v) => p.autoHide = v)],
                ),
                AxListTile(
                  title: 'Snap windows to screen edges',
                  subtitle: 'Hold a window by its title bar at the edge of the desktop for a moment to fit it to half the screen.',
                  controls: [
                    Switch(key: const ValueKey('settings-snap-windows'), value: p.snapToEdges, onChanged: (v) => p.snapToEdges = v),
                  ],
                ),
                AxListTile(
                  title: 'Health widget',
                  subtitle: 'Shows how busy your server is (processor, memory and disk) on the desktop.',
                  controls: [
                    Switch(key: const ValueKey('settings-show-health-widget'), value: p.showWidget, onChanged: (v) => p.showWidget = v),
                  ],
                ),
                AxListTile(
                  title: 'Wallpaper wordmark',
                  subtitle: 'Shows the Archangel OS name in the middle of the desktop.',
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
          ),
        SettingsCard(
          title: 'Start-up animation',
          intro: 'The short animation that plays when Archangel opens.',
          children: [
            AxListTile(
              title: 'Start-up sound',
              subtitle: 'A soft chime while the animation plays.',
              controls: [
                Switch(key: const ValueKey('settings-startup-sound'), value: app.startupSound, onChanged: (v) => app.startupSound = v),
              ],
            ),
            AxListTile(
              title: 'Replay it',
              subtitle: 'Plays every time on tablets and Macs. On phones, the long version plays the first time only.',
              controls: [
                AxButton.secondary(label: 'Replay first launch', small: true, onPressed: () => app.replayBoot(BootKind.first)),
                AxButton.secondary(label: 'Replay later launch', small: true, onPressed: () => app.replayBoot(BootKind.short)),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

/// Housekeeping for this device, help for when something is wrong, and the
/// risky actions at the bottom.
class SystemSection extends StatelessWidget {
  const SystemSection({super.key});

  @override
  Widget build(BuildContext context) {
    final backend = context.watch<ArchangeldConnection>();
    final paired = backend.isPaired;
    return SettingsStack(
      children: [
        SettingsCard(
          title: 'This device',
          intro: 'Tidy up the app on this device. Your server is not changed.',
          children: [
            AxListTile(
              title: 'Free up space',
              subtitle:
                  'Clears saved image previews and the temporary files Archangel made on this device. '
                  'Your files and your server are not touched.',
              controls: [AxButton.secondary(label: 'Clear now', small: true, onPressed: () => _clearCache(context))],
            ),
            AxListTile(
              title: 'Reset app settings',
              subtitle: 'Puts the theme, colour, size and layout back to how they were at the start.',
              controls: [AxButton.secondary(label: 'Reset settings', small: true, onPressed: () => _resetAppSettings(context))],
            ),
          ],
        ),
        SettingsCard(
          title: 'Help & diagnostics',
          intro: 'Something not working? Send us the details and we can help.',
          footnote: 'The report holds versions and status only. It never includes passwords, keys or your pairing code.',
          children: [
            AxListTile(
              title: 'Diagnostics',
              subtitle: 'A short report with versions, your server and the connection.',
              controls: [
                AxButton.ghost(label: 'View report', small: true, onPressed: () => _viewDiagnostics(context)),
                AxButton(
                  label: 'Copy diagnostics for support',
                  icon: Icons.copy_rounded,
                  small: true,
                  onPressed: () => _copyDiagnostics(context),
                ),
              ],
            ),
            AxListTile(
              title: 'Found a bug?',
              subtitle: 'Tell us what happened on GitHub. Paste the diagnostics in your message.',
              controls: [
                AxButton.secondary(
                  label: 'Report a problem',
                  icon: Icons.open_in_new,
                  small: true,
                  onPressed: () => launchUrl(Uri.parse('https://github.com/$kGithubRepoSlug/issues'), mode: LaunchMode.externalApplication),
                ),
              ],
            ),
          ],
        ),
        SettingsCard(
          title: 'Danger zone',
          intro: 'Serious actions. Each one asks you first.',
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

  /// The redacted report: versions, systems, connection, health, recent errors.
  String _report(BuildContext context) {
    final backend = context.read<ArchangeldConnection>();
    final monitoring = context.read<MonitoringService>();
    final wireguard = context.read<WireGuardController>();
    final admin = context.read<AdminModeService>();
    final phase = deriveConnectionPhase(
      paired: backend.isPaired,
      tunnel: wireguard.status,
      reachable: backend.reachable,
      healthFailures: backend.healthFailures,
    );
    return buildDiagnosticsReport(
      now: DateTime.now(),
      phase: phase,
      health: evaluateHealth(connected: monitoring.isConnected, metrics: monitoring.metrics),
      serverVersion: backend.backendVersion,
      metrics: monitoring.metrics,
      adminMode: admin.enabled,
      recentErrors: [?monitoring.error, ?wireguard.lastError, ?backend.backendVersionError],
      secrets: [backend.token, wireguard.config?.interfacePrivateKey, wireguard.config?.peerPublicKey],
    );
  }

  void _copyDiagnostics(BuildContext context) {
    Clipboard.setData(ClipboardData(text: _report(context)));
    showSnack(ScaffoldMessenger.maybeOf(context), 'Diagnostics copied. Paste them into your message to support.');
  }

  void _viewDiagnostics(BuildContext context) {
    final report = _report(context);
    final ax = context.ax;
    final c = ax.colors;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        scrollable: true,
        title: Text('Diagnostics report', style: ax.typo.title.copyWith(color: c.text)),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Container(
            padding: EdgeInsets.all(ax.space.md),
            decoration: BoxDecoration(
              color: c.surfaceAlt,
              borderRadius: BorderRadius.circular(ax.radii.sm),
              border: Border.all(color: c.border),
            ),
            child: SelectableText(report, style: ax.typo.mono.copyWith(color: c.text)),
          ),
        ),
        actions: [AxButton.ghost(label: 'Close', onPressed: () => Navigator.of(ctx).pop())],
      ),
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
