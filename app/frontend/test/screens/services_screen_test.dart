import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:archangel/data/app_state.dart';
import 'package:archangel/models/devops_model.dart';
import 'package:archangel/screens/devops_screen.dart';
import 'package:archangel/services/archangeld_connection.dart';
import 'package:archangel/services/devops_service.dart';
import 'package:archangel/ui/screens/services/script_editor_page.dart';
import 'package:archangel/ui/screens/services/services_logic.dart';
import 'package:archangel/ui/theme.dart';

import '../test_utils.dart';

class _FakeConn extends ArchangeldConnection {
  @override
  bool get isPaired => true;
}

class _FakeDevops extends DevopsService {
  final calls = <String>[];
  String? message;
  int? status;
  bool failActions = false;
  final saved = <String>[];

  @override
  List<DevRowModel> get services => const [
        DevRowModel(name: 'caddy.service', meta: 'Web server', status: 'active', ok: true, actions: []),
        DevRowModel(name: 'worker.service', meta: 'Job runner', status: 'failed', ok: false, actions: []),
      ];
  @override
  List<DevRowModel> get scheduled => const [
        DevRowModel(name: 'backup.timer', meta: 'Every night', status: 'waiting', ok: true, actions: []),
      ];
  @override
  List<DevRowModel> get proxy => const [
        DevRowModel(name: 'notes.example.com', meta: 'localhost:8080', status: 'ok', ok: true, actions: []),
      ];
  @override
  List<DevRowModel> get deployments => const [
        DevRowModel(name: 'deploy.sh', meta: 'Updated today', status: 'ready', ok: true, actions: []),
      ];
  @override
  bool get hasLoaded => true;
  @override
  String? get error => null;
  @override
  String? get lastActionMessage => message;
  @override
  int? get lastActionStatus => status;
  @override
  void init(ArchangeldConnection backend) {}
  @override
  Future<void> fetchAll() async {}

  @override
  Future<bool> triggerServiceAction(String name, String action) async {
    calls.add('$name:$action');
    return !failActions;
  }

  @override
  Future<bool> triggerScheduled(String name) async {
    calls.add('timer:$name');
    return true;
  }

  @override
  Future<String?> testProxy(String domain) async => 'Reachable (200 OK)';

  @override
  Future<Map<String, String>?> runDeployment(String name) async {
    calls.add('run:$name');
    return {'ok': 'true', 'message': 'Done', 'output': 'hello from script'};
  }

  @override
  Future<String?> getDeploymentContent(String name) async => '#!/bin/sh\necho hi\n';

  @override
  Future<Map<String, dynamic>> saveDeployment(String name, String content) async {
    saved.add(name);
    return {'success': true, 'message': 'ok'};
  }
}

Future<void> _pump(
  WidgetTester tester,
  _FakeDevops svc, {
  Size size = const Size(390, 844),
  Brightness brightness = Brightness.dark,
  Widget home = const DevopsScreen(),
}) async {
  ignoreFontDownloadErrors();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppState()),
        ChangeNotifierProvider<ArchangeldConnection>(create: (_) => _FakeConn()),
        ChangeNotifierProvider<DevopsService>.value(value: svc),
      ],
      child: MaterialApp(theme: buildTheme(brightness), home: Scaffold(body: home)),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _settle(WidgetTester tester) => tester.pump(const Duration(milliseconds: 300));

void main() {
  testWidgets('stop asks for confirmation first', (tester) async {
    final svc = _FakeDevops();
    await _pump(tester, svc);
    await tester.tap(find.text('Stop').first);
    await _settle(tester);
    expect(svc.calls, isEmpty);
    expect(find.text('Stop caddy.service?'), findsOneWidget);
    await tester.tap(find.text('Stop service'));
    await _settle(tester);
    expect(svc.calls, ['caddy.service:Stop']);
  });

  testWidgets('cancelling the stop confirmation does nothing', (tester) async {
    final svc = _FakeDevops();
    await _pump(tester, svc);
    await tester.tap(find.text('Stop').first);
    await _settle(tester);
    await tester.tap(find.text('Cancel'));
    await _settle(tester);
    expect(svc.calls, isEmpty);
  });

  testWidgets('a 403 admin-mode refusal is shown with an Open Settings action', (tester) async {
    final svc = _FakeDevops()
      ..failActions = true
      ..status = 403
      ..message = 'Admin mode is off - this action needs it';
    await _pump(tester, svc);
    await tester.tap(find.text('Start').first);
    await _settle(tester);
    expect(find.text('Admin mode is off - this action needs it'), findsOneWidget);
    expect(find.text('Open Settings'), findsOneWidget);
  });

  testWidgets('a stop-guard refusal shows its message without Open Settings', (tester) async {
    final svc = _FakeDevops()
      ..failActions = true
      ..status = 409
      ..message = 'ssh is protected: stopping it would lock you out of your server.';
    await _pump(tester, svc);
    await tester.tap(find.text('Restart').first);
    await _settle(tester);
    await tester.tap(find.text('Restart service'));
    await _settle(tester);
    expect(find.textContaining('would lock you out'), findsOneWidget);
    expect(find.text('Open Settings'), findsNothing);
  });

  testWidgets('web address test shows its result inline', (tester) async {
    final svc = _FakeDevops();
    await _pump(tester, svc);
    await tester.tap(find.text('Web addresses'));
    await _settle(tester);
    await tester.tap(find.text('Test'));
    await _settle(tester);
    expect(find.textContaining('Reachable (200 OK)'), findsOneWidget);
  });

  testWidgets('running a script confirms, then shows output with Copy', (tester) async {
    final svc = _FakeDevops();
    await _pump(tester, svc);
    await tester.tap(find.text('Scripts'));
    await _settle(tester);
    await tester.tap(find.text('Run').first);
    await _settle(tester);
    expect(find.textContaining('as the archangel user'), findsWidgets);
    expect(svc.calls, isEmpty);
    await tester.tap(find.text('Run script'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(svc.calls, ['run:deploy.sh']);
    expect(find.text('hello from script'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
  });

  testWidgets('deleting a script uses a danger confirmation', (tester) async {
    final svc = _FakeDevops();
    await _pump(tester, svc);
    await tester.tap(find.text('Scripts'));
    await _settle(tester);
    await tester.tap(find.text('Delete').first);
    await _settle(tester);
    expect(find.text('Delete deploy.sh?'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  group('script name validation', () {
    test('accepts safe names', () {
      expect(validateScriptName('deploy.sh'), isNull);
      expect(validateScriptName('my-app_v2.sh'), isNull);
    });
    test('rejects bad names', () {
      expect(validateScriptName(''), isNotNull);
      expect(validateScriptName('deploy'), contains('.sh'));
      expect(validateScriptName('.sh'), isNotNull);
      expect(validateScriptName('../x.sh'), isNotNull);
      expect(validateScriptName('a b.sh'), isNotNull);
      expect(validateScriptName('a/b.sh'), isNotNull);
      expect(validateScriptName('-rf.sh'), isNotNull);
      expect(validateScriptName('${'a' * 70}.sh'), isNotNull);
    });
    test('admin refusal detection', () {
      expect(isAdminModeRefusal('whatever', 403), isTrue);
      expect(isAdminModeRefusal('Admin mode is off', null), isTrue);
      expect(isAdminModeRefusal('protected service', 409), isFalse);
    });
  });

  testWidgets('new script with an invalid name is not saved', (tester) async {
    final svc = _FakeDevops();
    await _pump(tester, svc, home: ScriptEditorPage(service: svc));
    await tester.enterText(find.widgetWithText(TextField, 'Script name'), 'bad name.sh');
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(find.textContaining('Use only letters'), findsOneWidget);
    expect(svc.saved, isEmpty);

    await tester.enterText(find.widgetWithText(TextField, 'Script name'), 'good.sh');
    await tester.tap(find.text('Save'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(svc.saved, ['good.sh']);
  });

  testWidgets('leaving the editor with unsaved changes asks first', (tester) async {
    final svc = _FakeDevops();
    await _pump(tester, svc, home: Builder(
      builder: (context) => Center(
        child: ElevatedButton(
          onPressed: () => ScriptEditorPage.open(context, svc, scriptName: 'deploy.sh', initialContent: 'echo a\n'),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('deploy.sh'), findsOneWidget);

    // Untouched: back leaves straight away.
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Script'), 'echo b\n');
    await tester.pump();
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Discard your changes?'), findsOneWidget);

    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.text('deploy.sh'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard changes'));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
  });

  for (final b in Brightness.values) {
    for (final size in const [Size(390, 844), Size(1400, 900)]) {
      testWidgets('no overflow on every tab at ${size.width.toInt()} in ${b.name}', (tester) async {
        final svc = _FakeDevops();
        await _pump(tester, svc, size: size, brightness: b);
        for (final t in ServicesTab.values) {
          await tester.tap(find.text(t.label));
          await _settle(tester);
          expect(tester.takeException(), isNull, reason: t.label);
        }
      });
    }
  }
}
