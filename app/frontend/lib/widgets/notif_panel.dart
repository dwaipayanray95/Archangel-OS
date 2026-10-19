import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../screens/overview_screen.dart' show evaluateHealth, HealthLevel;
import '../services/containers_service.dart';
import '../services/devops_service.dart';
import '../services/monitoring_service.dart';
import '../theme/tokens.dart';

class _NotifItem {
  final String actor;
  final String text;
  final String detail;
  final Color color;
  const _NotifItem({required this.actor, required this.text, required this.detail, required this.color});
}

List<_NotifItem> _buildNotifItems(ContainersService contSvc, DevopsService devSvc) {
  final items = <_NotifItem>[];

  // Surface any warnings or active status from live containers
  final containers = contSvc.overview?.containers ?? [];
  for (final c in containers.take(3)) {
    items.add(_NotifItem(
      actor: c.name,
      text: c.running ? 'running' : 'stopped',
      detail: '${c.image} · ${c.uptime.isNotEmpty ? c.uptime : "idle"}',
      color: c.running ? AxColors.accent : AxColors.warn,
    ));
  }

  // Surface systemd services / deployments
  for (final s in devSvc.services.take(2)) {
    items.add(_NotifItem(
      actor: s.name,
      text: s.status,
      detail: s.meta,
      color: s.ok ? AxColors.accent : AxColors.bad,
    ));
  }
  return items;
}

/// True when the panel has something to list - drives the bell's accent dot.
bool hasNotifications(ContainersService contSvc, DevopsService devSvc) =>
    _buildNotifItems(contSvc, devSvc).isNotEmpty;

class NotifPanel extends StatelessWidget {
  const NotifPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final contSvc = context.watch<ContainersService>();
    final devSvc = context.watch<DevopsService>();
    final monSvc = context.watch<MonitoringService>();

    final items = _buildNotifItems(contSvc, devSvc);
    final health = evaluateHealth(connected: monSvc.isConnected, metrics: monSvc.metrics);

    return Positioned(
      top: 55,
      right: 10,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: AxMotion.pop,
        curve: AxMotion.easeOutSoft,
        builder: (context, t, child) => Opacity(
          opacity: t,
          child: Transform.translate(offset: Offset(0, (1 - t) * -12), child: child),
        ),
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 310,
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: AxColors.s2,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AxColors.line2),
              boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 50, offset: Offset(0, 20))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 5, 8, 8),
                  child: Row(
                    children: [
                      Text('NOTIFICATIONS', style: AxTextStyles.sans.copyWith(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1, color: AxColors.fg3)),
                      const Spacer(),
                      Text(
                        items.isEmpty
                            ? (health.isHealthy ? 'all nominal' : (monSvc.isConnected ? 'attention' : 'offline'))
                            : '${items.length} active',
                        style: AxTextStyles.mono.copyWith(fontSize: 10, color: AxColors.fg3),
                      ),
                    ],
                  ),
                ),
                if (items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
                    child: Center(
                      child: Text(
                        health.isHealthy
                            ? 'No active alerts · All systems nominal'
                            : (health.level == HealthLevel.unreachable ? "Can't reach your server. ${health.hint}" : health.headline),
                        textAlign: TextAlign.center,
                        style: AxTextStyles.mono.copyWith(fontSize: 11, color: AxColors.fg3),
                      ),
                    ),
                  )
                else
                  for (final n in items)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 5),
                              child: Container(width: 6, height: 6, decoration: BoxDecoration(color: n.color, shape: BoxShape.circle)),
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  RichText(
                                    text: TextSpan(
                                      style: AxTextStyles.sans.copyWith(fontSize: 12.5, height: 1.35),
                                      children: [
                                        TextSpan(text: '${n.actor} ', style: const TextStyle(fontWeight: FontWeight.w600)),
                                        TextSpan(text: n.text, style: const TextStyle(color: AxColors.fg2)),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(n.detail, style: AxTextStyles.mono.copyWith(fontSize: 10.5, color: AxColors.fg3), maxLines: 1, overflow: TextOverflow.ellipsis),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
