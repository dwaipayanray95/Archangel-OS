import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:archangel/data/app_state.dart';
import 'package:archangel/models/system_metrics.dart';
import 'package:archangel/screens/settings_screen.dart';
import 'package:archangel/services/admin_mode_service.dart';
import 'package:archangel/services/app_version.dart';
import 'package:archangel/services/archangeld_connection.dart';
import 'package:archangel/services/devices_service.dart';
import 'package:archangel/services/monitoring_service.dart';
import 'package:archangel/services/server_registry.dart';
import 'package:archangel/services/update_check_service.dart';
import 'package:archangel/services/wireguard_controller.dart';
import 'package:archangel/ui/screens/home/home_logic.dart';
import 'package:archangel/ui/screens/settings/diagnostics_report.dart';
import 'package:archangel/ui/screens/settings/settings_view.dart';
import 'package:archangel/ui/shell/connection_state.dart';
import 'package:archangel/ui/shell/desktop_prefs.dart';
import 'package:archangel/ui/ui.dart';

import '../test_utils.dart';

const _token = 'TOKEN-9f8e7d6c5b4a39281706f5e4d3c2b1a0';
const _privateKey = 'cHJpdmF0ZS1rZXktZm9yLXRlc3RzLW9ubHktMDAwMDAwMDA=';

const _wgConfig =
    '''
[Interface]
PrivateKey = $_privateKey
Address = 10.10.0.7/32

[Peer]
PublicKey = cHVibGljLWtleS1mb3ItdGVzdHMtb25seS0wMDAwMDAwMDA=
Endpoint = 203.0.113.9:51820
AllowedIPs = 10.10.0.0/24
''';

class _Monitoring extends MonitoringService {
  @override
  SystemMetrics? get metrics => _metrics;
  @override
  bool get isConnected => true;
  @override
  DateTime? get lastPolled => DateTime.now().subtract(const Duration(seconds: 7));
  @override
  String? get error => 'ws://10.10.0.1:8443/ws/stats?token=$_token dropped';
  @override
  void start(ArchangeldConnection backend) {}
  @override
  Future<void> fetchSnapshot() async {}
}

const _gb = 1024 * 1024 * 1024;
final _metrics = SystemMetrics(
  timestamp: 1,
  uptimeSeconds: 3 * 86400 + 4 * 3600,
  host: const HostInfo(hostname: 'box', os: 'Ubuntu 24.04.1 LTS', kernel: '6.8.0-45-generic', arch: 'amd64'),
  cpu: const CPUMetrics(
    usagePercent: 10,
    cores: [
      CoreMetric(id: 0, usagePercent: 10),
      CoreMetric(id: 1, usagePercent: 10),
      CoreMetric(id: 2, usagePercent: 10),
      CoreMetric(id: 3, usagePercent: 10),
    ],
    history: [],
  ),
  memory: const MemoryMetrics(totalBytes: 8 * _gb, usedBytes: 2 * _gb, availableBytes: 6 * _gb, usagePercent: 25, history: []),
  disk: const DiskMetrics(
    readBytesPerSec: 0,
    writeBytesPerSec: 0,
    totalBytes: 80 * _gb,
    usedBytes: 20 * _gb,
    usagePercent: 25,
    mounts: [],
    history: [],
  ),
  network: const NetworkMetrics(rxBytesPerSec: 0, txBytesPerSec: 0, interfaces: [], history: []),
);

http.Response _json(Object body) => http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});

Future<void> _pump(WidgetTester tester, {Size size = const Size(1400, 900), Brightness brightness = Brightness.dark}) async {
  final registry = ServerRegistry();
  final backend = ArchangeldConnection(client: MockClient((_) async => _json({'version': '0.5.0'})));
  final wg = WireGuardController();
  await tester.runAsync(() async {
    await useTempKvStore();
    final p = await registry.add(
      ServerProfile(
        id: 'a',
        name: 'Home server',
        host: '10.10.0.1:8443',
        token: _token,
        wgConfig: _wgConfig,
        sshUser: 'deploy',
        createdAt: DateTime.utc(2025),
      ),
    );
    await backend.pair(host: p.host, token: p.token);
    await wg.pair(_wgConfig);
  });
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: AppState()),
        ChangeNotifierProvider<ServerRegistry>.value(value: registry),
        ChangeNotifierProvider<WireGuardController>.value(value: wg),
        ChangeNotifierProvider<ArchangeldConnection>.value(value: backend),
        ChangeNotifierProvider<MonitoringService>(create: (_) => _Monitoring()),
        ChangeNotifierProvider(create: (_) => DevicesService(client: MockClient((_) async => _json([])))),
        ChangeNotifierProvider(create: (_) => AdminModeService(client: MockClient((_) async => _json({'enabled': true})))),
        ChangeNotifierProvider(create: (_) => UpdateCheckService()),
        ChangeNotifierProvider<DesktopPrefs>.value(value: DesktopPrefs()),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(brightness, AxAccent.green),
        home: const Scaffold(body: SettingsScreen()),
      ),
    ),
  );
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _open(WidgetTester tester, SettingsSectionId id) async {
  final nav = find.byKey(ValueKey('settings-nav-${id.name}'));
  if (nav.evaluate().isEmpty) return;
  await tester.tap(nav);
  await _settle(tester);
}

Future<void> _back(WidgetTester tester) async {
  final back = find.text('All settings');
  if (back.evaluate().isEmpty) return;
  await tester.tap(back);
  await _settle(tester);
}

/// Every string of visible text on screen.
List<String> _visibleText(WidgetTester tester) => [
  for (final t in tester.widgetList<Text>(find.byType(Text)))
    if (t.data != null) t.data! else if (t.textSpan != null) t.textSpan!.toPlainText(),
];

const _jargon = ['mesh tunnel', 'developer options', 'kernel', 'wireguard', 'tunnel', 'archangeld', 'daemon', 'container', 'peer endpoint'];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('about overview', () {
    testWidgets('shows this server in plain words', (tester) async {
      await _pump(tester);
      expect(find.text('This server'), findsOneWidget);
      expect(find.text('Home server'), findsWidgets);
      expect(find.text('Ubuntu 24.04'), findsOneWidget);
      expect(find.text('3 days 4 hours'), findsOneWidget);
      expect(find.text('4 CPU cores · 8 GB memory · 80 GB disk'), findsOneWidget);
      expect(find.text('Secure connection'), findsOneWidget);
      expect(find.text('10.10.0.7'), findsOneWidget);
      expect(find.text('Last checked 7s ago'), findsOneWidget);
      expect(find.text('(v${AppVersion.current} build ${AppVersion.build})'), findsOneWidget);
      expect(find.text('Storage & disk'), findsOneWidget);
      expect(find.text('20 GB used of 80 GB'), findsOneWidget);
      expect(find.text('Changelog'), findsOneWidget);
      expect(find.text('License'), findsOneWidget);
      expect(find.text('GitHub'), findsOneWidget);
      expect(find.text('Updates'), findsOneWidget);

      // License dialog opens
      await tester.tap(find.text('License'));
      await _settle(tester);
      expect(find.textContaining('The Awesome License v1'), findsOneWidget);
      expect(find.text('Open-source notices'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await _settle(tester);

      // Changelog dialog opens
      await tester.tap(find.text('Changelog'));
      await _settle(tester);
      expect(find.text('View all releases on GitHub'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await _settle(tester);

      await tester.tap(find.text('Updates'));
      await _settle(tester);
      expect(find.text('Archangel OS ${AppVersion.full}'), findsOneWidget);
      expect(find.text('Check now'), findsOneWidget);
      expect(find.text("You're up to date.").evaluate().length + find.text('No check yet. Press "Check now".').evaluate().length, 1);
    });

    testWidgets('technical values stay behind Technical details, each with a copy button', (tester) async {
      await _pump(tester);
      final collapsed = _visibleText(tester).join('\n').toLowerCase();
      for (final w in _jargon) {
        expect(collapsed.contains(w), isFalse, reason: w);
      }
      expect(collapsed.contains('203.0.113.9'), isFalse);

      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String?;
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

      final toggle = find.byKey(const ValueKey('technical-details-toggle'));
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await _settle(tester);
      expect(find.text('Kernel'), findsOneWidget);
      expect(find.text('6.8.0-45-generic'), findsOneWidget);
      expect(find.text('203.0.113.9:51820'), findsOneWidget);
      final copy = find.byTooltip('Copy Kernel');
      await tester.ensureVisible(copy);
      await tester.tap(copy);
      await _settle(tester);
      expect(copied, '6.8.0-45-generic');
      // The private key is never shown, even here.
      expect(_visibleText(tester).join('\n').contains(_privateKey), isFalse);
    });

    for (final size in [const Size(340, 600), const Size(390, 844), const Size(1400, 900)]) {
      for (final brightness in Brightness.values) {
        testWidgets('Technical details open: no overflow at ${size.width.toInt()} (${brightness.name})', (tester) async {
          await _pump(tester, size: size, brightness: brightness);
          await _open(tester, SettingsSectionId.about);
          final toggle = find.byKey(const ValueKey('technical-details-toggle'));
          await tester.ensureVisible(toggle);
          await tester.tap(toggle);
          await _settle(tester);
          expect(tester.takeException(), isNull);
          await _back(tester);
        });
      }
    }
  });

  group('plain words', () {
    testWidgets('no jargon and no Title Case headings on any section', (tester) async {
      await _pump(tester);
      final titleCase = RegExp(r'^[A-Z][a-z]+( [A-Z][a-z]+)+$');
      for (final id in SettingsSectionId.values) {
        await _open(tester, id);
        final texts = _visibleText(tester);
        final joined = texts.join('\n').toLowerCase();
        for (final w in _jargon) {
          expect(joined.contains(w), isFalse, reason: '"$w" in ${id.name}');
        }
        for (final t in texts) {
          expect(titleCase.hasMatch(t.trim()), isFalse, reason: '"$t" in ${id.name}');
        }
        for (final bad in ['Danger Zone', 'Software Updates', 'Storage & Cache', 'Developer Options & Diagnostics', 'System Information']) {
          expect(texts.contains(bad), isFalse, reason: bad);
        }
      }
    });

    testWidgets('System has Free up space, Help & diagnostics and Danger zone', (tester) async {
      await _pump(tester);
      await _open(tester, SettingsSectionId.system);
      expect(find.text('Free up space'), findsOneWidget);
      expect(find.text('Help & diagnostics'), findsOneWidget);
      expect(find.text('Copy diagnostics for support'), findsOneWidget);
      expect(find.text('Report a problem'), findsOneWidget);
      expect(find.text('Danger zone'), findsOneWidget);
    });
  });

  group('diagnostics', () {
    testWidgets('copy holds versions but never the token or private key', (tester) async {
      await _pump(tester);
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String?;
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

      await _open(tester, SettingsSectionId.system);
      final btn = find.text('Copy diagnostics for support');
      await tester.ensureVisible(btn);
      await tester.tap(btn);
      await _settle(tester);

      final report = copied!;
      expect(report, contains(AppVersion.current));
      expect(report, contains('0.5.0'));
      expect(report, contains('Ubuntu 24.04'));
      expect(report, contains('Recent errors'));
      expect(report, isNot(contains(_token)));
      expect(report, isNot(contains(_privateKey)));
      expect(report, isNot(contains('TOKEN-')));
      expect(report, isNot(contains('203.0.113.9')));
      expect(report, isNot(contains('10.10.0.7')));
      expect(find.textContaining('Diagnostics copied'), findsOneWidget);
    });

    test('redactSecrets removes known values and secret-looking text', () {
      final out = redactSecrets(
        'failed ws://h/ws?token=abc123 Bearer xyz987 PrivateKey = $_privateKey and my-known-secret-value',
        secrets: ['my-known-secret-value'],
      );
      expect(out, isNot(contains('abc123')));
      expect(out, isNot(contains('xyz987')));
      expect(out, isNot(contains(_privateKey)));
      expect(out, isNot(contains('my-known-secret-value')));
    });

    test('buildDiagnosticsReport scrubs recent errors', () {
      final report = buildDiagnosticsReport(
        now: DateTime.utc(2026),
        phase: ConnectionPhase.connected,
        health: const HealthStatus(HealthLevel.healthy),
        serverVersion: '0.5.0',
        recentErrors: ['bad: $_token'],
        secrets: [_token],
      );
      expect(report, isNot(contains(_token)));
      expect(report, contains('Server program: 0.5.0'));
      expect(report, contains('Connection: Connected'));
    });

    test('plainOsName and friends', () {
      expect(plainOsName('Ubuntu 24.04.1 LTS'), 'Ubuntu 24.04');
      expect(plainOsName('Debian GNU/Linux 12 (bookworm)'), 'Debian 12');
      expect(plainOsName(''), 'Unknown');
      expect(plainAgo(const Duration(seconds: 5)), '5s ago');
    });
  });
}
