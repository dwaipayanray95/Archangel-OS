import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// Platform bridge for native window operations on desktop operating systems.
/// Archangel OS is fullscreen-first by default.
class WindowService {
  static bool _initialized = false;

  /// Returns true if running on a real desktop platform (not in headless flutter test).
  static bool get isDesktop =>
      !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux) && !Platform.environment.containsKey('FLUTTER_TEST');

  /// Fallback flag for tests and non-desktop platforms.
  static bool _fallbackFullScreen = true;

  /// Optional listener for window close interception.
  static VoidCallback? onCloseRequested;

  /// Initializes the native window manager on desktop platforms.
  /// Launches fullscreen by default as Archangel OS is fullscreen first.
  static Future<void> init({bool fullScreen = true}) async {
    _fallbackFullScreen = fullScreen;
    if (!isDesktop || _initialized) return;
    try {
      await windowManager.ensureInitialized();
      _initialized = true;

      const options = WindowOptions(
        size: Size(1280, 800),
        minimumSize: Size(900, 600),
        center: true,
        backgroundColor: Colors.transparent,
        skipTaskbar: false,
        titleBarStyle: TitleBarStyle.hidden,
      );

      await windowManager.waitUntilReadyToShow(options, () async {
        if (fullScreen) {
          await windowManager.setFullScreen(true);
        }
        await windowManager.show();
        await windowManager.focus();
        await windowManager.setPreventClose(true);
      });

      windowManager.addListener(_InternalWindowListener());
    } catch (e) {
      debugPrint('WindowService.init error: $e');
    }
  }

  /// Sets fullscreen state explicitly.
  static Future<void> setFullScreen(bool fullScreen) async {
    _fallbackFullScreen = fullScreen;
    if (!isDesktop) return;
    try {
      await windowManager.setFullScreen(fullScreen);
    } catch (_) {}
  }

  /// Toggles fullscreen on desktop platforms.
  static Future<void> toggleFullScreen() async {
    if (!isDesktop) {
      _fallbackFullScreen = !_fallbackFullScreen;
      return;
    }
    try {
      final fs = await windowManager.isFullScreen();
      await windowManager.setFullScreen(!fs);
    } catch (_) {}
  }

  /// Checks if the window is currently in fullscreen mode.
  static Future<bool> isFullScreen() async {
    if (!isDesktop) return _fallbackFullScreen;
    try {
      return await windowManager.isFullScreen();
    } catch (_) {
      return _fallbackFullScreen;
    }
  }

  /// Initiates native OS window dragging (useful for custom title bar dragging when not fullscreen).
  static Future<void> startDragging() async {
    if (!isDesktop) return;
    try {
      final fs = await windowManager.isFullScreen();
      if (!fs) {
        await windowManager.startDragging();
      }
    } catch (_) {}
  }

  /// Minimizes the native OS window.
  static Future<void> minimize() async {
    if (!isDesktop) return;
    try {
      await windowManager.minimize();
    } catch (_) {}
  }

  /// Maximizes the native OS window.
  static Future<void> maximize() async {
    if (!isDesktop) return;
    try {
      await windowManager.maximize();
    } catch (_) {}
  }

  /// Restores the native OS window.
  static Future<void> unmaximize() async {
    if (!isDesktop) return;
    try {
      await windowManager.unmaximize();
    } catch (_) {}
  }

  /// Quits and closes the native OS application completely.
  static Future<void> destroy() async {
    if (!isDesktop) {
      exit(0);
    }
    try {
      await windowManager.destroy();
    } catch (_) {
      exit(0);
    }
  }
}

class _InternalWindowListener with WindowListener {
  @override
  void onWindowClose() async {
    if (WindowService.onCloseRequested != null) {
      WindowService.onCloseRequested!();
    } else {
      await windowManager.destroy();
    }
  }
}
