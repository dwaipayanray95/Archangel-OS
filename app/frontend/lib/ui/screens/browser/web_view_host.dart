import 'dart:async';

import 'package:flutter/widgets.dart';

/// Why a page failed to load, in terms the screen can explain.
enum AxWebErrorKind { notFound, timeout, certificate, offline, other }

class AxWebError {
  const AxWebError(this.kind);

  final AxWebErrorKind kind;
}

enum AxWebNavigationKind {
  /// A navigation began (the address may still redirect).
  started,

  /// The page's address was committed.
  committed,

  /// The page finished loading.
  finished,

  /// The page could not be loaded; see [AxWebNavigation.error].
  failed,

  /// The controller refused to follow [AxWebNavigation.url] (a scheme the
  /// browser does not open).
  blocked,
}

/// Something that happened in a web view.
@immutable
class AxWebNavigation {
  const AxWebNavigation(this.kind, this.url, {this.isMainFrame = true, this.isRedirect = false, this.error});

  final AxWebNavigationKind kind;
  final Uri url;
  final bool isMainFrame;
  final bool isRedirect;
  final AxWebError? error;
}

/// One browser tab's page, as the screen sees it.
///
/// This is the whole seam to the platform web view: the screen never touches
/// a plugin type. State changes call [notifyListeners]; things that happened
/// arrive on [onNavigation]. `flutter test` has no web view, so tests use a
/// fake of this class and nothing in the suite mounts the real one.
abstract class AxWebController extends ChangeNotifier {
  /// Starts loading [url].
  Future<void> load(Uri url);
  Future<void> reload();
  Future<void> stop();
  Future<void> goBack();
  Future<void> goForward();

  bool get canGoBack;
  bool get canGoForward;

  /// The address of the page (or the one being loaded); null before the first load.
  Uri? get currentUrl;
  String? get title;
  Uri? get faviconUrl;

  /// Load progress from 0 to 1; only meaningful while [isLoading].
  double get progress;
  bool get isLoading;

  Stream<AxWebNavigation> get onNavigation;

  /// The widget that shows the page. It may be built, disposed and built
  /// again (narrow windows only mount the selected tab); the controller then
  /// reloads its last address.
  Widget buildView(BuildContext context);
}

/// Makes the controller for a new tab.
typedef AxWebControllerFactory = AxWebController Function();

/// Where the app gets its controllers. `main.dart` installs the real one at
/// start-up; tests install a fake. Nothing here knows about any plugin.
class AxWebControllers {
  AxWebControllers._();

  static AxWebControllerFactory? factory;

  static AxWebController create() {
    final f = factory;
    if (f == null) throw StateError('No web controller factory is installed.');
    return f();
  }
}

/// Renders [controller]'s page, clipped to its box.
class AxWebViewHost extends StatelessWidget {
  const AxWebViewHost({super.key, required this.controller});

  final AxWebController controller;

  @override
  Widget build(BuildContext context) => ClipRect(child: controller.buildView(context));
}
