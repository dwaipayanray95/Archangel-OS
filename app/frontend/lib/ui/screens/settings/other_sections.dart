import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../data/app_state.dart';
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
    final app = context.watch<AppState>();
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Phones always use the bottom bar, so the layout choice only shows where
    // Desktop mode is possible. It follows the screen, not the window.
    final desktopPossible = MediaQuery.sizeOf(context).width >= kDesktopModeMinWidth;
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
        if (desktopPossible && app.layout == AxLayout.desktop)
          AxListTile(
            title: 'Desktop',
            subtitle: "Wallpaper, dock position and size, what's in the dock, the health widget.",
            controls: [AxButton.secondary(label: 'Customize', small: true, onPressed: () => showDesktopCustomize(context))],
          ),
        AxListTile(
          title: 'Start-up animation',
          subtitle: 'Plays every time on tablets and Macs. On phones, the long version plays the first time only.',
          controls: [
            AxButton.secondary(label: 'Replay first launch', small: true, onPressed: () => app.replayBoot(BootKind.first)),
            AxButton.secondary(label: 'Replay later launch', small: true, onPressed: () => app.replayBoot(BootKind.short)),
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
            AxButton.ghost(label: 'Check now', small: true, loading: updates.checking, onPressed: () => updates.checkForUpdates(force: true)),
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

/// Restart the server, forget it on this device, or uninstall Archangel.
class DangerZoneSection extends StatelessWidget {
  const DangerZoneSection({super.key});

  @override
  Widget build(BuildContext context) {
    final backend = context.watch<ArchangeldConnection>();
    final paired = backend.isPaired;
    return SettingsCard(
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
    );
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
    showSnack(messenger, result.success ? 'Restarting. Your server will be back in about a minute.' : "Couldn't restart: ${result.message}");
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
