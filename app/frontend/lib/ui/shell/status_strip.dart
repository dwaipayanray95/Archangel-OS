import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/app_state.dart';
import '../../services/archangeld_connection.dart';
import '../../services/containers_service.dart';
import '../../services/devops_service.dart';
import '../../services/server_registry.dart';
import '../../services/wireguard_controller.dart';
import '../../widgets/command_palette.dart' show paletteShortcutLabel;
import '../../widgets/notif_panel.dart' show hasNotifications;
import '../components/ax_button.dart';
import '../components/ax_icon_button.dart';
import '../theme.dart';
import 'connection_state.dart';

/// How often the server is asked whether it is reachable.
const kReachabilityInterval = Duration(seconds: 10);

/// The compact bar above every destination: whether the app is really
/// connected to the server (icon + words, never colour alone), which server
/// this is, and search / notifications.
///
/// It also drives the reachability check: right away, whenever the tunnel or
/// server changes, and every [kReachabilityInterval].
class StatusStrip extends StatefulWidget {
  const StatusStrip({super.key, this.showServerName = true, this.leading});

  /// The desktop rail already shows the server, so it can hide the name.
  final bool showServerName;

  /// Optional widget before the connection status (e.g. a back button).
  final Widget? leading;

  @override
  State<StatusStrip> createState() => _StatusStripState();
}

class _StatusStripState extends State<StatusStrip> {
  Timer? _timer;
  TunnelStatus? _lastTunnel;
  String? _lastHost;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(kReachabilityInterval, (_) => _check());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _check() {
    if (!mounted) return;
    context.read<ArchangeldConnection>().checkReachable();
  }

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final app = context.watch<AppState>();
    final wg = context.watch<WireGuardController>();
    final backend = context.watch<ArchangeldConnection>();
    final registry = context.watch<ServerRegistry>();
    final notify = hasNotifications(context.watch<ContainersService>(), context.watch<DevopsService>());
    final name = registry.active?.name;

    // Check straight away on start and whenever the tunnel or server changes.
    if (_lastTunnel != wg.status || _lastHost != backend.host) {
      _lastTunnel = wg.status;
      _lastHost = backend.host;
      WidgetsBinding.instance.addPostFrameCallback((_) => _check());
    }

    final phase = deriveConnectionPhase(
      paired: backend.isPaired,
      tunnel: wg.status,
      reachable: backend.reachable,
      healthFailures: backend.healthFailures,
    );
    final showName = widget.showServerName && name != null && name.isNotEmpty && phase != ConnectionPhase.connected;

    return Container(
      constraints: BoxConstraints(minHeight: axMinTarget(context) + ax.space.sm),
      padding: EdgeInsets.symmetric(horizontal: ax.space.md, vertical: ax.space.xs),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: Row(
        children: [
          if (widget.leading != null) widget.leading!,
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ConnectionStatusLine(phase: phase, serverName: name),
                  if (showName)
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ax.typo.caption.copyWith(color: c.textMuted),
                    ),
                ],
              ),
            ),
          ),
          if (phase == ConnectionPhase.offline && wg.isPaired && wg.status != TunnelStatus.unsupported)
            AxButton.ghost(label: 'Connect', icon: Icons.power_settings_new, onPressed: wg.connect),
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

/// Icon (or a spinner while changing) plus the words for [phase].
class ConnectionStatusLine extends StatelessWidget {
  const ConnectionStatusLine({super.key, required this.phase, this.serverName});

  final ConnectionPhase phase;
  final String? serverName;

  static IconData iconFor(ConnectionPhase p) => switch (p) {
        ConnectionPhase.connected => Icons.check_circle_outline,
        ConnectionPhase.serverNotResponding => Icons.warning_amber_rounded,
        ConnectionPhase.offline => Icons.cloud_off_outlined,
        ConnectionPhase.notPaired => Icons.shield_outlined,
        ConnectionPhase.starting || ConnectionPhase.reaching => Icons.sync,
      };

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final color = switch (phase) {
      ConnectionPhase.connected => c.success,
      ConnectionPhase.serverNotResponding => c.warning,
      ConnectionPhase.offline => c.danger,
      ConnectionPhase.starting || ConnectionPhase.reaching => c.textMuted,
      ConnectionPhase.notPaired => c.textMuted,
    };
    final text = connectionText(phase, serverName: serverName);
    return Semantics(
      liveRegion: true,
      label: text,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (connectionIsTransitional(phase))
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: color))
          else
            Icon(iconFor(phase), size: 16, color: color),
          SizedBox(width: ax.space.sm),
          Flexible(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: ax.typo.caption.copyWith(color: color, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
