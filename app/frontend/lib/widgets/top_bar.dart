import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/app_state.dart';
import '../services/containers_service.dart';
import '../services/devops_service.dart';
import '../services/monitoring_service.dart';
import '../services/wireguard_controller.dart';
import '../theme/tokens.dart';
import 'archangel_mark.dart';
import 'ax_widgets.dart';
import 'command_palette.dart' show paletteShortcutLabel;
import 'notif_panel.dart' show hasNotifications;

/// The persistent top status bar — present on every screen, showing tunnel
/// state and live system stats, functioning like a real OS's menu bar.
class TopBar extends StatelessWidget implements PreferredSizeWidget {
  final bool wide;

  const TopBar({super.key, required this.wide});

  @override
  Size get preferredSize => const Size.fromHeight(48);

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final wg = context.watch<WireGuardController>();
    final accent = app.accent;
    final tunnelColor = switch (wg.status) {
      TunnelStatus.connected => accent,
      TunnelStatus.connecting || TunnelStatus.disconnecting => AxColors.warn,
      TunnelStatus.error || TunnelStatus.unsupported => AxColors.bad,
      TunnelStatus.disconnected => AxColors.fg3,
    };
    final tunnelLabel = switch (wg.status) {
      TunnelStatus.connected => 'wg0',
      TunnelStatus.connecting => 'connecting',
      TunnelStatus.disconnecting => 'disconnecting',
      TunnelStatus.error => 'error',
      TunnelStatus.unsupported => 'unsupported',
      TunnelStatus.disconnected => 'wg0 down',
    };

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: const BoxDecoration(
        color: Color(0xFF080908),
        border: Border(bottom: BorderSide(color: AxColors.line)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final statsWide = constraints.maxWidth >= 900;
          return Row(
            children: [
              Container(
                width: 21,
                height: 21,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Center(
                  child: ArchangelMark(size: 12, color: AxColors.bg),
                ),
              ),
              if (wide) ...[
                const SizedBox(width: 9),
                Text(
                  'Archangel',
                  style: AxTextStyles.sans.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: tunnelColor.withValues(alpha: 0.11),
                  borderRadius: BorderRadius.circular(AxRadius.pill),
                  border: Border.all(
                    color: tunnelColor.withValues(alpha: 0.18),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    StatusDot(
                      color: tunnelColor,
                      size: 6,
                      pulse: wg.status == TunnelStatus.connected,
                    ),
                    const SizedBox(width: 7),
                    Text(
                      tunnelLabel,
                      style: AxTextStyles.mono.copyWith(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                        color: tunnelColor,
                      ),
                    ),
                    if (wide && wg.config != null) ...[
                      const SizedBox(width: 6),
                      Text(
                        wg.config!.interfaceAddress,
                        style: AxTextStyles.mono.copyWith(
                          fontSize: 10.5,
                          color: AxColors.fg3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Spacer(),
              if (statsWide) ...[
                () {
                  final mon = context.watch<MonitoringService>();
                  final metrics = mon.metrics;
                  final cpuStr =
                      metrics != null
                          ? '${metrics.cpu.usagePercent.round()}%'
                          : '—';
                  final memStr =
                      metrics != null
                          ? '${metrics.memory.usagePercent.round()}%'
                          : '—';
                  final upStr = metrics != null ? metrics.uptimeLabel : '—';

                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _BarStat(label: 'CPU', value: cpuStr, color: accent),
                      _BarStat(
                        label: 'MEM',
                        value: memStr,
                        color: AxColors.info,
                      ),
                      _BarStat(
                        label: 'UP',
                        value: upStr,
                        color: AxColors.fg2,
                        last: true,
                      ),
                    ],
                  );
                }(),
              ],
              const SizedBox(width: 8),
              _SearchButton(wide: wide),
              const SizedBox(width: 5),
              _NotifButton(),
            ],
          );
        },
      ),
    );
  }
}

class _BarStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final bool last;
  const _BarStat({
    required this.label,
    required this.value,
    required this.color,
    this.last = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        border: Border(
          right:
              last ? BorderSide.none : const BorderSide(color: AxColors.line),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: AxTextStyles.mono.copyWith(
              fontSize: 9,
              letterSpacing: 1.1,
              color: AxColors.fg3,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            value,
            style: AxTextStyles.mono.copyWith(
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchButton extends StatelessWidget {
  final bool wide;
  const _SearchButton({required this.wide});

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    return GestureDetector(
      onTap: app.openPalette,
      child: Container(
        height: 28,
        padding: EdgeInsets.symmetric(horizontal: wide ? 10 : 7),
        decoration: BoxDecoration(
          color: AxColors.s2,
          borderRadius: BorderRadius.circular(AxRadius.pill),
          border: Border.all(color: AxColors.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search, size: 14, color: AxColors.fg2),
            if (wide) ...[
              const SizedBox(width: 7),
              Text(
                'Search',
                style: AxTextStyles.sans.copyWith(
                  fontSize: 12,
                  color: AxColors.fg2,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: AxColors.bg,
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: AxColors.line),
                ),
                child: Text(
                  paletteShortcutLabel(),
                  style: AxTextStyles.mono.copyWith(
                    fontSize: 9.5,
                    color: AxColors.fg3,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NotifButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final showDot = hasNotifications(
      context.watch<ContainersService>(),
      context.watch<DevopsService>(),
    );
    return GestureDetector(
      onTap: app.toggleNotif,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: app.notifOpen ? AxColors.s3 : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Icon(
              Icons.notifications_outlined,
              size: 14,
              color: AxColors.fg2,
            ),
            if (showDot)
              Positioned(
                top: 3,
                right: 3,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: app.accent,
                    shape: BoxShape.circle,
                    border: Border.all(color: AxColors.s1, width: 1.5),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
