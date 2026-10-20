import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:archangel/data/app_state.dart';
import 'package:archangel/models/system_metrics.dart';
import 'package:archangel/screens/monitoring_screen.dart';
import 'package:archangel/services/archangeld_connection.dart';
import 'package:archangel/services/monitoring_service.dart';
import 'package:archangel/ui/screens/activity/activity_logic.dart';
import 'package:archangel/ui/theme.dart';

class FakeMonitoring extends MonitoringService {
  FakeMonitoring({this.fakeMetrics, this.procs = const []});
  SystemMetrics? fakeMetrics;
  List<LiveProcessInfo> procs;
  final List<(int, bool)> kills = [];
  final List<(int, int)> renices = [];
  ProcessActionResult killResult = const ProcessActionResult(success: true, message: 'ok');

  @override
  SystemMetrics? get metrics => fakeMetrics;
  @override
  List<LiveProcessInfo> get processes => procs;
  @override
  int get totalProcesses => procs.length;
  @override
  MonitoringStatus get status => MonitoringStatus.connected;
  @override
  bool get isConnected => true;
  @override
  DateTime? get lastPolled => DateTime.now();
  @override
  void start(ArchangeldConnection backend) {}
  @override
  Future<void> fetchSnapshot() async {}
  @override
  Future<ProcessActionResult> killProcess(int pid, {bool force = false}) async {
    kills.add((pid, force));
    return killResult;
  }

  @override
  Future<ProcessActionResult> reniceProcess(int pid, int priority) async {
    renices.add((pid, priority));
    return const ProcessActionResult(success: true, message: 'ok');
  }
}

class FakeBackend extends ArchangeldConnection {
  @override
  bool get isPaired => true;
}

const _gb = 1024 * 1024 * 1024;

SystemMetrics sampleMetrics() => SystemMetrics(
  timestamp: 1,
  uptimeSeconds: 100,
  cpu: CPUMetrics(
    usagePercent: 33,
    cores: [for (var i = 0; i < 8; i++) CoreMetric(id: i, usagePercent: 10.0 * i, mhz: 3200)],
    history: const [],
  ),
  memory: const MemoryMetrics(totalBytes: 8 * _gb, usedBytes: 4 * _gb, availableBytes: 4 * _gb, usagePercent: 50, history: []),
  disk: const DiskMetrics(
    readBytesPerSec: 2048,
    writeBytesPerSec: 4096,
    totalBytes: 100 * _gb,
    usedBytes: 40 * _gb,
    usagePercent: 40,
    mounts: [MountMetric(mountPoint: '/', device: 'd', totalBytes: 100 * _gb, usedBytes: 40 * _gb)],
    history: [],
  ),
  network: const NetworkMetrics(
    rxBytesPerSec: 150000,
    txBytesPerSec: 20000,
    interfaces: [NetInterfaceMetric(name: 'eth0', rxBytesPerSec: 150000, txBytesPerSec: 20000)],
    history: [],
  ),
);

const procs = [
  LiveProcessInfo(pid: 101, name: 'postgres', user: 'postgres', cpu: 12.5, mem: 3, rssBytes: 300 * 1024 * 1024, state: 'S'),
  LiveProcessInfo(pid: 202, name: 'nginx', user: 'www-data', cpu: 1.2, mem: 1, rssBytes: 40 * 1024 * 1024, state: 'S'),
];

Future<FakeMonitoring> pumpActivity(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  Brightness brightness = Brightness.dark,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  final mon = FakeMonitoring(fakeMetrics: sampleMetrics(), procs: procs);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: AppState()),
        ChangeNotifierProvider<MonitoringService>.value(value: mon),
        ChangeNotifierProvider<ArchangeldConnection>.value(value: FakeBackend()),
      ],
      child: MaterialApp(theme: buildTheme(brightness), home: const Scaffold(body: MonitoringScreen())),
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
  return mon;
}

Future<void> openTab(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label).first);
  await tester.pump();
  await tester.tap(find.text(label).first);
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  group('priority mapping', () {
    test('slider ends map to nice 19 and -20, middle to 0', () {
      expect(niceFromSlider(0), 19);
      expect(niceFromSlider(kPrioritySteps), -20);
      expect(niceFromSlider(19), 0);
    });
    test('is clamped and invertible', () {
      expect(niceFromSlider(-5), 19);
      expect(niceFromSlider(99), -20);
      for (var n = kNiceHighest; n <= kNiceLowest; n++) {
        expect(niceFromSlider(sliderFromNice(n)), n);
      }
      expect(sliderFromNice(100), 0);
    });
    test('plain labels', () {
      expect(priorityLabel(0), 'Normal');
      expect(priorityLabel(19), 'Much lower than normal');
      expect(priorityLabel(-20), 'Much higher than normal');
    });
  });

  group('chart helpers', () {
    test('niceCeil picks 1/2/5 steps and never shrinks below the value', () {
      expect(niceCeil(0), 2000);
      expect(niceCeil(1500, minimum: 1), 2000);
      expect(niceCeil(150000), 200000);
      expect(niceCeil(4000000), 5000000);
      expect(niceCeil(6000000), 10000000);
    });
    test('formatRate', () {
      expect(formatRate(0), '0 B/s');
      expect(formatRate(2048), '2.0 KB/s');
      expect(formatRate(3 * 1024 * 1024), '3.0 MB/s');
    });
    test('live samples are capped', () {
      final s = LiveSamples(capacity: 3);
      for (var i = 0; i < 5; i++) {
        s.add(sampleMetrics());
      }
      expect(s.length, 3);
    });
  });

  group('Activity screen', () {
    testWidgets('phone: tabs scroll, chart is labelled live', (tester) async {
      await pumpActivity(tester);
      for (final t in ['CPU', 'Memory', 'Disk', 'Network', 'Processes']) {
        expect(find.text(t), findsWidgets);
      }
      expect(find.text('Live (since you opened this screen)'), findsOneWidget);
      expect(tester.takeException(), isNull);
      for (final t in ['Memory', 'Disk', 'Network']) {
        await openTab(tester, t);
        expect(find.text('Live (since you opened this screen)'), findsOneWidget);
      }
    });

    testWidgets('phone: processes are list rows (no table) and open a details sheet', (tester) async {
      await pumpActivity(tester);
      await openTab(tester, 'Processes');
      expect(find.text('postgres'), findsOneWidget);
      expect(find.text('postgres · ID 101'), findsOneWidget);
      expect(find.text('CPU 12.5%'), findsOneWidget);
      expect(find.text('Status'), findsNothing); // table header only on desktop
      await tester.tap(find.text('postgres'));
      await tester.pumpAndSettle();
      expect(find.text('Stop process'), findsOneWidget);
      expect(find.text('Force stop'), findsOneWidget);
      expect(find.text('Change priority'), findsOneWidget);
      expect(find.textContaining('renice'), findsNothing);
    });

    testWidgets('desktop: processes use a table', (tester) async {
      await pumpActivity(tester, size: const Size(1400, 900));
      await openTab(tester, 'Processes');
      expect(find.text('Status'), findsOneWidget);
      expect(find.text('postgres'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('stop process asks first with a plain explanation, then sends SIGTERM', (tester) async {
      final mon = await pumpActivity(tester);
      await openTab(tester, 'Processes');
      await tester.tap(find.text('nginx'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Stop process'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Programs you stop may lose unsaved work. System processes can make the server unstable.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(mon.kills, isEmpty);

      await tester.tap(find.text('nginx'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Stop process'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Stop process'));
      await tester.pumpAndSettle();
      expect(mon.kills, [(202, false)]);
    });

    testWidgets('force stop sends SIGKILL after confirmation', (tester) async {
      final mon = await pumpActivity(tester);
      await openTab(tester, 'Processes');
      await tester.tap(find.text('nginx'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Force stop'));
      await tester.pumpAndSettle();
      expect(find.textContaining('immediately'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Force stop'));
      await tester.pumpAndSettle();
      expect(mon.kills, [(202, true)]);
    });

    testWidgets('change priority applies the mapped nice value', (tester) async {
      final mon = await pumpActivity(tester);
      await openTab(tester, 'Processes');
      await tester.tap(find.text('nginx'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Change priority'));
      await tester.pumpAndSettle();
      expect(find.text('Lower ↔ Higher priority'), findsOneWidget);
      expect(find.text('Normal'), findsOneWidget);
      // Drag the slider fully to the "Lower" end.
      await tester.drag(find.byType(Slider), const Offset(-2000, 0));
      await tester.pumpAndSettle();
      expect(find.text('Much lower than normal'), findsWidgets);
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(mon.renices, [(202, 19)]);
    });

    for (final size in const [Size(390, 844), Size(1400, 900)]) {
      for (final b in Brightness.values) {
        testWidgets('no overflow on any tab at ${size.width.toInt()}x${size.height.toInt()} (${b.name})', (tester) async {
          await pumpActivity(tester, size: size, brightness: b);
          for (final t in ['CPU', 'Memory', 'Disk', 'Network', 'Processes']) {
            await openTab(tester, t);
            expect(tester.takeException(), isNull, reason: t);
          }
        });
      }
    }
  });
}
