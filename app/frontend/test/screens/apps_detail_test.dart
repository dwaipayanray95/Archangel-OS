import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:archangel/data/app_state.dart';
import 'package:archangel/models/container_model.dart';
import 'package:archangel/screens/container_detail_screen.dart';
import 'package:archangel/services/archangeld_connection.dart';
import 'package:archangel/services/containers_service.dart';
import 'package:archangel/ui/screens/apps/log_view.dart';
import 'package:archangel/ui/theme.dart';


class _Svc extends ContainersService {
  final logs = <DockerLogEntry>[
    const DockerLogEntry(ts: '10:00:01', level: 'INFO', source: 'web', text: 'listening on :80'),
    const DockerLogEntry(ts: '10:00:02', level: 'ERROR', source: 'web', text: 'upstream failed'),
    const DockerLogEntry(ts: '10:00:03', level: 'WARN', source: 'web', text: 'slow request'),
  ];
  @override
  List<DockerLogEntry> get liveLogs => logs;
  @override
  void startLogStream(String containerId) {}
  @override
  void stopLogStream() {}
  void add(DockerLogEntry e) {
    logs.add(e);
    notifyListeners();
  }
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

Future<_Svc> _pump(WidgetTester tester, Size size, Brightness b) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  final svc = _Svc();
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppState()),
        ChangeNotifierProvider(create: (_) => ArchangeldConnection()),
        ChangeNotifierProvider<ContainersService>.value(value: svc),
      ],
      child: MaterialApp(theme: buildTheme(b), home: const ContainerDetailScreen(container: _web)),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
  return svc;
}

void main() {
  for (final b in Brightness.values) {
    for (final size in const [Size(390, 844), Size(1400, 900)]) {
      testWidgets('detail has no overflow at ${size.width.toInt()} (${b.name})', (tester) async {
        await _pump(tester, size, b);
        expect(tester.takeException(), isNull);
        expect(find.textContaining('upstream failed'), findsOneWidget);
        expect(find.byType(BackButton), findsOneWidget);
      });
    }
  }

  testWidgets('Clear view hides existing lines but keeps new ones', (tester) async {
    final svc = await _pump(tester, const Size(1400, 900), Brightness.dark);
    await tester.tap(find.text('Clear view'));
    await tester.pump();
    expect(find.textContaining('upstream failed', findRichText: true), findsNothing);
    expect(svc.logs, hasLength(3), reason: 'the real log buffer is untouched');

    svc.add(const DockerLogEntry(ts: '10:00:04', level: 'INFO', source: 'web', text: 'fresh line'));
    await tester.pump();
    expect(find.textContaining('fresh line', findRichText: true), findsOneWidget);
  });

  testWidgets('Pause scrolling toggles to Resume', (tester) async {
    await _pump(tester, const Size(1400, 900), Brightness.dark);
    await tester.tap(find.text('Pause scrolling'));
    await tester.pump();
    expect(find.text('Resume scrolling'), findsOneWidget);
  });

  test('log levels use theme colours', () {
    final c = ArchangelTheme.of(Brightness.light).colors;
    expect(logLevelColor(c, 'error'), c.danger);
    expect(logLevelColor(c, 'WARN'), c.warning);
    expect(logLevelColor(c, 'debug'), c.textSubtle);
    expect(logLevelColor(c, 'INFO'), c.info);
  });
}
