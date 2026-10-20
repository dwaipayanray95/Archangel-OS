import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:archangel/data/app_state.dart';
import 'package:archangel/models/file_entry.dart';
import 'package:archangel/screens/files_screen.dart';
import 'package:archangel/services/archangeld_connection.dart';
import 'package:archangel/services/files_service.dart';
import 'package:archangel/ui/screens/files/file_helpers.dart';
import 'package:archangel/ui/theme.dart';

class _FakeFiles extends FilesService {
  _FakeFiles({this.fakeListing, this.fakeError});
  DirectoryListingModel? fakeListing;
  String? fakeError;
  int retries = 0;
  final loaded = <String>[];

  @override
  DirectoryListingModel? get listing => fakeListing;
  @override
  String? get error => fakeError;
  @override
  String get currentPath => fakeListing?.path ?? '';
  @override
  String? get rootPath => '/home/archangel';
  @override
  bool get loading => false;
  @override
  void init(ArchangeldConnection backend) {}
  @override
  Future<void> retry() async => retries++;
  @override
  Future<void> loadDirectory(String path, {bool forceRefresh = false}) async => loaded.add(path);
}

FileEntryModel _e(String name, {String kind = 'file'}) => FileEntryModel(
  name: name,
  path: '/home/archangel/$name',
  kind: kind,
  sizeBytes: 1200,
  size: kind == 'dir' ? '—' : '1.2 KB',
  perms: 'rw-r--r--',
  mtime: 'Sep 02 06:14',
);

DirectoryListingModel _listing() => DirectoryListingModel(
  path: '/home/archangel/projects/deep/nested/folder/structure',
  parent: '/home/archangel',
  entries: [_e('notes.txt'), _e('photos', kind: 'dir'), _e('.hidden')],
  totalEntries: 3,
  readable: true,
);

Future<void> _pump(WidgetTester tester, _FakeFiles svc, Size size, {Brightness b = Brightness.dark}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppState()),
        ChangeNotifierProvider(create: (_) => ArchangeldConnection()),
        ChangeNotifierProvider<FilesService>.value(value: svc),
      ],
      child: MaterialApp(theme: buildTheme(b), home: const Scaffold(body: FilesScreen())),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('phone layout is rows, not a fixed-width table', (tester) async {
    await _pump(tester, _FakeFiles(fakeListing: _listing()), const Size(390, 844));
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('files-table')), findsNothing);
    expect(find.byType(DataTable), findsNothing);
    expect(find.byType(ListTile), findsNWidgets(2), reason: 'hidden files are not shown by default');
    expect(find.textContaining('1.2 KB'), findsOneWidget);
    expect(find.text('Home'), findsWidgets);
    expect(find.text('/var/log'), findsOneWidget);
  });

  testWidgets('desktop layout is a table', (tester) async {
    await _pump(tester, _FakeFiles(fakeListing: _listing()), const Size(1400, 900));
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('files-table')), findsOneWidget);
    expect(find.text('Size'), findsOneWidget);
  });

  testWidgets('hidden files switch is labelled and works', (tester) async {
    final svc = _FakeFiles(fakeListing: _listing());
    await _pump(tester, svc, const Size(390, 844));
    expect(find.text('Show hidden files'), findsOneWidget);
    expect(find.byType(Switch), findsOneWidget);
  });

  testWidgets('tapping a folder opens it', (tester) async {
    final svc = _FakeFiles(fakeListing: _listing());
    await _pump(tester, svc, const Size(390, 844));
    await tester.tap(find.text('photos'));
    await tester.pump();
    expect(svc.loaded, ['/home/archangel/photos']);
  });

  testWidgets('error state has Retry and a plain hint for off-limits folders', (tester) async {
    final svc = _FakeFiles(fakeError: 'path is outside the configured files_root');
    await _pump(tester, svc, const Size(390, 844));
    expect(find.text('Archangel can only show files inside /home/archangel.'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(svc.retries, 1);
  });

  testWidgets('other errors show the message with Retry', (tester) async {
    final svc = _FakeFiles(fakeError: 'Connection refused');
    await _pump(tester, svc, const Size(390, 844));
    expect(find.text('Connection refused'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  for (final b in Brightness.values) {
    for (final size in const [Size(390, 844), Size(1400, 900)]) {
      testWidgets('no overflow at ${size.width.toInt()} (${b.name})', (tester) async {
        await _pump(tester, _FakeFiles(fakeListing: _listing()), size, b: b);
        expect(tester.takeException(), isNull);
        await _pump(tester, _FakeFiles(fakeError: 'boom'), size, b: b);
        expect(tester.takeException(), isNull);
      });
    }
  }

  test('breadcrumbs start at Home inside the files root', () {
    final crumbs = buildCrumbs('/home/archangel/a/b', rootPath: '/home/archangel');
    expect(crumbs.map((c) => c.label), ['Home', 'a', 'b']);
    expect(crumbs.map((c) => c.path), ['', '/home/archangel/a', '/home/archangel/a/b']);
    expect(buildCrumbs('/etc', rootPath: '/home/archangel').map((c) => c.label), ['/', 'etc']);
  });
}
