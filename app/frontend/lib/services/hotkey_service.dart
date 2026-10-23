import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'window_service.dart';

/// Service managing OS-level global hotkeys via `package:hotkey_manager`.
/// Global hotkeys respond even when Archangel OS is in the background or minimized.
class HotkeyService {
  static bool _initialized = false;

  /// Returns true if running on a real desktop platform (not in headless test runner).
  static bool get isDesktop =>
      !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux) && !Platform.environment.containsKey('FLUTTER_TEST');

  /// Callbacks for global actions.
  static VoidCallback? onSummon;
  static VoidCallback? onQuickTerminal;
  static VoidCallback? onSwitchServer;

  /// Registered hotkeys.
  static HotKey? _summonHotKey;
  static HotKey? _terminalHotKey;
  static HotKey? _serverHotKey;

  /// Initializes global hotkeys on desktop.
  static Future<void> init({VoidCallback? onSummonAction, VoidCallback? onQuickTerminalAction, VoidCallback? onSwitchServerAction}) async {
    onSummon = onSummonAction ?? onSummon;
    onQuickTerminal = onQuickTerminalAction ?? onQuickTerminal;
    onSwitchServer = onSwitchServerAction ?? onSwitchServer;

    if (!isDesktop || _initialized) return;

    try {
      await hotKeyManager.unregisterAll();
      _initialized = true;

      final isMac = Platform.isMacOS;

      // 1. Global Summon Hotkey: Option + Space (or Alt + Space on Windows/Linux)
      _summonHotKey = HotKey(key: LogicalKeyboardKey.space, modifiers: [HotKeyModifier.alt], scope: HotKeyScope.system);
      await hotKeyManager.register(
        _summonHotKey!,
        keyDownHandler: (_) async {
          await _bringToFront();
          onSummon?.call();
        },
      );

      // 2. Global Quick Terminal: Option + Backtick (~)
      _terminalHotKey = HotKey(key: LogicalKeyboardKey.backquote, modifiers: [HotKeyModifier.alt], scope: HotKeyScope.system);
      await hotKeyManager.register(
        _terminalHotKey!,
        keyDownHandler: (_) async {
          await _bringToFront();
          onQuickTerminal?.call();
        },
      );

      // 3. Global Quick Server Switch: Option + Shift + S
      _serverHotKey = HotKey(
        key: LogicalKeyboardKey.keyS,
        modifiers: isMac ? [HotKeyModifier.meta, HotKeyModifier.alt] : [HotKeyModifier.control, HotKeyModifier.alt],
        scope: HotKeyScope.system,
      );
      await hotKeyManager.register(
        _serverHotKey!,
        keyDownHandler: (_) async {
          await _bringToFront();
          onSwitchServer?.call();
        },
      );
    } catch (e) {
      debugPrint('HotkeyService.init error: $e');
    }
  }

  /// Brings the Archangel OS window to the front and focuses it.
  static Future<void> _bringToFront() async {
    if (!WindowService.isDesktop) return;
    try {
      await WindowService.maximize(); // or unminimize if minimized
    } catch (_) {}
  }

  /// Unregisters all system hotkeys when closing or disabling.
  static Future<void> dispose() async {
    if (!isDesktop) return;
    try {
      await hotKeyManager.unregisterAll();
      _initialized = false;
    } catch (_) {}
  }
}
