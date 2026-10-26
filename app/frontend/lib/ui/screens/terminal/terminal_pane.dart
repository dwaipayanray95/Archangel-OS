import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import '../../../services/terminal_session.dart';
import '../../components/ax_button.dart';
import '../../components/ax_icon_button.dart';
import '../../shell/terminal_focus_marker.dart';
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

class TerminalPane extends StatefulWidget {
  const TerminalPane({
    super.key,
    required this.session,
    required this.controller,
    required this.fontSize,
    this.focusNode,
    this.adminModeEnabled,
    this.onOpenAdminMode,
    this.onSnippets,
    this.showAccessoryBar = false,
  });

  final TerminalSession session;
  final TerminalController controller;
  final double fontSize;
  final FocusNode? focusNode;
  final bool? adminModeEnabled;
  final VoidCallback? onOpenAdminMode;
  final VoidCallback? onSnippets;
  final bool showAccessoryBar;

  static bool get _isTouchPlatform =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  @override
  State<TerminalPane> createState() => _TerminalPaneState();
}

class _TerminalPaneState extends State<TerminalPane> {
  int _dismissedMatchCount = 0;

  int _countBlockedMatches(TerminalSession session) {
    final text = session.terminal.buffer.getText();
    int count = 0;
    count += 'sudo: a password is required'.allMatches(text).length;
    count += 'is not in the sudoers file'.allMatches(text).length;
    return count;
  }

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final tp = context.terminalPalette;
    final session = widget.session;

    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final status = session.status;
        final hasOutput = session.hasOutput;
        final exitCode = session.exitCode;

        final isConnecting = status == SessionStatus.connecting || (!hasOutput && status == SessionStatus.connected);
        final isDisconnected = (status == SessionStatus.closed || status == SessionStatus.error) && exitCode == null;
        final isSessionEnded = exitCode != null;

        final blockedMatches = _countBlockedMatches(session);
        final showBlockedBanner = widget.adminModeEnabled == false && blockedMatches > _dismissedMatchCount;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (session.notice != null)
              Semantics(
                liveRegion: true,
                container: true,
                child: Container(
                  key: const ValueKey('terminal-notice'),
                  color: c.warningWash,
                  padding: EdgeInsets.symmetric(horizontal: ax.space.md, vertical: ax.space.xs),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, size: 18, color: c.warning),
                      SizedBox(width: ax.space.sm),
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: ax.space.sm),
                          child: Text(session.notice!, style: ax.typo.body.copyWith(color: c.warning)),
                        ),
                      ),
                      AxIconButton(icon: Icons.close, tooltip: 'Dismiss notice', color: c.warning, onPressed: session.dismissNotice),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: ColoredBox(
                color: tp.termBg,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Opacity(
                      opacity: isDisconnected ? 0.35 : 1.0,
                      child: TerminalFocusMarker(
                        child: TerminalView(
                          session.terminal,
                          key: ValueKey('terminal-view-${session.name}-${session.terminalEpoch}'),
                          controller: widget.controller,
                          focusNode: widget.focusNode,
                          autofocus: true,
                          theme: tp.termTheme,
                          textStyle: TerminalStyle(
                            fontSize: widget.fontSize,
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
                          deleteDetection: TerminalPane._isTouchPlatform,
                          keyboardType: TextInputType.text,
                          cursorType: TerminalCursorType.block,
                        ),
                      ),
                    ),
                    if (isConnecting)
                      _OverlayCard(
                        key: const ValueKey('terminal-connecting-overlay'),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(width: 32, height: 32, child: CircularProgressIndicator(strokeWidth: 3)),
                            SizedBox(height: ax.space.md),
                            Text(
                              session.noDataTimedOut ? 'Still waiting. Your server is slow to answer.' : 'Reaching your server…',
                              textAlign: TextAlign.center,
                              style: ax.typo.title.copyWith(color: tp.text),
                            ),
                            SizedBox(height: ax.space.xs),
                            Text(
                              'Opening session "${session.name}".',
                              textAlign: TextAlign.center,
                              style: ax.typo.caption.copyWith(color: tp.textMuted),
                            ),
                            if (session.noDataTimedOut) ...[
                              SizedBox(height: ax.space.lg),
                              AxButton(label: 'Reconnect', icon: Icons.refresh, onPressed: session.reconnect),
                            ],
                          ],
                        ),
                      )
                    else if (isDisconnected)
                      _OverlayCard(
                        key: const ValueKey('terminal-disconnected-overlay'),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.cloud_off, size: 36, color: tp.textMuted),
                            SizedBox(height: ax.space.md),
                            Text('Disconnected', textAlign: TextAlign.center, style: ax.typo.title.copyWith(color: tp.text)),
                            SizedBox(height: ax.space.xs),
                            Text(
                              'Your session is still running on the server. Reconnect to pick up where you left off.',
                              textAlign: TextAlign.center,
                              style: ax.typo.body.copyWith(color: tp.textMuted),
                            ),
                            SizedBox(height: ax.space.lg),
                            AxButton(label: 'Reconnect', icon: Icons.refresh, onPressed: session.reconnect),
                          ],
                        ),
                      )
                    else if (isSessionEnded)
                      _OverlayCard(
                        key: const ValueKey('terminal-ended-overlay'),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.info_outline, size: 36, color: tp.textMuted),
                            SizedBox(height: ax.space.md),
                            Text('This session ended', textAlign: TextAlign.center, style: ax.typo.title.copyWith(color: tp.text)),
                            SizedBox(height: ax.space.xs),
                            Text('The shell exited.', textAlign: TextAlign.center, style: ax.typo.body.copyWith(color: tp.textMuted)),
                            SizedBox(height: ax.space.lg),
                            AxButton(label: 'Start a new session', icon: Icons.refresh, onPressed: session.reconnect),
                          ],
                        ),
                      ),
                    if (showBlockedBanner)
                      Positioned(
                        left: ax.space.md,
                        right: ax.space.md,
                        bottom: ax.space.md,
                        child: Semantics(
                          container: true,
                          liveRegion: true,
                          child: Container(
                            key: const ValueKey('terminal-blocked-banner'),
                            padding: EdgeInsets.all(ax.space.md),
                            decoration: BoxDecoration(
                              color: c.warningWash,
                              borderRadius: BorderRadius.circular(ax.radii.md),
                              border: Border.all(color: c.warning.withValues(alpha: 0.5)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.lock, size: 18, color: c.warning),
                                    SizedBox(width: ax.space.sm),
                                    Expanded(child: Text('That command needs Admin mode', style: ax.typo.title.copyWith(color: c.warning))),
                                  ],
                                ),
                                SizedBox(height: ax.space.xs),
                                Text(
                                  'Your server blocked it because Admin mode is off. Turn it on in Settings › Admin mode, then run the command again.',
                                  style: ax.typo.body.copyWith(color: c.text),
                                ),
                                SizedBox(height: ax.space.md),
                                Wrap(
                                  spacing: ax.space.sm,
                                  runSpacing: ax.space.sm,
                                  children: [
                                    if (widget.onOpenAdminMode != null)
                                      AxButton(label: 'Open Admin mode', onPressed: widget.onOpenAdminMode!),
                                    AxButton.ghost(
                                      label: 'Dismiss',
                                      onPressed: () => setState(() => _dismissedMatchCount = blockedMatches),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (widget.showAccessoryBar) TerminalAccessoryBar(session: session, onSnippets: widget.onSnippets),
          ],
        );
      },
    );
  }
}

class _OverlayCard extends StatelessWidget {
  const _OverlayCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final tp = context.terminalPalette;
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 380),
        margin: EdgeInsets.all(ax.space.lg),
        padding: EdgeInsets.all(ax.space.xl),
        decoration: BoxDecoration(
          color: tp.barBg,
          borderRadius: BorderRadius.circular(ax.radii.lg),
          border: Border.all(color: tp.line),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: tp.isDark ? 0.4 : 0.08), blurRadius: 24, offset: const Offset(0, 8))],
        ),
        child: child,
      ),
    );
  }
}
