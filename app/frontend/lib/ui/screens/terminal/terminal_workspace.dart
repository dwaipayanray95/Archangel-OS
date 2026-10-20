import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import '../../../services/terminal_session.dart';
import '../../components/ax_icon_button.dart';
import '../../theme.dart';
import 'terminal_accessory_bar.dart';
import 'terminal_pane.dart';

const double kTerminalMinFont = 10;
const double kTerminalMaxFont = 24;
const double kTerminalDefaultFont = 14;

/// The terminal's chrome (session chips + actions) around the selected
/// session's [TerminalPane]. Holds no session state itself: the screen owns
/// the sessions and passes callbacks, which keeps this widget easy to test.
class TerminalWorkspace extends StatelessWidget {
  const TerminalWorkspace({
    super.key,
    required this.sessions,
    required this.selected,
    required this.controllerFor,
    required this.fontSize,
    required this.onSelect,
    required this.onDetach,
    required this.onEnd,
    required this.onNew,
    required this.onShowSessions,
    required this.onFontSize,
    required this.onCopy,
    required this.onPaste,
  });

  final List<TerminalSession> sessions;
  final int selected;
  final TerminalController Function(TerminalSession) controllerFor;
  final double fontSize;
  final ValueChanged<int> onSelect;
  final ValueChanged<int> onDetach;
  final ValueChanged<int> onEnd;
  final VoidCallback onNew;
  final VoidCallback onShowSessions;
  final ValueChanged<double> onFontSize;
  final VoidCallback onCopy;
  final VoidCallback onPaste;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final phone = MediaQuery.sizeOf(context).width < kTerminalPhoneWidth;
    final current = sessions[selected];

    final tabs = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < sessions.length; i++)
            _SessionChip(session: sessions[i], selected: i == selected, onTap: () => onSelect(i), onDetach: () => onDetach(i)),
        ],
      ),
    );

    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AxIconButton(icon: Icons.add, tooltip: 'New session', onPressed: onNew),
        AxIconButton(icon: Icons.list_alt_outlined, tooltip: 'Sessions on this server', onPressed: onShowSessions),
        AxIconButton(icon: Icons.copy_outlined, tooltip: 'Copy selected text', onPressed: onCopy),
        AxIconButton(icon: Icons.content_paste_outlined, tooltip: 'Paste', onPressed: onPaste),
        AxIconButton(
          icon: Icons.text_decrease,
          tooltip: 'Smaller text',
          onPressed: fontSize > kTerminalMinFont ? () => onFontSize(fontSize - 1) : null,
        ),
        AxIconButton(
          icon: Icons.text_increase,
          tooltip: 'Larger text',
          onPressed: fontSize < kTerminalMaxFont ? () => onFontSize(fontSize + 1) : null,
        ),
        AxIconButton(icon: Icons.power_settings_new, tooltip: 'End session', color: c.danger, onPressed: () => onEnd(selected)),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(color: c.surface, border: Border(bottom: BorderSide(color: c.border))),
          padding: EdgeInsets.symmetric(horizontal: ax.space.sm, vertical: ax.space.xs),
          child:
              phone
                  ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [tabs, SingleChildScrollView(scrollDirection: Axis.horizontal, child: actions)],
                  )
                  : Row(children: [Expanded(child: tabs), SizedBox(width: ax.space.sm), actions]),
        ),
        Expanded(child: TerminalPane(key: ValueKey(current), session: current, controller: controllerFor(current), fontSize: fontSize)),
      ],
    );
  }
}

class _SessionChip extends StatelessWidget {
  const _SessionChip({required this.session, required this.selected, required this.onTap, required this.onDetach});

  final TerminalSession session;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDetach;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final target = axMinTarget(context);
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final (IconData icon, Color color, String word) = switch (session.status) {
          SessionStatus.connected => (Icons.check_circle_outline, c.success, 'connected'),
          SessionStatus.connecting => (Icons.sync, c.warning, 'connecting'),
          SessionStatus.error => (Icons.error_outline, c.danger, 'connection problem'),
          SessionStatus.closed => (Icons.stop_circle_outlined, c.textMuted, 'ended'),
        };
        return Padding(
          padding: EdgeInsets.only(right: ax.space.xs),
          child: Material(
            color: selected ? c.accentWash : Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(ax.radii.md),
              side: BorderSide(color: selected ? c.accent : c.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  button: true,
                  selected: selected,
                  label: 'Session ${session.label}, $word',
                  excludeSemantics: true,
                  onTap: onTap,
                  child: InkWell(
                    key: ValueKey('terminal-chip-${session.label}'),
                    customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ax.radii.md)),
                    onTap: onTap,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: target),
                      child: Padding(
                        padding: EdgeInsets.only(left: ax.space.md, right: ax.space.sm),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(icon, size: 16, color: color),
                            SizedBox(width: ax.space.sm),
                            Text(
                              session.label,
                              style: ax.typo.mono.copyWith(
                                color: selected ? c.text : c.textMuted,
                                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                AxIconButton(icon: Icons.close, tooltip: 'Detach — keeps running', onPressed: onDetach),
              ],
            ),
          ),
        );
      },
    );
  }
}
