import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:archangel/data/app_state.dart';
import 'package:archangel/models/devops_model.dart';
import 'package:archangel/screens/devops_screen.dart';
import 'package:archangel/services/archangeld_connection.dart';
import 'package:archangel/services/devops_service.dart';
import 'package:archangel/ui/components/ax_button.dart';
import 'package:archangel/ui/components/status_badge.dart';
import 'package:archangel/ui/screens/services/services_logic.dart';
import 'package:archangel/ui/screens/services/services_widgets.dart';
import 'package:archangel/ui/theme.dart';

class _FakeConn extends ArchangeldConnection {
  _FakeConn({this.paired = true});
  final bool paired;
  @override
  bool get isPaired => paired;
}

class _FakeDevops extends DevopsService {
  final calls = <String>[];
  String? testProxyResult;
  String? deploymentContent = '#!/bin/sh\necho "installed"';
  bool deleteOk = true;

  List<DevRowModel> customServices = [
    const DevRowModel(name: 'caddy', meta: 'Serves web addresses with HTTPS', status: 'Running', ok: true, actions: ['Restart', 'Stop']),
    const DevRowModel(name: 'postgresql', meta: 'Database', status: 'Failed', ok: false, actions: ['Start']),
    const DevRowModel(name: 'cups', meta: 'Printing', status: 'Stopped', ok: false, actions: ['Start']),
  ];

  List<DevRowModel> customScheduled = [
    const DevRowModel(name: 'backup.timer', meta: 'Every night', status: 'Waiting', ok: true, actions: ['Run now']),
  ];

  List<DevRowModel> customProxy = [
    const DevRowModel(name: 'notes.example.com', meta: 'Points to notes app', status: 'HTTPS on', ok: true, actions: ['Test']),
  ];

  List<DevRowModel> customDeployments = [
    const DevRowModel(name: 'deploy.sh', meta: 'Setup script', status: 'Saved', ok: true, actions: ['View', 'Remove']),
  ];

  bool fakeLoading = false;
  bool fakeLoaded = true;
  bool fakeServicesFailed = false;
  bool fakeScheduledFailed = false;
  bool fakeProxyFailed = false;
  bool fakeDeploymentsFailed = false;

  @override
  List<DevRowModel> get services => customServices;
  @override
  List<DevRowModel> get scheduled => customScheduled;
  @override
  List<DevRowModel> get proxy => customProxy;
  @override
  List<DevRowModel> get deployments => customDeployments;

  @override
  bool get loading => fakeLoading;
  @override
  bool get hasLoaded => fakeLoaded;

  @override
  bool get servicesFailed => fakeServicesFailed;
  @override
  bool get scheduledFailed => fakeScheduledFailed;
  @override
  bool get proxyFailed => fakeProxyFailed;
  @override
  bool get deploymentsFailed => fakeDeploymentsFailed;

  @override
  void init(ArchangeldConnection backend) {}

  @override
  Future<void> fetchAll() async {
    calls.add('fetchAll');
  }

  @override
  Future<bool> triggerServiceAction(String name, String action) async {
    calls.add('$name:$action');
    return true;
  }

  @override
  Future<bool> triggerScheduled(String name) async {
    calls.add('timer:$name');
    return true;
  }

  @override
  Future<String?> testProxy(String domain) async {
    calls.add('testProxy:$domain');
    return testProxyResult;
  }

  @override
  Future<String?> getDeploymentContent(String name) async {
    calls.add('getContent:$name');
    return deploymentContent;
  }

  @override
  Future<bool> deleteDeployment(String name) async {
    calls.add('delete:$name');
    return deleteOk;
  }
}

Future<void> _pump(
  WidgetTester tester,
  _FakeDevops svc, {
  Size size = const Size(1400, 900),
  Brightness brightness = Brightness.dark,
  bool paired = true,
}) async {
  DevopsScreen.resetTab();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppState()),
        ChangeNotifierProvider<ArchangeldConnection>(create: (_) => _FakeConn(paired: paired)),
        ChangeNotifierProvider<DevopsService>.value(value: svc),
      ],
      child: MaterialApp(theme: buildTheme(brightness), home: const Scaffold(body: DevopsScreen())),
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  setUp(() {
    DevopsScreen.resetTab();
  });
  group('Status badge mapping', () {
    test('ok == true maps to ok status with server text', () {
      const row = DevRowModel(name: 's', meta: '', status: 'Running', ok: true, actions: []);
      final badge = rowStatusBadge(row);
      expect(badge.label, 'Running');
      expect(badge.status, AxStatus.ok);
    });

    test('ok == false and status has fail or error maps to danger with server text', () {
      const row1 = DevRowModel(name: 's', meta: '', status: 'Failed', ok: false, actions: []);
      final badge1 = rowStatusBadge(row1);
      expect(badge1.label, 'Failed');
      expect(badge1.status, AxStatus.error);

      const row2 = DevRowModel(name: 's', meta: '', status: 'error-code 1', ok: false, actions: []);
      final badge2 = rowStatusBadge(row2);
      expect(badge2.label, 'error-code 1');
      expect(badge2.status, AxStatus.error);
    });

    test('otherwise maps to neutral with server text', () {
      const row = DevRowModel(name: 's', meta: '', status: 'Stopped', ok: false, actions: []);
      final badge = rowStatusBadge(row);
      expect(badge.label, 'Stopped');
      expect(badge.status, AxStatus.neutral);
    });
  });

  group('Pill tabs, counts and exact intro text', () {
    testWidgets('Tabs show counts and exact intro text per tab', (tester) async {
      final svc = _FakeDevops();
      await _pump(tester, svc);

      // Pill tabs with counts
      expect(find.text('Background'), findsOneWidget);
      expect(find.text('3'), findsOneWidget); // 3 background services
      expect(find.text('Scheduled'), findsOneWidget);
      expect(find.text('Web addresses'), findsOneWidget);
      expect(find.text('Deployments'), findsOneWidget);

      // Background intro
      expect(find.text('Programs that run all the time to keep things working, like your web server or database.'), findsOneWidget);

      // Switch to Scheduled tab
      await tester.tap(find.text('Scheduled'));
      await tester.pumpAndSettle();

      expect(find.text('Jobs that run by themselves at set times, like nightly backups.'), findsOneWidget);

      // Switch to Web addresses tab
      await tester.tap(find.text('Web addresses'));
      await tester.pumpAndSettle();

      expect(find.text('The web addresses that point to your apps, and the secure (HTTPS) setup behind them.'), findsOneWidget);

      // Switch to Deployments tab
      await tester.tap(find.text('Deployments'));
      await tester.pumpAndSettle();

      expect(find.text('Saved setups that describe how an app is installed. You can look inside one or remove it.'), findsOneWidget);
    });
  });

  group('Actions & Confirmations', () {
    testWidgets('Background: Start has no confirmation', (tester) async {
      final svc = _FakeDevops();
      await _pump(tester, svc);

      expect(find.text('caddy'), findsOneWidget);
      expect(find.text('postgresql'), findsOneWidget);

      // Start postgresql (failed, so only Start is available)
      await tester.tap(find.widgetWithText(AxButton, 'Start').first);
      await tester.pumpAndSettle();

      expect(svc.calls, contains('postgresql:Start'));
      expect(find.text('postgresql started.'), findsOneWidget);
    });

    testWidgets('Background: Stop confirms with exact wording and danger button', (tester) async {
      final svc = _FakeDevops();
      await _pump(tester, svc);

      await tester.tap(find.widgetWithText(AxButton, 'Stop').first);
      await tester.pumpAndSettle();

      expect(find.text('Stop caddy?'), findsOneWidget);
      expect(find.text('Anything that needs it stops working until you start it again.'), findsOneWidget);

      // Cancel does nothing
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(svc.calls.where((c) => c.contains('Stop')), isEmpty);

      // Re-open and confirm
      await tester.tap(find.widgetWithText(AxButton, 'Stop').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Stop').last);
      await tester.pumpAndSettle();

      expect(svc.calls, contains('caddy:Stop'));
      expect(find.text('caddy stopped.'), findsOneWidget);
    });

    testWidgets('Background: Restart confirms with exact wording and primary button', (tester) async {
      final svc = _FakeDevops();
      await _pump(tester, svc);

      await tester.tap(find.widgetWithText(AxButton, 'Restart').first);
      await tester.pumpAndSettle();

      expect(find.text('Restart caddy?'), findsOneWidget);
      expect(find.text('It goes offline for a few seconds, then comes back on its own.'), findsOneWidget);

      // Cancel does nothing
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(svc.calls.where((c) => c.contains('Restart')), isEmpty);

      // Confirm Restart
      await tester.tap(find.widgetWithText(AxButton, 'Restart').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Restart'));
      await tester.pumpAndSettle();

      expect(svc.calls, contains('caddy:Restart'));
      expect(find.text('caddy restarted.'), findsOneWidget);
    });

    testWidgets('Scheduled: Run now shows Running… then snackbar', (tester) async {
      final svc = _FakeDevops();
      await _pump(tester, svc);

      await tester.tap(find.text('Scheduled'));
      await tester.pumpAndSettle();

      expect(find.text('Run now'), findsOneWidget);
      await tester.tap(find.text('Run now'));
      await tester.pumpAndSettle();

      expect(svc.calls, contains('timer:backup.timer'));
      expect(find.text('backup.timer started'), findsOneWidget);
    });

    testWidgets('Web addresses: Test shows success and failure inline and changes button to Test again', (tester) async {
      final svc = _FakeDevops();
      // First: success test
      svc.testProxyResult = null; // null or reachable = success
      await _pump(tester, svc);

      await tester.tap(find.text('Web addresses'));
      await tester.pumpAndSettle();

      expect(find.text('Test'), findsOneWidget);
      await tester.tap(find.text('Test'));
      await tester.pumpAndSettle();

      expect(find.text('Works. The address answered with a secure connection.'), findsOneWidget);
      expect(find.text('Test again'), findsOneWidget);

      // Second: failure test
      svc.testProxyResult = 'Connection refused';
      await tester.tap(find.text('Test again'));
      await tester.pumpAndSettle();

      expect(find.text("Didn't work: Connection refused"), findsOneWidget);
      expect(find.text('Test again'), findsOneWidget);
    });

    testWidgets('Deployments: View shows content read-only with Copy and Close', (tester) async {
      final svc = _FakeDevops();
      await _pump(tester, svc);

      await tester.tap(find.text('Deployments'));
      await tester.pumpAndSettle();

      expect(find.text('View'), findsOneWidget);
      await tester.tap(find.text('View'));
      await tester.pumpAndSettle();

      expect(find.text('deploy.sh'), findsWidgets);
      expect(find.text('Read only'), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('#!/bin/sh\necho "installed"'), findsOneWidget);

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Read only'), findsNothing);
    });

    testWidgets('Deployments: Remove needs the typed name to enable confirmation', (tester) async {
      final svc = _FakeDevops();
      await _pump(tester, svc);

      await tester.tap(find.text('Deployments'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();

      expect(find.text('Remove deploy.sh?'), findsOneWidget);
      expect(find.text("This deletes the saved setup from your server. It can't be undone. Type deploy.sh to confirm."), findsOneWidget);

      // Remove button is disabled initially
      final removeBtnFinder = find.widgetWithText(FilledButton, 'Remove').last;
      expect(tester.widget<FilledButton>(removeBtnFinder).onPressed, isNull);

      // Type partial or wrong name
      await tester.enterText(find.byType(TextField), 'dep');
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(removeBtnFinder).onPressed, isNull);

      // Type full exact name
      await tester.enterText(find.byType(TextField), 'deploy.sh');
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(removeBtnFinder).onPressed, isNotNull);

      await tester.tap(removeBtnFinder);
      await tester.pumpAndSettle();

      expect(svc.calls, contains('delete:deploy.sh'));
      expect(find.text('deploy.sh removed'), findsOneWidget);
    });
  });

  group('States & Per-group Errors', () {
    testWidgets('Per-group error shows only on the failed tab', (tester) async {
      final svc = _FakeDevops()..fakeScheduledFailed = true;
      await _pump(tester, svc);

      // Background tab is fine
      expect(find.text('caddy'), findsOneWidget);
      expect(find.text("Couldn't load scheduled tasks"), findsNothing);

      // Switch to Scheduled tab
      await tester.tap(find.text('Scheduled'));
      await tester.pumpAndSettle();

      expect(find.text("Couldn't load scheduled tasks"), findsOneWidget);
      expect(find.text("Your server didn't answer. Check that it's online, then try again."), findsOneWidget);

      // Retry button triggers fetchAll
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(svc.calls, contains('fetchAll'));
    });

    testWidgets('Empty state per tab shows exact wording', (tester) async {
      final svc =
          _FakeDevops()
            ..customServices = []
            ..customScheduled = []
            ..customProxy = []
            ..customDeployments = [];
      await _pump(tester, svc);

      // Background empty
      expect(find.text('No background services found.'), findsOneWidget);

      // Scheduled empty
      await tester.tap(find.text('Scheduled'));
      await tester.pumpAndSettle();
      expect(find.text('No scheduled tasks yet.'), findsOneWidget);

      // Web addresses empty
      await tester.tap(find.text('Web addresses'));
      await tester.pumpAndSettle();
      expect(find.text('No web addresses yet. Make an app public in Apps to get one.'), findsOneWidget);

      // Deployments empty
      await tester.tap(find.text('Deployments'));
      await tester.pumpAndSettle();
      expect(find.text('No saved deployments.'), findsOneWidget);
    });

    testWidgets('Loading skeleton rows when loading and not hasLoaded', (tester) async {
      final svc =
          _FakeDevops()
            ..fakeLoading = true
            ..fakeLoaded = false;
      await _pump(tester, svc);

      expect(find.byType(ServicesLoadingSkeleton), findsOneWidget);
    });

    testWidgets('Not paired state shows empty state', (tester) async {
      final svc = _FakeDevops();
      await _pump(tester, svc, paired: false);

      expect(find.text('No server connected yet'), findsOneWidget);
      expect(find.text('Connect a server to view and manage background services.'), findsOneWidget);
      expect(find.text('Open Settings'), findsOneWidget);
    });
  });

  group('Layout & Overflow checks', () {
    for (final size in [const Size(1400, 900), const Size(390, 844), const Size(340, 800)]) {
      testWidgets('Renders at ${size.width.toInt()}x${size.height.toInt()} across all tabs without overflow', (tester) async {
        final svc = _FakeDevops();
        await _pump(tester, svc, size: size);

        for (final tab in ['Background', 'Scheduled', 'Web addresses', 'Deployments']) {
          await tester.ensureVisible(find.text(tab));
          await tester.pumpAndSettle();
          await tester.tap(find.text(tab));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: '$tab at ${size.width}');
        }
      });
    }
  });
}
