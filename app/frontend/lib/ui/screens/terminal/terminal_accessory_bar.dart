import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import '../../../services/terminal_session.dart';
import '../../theme.dart';
import 'terminal_palette.dart';

/// Widths below this show the on-screen key bar (matches the shell's phone breakpoint).
const double kTerminalPhoneWidth = 720;

/// Keys a phone keyboard lacks: Snippets, Esc, Tab, a sticky Ctrl, arrows and the
/// punctuation shells need. Everything goes through the emulator, so the
/// escape sequences match what the running program expects.
class TerminalAccessoryBar extends StatelessWidget {
  const TerminalAccessoryBar({super.key, required this.session, this.onSnippets});

  final TerminalSession session;
  final VoidCallback? onSnippets;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final tp = context.terminalPalette;
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        return Container(
          key: const ValueKey('terminal-accessory-bar'),
          decoration: BoxDecoration(
            color: tp.barBg,
            border: Border(top: BorderSide(color: tp.line)),
          ),
          padding: EdgeInsets.symmetric(horizontal: ax.space.xs, vertical: ax.space.xs),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _Key(icon: Icons.code, tooltip: 'Snippets', onTap: onSnippets ?? () {}),
                _Key(label: 'Esc', tooltip: 'Escape', onTap: () => session.pressKey(TerminalKey.escape)),
                _Key(label: 'Tab', tooltip: 'Tab', onTap: () => session.pressKey(TerminalKey.tab)),
                _Key(
                  label: 'Ctrl',
                  tooltip: 'Control (applies to the next key)',
                  active: session.ctrlLatched,
                  onTap: () => session.ctrlLatched = !session.ctrlLatched,
                ),
                _Key(icon: Icons.arrow_back, tooltip: 'Left arrow', onTap: () => session.pressKey(TerminalKey.arrowLeft)),
                _Key(icon: Icons.arrow_upward, tooltip: 'Up arrow', onTap: () => session.pressKey(TerminalKey.arrowUp)),
                _Key(icon: Icons.arrow_downward, tooltip: 'Down arrow', onTap: () => session.pressKey(TerminalKey.arrowDown)),
                _Key(icon: Icons.arrow_forward, tooltip: 'Right arrow', onTap: () => session.pressKey(TerminalKey.arrowRight)),
                _Key(label: '|', tooltip: 'Pipe', onTap: () => session.typeText('|')),
                _Key(label: '~', tooltip: 'Tilde', onTap: () => session.typeText('~')),
                _Key(label: '/', tooltip: 'Slash', onTap: () => session.typeText('/')),
                _Key(label: '-', tooltip: 'Dash', onTap: () => session.typeText('-')),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({this.label, this.icon, required this.tooltip, required this.onTap, this.active = false})
    : assert(label != null || icon != null);

  final String? label;
  final IconData? icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final tp = context.terminalPalette;
    final fg = active ? (tp.isDark ? const Color(0xFF0B0D1A) : Colors.white) : tp.text;
    final bg = active ? tp.accent : (tp.isDark ? tp.tabSelectedBg : tp.bg);
    final border = active ? tp.accent : tp.line;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Semantics(
        button: true,
        toggled: label == 'Ctrl' ? active : null,
        label: tooltip,
        excludeSemantics: true,
        onTap: onTap,
        child: Tooltip(
          message: tooltip,
          child: Material(
            color: bg,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(ax.radii.sm),
              side: BorderSide(color: border),
            ),
            child: InkWell(
              customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ax.radii.sm)),
              onTap: onTap,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: icon != null
                        ? Icon(icon, size: 20, color: fg)
                        : Text(
                            label!,
                            style: ax.typo.mono.copyWith(fontWeight: FontWeight.w600, color: fg),
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
