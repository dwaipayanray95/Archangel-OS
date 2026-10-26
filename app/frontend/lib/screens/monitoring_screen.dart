import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/app_state.dart';
import '../services/archangeld_connection.dart';
import '../services/monitoring_service.dart';
import '../ui/screens/activity/activity_view.dart';
import '../ui/ui.dart';

/// Activity: live server performance and processes rebuilt in the Halo design.
class MonitoringScreen extends StatefulWidget {
  const MonitoringScreen({super.key});

  @override
  State<MonitoringScreen> createState() => _MonitoringScreenState();
}

class _MonitoringScreenState extends State<MonitoringScreen> {
  MonitoringService? _mon;

  @override
  void initState() {
    super.initState();
    _mon = context.read<MonitoringService>();
    _mon?.setActive(true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final backend = context.read<ArchangeldConnection>();
      if (backend.isPaired) {
        _mon!.start(backend);
      }
    });
  }

  @override
  void dispose() {
    _mon?.setActive(false);
    super.dispose();
  }

  void _retry() {
    final backend = context.read<ArchangeldConnection>();
    if (!backend.isPaired) return;
    _mon!.start(backend);
    _mon!.fetchSnapshot();
  }

  @override
  Widget build(BuildContext context) {
    final backend = context.watch<ArchangeldConnection>();
    final mon = context.watch<MonitoringService>();
    final app = context.read<AppState>();
    final ax = context.ax;
    final c = ax.colors;

    // 1. Not paired
    if (!backend.isPaired) {
      return AxPage(
        title: 'Activity',
        child: EmptyState(
          icon: Icons.show_chart,
          title: 'No server connected yet',
          message: 'Connect a server to see how busy it is.',
          actionLabel: 'Open Settings',
          onAction: () => app.go(AxSection.settings),
        ),
      );
    }

    // 2. Not answering (status error or disconnected after having tried)
    final isError = mon.status == MonitoringStatus.error;
    final isDisconnectedWithNoMetrics = mon.status == MonitoringStatus.disconnected && mon.metrics == null;
    if (isError || isDisconnectedWithNoMetrics) {
      return AxPage(
        title: 'Activity',
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(ax.space.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.cloud_off, size: 48, color: c.danger),
                SizedBox(height: ax.space.md),
                Text("Your server isn't answering", style: ax.typo.headline.copyWith(color: c.text)),
                SizedBox(height: ax.space.xs),
                Text(
                  "It may be restarting or offline. We'll keep trying every few seconds.",
                  style: ax.typo.body.copyWith(color: c.textMuted),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: ax.space.lg),
                AxButton(label: 'Try now', onPressed: _retry),
              ],
            ),
          ),
        ),
      );
    }

    final metrics = mon.metrics;

    // 3. Connecting (no metrics yet, status connecting)
    if (metrics == null) {
      return AxPage(
        title: 'Activity',
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(ax.space.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                SizedBox(height: ax.space.md),
                Text('Reaching your server…', style: ax.typo.headline.copyWith(color: c.text)),
                SizedBox(height: ax.space.xs),
                Text(
                  'Live numbers appear in a moment.',
                  style: ax.typo.body.copyWith(color: c.textMuted),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    // 4. No data yet (connected, history empty)
    final hasNoHistory =
        metrics.cpu.history.isEmpty && metrics.memory.history.isEmpty && metrics.disk.history.isEmpty && metrics.network.history.isEmpty;
    if (hasNoHistory) {
      return AxPage(
        title: 'Activity',
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(ax.space.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.info_outline, size: 48, color: c.info),
                SizedBox(height: ax.space.md),
                Text('Waiting for the first reading', style: ax.typo.headline.copyWith(color: c.text)),
                SizedBox(height: ax.space.xs),
                Text(
                  'Connected. Charts fill in over the next minute. Numbers show "—" until then.',
                  style: ax.typo.body.copyWith(color: c.textMuted),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    // 5. Active live view
    return ActivityView(metrics: metrics, processes: mon.processes, totalProcesses: mon.totalProcesses, isConnected: mon.isConnected);
  }
}
