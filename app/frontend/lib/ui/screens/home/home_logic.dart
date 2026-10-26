import '../../../data/app_state.dart';
import '../../../models/container_model.dart';
import '../../../models/devops_model.dart';
import '../../../models/system_metrics.dart';
import '../../../services/app_version.dart';
import '../../components/status_badge.dart';

enum HealthLevel { unreachable, checking, warning, healthy }

class HealthStatus {
  final HealthLevel level;
  final List<String> problems;
  const HealthStatus(this.level, [this.problems = const []]);

  bool get isHealthy => level == HealthLevel.healthy;

  /// The big plain-language sentence on Home.
  String get headline => switch (level) {
    HealthLevel.unreachable => "Can't reach your server",
    HealthLevel.checking => 'Checking on your server...',
    HealthLevel.warning => problems.join(' · '),
    HealthLevel.healthy => 'Your server is healthy and guarded.',
  };

  /// A short follow-up line under the headline.
  String get detail => switch (level) {
    HealthLevel.unreachable => 'Check that the secure connection is on, or open Settings.',
    HealthLevel.checking => 'Waiting for the first reading.',
    HealthLevel.warning => 'Something is running low. See "Needs attention" below.',
    HealthLevel.healthy => 'Nothing needs you right now.',
  };

  String? get hint => level == HealthLevel.unreachable ? 'Check the tunnel is connected (top bar) or open Settings.' : null;

  String get pill => switch (level) {
    HealthLevel.unreachable => 'Offline',
    HealthLevel.checking => 'Connecting',
    HealthLevel.warning => 'Needs attention',
    HealthLevel.healthy => 'Healthy',
  };
}

/// Usage at or above this percentage counts as a problem.
const kUsageLimit = 90.0;

/// Healthy only when connected AND CPU, memory and every disk are under 90%.
HealthStatus evaluateHealth({required bool connected, required SystemMetrics? metrics}) {
  if (!connected) return const HealthStatus(HealthLevel.unreachable);
  if (metrics == null) return const HealthStatus(HealthLevel.checking);
  final problems = <String>[];
  if (metrics.cpu.usagePercent >= kUsageLimit) {
    problems.add('CPU is ${metrics.cpu.usagePercent.round()}% busy');
  }
  if (metrics.memory.usagePercent >= kUsageLimit) {
    problems.add('Memory is ${metrics.memory.usagePercent.round()}% used');
  }
  final mounts = metrics.disk.mounts;
  if (mounts.isEmpty) {
    if (metrics.disk.usagePercent >= kUsageLimit) problems.add('Disk is ${metrics.disk.usagePercent.round()}% full');
  } else {
    for (final m in mounts) {
      if (m.totalBytes > 0 && m.usagePercent >= kUsageLimit) {
        problems.add('Disk ${m.mountPoint} is ${m.usagePercent.round()}% full');
      }
    }
  }
  return problems.isEmpty ? const HealthStatus(HealthLevel.healthy) : HealthStatus(HealthLevel.warning, problems);
}

/// One row of Home's "Needs attention" list.
class AttentionItem {
  const AttentionItem({
    required this.id,
    required this.title,
    required this.detail,
    required this.status,
    required this.target,
    required this.actionLabel,
  });

  final String id;
  final String title;
  final String detail;
  final AxStatus status;

  /// Where tapping the row goes.
  final AxSection target;
  final String actionLabel;
}

/// Builds the "Needs attention" list from real data only. Pass whatever is
/// known; unknown (null/empty) inputs simply contribute nothing.
List<AttentionItem> buildAttentionItems({
  List<DockerContainerItem> containers = const [],
  List<DevRowModel> services = const [],
  SystemMetrics? metrics,
  bool updateAvailable = false,
  String? latestVersion,
}) {
  final items = <AttentionItem>[];

  for (final c in containers.where((c) => !c.running)) {
    items.add(
      AttentionItem(
        id: 'app:${c.id.isNotEmpty ? c.id : c.name}',
        title: '${c.name} is stopped',
        detail: 'This app is not running. Open Apps to start it again.',
        status: AxStatus.warning,
        target: AxSection.apps,
        actionLabel: 'Open Apps',
      ),
    );
  }

  for (final s in services.where((s) => !s.ok)) {
    items.add(
      AttentionItem(
        id: 'service:${s.name}',
        title: '${s.name} has a problem',
        detail: s.status.isNotEmpty ? 'Status: ${s.status}. Open Services to look into it.' : 'Open Services to look into it.',
        status: AxStatus.error,
        target: AxSection.services,
        actionLabel: 'Open Services',
      ),
    );
  }

  if (metrics != null) {
    final mounts = metrics.disk.mounts;
    final full = <(String, double)>[];
    if (mounts.isEmpty) {
      if (metrics.disk.usagePercent >= kUsageLimit) full.add(('/', metrics.disk.usagePercent));
    } else {
      for (final m in mounts) {
        if (m.totalBytes > 0 && m.usagePercent >= kUsageLimit) full.add((m.mountPoint, m.usagePercent));
      }
    }
    for (final (mount, pct) in full) {
      items.add(
        AttentionItem(
          id: 'disk:$mount',
          title: 'Disk $mount is ${pct.round()}% full',
          detail: 'When a disk fills up, apps can stop working. Free up some space soon.',
          status: AxStatus.error,
          target: AxSection.activity,
          actionLabel: 'See disk usage',
        ),
      );
    }
  }

  if (updateAvailable) {
    items.add(
      AttentionItem(
        id: 'update',
        title: 'Archangel OS update available',
        detail: latestVersion == null
            ? 'A new version is ready. Open Settings to update.'
            : 'Version $latestVersion is ready (you have ${AppVersion.current}). Open Settings to update.',
        status: AxStatus.info,
        target: AxSection.settings,
        actionLabel: 'Open Settings',
      ),
    );
  }
  return items;
}

/// The fullest disk's usage, or the overall figure when no mounts are listed.
double worstDiskPercent(DiskMetrics disk) {
  var worst = disk.mounts.isEmpty ? disk.usagePercent : 0.0;
  for (final m in disk.mounts) {
    if (m.totalBytes > 0 && m.usagePercent > worst) worst = m.usagePercent;
  }
  return worst;
}

/// The status for a usage percentage.
AxStatus usageStatus(double percent) => percent >= kUsageLimit
    ? AxStatus.error
    : percent >= 75
    ? AxStatus.warning
    : AxStatus.ok;

String usageBadgeLabel(double percent, {required String high, required String mid, String ok = 'Fine'}) =>
    percent >= kUsageLimit ? high : (percent >= 75 ? mid : ok);

/// "4.1" / "16" style amounts (one decimal under 10 GB, none above).
String gbText(double gb) {
  if (gb >= 10) return gb.toStringAsFixed(0);
  final s = gb.toStringAsFixed(1);
  return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
}

/// "3d 4h 12m" / "2h 5m 9s" / "4m 2s".
String formatUptime(int seconds) {
  if (seconds <= 0) return '-';
  final d = seconds ~/ 86400;
  final h = (seconds % 86400) ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  if (d > 0) return '${d}d ${h}h ${m}m';
  if (h > 0) return '${h}h ${m}m ${s}s';
  return '${m}m ${s}s';
}
