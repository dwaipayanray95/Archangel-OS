import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:archangel/data/app_state.dart';
import 'package:archangel/models/file_entry.dart';
import 'package:archangel/services/archangeld_connection.dart';
import 'package:archangel/services/files_service.dart';
import 'package:archangel/ui/screens/files/files_workspace.dart';
import 'package:archangel/ui/ui.dart';

/// A FilesService with a fixed listing whose upload() the test controls.
class _UploadFiles extends FilesService {
  _UploadFiles({this.canUpload = true});

  final bool canUpload;
  final calls = <List<String>>[];
  final loaded = <String>[];
  Completer<UploadResult>? pending;
  UploadCancelToken? lastToken;
  UploadProgress? progressToSend;
  UploadConflictChoice? conflictAnswer;
  UploadResult result = const UploadResult.success(1);
  bool showHiddenFlag = false;

  final _listing = const DirectoryListingModel(
    path: '/home/archangel/docs',
    parent: '/home/archangel',
    entries: [],
    totalEntries: 0,
    readable: true,
  );

  @override
  DirectoryListingModel? get listing => _listing;
  @override
  String get currentPath => _listing.path;
  @override
  String? get rootPath => '/home/archangel';
  @override
  bool get loading => false;
  @override
  bool get supportsUpload => canUpload;
  @override
  bool get showHidden => showHiddenFlag;
  @override
  void init(ArchangeldConnection backend) {}
  @override
  Future<void> loadDirectory(String path, {bool forceRefresh = false}) async => loaded.add(path);

  @override
  Future<UploadResult> upload(
    String dir,
    List<UploadFileItem> files, {
    void Function(UploadProgress progress)? onProgress,
    UploadCancelToken? cancel,
    Future<UploadConflictChoice> Function(String name)? onConflict,
  }) async {
    calls.add([dir, ...files.map((f) => f.name)]);
    lastToken = cancel;
    if (progressToSend != null) onProgress?.call(progressToSend!);
    if (conflictAnswer != null) {
      final answer = await onConflict?.call(files.first.name);
      conflictAnswer = answer;
    }
    final p = pending;
    if (p != null) return p.future;
    return result;
  }
}

Future<void> _pump(WidgetTester tester, _UploadFiles svc, Size size, Future<List<UploadFileItem>> Function() pick) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: AppState(),
      child: MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Scaffold(
          body: FilesWorkspace(files: svc, onOpenTerminal: (_) {}, onBackToRoot: () {}, pickFiles: pick),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
}

Future<List<UploadFileItem>> _pickTwo() async => const [
  UploadFileItem(name: 'a.txt', sizeBytes: 1024),
  UploadFileItem(name: 'b.txt', sizeBytes: 2048),
];

void main() {
  for (final size in const [Size(1400, 900), Size(390, 800), Size(340, 600)]) {
    testWidgets('upload buttons are hidden when unsupported ($size)', (tester) async {
      await _pump(tester, _UploadFiles(canUpload: false), size, _pickTwo);
      expect(find.byTooltip('Upload'), findsNothing);
      expect(find.byTooltip('Open terminal here'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('picks files, shows progress, then the done snackbar', (tester) async {
    final svc = _UploadFiles()
      ..pending = Completer<UploadResult>()
      ..progressToSend = const UploadProgress(fileIndex: 0, totalFiles: 2, currentFileName: 'a.txt', bytesSent: 512, totalBytes: 1024);
    await _pump(tester, svc, const Size(1400, 900), _pickTwo);

    await tester.tap(find.byTooltip('Upload'));
    await tester.pump();
    await tester.pump();

    expect(svc.calls.single, ['/home/archangel/docs', 'a.txt', 'b.txt']);
    expect(find.text('Uploading 2 files to docs'), findsOneWidget);
    expect(find.text('a.txt · 1 of 2'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);

    svc.pending!.complete(const UploadResult.success(2));
    await tester.pump();
    await tester.pump();

    expect(find.text('Uploaded 2 files'), findsOneWidget);
    expect(find.textContaining('Uploading'), findsNothing);
  });

  testWidgets('Cancel stops the upload and clears the card', (tester) async {
    final svc = _UploadFiles()..pending = Completer<UploadResult>();
    await _pump(tester, svc, const Size(390, 800), _pickTwo);

    await tester.tap(find.byTooltip('Upload'));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(svc.lastToken!.isCancelled, isTrue);

    svc.pending!.complete(const UploadResult.cancelled());
    await tester.pump();
    await tester.pump();
    expect(find.text('Upload cancelled'), findsOneWidget);
    expect(find.textContaining('Uploading'), findsNothing);
  });

  testWidgets('failure keeps the card with Try again, which resumes after finished files', (tester) async {
    final svc = _UploadFiles()..result = const UploadResult.failed('b.txt: That file is too big', uploadedCount: 1, processedCount: 1);
    await _pump(tester, svc, const Size(1400, 900), _pickTwo);

    await tester.tap(find.byTooltip('Upload'));
    await tester.pump();
    await tester.pump();
    expect(find.text('b.txt: That file is too big'), findsOneWidget);

    svc.result = const UploadResult.success(1);
    await tester.tap(find.text('Try again'));
    await tester.pump();
    await tester.pump();

    expect(svc.calls.length, 2);
    expect(svc.calls.last, ['/home/archangel/docs', 'b.txt']); // a.txt is not sent again
    expect(find.text('Uploaded 1 file'), findsOneWidget);
  });

  testWidgets('name clash asks "Replace <name>?" with Replace / Skip / Keep both', (tester) async {
    final svc = _UploadFiles()..conflictAnswer = UploadConflictChoice.skip;
    await _pump(tester, svc, const Size(1400, 900), _pickTwo);

    await tester.tap(find.byTooltip('Upload'));
    await tester.pumpAndSettle();

    expect(find.text('Replace a.txt?'), findsOneWidget);
    expect(find.text('Replace'), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);
    expect(find.text('Keep both'), findsOneWidget);

    await tester.tap(find.text('Keep both'));
    await tester.pumpAndSettle();
    expect(svc.conflictAnswer, UploadConflictChoice.keepBoth);
  });

  testWidgets('an empty pick does nothing', (tester) async {
    final svc = _UploadFiles();
    await _pump(tester, svc, const Size(1400, 900), () async => const <UploadFileItem>[]);
    await tester.tap(find.byTooltip('Upload'));
    await tester.pump();
    await tester.pump();
    expect(svc.calls, isEmpty);
    expect(find.textContaining('Uploading'), findsNothing);
  });
}
