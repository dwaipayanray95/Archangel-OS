import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:archangel/data/app_state.dart';
import 'package:archangel/models/file_entry.dart';
import 'package:archangel/screens/files_screen.dart';
import 'package:archangel/services/archangeld_connection.dart';
import 'package:archangel/services/files_service.dart';
import 'package:archangel/services/local_kv_store.dart';
import 'package:archangel/ui/screens/files/file_helpers.dart';
import 'package:archangel/ui/screens/files/files_preview.dart';
import 'package:archangel/ui/ui.dart';

import '../test_utils.dart';

class _FakeFiles extends FilesService {
  _FakeFiles({
    this.fakeListing,
    this.fakeError,
    this.fakeRoot = '/home/archangel',
    this.fakeSupportsUpload = false,
    this.fakeSupportsPrivateLink = false,
    this.fakeFileContent,
    this.fakeBytes,
  });

  DirectoryListingModel? fakeListing;
  String? fakeError;
  String? fakeRoot;
  bool fakeSupportsUpload;
  bool fakeSupportsPrivateLink;
  FileContentResult? fakeFileContent;
  Uint8List? fakeBytes;

  int retries = 0;
  final loaded = <String>[];
  bool _showHiddenFiles = false;

  @override
  DirectoryListingModel? get listing => fakeListing;

  @override
  String? get error => fakeError;

  @override
  String get currentPath => fakeListing?.path ?? '';

  @override
  String? get rootPath => fakeRoot;

  @override
  bool get loading => false;

  @override
  bool get showHidden => _showHiddenFiles;

  @override
  void toggleShowHidden() {
    _showHiddenFiles = !_showHiddenFiles;
    notifyListeners();
  }

  @override
  bool get supportsUpload => fakeSupportsUpload;

  @override
  bool get supportsPrivateLink => fakeSupportsPrivateLink;

  @override
  FileContentResult? get fileContent => fakeFileContent;

  @override
  void init(ArchangeldConnection backend) {}

  @override
  Future<void> retry() async {
    retries++;
    notifyListeners();
  }

  @override
  Future<void> loadDirectory(String path, {bool forceRefresh = false}) async {
    loaded.add(path);
  }

  @override
  Future<void> openFilePreview(String path) async {
    notifyListeners();
  }

  @override
  void closePreview() {
    fakeFileContent = null;
    notifyListeners();
  }

  @override
  Future<Uint8List?> downloadFileBytes(String path) async {
    return fakeBytes;
  }

  @override
  Future<DownloadResult> downloadToDisk(String path) async {
    return const DownloadResult.saved('/downloads/saved.txt');
  }

  @override
  Future<PrivateLinkResult> privateLink(String path) async {
    return const PrivateLinkResult.success('https://private.tunnel/file/abc');
  }

  @override
  Future<UploadResult> upload(String dir, List<UploadFileItem> files, {void Function(UploadProgress progress)? onProgress}) async {
    if (onProgress != null) {
      onProgress(
        UploadProgress(fileIndex: 0, totalFiles: files.length, currentFileName: files.first.name, bytesSent: 512, totalBytes: 1024),
      );
    }
    return UploadResult.success(files.length);
  }
}

FileEntryModel _entry(
  String name, {
  String dir = '/home/archangel/projects/notes',
  String kind = 'file',
  int sizeBytes = 1200,
  String size = '1.2 KB',
  String mtime = 'Sep 02 06:14',
}) => FileEntryModel(
  name: name,
  path: '$dir/$name',
  kind: kind,
  sizeBytes: sizeBytes,
  size: kind == 'dir' ? '—' : size,
  perms: 'rw-r--r--',
  mtime: mtime,
);

DirectoryListingModel _listing() => DirectoryListingModel(
  path: '/home/archangel/projects/notes',
  parent: '/home/archangel/projects',
  entries: [
    _entry('docs', kind: 'dir', mtime: 'Oct 18 22:10'),
    _entry('notes.txt', sizeBytes: 1000, size: '1.0 KB', mtime: 'Sep 02 06:14'),
    _entry('photo.jpg', sizeBytes: 5000, size: '5.0 KB', mtime: 'Oct 21 09:41'),
    _entry('.hidden', sizeBytes: 200, size: '200 B', mtime: 'Sep 01 00:00'),
  ],
  totalEntries: 4,
  readable: true,
);

Future<void> _pump(WidgetTester tester, _FakeFiles svc, Size size, {Brightness b = Brightness.dark}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);

  final appState = AppState();
  final backend = ArchangeldConnection();

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: appState),
        ChangeNotifierProvider.value(value: backend),
        ChangeNotifierProvider<FilesService>.value(value: svc),
      ],
      child: MaterialApp(theme: buildTheme(b), home: const Scaffold(body: FilesScreen(restoreSortOnStart: false))),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  group('Wide 1400x900 layout', () {
    testWidgets('shows two columns, Upload + Open terminal here, list header, preview card', (tester) async {
      final svc = _FakeFiles(
        fakeListing: _listing(),
        fakeSupportsUpload: true,
        fakeSupportsPrivateLink: true,
        fakeFileContent: const FileContentResult(
          path: '/home/archangel/projects/notes/notes.txt',
          name: 'notes.txt',
          sizeBytes: 1000,
          lines: ['Line 1', 'Line 2'],
          lineCount: 2,
          truncated: false,
          isBinary: false,
          mimeType: 'text/plain',
        ),
      );

      await _pump(tester, svc, const Size(1400, 900));
      expect(tester.takeException(), isNull);

      // Header title & subtitle (wide only)
      expect(find.text('Files'), findsOneWidget);
      expect(find.text('Everything here lives on your server, not on someone else\'s cloud.'), findsOneWidget);

      // Actions on wide: labeled buttons with tooltips
      expect(find.widgetWithText(AxButton, 'Open terminal here'), findsOneWidget);
      expect(find.widgetWithText(AxButton, 'Upload'), findsOneWidget);
      expect(find.byTooltip('Open terminal here'), findsOneWidget);
      expect(find.byTooltip('Upload'), findsOneWidget);

      // List headers
      expect(find.text('Name'), findsOneWidget);
      expect(find.text('Size'), findsOneWidget);
      expect(find.text('Modified'), findsOneWidget);

      // Tap on a file to open wide preview card
      await tester.tap(find.text('notes.txt'));
      await tester.pump();

      // Wide preview card displays Download and Copy private link
      expect(find.byType(WidePreviewCard), findsOneWidget);
      expect(find.widgetWithText(AxButton, 'Download'), findsOneWidget);
      expect(find.text('Copy private link'), findsOneWidget);
      expect(find.text('Showing the whole file.'), findsOneWidget);
    });

    testWidgets('no overflow in short wide desktop window with preview open (850x450)', (tester) async {
      final svc = _FakeFiles(
        fakeListing: _listing(),
        fakeSupportsUpload: true,
        fakeSupportsPrivateLink: true,
        fakeFileContent: const FileContentResult(
          path: '/home/archangel/projects/notes/notes.txt',
          name: 'notes.txt',
          sizeBytes: 1000,
          lines: [
            "version: '3.8'",
            '',
            'services:',
            '  tcu-backend:',
            '    build: .',
            '    container_name: tcu-backend',
            '    restart: unless-stopped',
            '    ports:',
            '      - "9000:9000"',
            '    environment:',
          ],
          lineCount: 10,
          truncated: false,
          isBinary: false,
          mimeType: 'text/plain',
        ),
      );

      await _pump(tester, svc, const Size(850, 450));
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('notes.txt'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(WidePreviewCard), findsOneWidget);
    });
  });

  group('Narrow 340 and 390 layout', () {
    testWidgets('no overflow at 340 (Desktop window), icon buttons, crumbs collapse', (tester) async {
      final svc = _FakeFiles(fakeListing: _listing(), fakeSupportsUpload: true);
      await _pump(tester, svc, const Size(340, 600));
      expect(tester.takeException(), isNull);

      // Icon buttons with tooltips on narrow
      expect(find.byTooltip('Open terminal here'), findsOneWidget);
      expect(find.byTooltip('Upload'), findsOneWidget);
      expect(find.text('Everything here lives on your server, not on someone else\'s cloud.'), findsNothing);

      // Breadcrumbs collapsed with ellipsis
      expect(find.text('…'), findsOneWidget);
      expect(find.text('notes'), findsOneWidget);
    });

    testWidgets('no overflow at 390 phone, preview full screen with back', (tester) async {
      final svc = _FakeFiles(
        fakeListing: _listing(),
        fakeSupportsUpload: true,
        fakeFileContent: const FileContentResult(
          path: '/home/archangel/projects/notes/notes.txt',
          name: 'notes.txt',
          sizeBytes: 1000,
          lines: ['First line'],
          lineCount: 1,
          truncated: false,
          isBinary: false,
          mimeType: 'text/plain',
        ),
      );

      await _pump(tester, svc, const Size(390, 844));
      expect(tester.takeException(), isNull);

      // Tap file opens narrow full screen preview
      await tester.tap(find.text('notes.txt'));
      await tester.pump();

      expect(find.byType(NarrowPreviewView), findsOneWidget);
      expect(find.text('‹ notes'), findsOneWidget);
      expect(find.text('Where'), findsOneWidget);

      // Tapping back closes preview
      await tester.tap(find.text('‹ notes'));
      await tester.pump();

      expect(find.byType(NarrowPreviewView), findsNothing);
      expect(find.text('notes.txt'), findsOneWidget);
    });
  });

  group('Sorting', () {
    testWidgets('sort menu changes order, folders stay first, choice persists', (tester) async {
      await tester.runAsync(() async {
        await useTempKvStore();
      });
      final svc = _FakeFiles(fakeListing: _listing());
      await _pump(tester, svc, const Size(1400, 900));

      // Default sort is Name
      expect(find.text('Sort: Name'), findsOneWidget);

      // Open sort menu and select Newest
      await tester.tap(find.text('Sort: Name'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Newest').last);
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();

      expect(find.text('Sort: Newest'), findsOneWidget);

      // Verify stored in LocalKvStore
      await tester.runAsync(() async {
        final stored = await LocalKvStore.instance.read(kFilesSortKey);
        expect(stored, 'newest');
      });
    });
  });

  group('Hidden toggle and Filter', () {
    testWidgets('hidden toggle shows hidden files', (tester) async {
      final svc = _FakeFiles(fakeListing: _listing());
      await _pump(tester, svc, const Size(1400, 900));

      // Hidden file not visible by default
      expect(find.text('.hidden'), findsNothing);

      // Toggle hidden
      await tester.tap(find.bySemanticsLabel('Show hidden files'));
      await tester.pump();

      expect(svc.showHidden, isTrue);
    });

    testWidgets('filter filters this folder and shows No match state', (tester) async {
      final svc = _FakeFiles(fakeListing: _listing());
      await _pump(tester, svc, const Size(1400, 900));

      await tester.enterText(find.byType(TextField), 'xyz');
      await tester.pumpAndSettle();

      expect(find.text('Nothing matches "xyz"'), findsOneWidget);
      expect(find.text('Try a shorter word. The filter only looks in this folder.'), findsOneWidget);

      // Clear filter button restores items
      await tester.tap(find.text('Clear filter'));
      await tester.pumpAndSettle();

      expect(find.text('docs'), findsOneWidget);
    });

    testWidgets('empty folder shows exact empty state text', (tester) async {
      final svc = _FakeFiles(
        fakeListing: const DirectoryListingModel(
          path: '/home/archangel/empty',
          parent: '/home/archangel',
          entries: [],
          totalEntries: 0,
          readable: true,
        ),
      );
      await _pump(tester, svc, const Size(1400, 900));

      expect(find.text('This folder is empty'), findsOneWidget);
      expect(find.text('Nothing has been saved here yet.'), findsOneWidget);
    });

    testWidgets('folder with only hidden files shows Only hidden files here', (tester) async {
      final svc = _FakeFiles(
        fakeListing: DirectoryListingModel(
          path: '/home/archangel/hiddenonly',
          parent: '/home/archangel',
          entries: [_entry('.secret')],
          totalEntries: 1,
          readable: true,
        ),
      );
      await _pump(tester, svc, const Size(1400, 900));

      expect(find.text('Only hidden files here'), findsOneWidget);
      expect(find.widgetWithText(AxButton, 'Show hidden files'), findsOneWidget);

      await tester.tap(find.widgetWithText(AxButton, 'Show hidden files'));
      await tester.pump();

      expect(svc.showHidden, isTrue);
    });
  });

  group('States (403 and Error)', () {
    testWidgets('403 shows not-allowed and the back button loads root', (tester) async {
      final svc = _FakeFiles(fakeError: '403 Forbidden: outside files_root', fakeRoot: '/home/archangel');
      await _pump(tester, svc, const Size(1400, 900));

      expect(find.text('This folder is off limits'), findsOneWidget);
      expect(
        find.text('Files only shows what\'s inside /home/archangel, to keep system files safe. Use the terminal to look elsewhere.'),
        findsOneWidget,
      );
      expect(find.text('Back to /home/archangel'), findsOneWidget);
      expect(find.text('Open terminal'), findsOneWidget);

      await tester.tap(find.text('Back to /home/archangel'));
      await tester.pump();

      expect(svc.loaded, contains(''));
    });

    testWidgets('error shows Retry button which retries', (tester) async {
      final svc = _FakeFiles(fakeError: 'Connection failed');
      await _pump(tester, svc, const Size(1400, 900));

      expect(find.text('Couldn\'t open this folder'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pump();

      expect(svc.retries, 1);
    });
  });

  group('Preview rendering', () {
    testWidgets('text preview shows truncation footer when truncated', (tester) async {
      final svc = _FakeFiles(
        fakeListing: _listing(),
        fakeFileContent: const FileContentResult(
          path: '/home/archangel/projects/notes/notes.txt',
          name: 'notes.txt',
          sizeBytes: 4000,
          lines: ['Line 1', 'Line 2'],
          lineCount: 2,
          truncated: true,
          isBinary: false,
          mimeType: 'text/plain',
        ),
      );

      await _pump(tester, svc, const Size(1400, 900));
      await tester.tap(find.text('notes.txt'));
      await tester.pump();

      expect(find.text('Showing the first 400 lines. Download to see the whole file.'), findsOneWidget);
    });

    testWidgets('image preview renders image from bytes', (tester) async {
      // 1x1 transparent PNG bytes
      final pngBytes = Uint8List.fromList([
        0x89,
        0x50,
        0x4E,
        0x47,
        0x0D,
        0x0A,
        0x1A,
        0x0A,
        0x00,
        0x00,
        0x00,
        0x0D,
        0x49,
        0x48,
        0x44,
        0x52,
        0x00,
        0x00,
        0x00,
        0x01,
        0x00,
        0x00,
        0x00,
        0x01,
        0x08,
        0x06,
        0x00,
        0x00,
        0x00,
        0x1F,
        0x15,
        0xC4,
        0x89,
        0x00,
        0x00,
        0x00,
        0x0A,
        0x49,
        0x44,
        0x41,
        0x54,
        0x78,
        0x9C,
        0x63,
        0x00,
        0x01,
        0x00,
        0x00,
        0x05,
        0x00,
        0x01,
        0x0D,
        0x0A,
        0x2D,
        0xB4,
        0x00,
        0x00,
        0x00,
        0x00,
        0x49,
        0x45,
        0x4E,
        0x44,
        0xAE,
        0x42,
        0x60,
        0x82,
      ]);

      final svc = _FakeFiles(fakeListing: _listing(), fakeBytes: pngBytes);

      await _pump(tester, svc, const Size(1400, 900));
      await tester.tap(find.text('photo.jpg'));
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Preview of photo.jpg'), findsOneWidget);
    });

    testWidgets('binary / non-previewable file shows no preview text', (tester) async {
      final svc = _FakeFiles(
        fakeListing: _listing(),
        fakeFileContent: const FileContentResult(
          path: '/home/archangel/projects/notes/notes.txt',
          name: 'notes.txt',
          sizeBytes: 1000,
          lines: [],
          lineCount: 0,
          truncated: false,
          isBinary: true,
          mimeType: 'application/octet-stream',
        ),
      );

      await _pump(tester, svc, const Size(1400, 900));
      await tester.tap(find.text('notes.txt'));
      await tester.pump();

      expect(find.text('There\'s no preview for this kind of file. Download it to open it on this device.'), findsOneWidget);
    });
  });

  group('Upload and Private Link', () {
    testWidgets('buttons hidden when service reports unsupported', (tester) async {
      final svc = _FakeFiles(
        fakeListing: _listing(),
        fakeSupportsUpload: false,
        fakeSupportsPrivateLink: false,
        fakeFileContent: const FileContentResult(
          path: '/home/archangel/projects/notes/notes.txt',
          name: 'notes.txt',
          sizeBytes: 1000,
          lines: ['hi'],
          lineCount: 1,
          truncated: false,
          isBinary: false,
          mimeType: 'text/plain',
        ),
      );

      await _pump(tester, svc, const Size(1400, 900));

      expect(find.byTooltip('Upload'), findsNothing);

      await tester.tap(find.text('notes.txt'));
      await tester.pump();

      expect(find.widgetWithText(AxButton, 'Copy private link'), findsNothing);
    });

    testWidgets('progress card and done snackbar with a fake service', (tester) async {
      final svc = _FakeFiles(fakeListing: _listing(), fakeSupportsUpload: true);

      await _pump(tester, svc, const Size(1400, 900));

      expect(find.byTooltip('Upload'), findsOneWidget);
      await tester.tap(find.byTooltip('Upload'));
      await tester.pump();

      expect(find.text('Uploaded 1 file'), findsOneWidget);
    });
  });

  group('Helpers', () {
    test('buildCrumbs handles root, subfolders and narrow collapse', () {
      final crumbs = buildCrumbs('/home/archangel/a/b', rootPath: '/home/archangel');
      expect(crumbs.map((c) => c.label), ['/home/archangel', 'a', 'b']);
      expect(crumbs.last.isCurrent, isTrue);

      final collapsed = buildCrumbs('/home/archangel/a/b', rootPath: '/home/archangel', collapseNarrow: true);
      expect(collapsed.map((c) => c.label), ['…', 'b']);
    });

    test('formatFileDate formats today, this year, and older', () {
      final now = DateTime(2026, 10, 21, 12, 0);

      expect(formatFileDate('2026-10-21T09:41:00Z', now: now), 'Today, 09:41');
      expect(formatFileDate('2026-10-18T22:10:00Z', now: now), '18 Oct, 22:10');
      expect(formatFileDate('2025-09-02T10:00:00Z', now: now), '2 Sep 2025');
    });

    test('sortEntries keeps folders first', () {
      final entries = [
        _entry('b.txt', sizeBytes: 500, mtime: 'Sep 01 10:00'),
        _entry('folder_b', kind: 'dir'),
        _entry('a.txt', sizeBytes: 1500, mtime: 'Oct 01 10:00'),
        _entry('folder_a', kind: 'dir'),
      ];

      final byName = sortEntries(entries, sort: FilesSortChoice.name);
      expect(byName.map((e) => e.name), ['folder_a', 'folder_b', 'a.txt', 'b.txt']);

      final byLargest = sortEntries(entries, sort: FilesSortChoice.largest);
      expect(byLargest.map((e) => e.name), ['folder_a', 'folder_b', 'a.txt', 'b.txt']);
    });

    test('fileIconFor categorizes various file types', () {
      expect(fileIconFor(_entry('folder', kind: 'dir')), Icons.folder_rounded);
      expect(fileIconFor(_entry('movie.mp4')), Icons.movie_outlined);
      expect(fileIconFor(_entry('song.mp3')), Icons.audio_file_outlined);
      expect(fileIconFor(_entry('archive.zip')), Icons.folder_zip_outlined);
      expect(fileIconFor(_entry('doc.pdf')), Icons.picture_as_pdf_outlined);
      expect(fileIconFor(_entry('code.dart')), Icons.description_outlined);
      expect(fileIconFor(_entry('unknown.xyz')), Icons.insert_drive_file_outlined);
    });
  });
}
