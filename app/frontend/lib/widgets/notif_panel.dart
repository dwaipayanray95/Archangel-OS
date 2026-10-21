import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../screens/overview_screen.dart' show evaluateHealth, HealthLevel;
import '../services/containers_service.dart';
import '../services/devops_service.dart';
import '../services/monitoring_service.dart';
import '../ui/ui.dart';

class _NotifItem {
  final String actor;
  final String text;
  final String detail;
  final AxStatus status;
  const _NotifItem({required this.actor, required this.text, required this.detail, required this.status});
}

List<_NotifItem> _buildNotifItems(ContainersService contSvc, DevopsService devSvc) {
  final items = <_NotifItem>[];

  // Surface any warnings or active status from live containers
  final containers = contSvc.overview?.containers ?? [];
  for (final c in containers.take(3)) {
    items.add(
      _NotifItem(
        actor: c.name,
        text: c.running ? 'running' : 'stopped',
        detail: '${c.image} · ${c.uptime.isNotEmpty ? c.uptime : "idle"}',
        status: c.running ? AxStatus.ok : AxStatus.warning,
      ),
    );
  }

  // Surface systemd services / deployments
  for (final s in devSvc.services.take(2)) {
    items.add(_NotifItem(actor: s.name, text: s.status, detail: s.meta, status: s.ok ? AxStatus.ok : AxStatus.error));
  }
  return items;
}

/// True when the panel has something to list - drives the bell's accent dot.
bool hasNotifications(ContainersService contSvc, DevopsService devSvc) => _buildNotifItems(contSvc, devSvc).isNotEmpty;

class NotifPanel extends StatelessWidget {
  const NotifPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final contSvc = context.watch<ContainersService>();
    final devSvc = context.watch<DevopsService>();
    final monSvc = context.watch<MonitoringService>();

    final items = _buildNotifItems(contSvc, devSvc);
    final health = evaluateHealth(connected: monSvc.isConnected, metrics: monSvc.metrics);

    final ax = context.ax;
    final c = ax.colors;

    Color statusColor(AxStatus st) => switch (st) {
      AxStatus.ok => c.success,
      AxStatus.warning => c.warning,
      AxStatus.error => c.danger,
      AxStatus.info => c.info,
      AxStatus.neutral => c.textMuted,
      AxStatus.accent => c.accent,
    };

    return Positioned(
      top: 55,
      right: 10,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 230),
        curve: Curves.easeOutCubic,
        builder: (context, t, child) => Opacity(opacity: t, child: Transform.translate(offset: Offset(0, (1 - t) * -12), child: child)),
        child: Semantics(
          container: true,
          label: 'Notifications',
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 310,
              padding: EdgeInsets.all(ax.space.sm),
              decoration: BoxDecoration(
                color: c.surfaceHigh,
                borderRadius: BorderRadius.circular(ax.radii.lg),
                border: Border.all(color: c.border),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(ax.space.sm, ax.space.xs, ax.space.sm, ax.space.sm),
                    child: Row(
                      children: [
                        Text(
                          'NOTIFICATIONS',
                          style: ax.typo.caption.copyWith(fontWeight: FontWeight.w700, letterSpacing: 1, color: c.textMuted),
                        ),
                        const Spacer(),
                        Text(
                          items.isEmpty
                              ? (health.isHealthy ? 'All good' : (monSvc.isConnected ? 'Needs attention' : 'Offline'))
                              : '${items.length} active',
                          style: ax.typo.caption.copyWith(color: c.textMuted),
                        ),
                      ],
                    ),
                  ),
                  if (items.isEmpty)
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: ax.space.lg, horizontal: ax.space.md),
                      child: Center(
                        child: Text(
                          health.isHealthy
                              ? 'No active alerts. Everything looks fine.'
                              : (health.level == HealthLevel.unreachable ? "Can't reach your server. ${health.hint}" : health.headline),
                          textAlign: TextAlign.center,
                          style: ax.typo.caption.copyWith(color: c.textMuted),
                        ),
                      ),
                    )
                  else
                    for (final n in items)
                      Padding(
                        padding: EdgeInsets.all(ax.space.sm),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(StatusBadge.defaultIcon(n.status), size: 16, color: statusColor(n.status)),
                            SizedBox(width: ax.space.sm),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text.rich(
                                    TextSpan(
                                      style: ax.typo.body.copyWith(color: c.text),
                                      children: [
                                        TextSpan(text: '${n.actor} ', style: const TextStyle(fontWeight: FontWeight.w600)),
                                        TextSpan(text: n.text, style: TextStyle(color: c.textMuted)),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    n.detail,
                                    style: ax.typo.caption.copyWith(color: c.textMuted),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
