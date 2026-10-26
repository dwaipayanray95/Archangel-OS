import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:archangel/data/app_state.dart';
import 'package:archangel/models/container_model.dart';
import 'package:archangel/screens/containers_screen.dart';
import 'package:archangel/services/archangeld_connection.dart';
import 'package:archangel/services/containers_service.dart';
import 'package:archangel/ui/screens/apps/run_app_page.dart';
import 'package:archangel/ui/theme.dart';

class _FakeContainers extends ContainersService {
  _FakeContainers(this._ov);
  final DockerOverviewModel? _ov;
  final actions = <String>[];

  @override
  DockerOverviewModel? get overview => _ov;
  @override
  void init(ArchangeldConnection backend) {}
  @override
  Future<void> fetchContainers() async {}
  @override
  Future<bool> triggerAction(String containerId, String action) async {
    actions.add('$containerId:$action');
    return true;
  }

  Map<String, dynamic>? lastCreate;
  @override
  Future<Map<String, dynamic>> createContainer({
    required String image,
    String? name,
    List<String>? ports,
    List<String>? env,
    String? restart,
    List<String>? volumes,
  }) async {
    lastCreate = {'image': image, 'ports': ports, 'volumes': volumes, 'env': env, 'restart': restart};
    return {'success': true, 'message': 'started'};
  }
}

class _FailingContainers extends _FakeContainers {
  _FailingContainers(super.ov);
  @override
  Future<Map<String, dynamic>> createContainer({
    required String image,
    String? name,
    List<String>? ports,
    List<String>? env,
    String? restart,
    List<String>? volumes,
  }) async => {'success': false, 'message': 'Port 8081 is already in use'};
}

const _web = DockerContainerItem(
  id: 'abc123',
  name: 'web',
  image: 'nginx',
  stack: 'standalone',
  state: 'running',
  status: 'Up',
  uptime: '2h',
  cpu: 1.5,
  memMb: 40,
  memLabel: '40 MB',
  ports: '8080',
  cid: 'abc123',
  running: true,
);
const _db = DockerContainerItem(
  id: 'def456',
  name: 'db',
  image: 'postgres',
  stack: 'standalone',
  state: 'exited',
  status: 'Exited',
  uptime: '—',
  cpu: 0,
  memMb: 0,
  memLabel: '—',
  ports: '—',
  cid: 'def456',
  running: false,
);

DockerOverviewModel _overview({bool docker = true, List<DockerContainerItem> apps = const [_web, _db]}) => DockerOverviewModel(
  dockerAvailable: docker,
  engineVersion: '27.0',
  runningCount: apps.where((a) => a.running).length,
  stoppedCount: apps.where((a) => !a.running).length,
  totalImagesSize: '1 GB',
  containers: apps,
  stacks: const [],
  stackMeta: const {},
);

Future<void> _pump(
  WidgetTester tester,
  _FakeContainers svc, {
  Size size = const Size(1400, 900),
  Brightness brightness = Brightness.dark,
  Widget home = const ContainersScreen(),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppState()),
        ChangeNotifierProvider(create: (_) => ArchangeldConnection()),
        ChangeNotifierProvider<ContainersService>.value(value: svc),
      ],
      child: MaterialApp(
        theme: buildTheme(brightness),
        home: Scaffold(body: home),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('Docker not running shows an explanation, not an empty list', (tester) async {
    await _pump(tester, _FakeContainers(_overview(docker: false, apps: const [])));
    expect(find.text('Docker isn’t running'), findsOneWidget);
    expect(find.textContaining('start it in Services'), findsOneWidget);
    expect(find.text('Run an app'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('header counts are in words', (tester) async {
    await _pump(tester, _FakeContainers(_overview()));
    expect(find.text('1 running, 1 stopped'), findsOneWidget);
  });

  testWidgets('removing an app needs its name typed', (tester) async {
    final svc = _FakeContainers(_overview());
    await _pump(tester, svc, size: const Size(390, 844));
    await tester.tap(find.text('Remove').last);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Data saved in folders'), findsOneWidget);

    FilledButton confirm() => tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Remove app'));
    expect(confirm().onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'nope');
    await tester.pump();
    expect(confirm().onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'db');
    await tester.pump();
    expect(confirm().onPressed, isNotNull);
    await tester.tap(find.widgetWithText(FilledButton, 'Remove app'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(svc.actions, contains('def456:remove'));
  });

  testWidgets('stop asks for confirmation first', (tester) async {
    final svc = _FakeContainers(_overview());
    await _pump(tester, svc, size: const Size(390, 844));
    await tester.tap(find.text('Stop').first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(svc.actions, isEmpty);
    expect(find.text('Stop web?'), findsOneWidget);
    await tester.tap(find.text('Stop app'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(svc.actions, ['abc123:stop']);
  });

  Future<void> pickSomethingElse(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Something else'));
    await tester.tap(find.text('Something else'));
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('run an app starts with a catalog; a preset fills in port and folder', (tester) async {
    final svc = _FakeContainers(_overview());
    await _pump(
      tester,
      svc,
      size: const Size(390, 844),
      home: RunAppPage(service: svc),
    );
    expect(find.text('What would you like to run?'), findsOneWidget);
    await tester.tap(find.text('Uptime Kuma'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Who can open it?'), findsOneWidget);
    expect(find.textContaining('/srv/uptime-kuma'), findsOneWidget);
    await tester.ensureVisible(find.text('Run app'));
    await tester.tap(find.text('Run app'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(svc.lastCreate?['image'], 'louislam/uptime-kuma:1');
    expect(svc.lastCreate?['ports'], ['3001:3001']);
    expect(svc.lastCreate?['volumes'], ['/srv/uptime-kuma:/app/data']);
    expect(find.text('uptime-kuma is running.'), findsOneWidget);
    expect(find.text('Done'), findsWidgets);
  });

  testWidgets('public shows a warning and builds the 0.0.0.0 spec', (tester) async {
    final svc = _FakeContainers(_overview());
    await _pump(
      tester,
      svc,
      size: const Size(390, 844),
      home: RunAppPage(service: svc),
    );
    await pickSomethingElse(tester);
    await tester.enterText(find.widgetWithText(TextFormField, 'Image'), 'nginx');
    expect(find.textContaining('Anyone on the internet will be able'), findsNothing);

    await tester.enterText(find.widgetWithText(TextFormField, 'Port inside the app'), '80');
    await tester.enterText(find.widgetWithText(TextFormField, 'Port on your server'), '8080');
    await tester.pump(const Duration(milliseconds: 300)); // let the field finish scrolling into view
    await tester.ensureVisible(find.text('Public'));
    await tester.tap(find.text('Public'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Anyone on the internet will be able'), findsOneWidget);

    await tester.ensureVisible(find.text('Run app'));
    await tester.tap(find.text('Run app'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(svc.lastCreate?['ports'], ['0.0.0.0:8080:80']);
    expect(svc.lastCreate?['restart'], 'unless-stopped');
  });

  testWidgets('invalid ports block the form', (tester) async {
    final svc = _FakeContainers(_overview());
    await _pump(
      tester,
      svc,
      size: const Size(390, 844),
      home: RunAppPage(service: svc),
    );
    await pickSomethingElse(tester);
    await tester.enterText(find.widgetWithText(TextFormField, 'Image'), 'nginx');
    await tester.enterText(find.widgetWithText(TextFormField, 'Port inside the app'), '70000');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Run app'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Run app'));
    await tester.pumpAndSettle();
    expect(find.textContaining('between 1 and 65535'), findsOneWidget);
    expect(svc.lastCreate, isNull);
  });

  testWidgets('a server error offers to change settings', (tester) async {
    final svc = _FailingContainers(_overview());
    await _pump(
      tester,
      svc,
      size: const Size(390, 844),
      home: RunAppPage(service: svc),
    );
    await tester.tap(find.text('Vaultwarden'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.ensureVisible(find.text('Run app'));
    await tester.tap(find.text('Run app'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('That didn’t work'), findsOneWidget);
    expect(find.text('Port 8081 is already in use'), findsOneWidget);
    await tester.tap(find.text('Change settings'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Who can open it?'), findsOneWidget);
  });

  for (final b in Brightness.values) {
    for (final size in const [Size(390, 844), Size(1400, 900)]) {
      testWidgets('no overflow at ${size.width.toInt()} (${b.name})', (tester) async {
        await _pump(tester, _FakeContainers(_overview()), size: size, brightness: b);
        expect(tester.takeException(), isNull);
        expect(find.text('web'), findsWidgets);
      });
    }
  }

  testWidgets('run app page has no overflow at 390 and 1400', (tester) async {
    for (final size in const [Size(390, 844), Size(1400, 900)]) {
      final svc = _FakeContainers(_overview());
      await _pump(
        tester,
        svc,
        size: size,
        home: RunAppPage(key: ValueKey(size), service: svc),
      );
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Something else'));
      await tester.tap(find.text('Something else'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.ensureVisible(find.text('More options'));
      await tester.tap(find.text('More options'));
      await tester.pump();
      for (final label in ['Add a port', 'Add a folder', 'Add a setting']) {
        await tester.ensureVisible(find.text(label));
        await tester.tap(find.text(label));
        await tester.pump();
      }
      expect(tester.takeException(), isNull);
    }
  });
}
