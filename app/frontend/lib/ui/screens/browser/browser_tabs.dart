import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding;

import '../../../services/browser_service.dart';
import 'browser_url.dart';
import 'web_view_host.dart';

/// At most this many tabs stay open.
const int kBrowserMaxTabs = 12;

/// What a tab's page area shows.
enum BrowserTabView { page, newTab, blocked, error, offline }

/// One tab: its web controller plus the states the controller does not know
/// about (a refused link, a failed load).
class BrowserTab extends ChangeNotifier {
  BrowserTab({required this.id, required this.controller, required BrowserService service}) : _service = service {
    _sub = controller.onNavigation.listen(_onNavigation);
    controller.addListener(_onController);
  }

  final String id;
  final AxWebController controller;
  final BrowserService _service;
  StreamSubscription<AxWebNavigation>? _sub;

  String? _blockedInput;
  AxWebError? _error;
  String? _visitId;

  /// What was refused, when the tab shows the blocked state.
  String? get blockedInput => _blockedInput;
  AxWebError? get error => _error;

  BrowserTabView get view {
    if (_blockedInput != null) return BrowserTabView.blocked;
    final e = _error;
    if (e != null) return e.kind == AxWebErrorKind.offline ? BrowserTabView.offline : BrowserTabView.error;
    if (isBlankUri(controller.currentUrl)) return BrowserTabView.newTab;
    return BrowserTabView.page;
  }

  /// The address bar text for the page.
  String get address {
    final blocked = _blockedInput;
    if (blocked != null) return blocked;
    final url = controller.currentUrl;
    return url == null || isBlankUri(url) ? '' : url.toString();
  }

  String get displayTitle {
    final t = controller.title?.trim();
    if (t != null && t.isNotEmpty && view != BrowserTabView.newTab) return t;
    final url = controller.currentUrl;
    if (url != null && url.host.isNotEmpty) return url.host;
    return 'New tab';
  }

  /// The page can be bookmarked: it is a real address and not an error.
  bool get canBookmark => view == BrowserTabView.page && controller.currentUrl != null;

  /// Opens what the person typed (an address, a search, or a refused link).
  Future<void> submit(String input) async {
    switch (resolveOmniboxInput(input)) {
      case OmniboxEmpty():
        return;
      case OmniboxBlocked(:final input):
        _block(input);
        if (controller.isLoading) unawaited(controller.stop());
      case OmniboxLoad(:final url):
        await open(url);
    }
  }

  Future<void> open(Uri url) async {
    if (!isAllowedBrowserUri(url)) {
      _block(url.toString());
      return;
    }
    _blockedInput = null;
    _error = null;
    notifyListeners();
    await controller.load(url);
  }

  /// "Back" in the blocked state: drop the notice, keep the page behind it.
  void dismissBlocked() {
    if (_blockedInput == null) return;
    _blockedInput = null;
    notifyListeners();
  }

  Future<void> retry() async {
    final url = controller.currentUrl;
    _error = null;
    notifyListeners();
    if (url == null) return;
    await controller.load(url);
  }

  /// Back, leaving any error or refused-link notice behind.
  Future<void> goBack() async {
    final hadNotice = _error != null || _blockedInput != null;
    _error = null;
    _blockedInput = null;
    if (hadNotice) notifyListeners();
    await controller.goBack();
  }

  Future<void> reload() async {
    if (_error != null) return retry();
    await controller.reload();
  }

  void _block(String input) {
    _blockedInput = input;
    _error = null;
    notifyListeners();
  }

  void _onNavigation(AxWebNavigation e) {
    if (!e.isMainFrame) return;
    switch (e.kind) {
      case AxWebNavigationKind.started:
        if (!isAllowedBrowserUri(e.url)) {
          _refuse(e.url);
        } else if (_error != null || _blockedInput != null) {
          _error = null;
          _blockedInput = null;
          notifyListeners();
        }
      case AxWebNavigationKind.committed:
        if (!isAllowedBrowserUri(e.url)) {
          _refuse(e.url);
          return;
        }
        if (!e.isRedirect && !isBlankUri(e.url)) {
          _visitId = _service.recordVisit(e.url.toString(), title: controller.title) ?? _visitId;
        }
      case AxWebNavigationKind.finished:
        break;
      case AxWebNavigationKind.failed:
        _error = e.error ?? const AxWebError(AxWebErrorKind.other);
        notifyListeners();
      case AxWebNavigationKind.blocked:
        _block(e.url.toString());
    }
  }

  void _refuse(Uri url) {
    unawaited(controller.stop());
    _block(url.toString());
  }

  void _onController() {
    final title = controller.title;
    final id = _visitId;
    if (id != null && title != null && title.isNotEmpty) _service.updateVisitTitle(id, title);
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    controller.removeListener(_onController);
    controller.dispose();
    super.dispose();
  }
}

/// The open tabs. Closing the last one leaves a fresh empty tab.
class BrowserTabs extends ChangeNotifier {
  BrowserTabs({required BrowserService service, AxWebControllerFactory? factory})
    : _service = service,
      _factory = factory ?? AxWebControllers.create {
    _tabs.add(_make());
  }

  final BrowserService _service;
  final AxWebControllerFactory _factory;
  final List<BrowserTab> _tabs = [];
  int _selected = 0;
  int _nextId = 1;

  List<BrowserTab> get tabs => List.unmodifiable(_tabs);
  int get selectedIndex => _selected;
  BrowserTab get selected => _tabs[_selected];
  bool get atCap => _tabs.length >= kBrowserMaxTabs;

  BrowserTab _make() => BrowserTab(id: 't${_nextId++}', controller: _factory(), service: _service);

  /// Opens an empty tab and selects it; null at the cap.
  BrowserTab? newTab() {
    if (atCap) return null;
    final tab = _make();
    _tabs.add(tab);
    _selected = _tabs.length - 1;
    notifyListeners();
    return tab;
  }

  void select(BrowserTab tab) {
    final i = _tabs.indexOf(tab);
    if (i < 0 || i == _selected) return;
    _selected = i;
    notifyListeners();
  }

  void close(BrowserTab tab) {
    final i = _tabs.indexOf(tab);
    if (i < 0) return;
    final wasSelected = i == _selected;
    _tabs.removeAt(i);
    if (_tabs.isEmpty) {
      _tabs.add(_make());
      _selected = 0;
    } else if (i < _selected || (wasSelected && _selected >= _tabs.length)) {
      _selected = (_selected - 1).clamp(0, _tabs.length - 1);
    }
    notifyListeners();
    // Disposed once the widgets have rebuilt without it.
    WidgetsBinding.instance.addPostFrameCallback((_) => tab.dispose());
  }

  @override
  void dispose() {
    for (final t in _tabs) {
      t.dispose();
    }
    _tabs.clear();
    super.dispose();
  }
}
