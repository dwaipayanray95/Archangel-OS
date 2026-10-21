import 'package:flutter/services.dart';

/// Platform bridge for native window operations (e.g. macOS / desktop fullscreen).
class WindowService {
  static const _channel = MethodChannel('archangel/window');

  /// Toggles fullscreen on desktop platforms.
  static Future<void> toggleFullScreen() async {
    try {
      await _channel.invokeMethod('toggleFullScreen');
    } catch (_) {
      // Platform doesn't implement window channel or is mobile
    }
  }

  /// Sets fullscreen state explicitly.
  static Future<void> setFullScreen(bool fullScreen) async {
    try {
      await _channel.invokeMethod('setFullScreen', {'fullScreen': fullScreen});
    } catch (_) {}
  }

  /// Checks if the window is currently in fullscreen mode.
  static Future<bool> isFullScreen() async {
    try {
      final res = await _channel.invokeMethod<bool>('isFullScreen');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }
}
