import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:archangel/data/app_state.dart';
import 'package:archangel/models/system_metrics.dart';
import 'package:archangel/screens/monitoring_screen.dart';
import 'package:archangel/services/admin_mode_service.dart';
import 'package:archangel/services/archangeld_connection.dart';
import 'package:archangel/services/monitoring_service.dart';
import 'package:archangel/ui/components/status_badge.dart';
import 'package:archangel/ui/screens/activity/activity_logic.dart';
import 'package:archangel/ui/theme.dart';

class FakeMonitoring extends MonitoringService {
  FakeMonitoring({this.fakeMetrics, this.procs = const [], this.fakeStatus = MonitoringStatus.connected});

  SystemMetrics? fakeMetrics;
  List<LiveProcessInfo> procs;
  MonitoringStatus fakeStatus;

  final List<(int, bool)> kills = [];
  final List<(int, int)> renices = [];
  int retryCalls = 0;
  ProcessActionResult killResult = const ProcessActionResult(success: true, message: 'ok');

  @override
  SystemMetrics? get metrics => fakeMetrics;
  @override
  List<LiveProcessInfo> get processes => procs;
  @override
  int get totalProcesses => procs.length;
  @override
  MonitoringStatus get status => fakeStatus;
  @override
  bool get isConnected => fakeStatus == MonitoringStatus.connected;
  @override
  DateTime? get lastPolled => DateTime.now();

  @override
  void start(ArchangeldConnection backend) {
    retryCalls++;
  }

  @override
  Future<void> fetchSnapshot() async {
    retryCalls++;
  }

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
  FakeBackend({this.paired = true});
  final bool paired;
  @override
  bool get isPaired => paired;
}

class FakeAdminMode extends AdminModeService {
  FakeAdminMode({this.isAdmin = false});
  final bool isAdmin;
  @override
  bool? get enabled => isAdmin;
}

const _gb = 1024 * 1024 * 1024;

SystemMetrics sampleMetrics({
  double cpu = 33,
  double memoryPercent = 50,
  double diskPercent = 40,
  double netRx = 1000000,
  double netTx = 400000,
  List<double>? cpuHist,
  List<double>? memHist,
  List<double>? diskHist,
  List<double>? netHist,
}) => SystemMetrics(
  timestamp: 1,
  uptimeSeconds: 1047780, // 12 days, 3 hours
  host: const HostInfo(hostname: 'halo-vps', os: 'Ubuntu 24.04', arch: 'x86_64'),
  cpu: CPUMetrics(
    usagePercent: cpu,
    cores: [for (var i = 0; i < 4; i++) CoreMetric(id: i, usagePercent: 10.0 * i, mhz: 3200)],
    history: cpuHist ?? [12, 14, 15, 12, 13],
  ),
  memory: MemoryMetrics(
    totalBytes: 4 * _gb,
    usedBytes: ((4 * _gb) * (memoryPercent / 100)).round(),
    availableBytes: 2 * _gb,
    usagePercent: memoryPercent,
    history: memHist ?? [50, 52, 53, 51, 52],
  ),
  disk: DiskMetrics(
    readBytesPerSec: 1200000,
    writeBytesPerSec: 200000,
    totalBytes: 100 * _gb,
    usedBytes: ((100 * _gb) * (diskPercent / 100)).round(),
    usagePercent: diskPercent,
    mounts: [MountMetric(mountPoint: '/', device: 'd', totalBytes: 100 * _gb, usedBytes: 40 * _gb)],
    history: diskHist ?? [20, 25, 30, 22, 28],
  ),
  network: NetworkMetrics(
    rxBytesPerSec: netRx,
    txBytesPerSec: netTx,
    interfaces: [NetInterfaceMetric(name: 'eth0', rxBytesPerSec: netRx, txBytesPerSec: netTx)],
    history: netHist ?? [1000000, 1200000, 1400000],
  ),
);

const sampleProcs = [
  LiveProcessInfo(pid: 101, name: 'dockerd', user: 'root', cpu: 4.2, mem: 5.3, rssBytes: 212 * 1024 * 1024, state: 'S'),
  LiveProcessInfo(pid: 202, name: 'php-fpm', user: 'www-data', cpu: 3.1, mem: 9.5, rssBytes: 380 * 1024 * 1024, state: 'S'),
  LiveProcessInfo(pid: 303, name: 'jellyfin', user: 'jellyfin', cpu: 1.8, mem: 13.5, rssBytes: 540 * 1024 * 1024, state: 'S'),
  LiveProcessInfo(pid: 404, name: 'archangeld', user: 'archangel', cpu: 0.6, mem: 1.0, rssBytes: 38 * 1024 * 1024, state: 'S'),
  LiveProcessInfo(pid: 505, name: 'postgres', user: 'postgres', cpu: 0.4, mem: 4.1, rssBytes: 164 * 1024 * 1024, state: 'S'),
  LiveProcessInfo(pid: 606, name: 'caddy', user: 'caddy', cpu: 0.2, mem: 1.0, rssBytes: 41 * 1024 * 1024, state: 'S'),
];

Future<FakeMonitoring> pumpActivity(
  WidgetTester tester, {
  Size size = const Size(1400, 900),
  Brightness brightness = Brightness.dark,
  FakeMonitoring? customMon,
  bool paired = true,
  bool isAdmin = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);

  final mon = customMon ?? FakeMonitoring(fakeMetrics: sampleMetrics(), procs: sampleProcs);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: AppState()),
        ChangeNotifierProvider<MonitoringService>.value(value: mon),
        ChangeNotifierProvider<ArchangeldConnection>.value(value: FakeBackend(paired: paired)),
        ChangeNotifierProvider<AdminModeService>.value(value: FakeAdminMode(isAdmin: isAdmin)),
      ],
      child: MaterialApp(theme: buildTheme(brightness), home: const Scaffold(body: MonitoringScreen())),
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
  return mon;
}

void main() {
  group('Status sentence for calm / busy / struggling at threshold edges', () {
    test('calm when CPU < 60 and memory < 75', () {
      final s = calculateServerStatus(59.9, 74.9);
      expect(s.state, ServerActivityState.calm);
      expect(s.title, 'Your server is calm');
      expect(s.line, 'Everything is running comfortably. Nothing needs your attention.');
      expect(s.status, AxStatus.ok);
    });

    test('busy when CPU reaches 60 or memory reaches 75', () {
      final s1 = calculateServerStatus(60.0, 50.0);
      expect(s1.state, ServerActivityState.busy);
      expect(s1.title, 'Your server is busy');
      expect(s1.line, "It's working hard right now. That's fine for a while. If it stays busy, check the programs below.");
      expect(s1.status, AxStatus.warning);

      final s2 = calculateServerStatus(40.0, 75.0);
      expect(s2.state, ServerActivityState.busy);
      expect(s2.title, 'Your server is busy');
    });

    test('struggling when CPU >= 90 or memory >= 95', () {
      final s1 = calculateServerStatus(90.0, 10.0);
      expect(s1.state, ServerActivityState.struggling);
      expect(s1.title, 'Your server is struggling');
      expect(s1.line, "It's close to its limits, so things may feel slow. The busiest programs are below.");
      expect(s1.status, AxStatus.error);

      final s2 = calculateServerStatus(20.0, 95.0);
      expect(s2.state, ServerActivityState.struggling);
      expect(s2.title, 'Your server is struggling');
    });
  });

  group('Meaning labels at thresholds with icon and text', () {
    test('CPU meanings', () {
      final m1 = cpuMeaning(49.9);
      expect(m1.label, 'Plenty free');
      expect(m1.status, AxStatus.ok);

      final m2 = cpuMeaning(50.0);
      expect(m2.label, 'Working hard');
      expect(m2.status, AxStatus.warning);

      final m3 = cpuMeaning(84.9);
      expect(m3.label, 'Working hard');

      final m4 = cpuMeaning(85.0);
      expect(m4.label, 'Maxed out');
      expect(m4.status, AxStatus.error);
    });

    test('Memory meanings', () {
      final m1 = memoryMeaning(74.9);
      expect(m1.label, 'Comfortable');
      expect(m1.status, AxStatus.ok);

      final m2 = memoryMeaning(75.0);
      expect(m2.label, 'Running low');
      expect(m2.status, AxStatus.warning);

      final m3 = memoryMeaning(94.9);
      expect(m3.label, 'Running low');

      final m4 = memoryMeaning(95.0);
      expect(m4.label, 'Almost full');
      expect(m4.status, AxStatus.error);
    });

    test('Disk meanings', () {
      final m1 = diskMeaning(69.9);
      expect(m1.label, 'Plenty of space');
      expect(m1.status, AxStatus.ok);

      final m2 = diskMeaning(70.0);
      expect(m2.label, 'Getting full');
      expect(m2.status, AxStatus.warning);

      final m3 = diskMeaning(89.9);
      expect(m3.label, 'Getting full');

      final m4 = diskMeaning(90.0);
      expect(m4.label, 'Almost full');
      expect(m4.status, AxStatus.error);
    });

    test('Network meanings', () {
      final m1 = networkMeaning(1.9 * 1024 * 1024);
      expect(m1.label, 'Quiet');
      expect(m1.status, AxStatus.ok);

      final m2 = networkMeaning(2.1 * 1024 * 1024);
      expect(m2.label, 'Normal');
      expect(m2.status, AxStatus.ok);
    });
  });

  group('Layout & Responsive Display', () {
    testWidgets('Wide at 1400x900 shows 4 charts, server info and table without overflow', (tester) async {
      await pumpActivity(tester, size: const Size(1400, 900));

      expect(find.text('Activity'), findsOneWidget);
      expect(find.text('Live from halo-vps. Updates every 2 seconds.'), findsOneWidget);
      expect(find.text('Live'), findsOneWidget); // wide live badge

      expect(find.text('Your server is calm'), findsOneWidget);

      // Four measure cards
      expect(find.text('CPU'), findsWidgets);
      expect(find.text('Memory'), findsWidgets);
      expect(find.text('Disk'), findsWidgets);
      expect(find.text('Network'), findsWidgets);

      // Server info
      expect(find.text('halo-vps'), findsWidgets);
      expect(find.text('Ubuntu 24.04 · x86_64'), findsOneWidget);
      expect(find.text('12 days, 3 hours'), findsOneWidget);

      // Table header & rows
      expect(find.text('Program'), findsOneWidget);
      expect(find.text('Run by'), findsOneWidget);
      expect(find.text('dockerd'), findsOneWidget);
      expect(find.text('root'), findsOneWidget);
      expect(find.text('Showing the 6 busiest of 6 programs.'), findsOneWidget);

      expect(tester.takeException(), isNull);
    });

    testWidgets('Compact at 390 and 340 shows rows, no overflow, and expands chart on tap', (tester) async {
      for (final width in [390.0, 340.0]) {
        await pumpActivity(tester, size: Size(width, 844));

        expect(find.text('Activity'), findsOneWidget);
        expect(find.text('Live from halo-vps'), findsOneWidget);
        expect(find.text('Live'), findsNothing); // wide-only live badge

        expect(find.text('Your server is calm'), findsOneWidget);

        // Compact list rows
        expect(find.text('CPU'), findsWidgets);
        expect(find.text('Plenty free'), findsOneWidget);
        expect(find.text('dockerd'), findsOneWidget);
        expect(find.textContaining('CPU ·'), findsWidgets);

        expect(tester.takeException(), isNull);

        // Tap a measure row to expand its chart
        expect(find.bySemanticsLabel('CPU over the last minute'), findsNothing);
        await tester.tap(find.text('CPU').first);
        await tester.pumpAndSettle();

        expect(find.bySemanticsLabel('CPU over the last minute'), findsOneWidget);

        // Tap another row (Memory) - CPU collapses and Memory expands
        await tester.tap(find.text('Memory').first);
        await tester.pumpAndSettle();

        expect(find.bySemanticsLabel('CPU over the last minute'), findsNothing);
        expect(find.bySemanticsLabel('Memory over the last minute'), findsOneWidget);

        // Tap Memory again to collapse it
        await tester.tap(find.text('Memory').first);
        await tester.pumpAndSettle();
        expect(find.bySemanticsLabel('Memory over the last minute'), findsNothing);

        expect(tester.takeException(), isNull);
      }
    });
  });

  group('Busiest programs search, sort and count', () {
    testWidgets('Search filters by name and user, showing no match if empty', (tester) async {
      await pumpActivity(tester);

      expect(find.text('dockerd'), findsOneWidget);
      expect(find.text('postgres'), findsWidgets);

      await tester.enterText(find.byType(TextField), 'post');
      await tester.pumpAndSettle();

      expect(find.text('postgres'), findsWidgets);
      expect(find.text('dockerd'), findsNothing);
      expect(find.text('Showing the 1 busiest of 6 programs.'), findsOneWidget);

      // Search with no match
      await tester.enterText(find.byType(TextField), 'unknown-xyz');
      await tester.pumpAndSettle();

      expect(find.text('Nothing matches "unknown-xyz"'), findsOneWidget);
      expect(find.text('Showing the 0 busiest of 6 programs.'), findsOneWidget);
    });

    testWidgets('Sort toggles CPU and Memory descending', (tester) async {
      await pumpActivity(tester);

      // Default sort is CPU
      expect(find.text('CPU ↓'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('sort-memory')));
      await tester.pumpAndSettle();

      expect(find.text('Memory ↓'), findsOneWidget);
    });
  });

  group('Confirmations: Stop, Force Stop, Change Priority', () {
    testWidgets('Stop dialog exact wording, Cancel does nothing, confirm calls killProcess', (tester) async {
      final mon = await pumpActivity(tester);

      await tester.tap(find.byTooltip('More for dockerd'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Stop'));
      await tester.pumpAndSettle();

      expect(find.text('Stop dockerd?'), findsOneWidget);
      expect(
        find.text("This asks it to close. Whatever it's doing stops, and apps that rely on it may stop working until it runs again."),
        findsOneWidget,
      );

      // Cancel does nothing
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(mon.kills, isEmpty);

      // Re-open and confirm Stop
      await tester.tap(find.byTooltip('More for dockerd'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Stop'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Stop'));
      await tester.pumpAndSettle();

      expect(mon.kills, [(101, false)]);
      expect(find.text('dockerd stopped'), findsOneWidget);
    });

    testWidgets('Force stop dialog exact wording and danger action', (tester) async {
      final mon = await pumpActivity(tester);

      await tester.tap(find.byTooltip('More for dockerd'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Force stop'));
      await tester.pumpAndSettle();

      expect(find.text('Force stop dockerd?'), findsOneWidget);
      expect(
        find.text("Use this only if Stop didn't work. It ends the program at once, so anything it hadn't saved is lost."),
        findsOneWidget,
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Force stop'));
      await tester.pumpAndSettle();

      expect(mon.kills, [(101, true)]);
      expect(find.text('dockerd stopped'), findsOneWidget);
    });

    testWidgets('Change priority dialog wording and Higher disabled when Admin mode is off', (tester) async {
      final mon = await pumpActivity(tester, isAdmin: false);

      await tester.tap(find.byTooltip('More for dockerd'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Change priority…'));
      await tester.pumpAndSettle();

      expect(find.text('Change priority'), findsOneWidget);
      expect(
        find.text('Lower priority lets other programs go first when the server is busy. Most people never need this.'),
        findsOneWidget,
      );
      expect(find.text('Higher needs Admin mode.'), findsOneWidget);

      // Higher is disabled when Admin mode is off, so tapping it does not select it
      await tester.tap(find.text('Higher'));
      await tester.pumpAndSettle();

      // Lower can be selected
      await tester.tap(find.text('Lower'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(mon.renices, [(101, 10)]);
      expect(find.text('Priority changed'), findsOneWidget);
    });

    testWidgets('Change priority allows Higher when Admin mode is on', (tester) async {
      final mon = await pumpActivity(tester, isAdmin: true);

      await tester.tap(find.byTooltip('More for dockerd'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Change priority…'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Higher'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(mon.renices, [(101, -5)]);
      expect(find.text('Priority changed'), findsOneWidget);
    });
  });

  group('States', () {
    testWidgets('Connecting state', (tester) async {
      final mon = FakeMonitoring(fakeMetrics: null, fakeStatus: MonitoringStatus.connecting);
      await pumpActivity(tester, customMon: mon);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Reaching your server…'), findsOneWidget);
      expect(find.text('Live numbers appear in a moment.'), findsOneWidget);
    });

    testWidgets('Not answering state and Try now button', (tester) async {
      final mon = FakeMonitoring(fakeMetrics: null, fakeStatus: MonitoringStatus.error);
      await pumpActivity(tester, customMon: mon);

      expect(find.byIcon(Icons.cloud_off), findsOneWidget);
      expect(find.text("Your server isn't answering"), findsOneWidget);
      expect(find.text("It may be restarting or offline. We'll keep trying every few seconds."), findsOneWidget);

      await tester.tap(find.text('Try now'));
      await tester.pumpAndSettle();

      expect(mon.retryCalls, greaterThan(0));
    });

    testWidgets('No data yet state', (tester) async {
      final emptyHistMetrics = sampleMetrics(cpuHist: const [], memHist: const [], diskHist: const [], netHist: const []);
      final mon = FakeMonitoring(fakeMetrics: emptyHistMetrics, fakeStatus: MonitoringStatus.connected);
      await pumpActivity(tester, customMon: mon);

      expect(find.byIcon(Icons.info_outline), findsOneWidget);
      expect(find.text('Waiting for the first reading'), findsOneWidget);
      expect(find.text('Connected. Charts fill in over the next minute. Numbers show "—" until then.'), findsOneWidget);
    });

    testWidgets('Not paired state', (tester) async {
      await pumpActivity(tester, paired: false);

      expect(find.text('No server connected yet'), findsOneWidget);
      expect(find.text('Connect a server to see how busy it is.'), findsOneWidget);
      expect(find.text('Open Settings'), findsOneWidget);
    });
  });
}
