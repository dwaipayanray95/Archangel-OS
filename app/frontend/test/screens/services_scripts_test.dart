import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

class _Conn extends ArchangeldConnection {
  @override
  bool get isPaired => true;
}

class _Devops extends DevopsService {
  final calls = <String>[];
  Map<String, String> runResult = {'ok': 'true', 'message': 'Success', 'output': 'hello from the script'};
  Map<String, dynamic> saveResult = {'success': true, 'message': 'Success'};
  int? status;
  String? statusMessage;

  @override
  int? get lastActionStatus => status;
  @override
  String? get lastActionMessage => statusMessage;

  @override
  List<DevRowModel> get services => const [
    DevRowModel(name: 'caddy', meta: 'Web server', status: 'Running', ok: true, actions: ['Restart', 'Stop']),
  ];
  @override
  List<DevRowModel> get scheduled => const [];
  @override
  List<DevRowModel> get proxy => const [];
  @override
  List<DevRowModel> get deployments => const [
    DevRowModel(name: 'deploy.sh', meta: 'Setup script', status: 'Saved', ok: true, actions: ['View', 'Remove']),
  ];
  @override
  bool get loading => false;
  @override
  bool get hasLoaded => true;
  @override
  void init(ArchangeldConnection backend) {}
  @override
  Future<void> fetchAll() async {}

  @override
  Future<bool> triggerServiceAction(String name, String action) async {
    calls.add('$name:$action');
    return status == null;
  }

  @override
  Future<String?> getDeploymentContent(String name) async => '#!/bin/sh\necho hi';

  @override
  Future<Map<String, String>?> runDeployment(String name) async {
    calls.add('run:$name');
    return runResult;
  }

  @override
  Future<Map<String, dynamic>> saveDeployment(String name, String content) async {
    calls.add('save:$name');
    return saveResult;
  }
}

late AppState _app;

Future<_Devops> _pump(
  WidgetTester tester, {
  Size size = const Size(1400, 900),
  Brightness brightness = Brightness.dark,
  _Devops? svc,
}) async {
  DevopsScreen.resetTab();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  final service = svc ?? _Devops();
  _app = AppState();
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: _app),
        ChangeNotifierProvider<ArchangeldConnection>(create: (_) => _Conn()),
        ChangeNotifierProvider<DevopsService>.value(value: service),
      ],
      child: MaterialApp(
        theme: buildTheme(brightness),
        home: const Scaffold(body: DevopsScreen()),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
  await tester.ensureVisible(find.text('Deployments'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Deployments'));
  await tester.pumpAndSettle();
  return service;
}

void main() {
  group('Script name validation', () {
    test('accepts good names', () {
      for (final n in ['deploy.sh', 'a-b_c.1.sh', 'x.sh', ' deploy.sh ']) {
        expect(validateScriptName(n), isNull, reason: n);
      }
      expect(validateScriptName('a' * 61 + '.sh'), isNull); // 64 characters
    });

    test('rejects bad names', () {
      expect(validateScriptName(''), isNotNull);
      expect(validateScriptName('deploy'), isNotNull);
      expect(validateScriptName('deploy.txt'), isNotNull);
      expect(validateScriptName('a' * 62 + '.sh'), isNotNull); // 65 characters
      expect(validateScriptName('.hidden.sh'), isNotNull);
      expect(validateScriptName('-flag.sh'), isNotNull);
      expect(validateScriptName('.sh'), isNotNull);
      expect(validateScriptName('my script.sh'), isNotNull);
      expect(validateScriptName('dir/run.sh'), isNotNull);
      expect(validateScriptName('run;rm.sh'), isNotNull);
    });

    test('admin-mode refusal detection', () {
      expect(isAdminModeRefusal('nope', 403), isTrue);
      expect(isAdminModeRefusal('Admin mode is off', null), isTrue);
      expect(isAdminModeRefusal('Something broke', 500), isFalse);
      expect(isAdminModeRefusal(null, null), isFalse);
    });
  });

  group('Run a script', () {
    testWidgets('confirms, runs and shows the output with Copy and a Finished badge', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String?;
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      final svc = await _pump(tester);

      await tester.tap(find.text('Run'));
      await tester.pumpAndSettle();
      expect(find.text('Run deploy.sh?'), findsOneWidget);
      expect(find.text('This runs the script on your server as the archangel user.'), findsOneWidget);
      expect(svc.calls, isEmpty);

      await tester.tap(find.text('Run script'));
      await tester.pumpAndSettle();

      expect(svc.calls, ['run:deploy.sh']);
      expect(find.text('Finished'), findsOneWidget);
      expect(find.text('hello from the script'), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);

      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();
      expect(find.text('Copied'), findsOneWidget);
      expect(copied, 'hello from the script');

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Finished'), findsNothing);
    });

    testWidgets('cancelling the confirmation does not run anything', (tester) async {
      final svc = await _pump(tester);
      await tester.tap(find.text('Run'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(svc.calls, isEmpty);
    });

    testWidgets('a failed run shows Did not finish with its output', (tester) async {
      final svc = _Devops()..runResult = {'ok': 'false', 'message': 'Exited with code 1', 'output': 'boom'};
      await _pump(tester, svc: svc);
      await tester.tap(find.text('Run'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Run script'));
      await tester.pumpAndSettle();
      expect(find.text('Did not finish'), findsOneWidget);
      expect(find.text('boom'), findsOneWidget);
      expect(find.text('Exited with code 1'), findsOneWidget);
    });
  });

  group('Script editor', () {
    testWidgets('Edit opens the editor with a read-only name and guards unsaved changes', (tester) async {
      await _pump(tester);
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      expect(find.byType(ScriptEditorPage), findsOneWidget);
      expect(find.byKey(const ValueKey('script-name')), findsNothing);
      expect(find.text('deploy.sh'), findsWidgets);
      expect(find.text('This script runs on your server as the archangel user.'), findsOneWidget);

      // Nothing changed: Back leaves without asking.
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.byType(ScriptEditorPage), findsNothing);

      // Change something: Back asks first.
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('script-content')), '#!/bin/sh\necho changed');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Discard your changes?'), findsOneWidget);

      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(find.byType(ScriptEditorPage), findsOneWidget);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard changes'));
      await tester.pumpAndSettle();
      expect(find.byType(ScriptEditorPage), findsNothing);
    });

    testWidgets('Save is off until something changes, then saves and closes', (tester) async {
      final svc = await _pump(tester);
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save')).onPressed, isNull);
      await tester.enterText(find.byKey(const ValueKey('script-content')), 'echo new');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(svc.calls, ['save:deploy.sh']);
      expect(find.byType(ScriptEditorPage), findsNothing);
      expect(find.text('deploy.sh saved'), findsOneWidget);
    });

    testWidgets('New script checks the name before saving', (tester) async {
      final svc = await _pump(tester);
      await tester.tap(find.text('New script'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('script-name')), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('script-name')), 'notes.txt');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('The name must end with .sh, for example deploy.sh.'), findsOneWidget);
      expect(svc.calls, isEmpty);

      await tester.enterText(find.byKey(const ValueKey('script-name')), '-bad.sh');
      await tester.pumpAndSettle();
      expect(find.text("The name can't start with a dot or a dash."), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('script-name')), 'good-name.sh');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(svc.calls, ['save:good-name.sh']);
      expect(find.text('Script saved'), findsOneWidget);
    });

    testWidgets('a failed save keeps the editor open and shows why', (tester) async {
      final svc = _Devops()..saveResult = {'success': false, 'message': 'Disk is full'};
      await _pump(tester, svc: svc);
      await tester.tap(find.text('New script'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('script-name')), 'a.sh');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.byType(ScriptEditorPage), findsOneWidget);
      expect(find.text('Disk is full'), findsOneWidget);
    });
  });

  group('Admin mode refusal banner', () {
    testWidgets('a refused run shows the server message with Open Settings, dismissible', (tester) async {
      final svc = _Devops()
        ..status = 403
        ..runResult = {'ok': 'false', 'message': 'Turn on Admin mode in Settings first.', 'output': ''};
      await _pump(tester, svc: svc);

      await tester.tap(find.text('Run'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Run script'));
      await tester.pumpAndSettle();

      expect(find.text('Turn on Admin mode in Settings first.'), findsOneWidget);
      expect(find.text('Finished'), findsNothing);
      expect(find.text('Did not finish'), findsNothing);

      await tester.tap(find.text('Open Settings'));
      await tester.pumpAndSettle();
      expect(_app.section, AxSection.settings);

      await tester.tap(find.byTooltip('Dismiss message'));
      await tester.pumpAndSettle();
      expect(find.text('Turn on Admin mode in Settings first.'), findsNothing);
    });

    testWidgets('a refused service action shows the banner instead of a snackbar', (tester) async {
      final svc = _Devops()
        ..status = 403
        ..statusMessage = 'Admin mode is off.';
      await _pump(tester, svc: svc);
      await tester.tap(find.text('Background'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Restart'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Restart').last);
      await tester.pumpAndSettle();

      expect(find.text('Admin mode is off.'), findsOneWidget);
      expect(find.text('Open Settings'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('other failures stay a snackbar', (tester) async {
      final svc = _Devops()
        ..status = 500
        ..statusMessage = 'The service is not installed.';
      await _pump(tester, svc: svc);
      await tester.tap(find.text('Background'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Restart'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Restart').last);
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('Open Settings'), findsNothing);
    });
  });

  group('Layout', () {
    for (final brightness in Brightness.values) {
      for (final size in [const Size(1400, 900), const Size(390, 844), const Size(340, 800)]) {
        testWidgets('Deployments, banner, output and editor at ${size.width.toInt()} in ${brightness.name}', (tester) async {
          final svc = _Devops()
            ..status = 403
            ..runResult = {'ok': 'false', 'message': 'Turn on Admin mode in Settings first, then try this again.', 'output': ''};
          await _pump(tester, size: size, brightness: brightness, svc: svc);
          expect(tester.takeException(), isNull);

          // Banner
          await tester.ensureVisible(find.text('Run'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Run'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Run script'));
          await tester.pumpAndSettle();
          expect(find.text('Open Settings'), findsOneWidget);
          expect(tester.takeException(), isNull);

          // Output sheet
          svc
            ..status = null
            ..runResult = {'ok': 'true', 'message': 'Success', 'output': List.generate(40, (i) => 'line $i of the output').join('\n')};
          await tester.ensureVisible(find.text('Run'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Run'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Run script'));
          await tester.pumpAndSettle();
          expect(find.text('Finished'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.tap(find.text('Close'));
          await tester.pumpAndSettle();

          // Editor (new script)
          await tester.ensureVisible(find.text('New script'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('New script'));
          await tester.pumpAndSettle();
          await tester.enterText(find.byKey(const ValueKey('script-name')), 'bad name');
          await tester.pumpAndSettle();
          await tester.tap(find.text('Save'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}
