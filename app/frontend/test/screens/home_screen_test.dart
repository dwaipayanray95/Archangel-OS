import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:archangel/data/app_state.dart';
import 'package:archangel/models/container_model.dart';
import 'package:archangel/models/devops_model.dart';
import 'package:archangel/models/system_metrics.dart';
import 'package:archangel/screens/overview_screen.dart';
import 'package:archangel/services/archangeld_connection.dart';
import 'package:archangel/services/containers_service.dart';
import 'package:archangel/services/devops_service.dart';
import 'package:archangel/services/monitoring_service.dart';
import 'package:archangel/services/update_check_service.dart';
import 'package:archangel/ui/theme.dart';

import '../test_utils.dart';

class FakeMonitoring extends MonitoringService {
  FakeMonitoring({this.fakeMetrics, this.fakeStatus = MonitoringStatus.connected, this.rebootResult});
  SystemMetrics? fakeMetrics;
  MonitoringStatus fakeStatus;
  ProcessActionResult? rebootResult;
  int rebootCalls = 0;

  @override
  SystemMetrics? get metrics => fakeMetrics;
  @override
  MonitoringStatus get status => fakeStatus;
  @override
  bool get isConnected => fakeStatus == MonitoringStatus.connected;
  @override
  DateTime? get lastPolled => null;
  @override
  void start(ArchangeldConnection backend) {}
  @override
  Future<void> fetchSnapshot() async {}
  @override
  Future<ProcessActionResult> rebootHost() async {
    rebootCalls++;
    return rebootResult ?? const ProcessActionResult(success: true, message: 'ok');
  }
}

class FakeBackend extends ArchangeldConnection {
  FakeBackend({this.paired = true, this.version});
  final bool paired;
  final String? version;
  @override
  bool get isPaired => paired;
  @override
  String? get host => paired ? '10.0.0.1:8443' : null;
  @override
  String? get backendVersion => version;
}

class FakeContainers extends ContainersService {
  FakeContainers(this.items);
  final List<DockerContainerItem> items;
  @override
  DockerOverviewModel? get overview => DockerOverviewModel(
        dockerAvailable: true,
        engineVersion: '27',
        runningCount: items.where((c) => c.running).length,
        stoppedCount: items.where((c) => !c.running).length,
        totalImagesSize: '0 B',
        containers: items,
        stacks: const [],
        stackMeta: const {},
      );
  @override
  void init(ArchangeldConnection backend) {}
}

class FakeDevops extends DevopsService {
  FakeDevops(this.rows);
  final List<DevRowModel> rows;
  @override
  List<DevRowModel> get services => rows;
  @override
  void init(ArchangeldConnection backend) {}
}

class FakeUpdates extends UpdateCheckService {
  FakeUpdates(this.backendLatest);
  final String? backendLatest;
  @override
  String? get latestBackend => backendLatest;
}

DockerContainerItem container(String name, {required bool running}) => DockerContainerItem(
      id: name,
      name: name,
      image: 'img',
      stack: 'standalone',
      state: running ? 'running' : 'exited',
      status: '',
      uptime: '',
      cpu: 0,
      memMb: 0,
      memLabel: '',
      ports: '',
      cid: name,
      running: running,
    );

SystemMetrics metrics({double cpu = 12, double memPct = 50, List<MountMetric> mounts = const []}) {
  const gb = 1024 * 1024 * 1024;
  return SystemMetrics(
    timestamp: 1,
    uptimeSeconds: 90061,
    host: const HostInfo(hostname: 'box'),
    cpu: CPUMetrics(usagePercent: cpu, cores: const [CoreMetric(id: 0, usagePercent: 10)], history: const [10, 20, 30]),
    memory: MemoryMetrics(
        totalBytes: 8 * gb, usedBytes: (4.1 * gb).round(), availableBytes: 4 * gb, usagePercent: memPct, history: const [40, 50]),
    disk: DiskMetrics(
      readBytesPerSec: 0,
      writeBytesPerSec: 0,
      totalBytes: 100 * gb,
      usedBytes: 30 * gb,
      usagePercent: 30,
      mounts: mounts,
      history: const [],
    ),
    network: const NetworkMetrics(rxBytesPerSec: 0, txBytesPerSec: 0, interfaces: [], history: []),
  );
}

Future<(AppState, FakeMonitoring)> pumpHome(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  Brightness brightness = Brightness.dark,
  SystemMetrics? data,
  MonitoringStatus status = MonitoringStatus.connected,
  bool paired = true,
  List<DockerContainerItem> containers = const [],
  List<DevRowModel> services = const [],
  String? backendVersion,
  String? latestBackend,
  ProcessActionResult? rebootResult,
}) async {
  ignoreFontDownloadErrors();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  final app = AppState();
  final mon = FakeMonitoring(fakeMetrics: data, fakeStatus: status, rebootResult: rebootResult);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<AppState>.value(value: app),
      ChangeNotifierProvider<MonitoringService>.value(value: mon),
      ChangeNotifierProvider<ArchangeldConnection>.value(value: FakeBackend(paired: paired, version: backendVersion)),
      ChangeNotifierProvider<ContainersService>.value(value: FakeContainers(containers)),
      ChangeNotifierProvider<DevopsService>.value(value: FakeDevops(services)),
      ChangeNotifierProvider<UpdateCheckService>.value(value: FakeUpdates(latestBackend)),
    ],
    child: MaterialApp(
      theme: buildTheme(brightness),
      home: const Scaffold(body: OverviewScreen()),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 50));
  return (app, mon);
}

void main() {
  group('health sentence', () {
    test('healthy', () {
      final h = evaluateHealth(connected: true, metrics: metrics());
      expect(h.headline, 'All good');
      expect(h.detail, 'Your server is running smoothly.');
    });
    test('offline', () {
      expect(evaluateHealth(connected: false, metrics: null).headline, "Can't reach your server");
    });
    test('checking', () {
      expect(evaluateHealth(connected: true, metrics: null).level, HealthLevel.checking);
    });
    test('names the full disk', () {
      final h = evaluateHealth(
        connected: true,
        metrics: metrics(mounts: [const MountMetric(mountPoint: '/', device: 'd', totalBytes: 100, usedBytes: 94)]),
      );
      expect(h.headline, 'Disk / is 94% full');
    });
    test('combines problems', () {
      final h = evaluateHealth(connected: true, metrics: metrics(cpu: 95, memPct: 92));
      expect(h.headline, 'CPU is 95% busy · Memory is 92% used');
    });
  });

  group('needs attention (pure)', () {
    test('collects stopped apps, failed services, full disks and an update', () {
      final items = buildAttentionItems(
        containers: [container('web', running: false), container('db', running: true)],
        services: const [
          DevRowModel(name: 'nginx', meta: '', status: 'failed', ok: false, actions: []),
          DevRowModel(name: 'ssh', meta: '', status: 'active', ok: true, actions: []),
        ],
        metrics: metrics(mounts: [const MountMetric(mountPoint: '/data', device: 'd', totalBytes: 100, usedBytes: 95)]),
        backendVersion: '0.4.0',
        latestBackend: '0.5.0',
      );
      expect(items.map((i) => i.title), [
        'web is stopped',
        'nginx has a problem',
        'Disk /data is 95% full',
        'Archangel server update available',
      ]);
      expect(items.map((i) => i.target), [AxSection.apps, AxSection.services, AxSection.activity, AxSection.settings]);
    });

    test('nothing when all is well and versions match', () {
      expect(
        buildAttentionItems(
          containers: [container('db', running: true)],
          metrics: metrics(),
          backendVersion: '0.5.0',
          latestBackend: '0.5.0',
        ),
        isEmpty,
      );
    });
  });

  group('Home screen', () {
    testWidgets('shows sentence, plain cards and tap-to-navigate attention rows', (tester) async {
      final (app, _) = await pumpHome(
        tester,
        data: metrics(),
        containers: [container('web-app', running: false)],
        services: const [DevRowModel(name: 'nginx', meta: '', status: 'failed', ok: false, actions: [])],
        backendVersion: '0.4.0',
        latestBackend: '0.5.0',
      );
      expect(find.text('All good'), findsOneWidget);
      expect(find.text('4.1 of 8 GB'), findsOneWidget);
      expect(find.text('Uptime'), findsOneWidget);
      expect(find.text('Needs attention'), findsOneWidget);
      expect(find.text('web-app is stopped'), findsOneWidget);
      expect(find.text('nginx has a problem'), findsOneWidget);
      expect(find.text('Archangel server update available'), findsOneWidget);

      await tester.ensureVisible(find.text('web-app is stopped'));
      await tester.tap(find.text('web-app is stopped'));
      await tester.pump();
      expect(app.section, AxSection.apps);
      await tester.ensureVisible(find.text('nginx has a problem'));
      await tester.tap(find.text('nginx has a problem'));
      await tester.pump();
      expect(app.section, AxSection.services);
    });

    testWidgets('quick actions navigate', (tester) async {
      final (app, _) = await pumpHome(tester, data: metrics());
      await tester.ensureVisible(find.text('Run an app'));
      await tester.tap(find.text('Run an app'));
      await tester.pump();
      expect(app.section, AxSection.apps);
      await tester.tap(find.text('Browse files'));
      await tester.pump();
      expect(app.section, AxSection.files);
      await tester.tap(find.text('Open terminal'));
      await tester.pump();
      expect(app.section, AxSection.terminal);
    });

    testWidgets('reboot asks first, explains, and only then reboots', (tester) async {
      final (_, mon) = await pumpHome(tester, data: metrics());
      await tester.ensureVisible(find.text('Reboot server'));
      await tester.tap(find.text('Reboot server'));
      await tester.pumpAndSettle();
      expect(find.textContaining("Everything stops for about a minute; you'll reconnect automatically"), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(mon.rebootCalls, 0);

      await tester.tap(find.text('Reboot server'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Reboot server').last);
      await tester.pumpAndSettle();
      expect(mon.rebootCalls, 1);
    });

    testWidgets('shows the server message when Admin mode is off (403)', (tester) async {
      await pumpHome(
        tester,
        data: metrics(),
        rebootResult: const ProcessActionResult(success: false, message: 'Admin mode is off. Turn it on in Settings to do this.'),
      );
      await tester.ensureVisible(find.text('Reboot server'));
      await tester.tap(find.text('Reboot server'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Reboot server').last);
      await tester.pumpAndSettle();
      expect(find.text('Admin mode is off. Turn it on in Settings to do this.'), findsOneWidget);
    });

    testWidgets('not paired, loading and offline states', (tester) async {
      await pumpHome(tester, paired: false);
      expect(find.text('No server connected yet'), findsOneWidget);

      await pumpHome(tester, data: null, status: MonitoringStatus.connecting);
      expect(find.text('Connecting to your server...'), findsOneWidget);

      await pumpHome(tester, data: null, status: MonitoringStatus.error);
      expect(find.text("Can't reach your server"), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    for (final size in const [Size(390, 844), Size(1400, 900)]) {
      for (final b in Brightness.values) {
        testWidgets('no overflow at ${size.width.toInt()}x${size.height.toInt()} (${b.name})', (tester) async {
          await pumpHome(
            tester,
            size: size,
            brightness: b,
            data: metrics(cpu: 95, mounts: [const MountMetric(mountPoint: '/', device: 'd', totalBytes: 100, usedBytes: 95)]),
            containers: [container('a-rather-long-application-name-that-keeps-going', running: false)],
            services: const [DevRowModel(name: 'some-long-service.service', meta: '', status: 'failed', ok: false, actions: [])],
            backendVersion: '0.4.0',
            latestBackend: '0.5.0',
          );
          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}
