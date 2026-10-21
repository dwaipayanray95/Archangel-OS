import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import '../../../services/terminal_session.dart';
import '../../components/ax_icon_button.dart';
import '../../theme.dart';
import 'terminal_accessory_bar.dart';
import 'terminal_palette.dart';
import 'terminal_pane.dart';
import 'terminal_snippets.dart';

const double kTerminalMinFont = 10;
const double kTerminalMaxFont = 24;
const double kTerminalDefaultFont = 14;

/// The terminal's chrome around the selected session's [TerminalPane].
class TerminalWorkspace extends StatefulWidget {
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
    this.adminModeEnabled,
    this.onToggleAdminMode,
    this.serverName,
    this.showAccessoryBar,
    this.onOpenAdminMode,
    this.runningSinceText,
    this.onReorderSessions,
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
  final bool? adminModeEnabled;
  final ValueChanged<bool>? onToggleAdminMode;
  final String? serverName;
  final bool? showAccessoryBar;
  final VoidCallback? onOpenAdminMode;
  final String? runningSinceText;
  final void Function(int oldIndex, int newIndex)? onReorderSessions;

  @override
  State<TerminalWorkspace> createState() => _TerminalWorkspaceState();
}

class _TerminalWorkspaceState extends State<TerminalWorkspace> {
  bool _snippetsOpen = false;
  List<TerminalSnippet> _snippets = List.of(kDefaultSnippets);

  @override
  void initState() {
    super.initState();
    _loadSnippets();
  }

  Future<void> _loadSnippets() async {
    final list = await loadTerminalSnippets();
    if (mounted) {
      setState(() => _snippets = list);
    }
  }

  Future<void> _saveSnippet() async {
    final s = await showSaveSnippetDialog(context);
    if (s != null && mounted) {
      final updated = [..._snippets, s];
      setState(() => _snippets = updated);
      await saveTerminalSnippets(updated);
    }
  }

  Future<void> _deleteSnippet(TerminalSnippet s) async {
    final updated = _snippets.where((item) => item != s).toList();
    setState(() => _snippets = updated);
    await saveTerminalSnippets(updated);
  }

  void _applySnippet(TerminalSnippet s) {
    if (widget.sessions.isEmpty) return;
    final current = widget.sessions[widget.selected];
    current.typeText(s.command);
  }

  Future<void> _reorderSnippets(int oldIndex, int newIndex) async {
    final next = List<TerminalSnippet>.from(_snippets);
    final item = next.removeAt(oldIndex);
    next.insert(newIndex, item);
    setState(() => _snippets = next);
    await saveTerminalSnippets(next);
  }

  void _handleReorderSessions(int oldIndex, int newIndex) {
    if (widget.onReorderSessions != null) {
      widget.onReorderSessions!(oldIndex, newIndex);
    } else {
      final currentSelected =
          widget.sessions.isNotEmpty && widget.selected >= 0 && widget.selected < widget.sessions.length
              ? widget.sessions[widget.selected]
              : null;
      final session = widget.sessions.removeAt(oldIndex);
      widget.sessions.insert(newIndex, session);
      if (currentSelected != null) {
        final newSel = widget.sessions.indexOf(currentSelected);
        if (newSel != -1) widget.onSelect(newSel);
      }
    }
  }

  void _openSnippetsSheet() {
    showSnippetsBottomSheet(
      context: context,
      snippets: _snippets,
      onSelect: _applySnippet,
      onSave: _saveSnippet,
      onDelete: _deleteSnippet,
      onReorder: _reorderSnippets,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final tp = context.terminalPalette;
    final current = widget.sessions.isNotEmpty ? widget.sessions[widget.selected] : null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 640;
        final isPhone = MediaQuery.sizeOf(context).width < kTerminalPhoneWidth;
        final showAccessory = widget.showAccessoryBar ?? isPhone;

        final tabs = ReorderableListView.builder(
          scrollDirection: Axis.horizontal,
          buildDefaultDragHandles: false,
          shrinkWrap: true,
          itemCount: widget.sessions.length,
          onReorderItem: _handleReorderSessions,
          proxyDecorator: (child, index, animation) {
            return Material(
              color: Colors.transparent,
              elevation: 4,
              shadowColor: Colors.black.withValues(alpha: tp.isDark ? 0.5 : 0.15),
              child: child,
            );
          },
          footer: Align(
            alignment: Alignment.bottomLeft,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 4, left: 2),
              child: AxIconButton(icon: Icons.add, tooltip: 'New session', color: tp.textMuted, onPressed: widget.onNew),
            ),
          ),
          itemBuilder: (context, i) {
            final session = widget.sessions[i];
            return Align(
              key: ValueKey(session),
              alignment: Alignment.bottomLeft,
              child: ReorderableDragStartListener(
                index: i,
                child: _SessionTab(
                  session: session,
                  selected: i == widget.selected,
                  narrow: !wide,
                  onTap: () => widget.onSelect(i),
                  onEnd: () => widget.onEnd(i),
                ),
              ),
            );
          },
        );

        final adminButton =
            widget.adminModeEnabled == null
                ? const SizedBox.shrink()
                : _AdminButton(enabled: widget.adminModeEnabled!, onToggle: widget.onToggleAdminMode);

        Widget topBar;
        if (wide) {
          topBar = Container(
            height: 44,
            decoration: BoxDecoration(color: tp.barBg),
            child: Stack(
              children: [
                Positioned(left: 0, right: 0, bottom: 0, child: Container(height: 1, color: tp.line)),
                Positioned.fill(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: ax.space.xs),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(child: tabs),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.dns_outlined, size: 12, color: tp.textMuted.withValues(alpha: 0.6)),
                              const SizedBox(width: 4),
                              Text(
                                'ray@${widget.serverName ?? 'server'}',
                                style: ax.typo.mono.copyWith(fontSize: 11.5, color: tp.textMuted),
                              ),
                              SizedBox(width: ax.space.sm),
                              Container(width: 1, height: 14, color: tp.line),
                              SizedBox(width: ax.space.sm),
                              if (widget.adminModeEnabled != null) ...[adminButton, SizedBox(width: ax.space.xs)],
                              AxIconButton(
                                icon: Icons.code,
                                tooltip: 'Snippets',
                                color: _snippetsOpen ? tp.accent : tp.textMuted,
                                onPressed: () => setState(() => _snippetsOpen = !_snippetsOpen),
                              ),
                              _TerminalMoreMenu(
                                fontSize: widget.fontSize,
                                onFontSize: widget.onFontSize,
                                onCopy: widget.onCopy,
                                onPaste: widget.onPaste,
                                onShowSessions: widget.onShowSessions,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        } else {
          // Narrow top bar
          topBar = Container(
            height: 44,
            decoration: BoxDecoration(color: tp.barBg),
            child: Stack(
              children: [
                Positioned(left: 0, right: 0, bottom: 0, child: Container(height: 1, color: tp.line)),
                Positioned.fill(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: ax.space.xs),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(child: tabs),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: _TerminalMoreMenu(
                            fontSize: widget.fontSize,
                            onFontSize: widget.onFontSize,
                            onSnippets: _openSnippetsSheet,
                            onCopy: widget.onCopy,
                            onPaste: widget.onPaste,
                            onShowSessions: widget.onShowSessions,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        Widget footer;
        if (current == null) {
          footer = const SizedBox.shrink();
        } else {
          footer = ListenableBuilder(
            listenable: current,
            builder: (context, _) {
              final status = current.status;
              final (IconData statusIcon, Color statusColor, String statusText, bool isSpinning) = switch (status) {
                SessionStatus.connected => (Icons.shield_outlined, ax.colors.success, 'Connected', false),
                SessionStatus.connecting => (Icons.sync, ax.colors.warning, 'Connecting…', true),
                SessionStatus.error || SessionStatus.closed => (Icons.cloud_off, ax.colors.danger, 'Not connected', false),
              };

              final statusBadge = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isSpinning)
                    SizedBox(width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 2, color: statusColor))
                  else
                    Icon(statusIcon, size: 13, color: statusColor),
                  SizedBox(width: ax.space.xs),
                  Text(statusText, style: ax.typo.mono.copyWith(fontSize: 11, color: statusColor, fontWeight: FontWeight.w600)),
                ],
              );

              return Container(
                height: 30,
                padding: EdgeInsets.symmetric(horizontal: ax.space.md),
                decoration: BoxDecoration(color: tp.barBg, border: Border(top: BorderSide(color: tp.line))),
                child: Row(children: [statusBadge, const Spacer(), if (!wide && widget.adminModeEnabled != null) adminButton]),
              );
            },
          );
        }

        return Container(
          color: tp.bg,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              topBar,
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (current != null)
                      Expanded(
                        child: TerminalPane(
                          key: ValueKey(current),
                          session: current,
                          controller: widget.controllerFor(current),
                          fontSize: widget.fontSize,
                          adminModeEnabled: widget.adminModeEnabled,
                          onOpenAdminMode: widget.onOpenAdminMode,
                          onSnippets: _openSnippetsSheet,
                          showAccessoryBar: showAccessory,
                        ),
                      ),
                    if (wide && _snippetsOpen)
                      SizedBox(
                        width: 260,
                        child: Container(
                          decoration: BoxDecoration(color: tp.snipsBg, border: Border(left: BorderSide(color: tp.line))),
                          child: SnippetsView(
                            snippets: _snippets,
                            onSelect: _applySnippet,
                            onSave: _saveSnippet,
                            onDelete: _deleteSnippet,
                            onReorder: _reorderSnippets,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              footer,
            ],
          ),
        );
      },
    );
  }
}

class _SessionTab extends StatelessWidget {
  const _SessionTab({required this.session, required this.selected, required this.narrow, required this.onTap, required this.onEnd});

  final TerminalSession session;
  final bool selected;
  final bool narrow;
  final VoidCallback onTap;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final tp = context.terminalPalette;
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final dotColor = switch (session.status) {
          SessionStatus.connected => tp.liveDotGreen,
          SessionStatus.connecting => tp.liveDotAmber,
          SessionStatus.error || SessionStatus.closed => tp.liveDotGrey,
        };

        if (selected) {
          return Container(
            height: 36,
            margin: const EdgeInsets.only(right: 3),
            decoration: BoxDecoration(
              color: tp.termBg,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
              border: Border(top: BorderSide(color: tp.line), left: BorderSide(color: tp.line), right: BorderSide(color: tp.line)),
            ),
            child: Material(
              color: Colors.transparent,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
                    onTap: onTap,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(width: 7, height: 7, decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle)),
                          SizedBox(width: ax.space.sm),
                          Text(session.name, style: ax.typo.mono.copyWith(fontSize: 12.5, fontWeight: FontWeight.w600, color: tp.text)),
                        ],
                      ),
                    ),
                  ),
                  Semantics(
                    button: true,
                    label: 'End session ${session.name}',
                    child: Tooltip(
                      message: 'End session ${session.name}',
                      child: InkWell(
                        customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        onTap: onEnd,
                        child: Padding(padding: const EdgeInsets.all(6), child: Icon(Icons.close, size: 14, color: tp.textMuted)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
          );
        }

        return Container(
          height: 32,
          margin: const EdgeInsets.only(right: 3, bottom: 2),
          decoration: BoxDecoration(color: Colors.transparent, borderRadius: BorderRadius.circular(ax.radii.sm)),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(ax.radii.sm),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ax.radii.sm)),
                  onTap: onTap,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(color: dotColor.withValues(alpha: 0.6), shape: BoxShape.circle),
                        ),
                        SizedBox(width: ax.space.sm),
                        Text(session.name, style: ax.typo.mono.copyWith(fontSize: 12.5, fontWeight: FontWeight.w500, color: tp.textMuted)),
                      ],
                    ),
                  ),
                ),
                if (!narrow)
                  Semantics(
                    button: true,
                    label: 'End session ${session.name}',
                    child: Tooltip(
                      message: 'End session ${session.name}',
                      child: InkWell(
                        customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        onTap: onEnd,
                        child: Padding(padding: const EdgeInsets.all(6), child: Icon(Icons.close, size: 14, color: tp.textMuted)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AdminButton extends StatelessWidget {
  const _AdminButton({required this.enabled, this.onToggle});

  final bool enabled;
  final ValueChanged<bool>? onToggle;

  @override
  Widget build(BuildContext context) {
    final tp = context.terminalPalette;
    final color = enabled ? tp.chipOnFg : tp.textMuted;
    return Tooltip(
      message: 'Admin mode',
      child: Semantics(
        label: 'Admin mode',
        toggled: enabled,
        button: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onToggle != null ? () => onToggle!(!enabled) : null,
          child: Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: enabled ? tp.chipOnBg : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: enabled ? tp.chipOnFg.withValues(alpha: 0.35) : tp.line, width: 1),
            ),
            alignment: Alignment.center,
            child: Icon(Icons.key_rounded, size: 13.5, color: color),
          ),
        ),
      ),
    );
  }
}

class _TerminalMoreMenu extends StatelessWidget {
  const _TerminalMoreMenu({
    required this.fontSize,
    required this.onFontSize,
    this.onSnippets,
    required this.onCopy,
    required this.onPaste,
    required this.onShowSessions,
  });

  final double fontSize;
  final ValueChanged<double> onFontSize;
  final VoidCallback? onSnippets;
  final VoidCallback onCopy;
  final VoidCallback onPaste;
  final VoidCallback onShowSessions;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final tp = context.terminalPalette;
    return PopupMenuButton<String>(
      tooltip: 'More',
      icon: Icon(Icons.more_horiz, color: tp.textMuted),
      offset: const Offset(0, 44),
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: tp.isDark ? 0.6 : 0.15),
      color: tp.barBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: tp.line)),
      constraints: const BoxConstraints(minWidth: 240, maxWidth: 270),
      onSelected: (val) {
        if (val == 'snippets') {
          onSnippets?.call();
        } else if (val == 'copy') {
          onCopy();
        } else if (val == 'paste') {
          onPaste();
        } else if (val == 'sessions') {
          onShowSessions();
        }
      },
      itemBuilder: (context) {
        return [
          _TextSizeMenuItem(initialFontSize: fontSize, onFontSize: onFontSize),
          if (onSnippets != null)
            PopupMenuItem<String>(
              value: 'snippets',
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text('Snippets', style: ax.typo.body.copyWith(fontSize: 13, color: tp.text)),
            ),
          PopupMenuItem<String>(
            value: 'copy',
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('Copy selection', style: ax.typo.body.copyWith(fontSize: 13, color: tp.text)),
          ),
          PopupMenuItem<String>(
            value: 'paste',
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('Paste', style: ax.typo.body.copyWith(fontSize: 13, color: tp.text)),
          ),
          PopupMenuDivider(height: 1),
          PopupMenuItem<String>(
            value: 'sessions',
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('Sessions on this server', style: ax.typo.body.copyWith(fontSize: 13, color: tp.text)),
          ),
        ];
      },
    );
  }
}

class _TextSizeMenuItem extends PopupMenuEntry<String> {
  const _TextSizeMenuItem({required this.initialFontSize, required this.onFontSize});

  final double initialFontSize;
  final ValueChanged<double> onFontSize;

  @override
  double get height => 38;

  @override
  bool represents(String? value) => false;

  @override
  State<_TextSizeMenuItem> createState() => _TextSizeMenuItemState();
}

class _TextSizeMenuItemState extends State<_TextSizeMenuItem> {
  late double _current;

  @override
  void initState() {
    super.initState();
    _current = widget.initialFontSize;
  }

  void _step(double delta) {
    final next = (_current + delta).clamp(kTerminalMinFont, kTerminalMaxFont);
    if (next != _current) {
      setState(() => _current = next);
      widget.onFontSize(next);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final tp = context.terminalPalette;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Text size', style: ax.typo.body.copyWith(fontSize: 13, color: tp.text)),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Tooltip(
                message: 'Smaller text',
                triggerMode: TooltipTriggerMode.manual,
                child: InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: _current > kTerminalMinFont ? () => _step(-1) : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: tp.text.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(6)),
                    child: Text(
                      'A−',
                      style: TextStyle(
                        fontFamily: kUiFontFamily,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                        color: _current > kTerminalMinFont ? tp.text : tp.textMuted.withValues(alpha: 0.35),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  '${_current.toInt()}',
                  style: ax.typo.mono.copyWith(fontSize: 12, fontWeight: FontWeight.w600, color: tp.accent),
                ),
              ),
              Tooltip(
                message: 'Bigger text',
                triggerMode: TooltipTriggerMode.manual,
                child: InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: _current < kTerminalMaxFont ? () => _step(1) : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: tp.text.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(6)),
                    child: Text(
                      'A+',
                      style: TextStyle(
                        fontFamily: kUiFontFamily,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                        color: _current < kTerminalMaxFont ? tp.text : tp.textMuted.withValues(alpha: 0.35),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
