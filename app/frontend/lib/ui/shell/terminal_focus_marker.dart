import 'package:flutter/widgets.dart';

/// Wraps a terminal so the shell can tell when keyboard focus is inside one.
///
/// xterm's `TerminalView` is not an `EditableText`, so the desktop shortcut
/// handler could not see it. The terminal needs keys like Alt+Arrow (word
/// jump) and Ctrl+Alt+Arrow (tmux/vim) for itself.
class TerminalFocusMarker extends InheritedWidget {
  const TerminalFocusMarker({super.key, required super.child});

  /// True when the primary focus sits inside a [TerminalFocusMarker].
  static bool isFocusInside() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    return ctx?.getInheritedWidgetOfExactType<TerminalFocusMarker>() != null;
  }

  @override
  bool updateShouldNotify(TerminalFocusMarker oldWidget) => false;
}
