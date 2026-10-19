import 'package:flutter_test/flutter_test.dart';
import 'package:archangel/models/system_metrics.dart';
import 'package:archangel/screens/overview_screen.dart';

SystemMetrics metrics({double cpu = 10, double mem = 20, List<MountMetric> mounts = const []}) {
  return SystemMetrics(
    timestamp: 0,
    cpu: CPUMetrics(usagePercent: cpu, cores: const [], history: const []),
    memory: MemoryMetrics(totalBytes: 100, usedBytes: 20, availableBytes: 80, usagePercent: mem, history: const []),
    disk: DiskMetrics(
      readBytesPerSec: 0,
      writeBytesPerSec: 0,
      totalBytes: 100,
      usedBytes: 10,
      usagePercent: 10,
      mounts: mounts,
      history: const [],
    ),
    network: const NetworkMetrics(rxBytesPerSec: 0, txBytesPerSec: 0, interfaces: [], history: []),
  );
}

MountMetric mount(String p, int used) => MountMetric(mountPoint: p, device: 'd', totalBytes: 100, usedBytes: used);

void main() {
  test('disconnected is unreachable', () {
    final h = evaluateHealth(connected: false, metrics: metrics());
    expect(h.level, HealthLevel.unreachable);
    expect(h.headline, "Can't reach your server");
    expect(h.hint, isNotNull);
  });

  test('connected without data is only "checking"', () {
    expect(evaluateHealth(connected: true, metrics: null).isHealthy, isFalse);
  });

  test('healthy below 90 everywhere', () {
    expect(evaluateHealth(connected: true, metrics: metrics(mounts: [mount('/', 89)])).isHealthy, isTrue);
  });

  test('reports each problem in plain words', () {
    final h = evaluateHealth(
      connected: true,
      metrics: metrics(cpu: 95, mem: 91, mounts: [mount('/', 94), mount('/data', 10)]),
    );
    expect(h.level, HealthLevel.warning);
    expect(h.problems, ['CPU is 95% busy', 'Memory is 91% used', 'Disk / is 94% full']);
  });
}
