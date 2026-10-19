import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/app_state.dart';
import '../../services/containers_service.dart';
import '../../services/devops_service.dart';
import '../../services/server_registry.dart';
import '../../services/wireguard_controller.dart';
import '../../widgets/command_palette.dart' show paletteShortcutLabel;
import '../../widgets/notif_panel.dart' show hasNotifications;
import '../components/ax_icon_button.dart';
import '../components/status_badge.dart';
import '../theme.dart';

/// The compact bar above every destination: whether the secure connection is
/// up, which server this is, and search / notifications.
class StatusStrip extends StatelessWidget {
  const StatusStrip({super.key, this.showServerName = true, this.leading});

  /// The desktop rail already shows the server, so it can hide the name.
  final bool showServerName;

  /// Optional widget before the connection badge (e.g. a back button).
  final Widget? leading;

  /// The badge for a tunnel state: always an icon plus words.
  static StatusBadge badgeFor(TunnelStatus status) => switch (status) {
        TunnelStatus.connected => const StatusBadge.ok('Secure connection on'),
        TunnelStatus.connecting => const StatusBadge.warning('Connecting...', icon: Icons.sync),
        TunnelStatus.disconnecting => const StatusBadge.warning('Disconnecting...', icon: Icons.sync),
        TunnelStatus.error => const StatusBadge.error('Secure connection problem'),
        TunnelStatus.unsupported => const StatusBadge.error('Secure connection unavailable'),
        TunnelStatus.disconnected => const StatusBadge.neutral('Secure connection off', icon: Icons.shield_outlined),
      };

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final app = context.watch<AppState>();
    final wg = context.watch<WireGuardController>();
    final registry = context.watch<ServerRegistry>();
    final notify = hasNotifications(context.watch<ContainersService>(), context.watch<DevopsService>());
    final name = registry.active?.name;

    return Container(
      constraints: BoxConstraints(minHeight: axMinTarget(context) + ax.space.sm),
      padding: EdgeInsets.symmetric(horizontal: ax.space.md, vertical: ax.space.xs),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: Row(
        children: [
          if (leading != null) leading!,
          Flexible(child: badgeFor(wg.status)),
          if (showServerName && name != null) ...[
            SizedBox(width: ax.space.md),
            Flexible(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ax.typo.label.copyWith(color: c.textMuted),
              ),
            ),
          ],
          const Spacer(),
          AxIconButton(
            icon: Icons.search,
            tooltip: 'Search (${paletteShortcutLabel()})',
            onPressed: app.openPalette,
          ),
          AxIconButton(
            icon: Icons.notifications_outlined,
            tooltip: notify ? 'Notifications (new)' : 'Notifications',
            showBadge: notify,
            selected: app.notifOpen,
            onPressed: app.toggleNotif,
          ),
        ],
      ),
    );
  }
}

