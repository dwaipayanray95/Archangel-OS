import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import '../../../services/terminal_session.dart';
import '../../components/ax_button.dart';
import '../../components/ax_icon_button.dart';
import '../../theme.dart';
import 'terminal_accessory_bar.dart';
import 'terminal_palette.dart';

/// The text currently selected in [session]'s terminal, or null.
String? selectedTerminalText(TerminalSession session, TerminalController controller) {
  final range = controller.selection;
  if (range == null) return null;
  final text = session.terminal.buffer.getText(range);
  return text.isEmpty ? null : text;
}

/// One session's emulator plus its status banners and (on phones) the key
/// bar. Banners sit above the emulator rather than over it so the
/// [TerminalView] stays mounted and keeps reporting its size.
class TerminalPane extends StatelessWidget {
  const TerminalPane({super.key, required this.session, required this.controller, required this.fontSize, this.focusNode});

  final TerminalSession session;
  final TerminalController controller;
  final double fontSize;
  final FocusNode? focusNode;

  static bool get _isTouchPlatform =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  @override
  Widget build(BuildContext context) {
    final phone = MediaQuery.sizeOf(context).width < kTerminalPhoneWidth;
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Banners(session: session),
            Expanded(
              child: ColoredBox(
                color: kTerminalBg,
                child: TerminalView(
                  session.terminal,
                  key: ValueKey('terminal-view-${session.name}-${session.terminalEpoch}'),
                  controller: controller,
                  focusNode: focusNode,
                  autofocus: true,
                  theme: kTerminalTheme,
                  textStyle: TerminalStyle(
                    fontSize: fontSize,
                    height: 1.25,
                    fontFamily: kMonoFontFamily,
                    fontFamilyFallback: const [
                      'Menlo',
                      'Consolas',
                      'Liberation Mono',
                      'Noto Sans Mono',
                      'Noto Sans Symbols',
                      'Noto Color Emoji',
                      'monospace',
                    ],
                  ),
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                  deleteDetection: _isTouchPlatform,
                  keyboardType: TextInputType.text,
                  cursorType: TerminalCursorType.block,
                ),
              ),
            ),
            if (phone) TerminalAccessoryBar(session: session),
          ],
        );
      },
    );
  }
}

class _Banners extends StatelessWidget {
  const _Banners({required this.session});

  final TerminalSession session;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final status = session.status;
    final children = <Widget>[];

    if (session.notice != null) {
      children.add(
        _Banner(
          key: const ValueKey('terminal-notice'),
          color: c.warningWash,
          fg: c.warning,
          icon: Icons.warning_amber_rounded,
          text: session.notice!,
          trailing: AxIconButton(icon: Icons.close, tooltip: 'Dismiss notice', color: c.warning, onPressed: session.dismissNotice),
        ),
      );
    }

    if (status == SessionStatus.error || status == SessionStatus.closed) {
      final isError = status == SessionStatus.error;
      children.add(
        _Banner(
          key: const ValueKey('terminal-status-banner'),
          color: isError ? c.dangerWash : c.surfaceAlt,
          fg: isError ? c.danger : c.textMuted,
          icon: isError ? Icons.error_outline : Icons.info_outline,
          text: isError ? (session.error ?? 'The connection failed.') : 'This session ended (exit code ${session.exitCode ?? 0}).',
          trailing: AxButton.secondary(label: 'Reconnect', icon: Icons.refresh, onPressed: session.reconnect),
        ),
      );
    } else if (status == SessionStatus.connecting) {
      children.add(
        _Banner(
          key: const ValueKey('terminal-connecting'),
          color: c.surfaceAlt,
          fg: c.textMuted,
          icon: Icons.sync,
          text: 'Connecting to your server...',
        ),
      );
    } else if (!session.hasOutput) {
      children.add(
        _Banner(
          key: const ValueKey('terminal-waiting'),
          color: c.surfaceAlt,
          fg: c.textMuted,
          icon: Icons.hourglass_empty,
          text:
              session.noDataTimedOut
                  ? 'Still nothing from your server. Check that the secure connection is on, or open Settings.'
                  : 'Waiting for the shell to start...',
        ),
      );
    }

    if (children.isEmpty) return const SizedBox.shrink();
    return Column(mainAxisSize: MainAxisSize.min, children: children);
  }
}

class _Banner extends StatelessWidget {
  const _Banner({super.key, required this.color, required this.fg, required this.icon, required this.text, this.trailing});

  final Color color;
  final Color fg;
  final IconData icon;
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        color: color,
        padding: EdgeInsets.symmetric(horizontal: ax.space.md, vertical: ax.space.xs),
        child: Row(
          children: [
            Icon(icon, size: 18, color: fg),
            SizedBox(width: ax.space.sm),
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: ax.space.sm),
                child: Text(text, style: ax.typo.body.copyWith(color: fg)),
              ),
            ),
            if (trailing != null) ...[SizedBox(width: ax.space.sm), trailing!],
          ],
        ),
      ),
    );
  }
}
