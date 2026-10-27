// The real web view. This is the ONLY file that imports the web view plugin.
// `flutter test` has no web view platform, so nothing in the suite reaches
// this file's widget; tests use a fake AxWebController instead.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'browser_url.dart';
import 'web_view_host.dart';

/// An [AxWebController] over `flutter_inappwebview` (macOS and Android).
///
/// It never reads or writes cookies: logins stay in the platform web view on
/// this device.
class InAppWebController extends AxWebController {
  InAppWebController();

  /// Install this at start-up: `AxWebControllers.factory = InAppWebController.new;`
  static AxWebController create() => InAppWebController();

  final StreamController<AxWebNavigation> _events = StreamController<AxWebNavigation>.broadcast();
  InAppWebViewController? _web;
  Uri? _url;
  Uri? _pending; // loaded when the view is (re)created
  String? _title;
  Uri? _favicon;
  double _progress = 0;
  bool _loading = false;
  bool _canBack = false;
  bool _canForward = false;
  bool _disposed = false;

  @override
  bool get canGoBack => _canBack;
  @override
  bool get canGoForward => _canForward;
  @override
  Uri? get currentUrl => _url;
  @override
  String? get title => _title;
  @override
  Uri? get faviconUrl => _favicon;
  @override
  double get progress => _progress;
  @override
  bool get isLoading => _loading;
  @override
  Stream<AxWebNavigation> get onNavigation => _events.stream;

  void _emit(AxWebNavigation e) {
    if (!_events.isClosed) _events.add(e);
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  Future<void> load(Uri url) async {
    _url = url;
    _pending = url;
    _title = null;
    _favicon = null;
    _loading = true;
    _progress = 0;
    _changed();
    await _web?.loadUrl(urlRequest: URLRequest(url: WebUri(url.toString())));
  }

  @override
  Future<void> reload() async {
    final web = _web;
    if (web == null) {
      final url = _pending ?? _url;
      if (url != null) await load(url);
      return;
    }
    _loading = true;
    _progress = 0;
    _changed();
    await web.reload();
  }

  @override
  Future<void> stop() async {
    _loading = false;
    _changed();
    await _web?.stopLoading();
  }

  @override
  Future<void> goBack() async => _web?.goBack();

  @override
  Future<void> goForward() async => _web?.goForward();

  Future<void> _refreshHistory() async {
    final web = _web;
    if (web == null) return;
    try {
      final back = await web.canGoBack();
      final forward = await web.canGoForward();
      if (back != _canBack || forward != _canForward) {
        _canBack = back;
        _canForward = forward;
        _changed();
      }
    } catch (_) {}
  }

  Future<void> _refreshFavicon() async {
    try {
      final icons = await _web?.getFavicons();
      if (icons == null || icons.isEmpty) return;
      icons.sort((a, b) => (b.width ?? 0).compareTo(a.width ?? 0));
      _favicon = Uri.tryParse(icons.first.url.toString());
      _changed();
    } catch (_) {
      // Not every platform can list icons; the tab shows a globe instead.
    }
  }

  AxWebError? _mapError(WebResourceError error) {
    final t = error.type;
    if (t == WebResourceErrorType.CANCELLED) return null; // Stop, or a new load replaced this one
    if (t == WebResourceErrorType.HOST_LOOKUP) return const AxWebError(AxWebErrorKind.notFound);
    if (t == WebResourceErrorType.TIMEOUT) return const AxWebError(AxWebErrorKind.timeout);
    if (t == WebResourceErrorType.NOT_CONNECTED_TO_INTERNET || t == WebResourceErrorType.NETWORK_CONNECTION_LOST) {
      return const AxWebError(AxWebErrorKind.offline);
    }
    if (t == WebResourceErrorType.FAILED_SSL_HANDSHAKE ||
        t == WebResourceErrorType.SECURE_CONNECTION_FAILED ||
        t == WebResourceErrorType.SERVER_CERTIFICATE_UNTRUSTED ||
        t == WebResourceErrorType.SERVER_CERTIFICATE_HAS_BAD_DATE ||
        t == WebResourceErrorType.SERVER_CERTIFICATE_HAS_UNKNOWN_ROOT ||
        t == WebResourceErrorType.SERVER_CERTIFICATE_NOT_YET_VALID) {
      return const AxWebError(AxWebErrorKind.certificate);
    }
    return const AxWebError(AxWebErrorKind.other);
  }

  @override
  Widget buildView(BuildContext context) => _InAppWebViewShell(controller: this);

  @override
  void dispose() {
    _disposed = true;
    _web = null;
    _events.close();
    super.dispose();
  }
}

class _InAppWebViewShell extends StatefulWidget {
  const _InAppWebViewShell({required this.controller});

  final InAppWebController controller;

  @override
  State<_InAppWebViewShell> createState() => _InAppWebViewShellState();
}

class _InAppWebViewShellState extends State<_InAppWebViewShell> {
  InAppWebController get c => widget.controller;

  @override
  void dispose() {
    // The platform view is going away; keep the address so a new view reloads it.
    c._web = null;
    c._loading = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final start = c._pending ?? c._url;
    return InAppWebView(
      initialUrlRequest: start == null ? null : URLRequest(url: WebUri(start.toString())),
      initialSettings: InAppWebViewSettings(
        useShouldOverrideUrlLoading: true,
        javaScriptCanOpenWindowsAutomatically: false,
        supportMultipleWindows: false,
        isInspectable: kDebugMode,
      ),
      onWebViewCreated: (web) => c._web = web,
      shouldOverrideUrlLoading: (web, action) async {
        final uri = action.request.url == null ? null : Uri.tryParse(action.request.url.toString());
        if (uri != null && isAllowedBrowserUri(uri)) return NavigationActionPolicy.ALLOW;
        if (action.isForMainFrame && uri != null) c._emit(AxWebNavigation(AxWebNavigationKind.blocked, uri));
        return NavigationActionPolicy.CANCEL;
      },
      onLoadStart: (web, url) {
        final uri = url == null ? null : Uri.tryParse(url.toString());
        if (uri == null) return;
        c._url = uri;
        c._pending = uri;
        c._loading = true;
        c._progress = 0;
        c._changed();
        c._emit(AxWebNavigation(AxWebNavigationKind.started, uri));
      },
      onUpdateVisitedHistory: (web, url, isReload) {
        final uri = url == null ? null : Uri.tryParse(url.toString());
        if (uri == null) return;
        c._url = uri;
        c._pending = uri;
        c._emit(AxWebNavigation(AxWebNavigationKind.committed, uri));
        c._refreshHistory();
      },
      onProgressChanged: (web, percent) {
        c._progress = percent / 100;
        c._loading = percent < 100;
        c._changed();
      },
      onTitleChanged: (web, title) {
        c._title = title;
        c._changed();
      },
      onLoadStop: (web, url) async {
        c._loading = false;
        c._progress = 1;
        c._changed();
        final uri = url == null ? c._url : Uri.tryParse(url.toString());
        if (uri != null) c._emit(AxWebNavigation(AxWebNavigationKind.finished, uri));
        c._title = await web.getTitle() ?? c._title;
        c._changed();
        await c._refreshHistory();
        await c._refreshFavicon();
      },
      onReceivedError: (web, request, error) {
        if (request.isForMainFrame == false) return;
        final mapped = c._mapError(error);
        c._loading = false;
        c._changed();
        final uri = Uri.tryParse(request.url.toString()) ?? c._url;
        if (mapped == null || uri == null) return;
        c._emit(AxWebNavigation(AxWebNavigationKind.failed, uri, error: mapped));
      },
    );
  }
}
