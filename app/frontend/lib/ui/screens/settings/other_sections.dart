import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../data/app_state.dart';
import '../../../services/app_version.dart';
import '../../../services/archangeld_connection.dart';
import '../../../services/semver.dart';
import '../../../services/server_registry.dart';
import '../../../services/ssh_credentials.dart';
import '../../../services/update_check_service.dart';
import '../../../services/wireguard_controller.dart';
import '../../../widgets/manage_ssh_key_dialog.dart';
import '../../../widgets/passphrase_prompt_dialog.dart';
import '../../../widgets/uninstall_dialog.dart';
import '../../ui.dart';
import 'settings_parts.dart';

/// Passphrase and saved-key management.
class SecuritySection extends StatelessWidget {
  const SecuritySection({super.key});

  /// "Change passphrase" for the saved SSH key: asks for the current and a new
  /// passphrase, then re-encrypts the saved key.
  Future<void> _changePassphrase(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (!await hasSavedSshCredentials()) {
      showSnack(messenger, 'No SSH key is saved yet - use "Manage saved SSH key" to save one.');
      return;
    }
    if (!context.mounted) return;
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

  Future<void> _forget(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (!await hasSavedSshCredentials()) {
      showSnack(messenger, 'No SSH key is saved on this device.');
      return;
    }
    if (!context.mounted) return;
    final ok = await showConfirmDialog(
      context,
      title: 'Forget the saved SSH key?',
      message: 'The key is deleted from this device. The next time you update or repair your server you will have to enter it again. Your server is not changed.',
      confirmLabel: 'Forget key',
      danger: true,
    );
    if (!ok) return;
    await clearSavedSshCredentials();
    showSnack(messenger, 'Saved SSH key forgotten.');
  }

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    return SettingsSection(
      title: 'Security',
      explanation: 'An SSH key lets this app manage your server (updates, repairs). It can be saved here, locked by a passphrase.',
      help: const HelpTip(
        title: 'Saved SSH key',
        message: 'An SSH key is like a long password stored in a file. If you save it here it is encrypted with a passphrase you choose, '
            'so you only type the passphrase instead of pasting the key each time. The passphrase cannot be recovered if you forget it - '
            'you would just save the key again.',
      ),
      child: Wrap(
        spacing: ax.space.sm,
        runSpacing: ax.space.sm,
        children: [
          AxButton.secondary(label: 'Change passphrase', icon: Icons.password, onPressed: () => _changePassphrase(context)),
          AxButton.secondary(label: 'Manage saved SSH key', icon: Icons.vpn_key_outlined, onPressed: () => showManageSshKeyDialog(context)),
          AxButton.secondary(label: 'Forget saved SSH key', icon: Icons.delete_outline, onPressed: () => _forget(context)),
        ],
      ),
    );
  }
}

/// Theme (System / Light / Dark) and accent colour, remembered on this device.
class AppearanceSection extends StatelessWidget {
  const AppearanceSection({super.key});

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final app = context.watch<AppState>();
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SettingsSection(
      title: 'Appearance',
      explanation: 'Choose light or dark, and the highlight colour. Saved on this device.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Theme', style: ax.typo.label.copyWith(color: c.text)),
          SizedBox(height: ax.space.sm),
          SegmentedButton<ThemeMode>(
            showSelectedIcon: true,
            segments: const [
              ButtonSegment(value: ThemeMode.system, label: Text('System'), icon: Icon(Icons.brightness_auto_outlined)),
              ButtonSegment(value: ThemeMode.light, label: Text('Light'), icon: Icon(Icons.light_mode_outlined)),
              ButtonSegment(value: ThemeMode.dark, label: Text('Dark'), icon: Icon(Icons.dark_mode_outlined)),
            ],
            selected: {app.themeMode},
            onSelectionChanged: (s) => app.themeMode = s.first,
          ),
          SizedBox(height: ax.space.lg),
          Text('Accent colour', style: ax.typo.label.copyWith(color: c.text)),
          SizedBox(height: ax.space.sm),
          Wrap(
            spacing: ax.space.sm,
            runSpacing: ax.space.sm,
            children: [
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
        ],
      ),
    );
  }
}

/// Check for new versions, and where to download a new app.
class UpdatesSection extends StatelessWidget {
  const UpdatesSection({super.key});

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final updates = context.watch<UpdateCheckService>();
    final appUpdate = isUpdateAvailable(current: AppVersion.current, latest: updates.latestFrontend) ? updates.latestFrontend : null;
    final checked = updates.lastChecked;
    final url = updates.releaseUrl;
    return SettingsSection(
      title: 'Updates',
      explanation: 'Look for newer versions of this app and of the Archangel server.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: ax.space.md,
            runSpacing: ax.space.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              AxButton.secondary(
                label: 'Check now',
                icon: Icons.refresh,
                loading: updates.checking,
                onPressed: () => updates.checkForUpdates(force: true),
              ),
              if (checked != null) Text('Last checked ${formatSettingsDate(checked)}', style: ax.typo.caption.copyWith(color: c.textMuted)),
            ],
          ),
          SizedBox(height: ax.space.md),
          if (appUpdate != null) ...[
            const StatusBadge.warning('A new version of the app is available'),
            SizedBox(height: ax.space.sm),
            Text('Version $appUpdate is out (you have ${AppVersion.current}).', style: ax.typo.body.copyWith(color: c.text)),
            if (url != null) ...[
              SizedBox(height: ax.space.sm),
              AxButton.secondary(
                label: 'Download the new app',
                icon: Icons.open_in_new,
                onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
              ),
            ],
          ] else
            Text('This app is up to date.', style: ax.typo.body.copyWith(color: c.textMuted)),
        ],
      ),
    );
  }
}

/// Unpair this device and uninstall Archangel from the server.
class DangerZoneSection extends StatelessWidget {
  const DangerZoneSection({super.key});

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final backend = context.watch<ArchangeldConnection>();
    return SettingsSection(
      title: 'Danger zone',
      danger: true,
      explanation: 'These are hard to undo. Read what each one does first.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Unpair this device', style: ax.typo.label.copyWith(color: c.text)),
          Text(
            'This app forgets the active server. The server keeps running and this device stays in its device list until you revoke it.',
            style: ax.typo.body.copyWith(color: c.textMuted),
          ),
          SizedBox(height: ax.space.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: AxButton.danger(
              label: 'Unpair',
              icon: Icons.link_off,
              onPressed: backend.isPaired ? () => _unpair(context) : null,
            ),
          ),
          SizedBox(height: ax.space.lg),
          Text('Uninstall from server', style: ax.typo.label.copyWith(color: c.text)),
          Text(
            'Stops and removes Archangel and its secure connection from the server for everyone. You would have to set it up again from scratch.',
            style: ax.typo.body.copyWith(color: c.textMuted),
          ),
          SizedBox(height: ax.space.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: AxButton.danger(
              label: 'Uninstall from server',
              icon: Icons.delete_forever_outlined,
              onPressed: backend.isPaired ? () => showUninstallDialog(context) : null,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _unpair(BuildContext context) async {
    final registry = context.read<ServerRegistry>();
    final wg = context.read<WireGuardController>();
    final backend = context.read<ArchangeldConnection>();
    final name = registry.active?.name;
    final ok = await showConfirmDialog(
      context,
      title: name == null ? 'Unpair from this server?' : 'Unpair from "$name"?',
      message: 'This app will forget the server address and its key, so you will need to pair again to use the terminal, files, apps and activity. '
          'The server itself is not changed, and this device stays in its list of paired devices until you revoke it.',
      confirmLabel: 'Unpair',
      danger: true,
    );
    if (ok) await removeActiveServer(registry: registry, wg: wg, backend: backend);
  }
}
