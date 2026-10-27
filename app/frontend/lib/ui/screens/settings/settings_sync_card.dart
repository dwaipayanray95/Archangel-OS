import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../services/prefs_sync_service.dart';
import '../../ui.dart';
import 'diagnostics_report.dart';
import 'settings_parts.dart';

/// The "Settings sync" card: whether the look of the app follows this person
/// between devices through their server, and the local switch to opt out.
/// Hidden where no [PrefsSyncService] is provided.
class SettingsSyncCard extends StatelessWidget {
  const SettingsSyncCard({super.key, this.now});

  /// Test seam for the "last synced" wording.
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context) {
    PrefsSyncService? sync;
    try {
      sync = Provider.of<PrefsSyncService>(context);
    } catch (_) {
      sync = null;
    }
    final s = sync;
    if (s == null) return const SizedBox.shrink();
    final last = s.lastSync;
    final ago = last == null ? null : 'Last synced ${plainAgo((now ?? DateTime.now)().difference(last))}.';
    final (StatusBadge badge, String line) = switch (s.status) {
      PrefsSyncStatus.unpaired => (
        const StatusBadge.neutral('Local only', icon: Icons.phonelink_off_outlined),
        'Pair a server to keep your settings the same on every device.',
      ),
      PrefsSyncStatus.unsupported => (
        const StatusBadge.neutral('Local only', icon: Icons.phonelink_off_outlined),
        "This server can't sync settings yet. They stay on this device.",
      ),
      PrefsSyncStatus.idle => (const StatusBadge.info('Waiting', icon: Icons.sync), 'Your settings will sync when your server answers.'),
      PrefsSyncStatus.syncing => (const StatusBadge.info('Syncing…', icon: Icons.sync), 'Checking your server for changes.'),
      PrefsSyncStatus.synced => (const StatusBadge.ok('Synced'), ago ?? 'Your settings are up to date.'),
      PrefsSyncStatus.offline => (
        const StatusBadge.warning('Waiting for server', icon: Icons.cloud_off_outlined),
        s.pendingCount > 0
            ? 'Your changes are saved here and will sync when your server answers.${ago == null ? '' : ' $ago'}'
            : 'Your server did not answer. ${ago ?? 'Settings stay on this device until it does.'}',
      ),
    };
    return SettingsCard(
      title: 'Across your devices',
      intro: 'Your look follows you between your devices, through your own server.',
      children: [
        AxListTile(
          title: 'Settings sync',
          subtitle: line,
          controls: [KeyedSubtree(key: const ValueKey('settings-sync-status'), child: badge)],
        ),
        AxListTile(
          title: "Don't take appearance from my server",
          subtitle: 'Keep this device\'s theme, accent and start-up sound, even if your server has different ones.',
          controls: [
            Switch(
              key: const ValueKey('settings-ignore-server-appearance'),
              value: s.ignoreServerAppearance,
              onChanged: (v) => s.setIgnoreServerAppearance(v),
            ),
          ],
        ),
      ],
    );
  }
}
