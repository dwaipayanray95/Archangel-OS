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
    this.serverName,
    this.showAccessoryBar,
    this.onOpenAdminMode,
    this.runningSinceText,
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
  final String? serverName;
  final bool? showAccessoryBar;
  final VoidCallback? onOpenAdminMode;
  final String? runningSinceText;

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

  void _openSnippetsSheet() {
    showSnippetsBottomSheet(context: context, snippets: _snippets, onSelect: _applySnippet, onSave: _saveSnippet, onDelete: _deleteSnippet);
  }

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final current = widget.sessions.isNotEmpty ? widget.sessions[widget.selected] : null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 640;
        final isPhone = MediaQuery.sizeOf(context).width < kTerminalPhoneWidth;
        final showAccessory = widget.showAccessoryBar ?? isPhone;

        final tabs = SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < widget.sessions.length; i++)
                _SessionTab(
                  session: widget.sessions[i],
                  selected: i == widget.selected,
                  narrow: !wide,
                  onTap: () => widget.onSelect(i),
                  onEnd: () => widget.onEnd(i),
                ),
            ],
          ),
        );

        final adminChip = widget.adminModeEnabled == null ? const SizedBox.shrink() : _AdminChip(enabled: widget.adminModeEnabled!);

        Widget topBar;
        if (wide) {
          topBar = Container(
            height: 46,
            padding: EdgeInsets.symmetric(horizontal: ax.space.xs),
            decoration: const BoxDecoration(color: kConBarBg, border: Border(bottom: BorderSide(color: kConLine))),
            child: Row(
              children: [
                Expanded(child: tabs),
                AxIconButton(icon: Icons.add, tooltip: 'New session', color: kConMuted, onPressed: widget.onNew),
                Container(width: 1, height: 20, margin: EdgeInsets.symmetric(horizontal: ax.space.xs), color: kConLine),
                Text('ray@${widget.serverName ?? 'server'}', style: ax.typo.mono.copyWith(fontSize: 12, color: kConMuted)),
                if (widget.adminModeEnabled != null) ...[SizedBox(width: ax.space.sm), adminChip],
                SizedBox(width: ax.space.xs),
                _TextButton(
                  label: 'A−',
                  tooltip: 'Smaller text',
                  onPressed:
                      widget.fontSize > kTerminalMinFont
                          ? () => widget.onFontSize((widget.fontSize - 1).clamp(kTerminalMinFont, kTerminalMaxFont))
                          : null,
                ),
                _TextButton(
                  label: 'A+',
                  tooltip: 'Bigger text',
                  onPressed:
                      widget.fontSize < kTerminalMaxFont
                          ? () => widget.onFontSize((widget.fontSize + 1).clamp(kTerminalMinFont, kTerminalMaxFont))
                          : null,
                ),
                AxIconButton(icon: Icons.copy_outlined, tooltip: 'Copy selection', color: kConMuted, onPressed: widget.onCopy),
                AxIconButton(icon: Icons.content_paste_outlined, tooltip: 'Paste', color: kConMuted, onPressed: widget.onPaste),
                AxIconButton(
                  icon: Icons.code,
                  tooltip: 'Snippets',
                  color: _snippetsOpen ? kConAccent : kConMuted,
                  onPressed: () => setState(() => _snippetsOpen = !_snippetsOpen),
                ),
                PopupMenuButton<String>(
                  tooltip: 'More',
                  icon: const Icon(Icons.more_horiz, color: kConMuted),
                  onSelected: (val) {
                    if (val == 'sessions') widget.onShowSessions();
                  },
                  itemBuilder: (_) => const [PopupMenuItem(value: 'sessions', child: Text('Sessions on this server'))],
                ),
              ],
            ),
          );
        } else {
          // Narrow top bar
          topBar = Container(
            height: 46,
            padding: EdgeInsets.symmetric(horizontal: ax.space.xs),
            decoration: const BoxDecoration(color: kConBarBg, border: Border(bottom: BorderSide(color: kConLine))),
            child: Row(
              children: [
                Expanded(child: tabs),
                AxIconButton(icon: Icons.add, tooltip: 'New session', color: kConMuted, onPressed: widget.onNew),
                _NarrowMoreMenu(
                  fontSize: widget.fontSize,
                  onFontSize: widget.onFontSize,
                  onSnippets: _openSnippetsSheet,
                  onCopy: widget.onCopy,
                  onPaste: widget.onPaste,
                  onShowSessions: widget.onShowSessions,
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
                    SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: statusColor))
                  else
                    Icon(statusIcon, size: 14, color: statusColor),
                  SizedBox(width: ax.space.xs),
                  Text(statusText, style: ax.typo.mono.copyWith(fontSize: 11.5, color: statusColor, fontWeight: FontWeight.w600)),
                ],
              );

              if (wide) {
                final running = widget.runningSinceText ?? 'running';
                return Container(
                  height: 36,
                  padding: EdgeInsets.symmetric(horizontal: ax.space.md),
                  decoration: const BoxDecoration(color: kConBarBg, border: Border(top: BorderSide(color: kConLine))),
                  child: Row(
                    children: [
                      statusBadge,
                      Text(' · ', style: ax.typo.mono.copyWith(color: kConMuted, fontSize: 11.5)),
                      Flexible(
                        child: Text(
                          'session "${current.name}" · $running',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ax.typo.mono.copyWith(color: kConMuted, fontSize: 11.5),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Spacer(),
                      Flexible(
                        child: Text(
                          'Keeps running on your server when you close the app',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ax.typo.mono.copyWith(color: kConMuted, fontSize: 11.5),
                        ),
                      ),
                    ],
                  ),
                );
              } else {
                return Container(
                  height: 36,
                  padding: EdgeInsets.symmetric(horizontal: ax.space.md),
                  decoration: const BoxDecoration(color: kConBarBg, border: Border(top: BorderSide(color: kConLine))),
                  child: Row(children: [statusBadge, const Spacer(), if (widget.adminModeEnabled != null) adminChip]),
                );
              }
            },
          );
        }

        return Container(
          color: kConBg,
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
                          decoration: const BoxDecoration(color: kConSnipsBg, border: Border(left: BorderSide(color: kConLine))),
                          child: SnippetsView(snippets: _snippets, onSelect: _applySnippet, onSave: _saveSnippet, onDelete: _deleteSnippet),
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
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final dotColor = switch (session.status) {
          SessionStatus.connected => kConLiveDotGreen,
          SessionStatus.connecting => kConLiveDotAmber,
          SessionStatus.error || SessionStatus.closed => kConLiveDotGrey,
        };

        return Padding(
          padding: const EdgeInsets.only(right: 2),
          child: Material(
            color: selected ? kConTabSelectedBg : Colors.transparent,
            borderRadius: BorderRadius.circular(ax.radii.sm),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ax.radii.sm)),
                  onTap: onTap,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(width: 7, height: 7, decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle)),
                        SizedBox(width: ax.space.sm),
                        Text(
                          session.name,
                          style: ax.typo.mono.copyWith(fontSize: 12.5, fontWeight: FontWeight.w500, color: selected ? kConText : kConMuted),
                        ),
                      ],
                    ),
                  ),
                ),
                if (!narrow || selected)
                  Semantics(
                    button: true,
                    label: 'End session ${session.name}',
                    child: Tooltip(
                      message: 'End session ${session.name}',
                      child: InkWell(
                        customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        onTap: onEnd,
                        child: const Padding(padding: EdgeInsets.all(6), child: Icon(Icons.close, size: 14, color: kConMuted)),
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

class _AdminChip extends StatelessWidget {
  const _AdminChip({required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final bg = enabled ? kConChipOnBg : kConChipOffBg;
    final fg = enabled ? kConChipOnFg : kConMuted;
    final icon = enabled ? Icons.key : Icons.lock;
    final text = enabled ? 'Admin on' : 'Admin off';
    final tooltip = enabled ? 'Administrator commands (sudo) are allowed' : 'Administrator commands (sudo) are blocked';

    return Tooltip(
      message: tooltip,
      child: Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(ax.radii.pill)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: fg),
            SizedBox(width: ax.space.xs),
            Text(text, style: ax.typo.caption.copyWith(fontWeight: FontWeight.w600, fontSize: 11.5, color: fg)),
          ],
        ),
      ),
    );
  }
}

class _TextButton extends StatelessWidget {
  const _TextButton({required this.label, required this.tooltip, required this.onPressed});

  final String label;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onPressed,
        child: SizedBox(
          width: 34,
          height: 34,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: kUiFontFamily,
                fontWeight: FontWeight.w600,
                fontSize: 12,
                color: onPressed != null ? kConMuted : kConMuted.withValues(alpha: 0.4),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NarrowMoreMenu extends StatelessWidget {
  const _NarrowMoreMenu({
    required this.fontSize,
    required this.onFontSize,
    required this.onSnippets,
    required this.onCopy,
    required this.onPaste,
    required this.onShowSessions,
  });

  final double fontSize;
  final ValueChanged<double> onFontSize;
  final VoidCallback onSnippets;
  final VoidCallback onCopy;
  final VoidCallback onPaste;
  final VoidCallback onShowSessions;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'More',
      icon: const Icon(Icons.more_horiz, color: kConMuted),
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 280),
      onSelected: (val) {
        if (val == 'snippets') {
          onSnippets();
        } else if (val == 'copy') {
          onCopy();
        } else if (val == 'paste') {
          onPaste();
        } else if (val == 'sessions') {
          onShowSessions();
        }
      },
      itemBuilder: (context) {
        final ax = context.ax;
        return [
          _CustomMenuItem(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Text size', style: ax.typo.body),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Tooltip(
                      message: 'Smaller text',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(ax.radii.sm),
                        onTap:
                            fontSize > kTerminalMinFont ? () => onFontSize((fontSize - 1).clamp(kTerminalMinFont, kTerminalMaxFont)) : null,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                          child: Text('A−', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text('${fontSize.toInt()}', style: ax.typo.mono.copyWith(fontWeight: FontWeight.w600)),
                    ),
                    Tooltip(
                      message: 'Bigger text',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(ax.radii.sm),
                        onTap:
                            fontSize < kTerminalMaxFont ? () => onFontSize((fontSize + 1).clamp(kTerminalMinFont, kTerminalMaxFont)) : null,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                          child: Text('A+', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const PopupMenuItem(value: 'snippets', child: Text('Snippets')),
          const PopupMenuItem(value: 'copy', child: Text('Copy selection')),
          const PopupMenuItem(value: 'paste', child: Text('Paste')),
          const PopupMenuDivider(),
          const PopupMenuItem(value: 'sessions', child: Text('Sessions on this server')),
        ];
      },
    );
  }
}

class _CustomMenuItem<T> extends PopupMenuEntry<T> {
  const _CustomMenuItem({required this.child});

  final Widget child;

  @override
  double get height => 48;

  @override
  bool represents(T? value) => false;

  @override
  State<_CustomMenuItem<T>> createState() => _CustomMenuItemState<T>();
}

class _CustomMenuItemState<T> extends State<_CustomMenuItem<T>> {
  @override
  Widget build(BuildContext context) {
    return Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: widget.child);
  }
}
