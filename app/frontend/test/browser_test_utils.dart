import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:archangel/data/app_state.dart';
import 'package:archangel/screens/browser_screen.dart';
import 'package:archangel/services/archangeld_connection.dart';
import 'package:archangel/services/browser_service.dart';
import 'package:archangel/ui/screens/browser/web_view_host.dart';
import 'package:archangel/ui/theme.dart';

/// Stands in for the platform web view in every browser test. Nothing in the
/// suite mounts the real one.
class FakeWebController extends AxWebController {
  FakeWebController({this.autoFinish = true});

  /// When true, [load] commits and finishes at once. Set false to hold a page
  /// in the loading state, then call [finishLoading].
  bool autoFinish;

  final loaded = <Uri>[];
  int reloads = 0;
  int stops = 0;
  int backs = 0;
  int forwards = 0;

  /// How many of this controller's views are in the tree right now.
  int mounted = 0;

  /// How many views were ever built.
  int mountCount = 0;

  /// Titles by host; anything else gets the host as its title.
  final titles = <String, String>{};

  final _events = StreamController<AxWebNavigation>.broadcast(sync: true);
  Uri? _url;
  String? _title;
  double _progress = 0;
  bool _loading = false;
  bool _back = false;
  bool _forward = false;
  bool _disposed = false;

  bool get disposed => _disposed;

  @override
  bool get canGoBack => _back;
  @override
  bool get canGoForward => _forward;
  @override
  Uri? get currentUrl => _url;
  @override
  String? get title => _title;
  @override
  Uri? get faviconUrl => null;
  @override
  double get progress => _progress;
  @override
  bool get isLoading => _loading;
  @override
  Stream<AxWebNavigation> get onNavigation => _events.stream;

  void emit(AxWebNavigation e) => _events.add(e);

  void setHistory({bool back = false, bool forward = false}) {
    _back = back;
    _forward = forward;
    notifyListeners();
  }

  void setProgress(double p) {
    _loading = true;
    _progress = p;
    notifyListeners();
  }

  /// The page the person is on changed by itself (a link, a redirect).
  void navigateInPage(Uri url, {bool redirect = false, bool mainFrame = true}) {
    emit(AxWebNavigation(AxWebNavigationKind.started, url, isMainFrame: mainFrame));
    if (mainFrame) {
      _url = url;
      _title = titles[url.host] ?? url.host;
    }
    notifyListeners();
    emit(AxWebNavigation(AxWebNavigationKind.committed, url, isMainFrame: mainFrame, isRedirect: redirect));
    emit(AxWebNavigation(AxWebNavigationKind.finished, url, isMainFrame: mainFrame));
  }

  void finishLoading() {
    _loading = false;
    _progress = 1;
    notifyListeners();
    final u = _url;
    if (u != null) emit(AxWebNavigation(AxWebNavigationKind.finished, u));
  }

  void fail(AxWebErrorKind kind) {
    _loading = false;
    notifyListeners();
    emit(AxWebNavigation(AxWebNavigationKind.failed, _url ?? Uri.parse('https://example.com'), error: AxWebError(kind)));
  }

  @override
  Future<void> load(Uri url) async {
    loaded.add(url);
    _url = url;
    _title = titles[url.host] ?? (url.host.isEmpty ? null : url.host);
    _loading = true;
    _progress = 0.1;
    notifyListeners();
    emit(AxWebNavigation(AxWebNavigationKind.started, url));
    if (url.scheme == 'http' || url.scheme == 'https') {
      emit(AxWebNavigation(AxWebNavigationKind.committed, url));
    }
    if (autoFinish) finishLoading();
  }

  @override
  Future<void> reload() async {
    reloads++;
    final u = _url;
    if (u == null) return;
    emit(AxWebNavigation(AxWebNavigationKind.started, u));
    emit(AxWebNavigation(AxWebNavigationKind.committed, u));
    if (autoFinish) finishLoading();
  }

  @override
  Future<void> stop() async {
    stops++;
    _loading = false;
    notifyListeners();
  }

  @override
  Future<void> goBack() async {
    backs++;
  }

  @override
  Future<void> goForward() async {
    forwards++;
  }

  @override
  Widget buildView(BuildContext context) => _FakeView(controller: this);

  @override
  void dispose() {
    _disposed = true;
    _events.close();
    super.dispose();
  }
}

class _FakeView extends StatefulWidget {
  const _FakeView({required this.controller});

  final FakeWebController controller;

  @override
  State<_FakeView> createState() => _FakeViewState();
}

class _FakeViewState extends State<_FakeView> {
  @override
  void initState() {
    super.initState();
    widget.controller
      ..mounted += 1
      ..mountCount += 1;
  }

  @override
  void dispose() {
    widget.controller.mounted -= 1;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand(child: ColoredBox(color: Colors.white));
}

/// History and bookmarks held in memory, counting writes.
class MemoryBrowserStore implements BrowserStore {
  List<BrowserVisit> history = [];
  List<BrowserBookmark> bookmarks = [];
  int historyWrites = 0;
  int bookmarkWrites = 0;

  @override
  Future<List<BrowserVisit>> loadHistory() async => history;

  @override
  Future<void> saveHistory(List<BrowserVisit> visits) async {
    historyWrites++;
    history = List.of(visits);
  }

  @override
  Future<List<BrowserBookmark>> loadBookmarks() async => bookmarks;

  @override
  Future<void> saveBookmarks(List<BrowserBookmark> list) async {
    bookmarkWrites++;
    bookmarks = List.of(list);
  }
}

class PairedConnection extends ArchangeldConnection {
  @override
  bool get isPaired => true;
}

/// A service whose writes happen at once (no 2 s wait) so no timer is left pending.
BrowserService testBrowserService({BrowserStore? store, DateTime Function()? now}) =>
    BrowserService(store: store ?? MemoryBrowserStore(), now: now, writeDelay: Duration.zero);

class BrowserHarness {
  BrowserHarness(this.service);

  final BrowserService service;
  final controllers = <FakeWebController>[];

  /// Set before pumping to make every new controller hold its loads.
  bool autoFinish = true;

  FakeWebController make() {
    final c = FakeWebController(autoFinish: autoFinish);
    controllers.add(c);
    return c;
  }

  FakeWebController get first => controllers.first;
}

/// Mounts [BrowserScreen] on its own, paired, at [size].
Future<BrowserHarness> pumpBrowser(
  WidgetTester tester, {
  Size size = const Size(1400, 900),
  Brightness brightness = Brightness.dark,
  BrowserService? service,
  Key? key,
  BrowserHarness? harness,
  bool paired = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  final h = harness ?? BrowserHarness(service ?? testBrowserService());
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppState()),
        ChangeNotifierProvider<ArchangeldConnection>.value(value: paired ? PairedConnection() : ArchangeldConnection()),
        ChangeNotifierProvider<BrowserService>.value(value: h.service),
      ],
      child: MaterialApp(
        theme: buildTheme(brightness),
        home: BrowserScreen(key: key, controllerFactory: h.make),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
  return h;
}

/// Types [text] into the omnibox and submits it.
Future<void> submitOmnibox(WidgetTester tester, String text) async {
  final field = find.byKey(const ValueKey('browser-omnibox'));
  await tester.tap(field);
  await tester.pump();
  await tester.enterText(field, text);
  await tester.pumpAndSettle();
  await tester.testTextInput.receiveAction(TextInputAction.go);
  await tester.pump();
}
