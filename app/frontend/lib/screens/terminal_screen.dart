import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../data/app_state.dart';
import '../services/archangeld_connection.dart';
import '../services/terminal_session.dart';
import '../theme/tokens.dart';
import '../widgets/ax_widgets.dart';
import '../widgets/pairing_dialog.dart';

class TerminalScreen extends StatefulWidget {
  const TerminalScreen({super.key});

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  final List<TerminalSession> _sessions = [];
  List<TerminalSessionInfo> _serverSessions = const [];
  int _tab = 0;
  bool _bootstrapping = false;
  bool _bootstrapped = false;

  @override
  void dispose() {
    for (final s in _sessions) {
      s.dispose();
    }
    super.dispose();
  }

  Iterable<String> get _takenNames => [..._serverSessions.map((s) => s.name), ..._sessions.map((s) => s.name)];

  /// Fetches the server's session list, then attaches to "main" (or the first
  /// existing session when there is no "main").
  Future<void> _bootstrap(ArchangeldConnection backend, {String? initialDir}) async {
    if (_bootstrapping) return;
    _bootstrapping = true;
    final list = await TerminalSessionApi.list(backend);
    if (!mounted) return;
    if (list != null) _serverSessions = list;
    final names = _serverSessions.map((s) => s.name).toList();
    final name = names.isEmpty || names.contains('main') ? 'main' : names.first;
    _bootstrapped = true;
    _bootstrapping = false;
    if (_sessions.isEmpty) _openSession(backend, name: name, initialDir: initialDir);
  }

  Future<void> _refreshServerSessions(ArchangeldConnection backend) async {
    final list = await TerminalSessionApi.list(backend);
    if (!mounted || list == null) return;
    setState(() => _serverSessions = list);
  }

  void _openSession(ArchangeldConnection backend, {String? name, String? initialDir, String? initialCommand}) {
    final sessionName = name ?? nextSessionName(_takenNames);
    final existing = _sessions.indexWhere((s) => s.name == sessionName);
    if (existing >= 0) {
      setState(() => _tab = existing);
      return;
    }
    final session = TerminalSession(label: sessionName);
    session.connect(backend);
    if (initialDir != null && initialDir.isNotEmpty) {
      session.changeDirectory(initialDir);
    } else if (initialCommand != null && initialCommand.isNotEmpty) {
      session.waitForFirstOutput().then((_) => session.sendInput('$initialCommand\n')); // no-op once disposed
    }
    setState(() {
      _sessions.add(session);
      _tab = _sessions.length - 1;
    });
  }

  /// Detach: drops this tab's connection; the shell keeps running server-side.
  void _detachSession(int index, ArchangeldConnection backend) {
    final session = _sessions[index];
    session.close();
    session.dispose();
    setState(() {
      _sessions.removeAt(index);
      if (index < _tab) _tab--;
      if (_tab >= _sessions.length) _tab = _sessions.length - 1;
      if (_tab < 0) _tab = 0;
    });
    _refreshServerSessions(backend);
  }

  Future<void> _endSession(int index, ArchangeldConnection backend) async {
    final session = _sessions[index];
    final ok = await _confirmEnd(context, session.name);
    if (ok != true || !mounted) return;
    final err = await TerminalSessionApi.end(backend, session.name);
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err), backgroundColor: AxColors.bad));
      return;
    }
    final i = _sessions.indexOf(session);
    if (i >= 0) _detachSession(i, backend);
  }

  Future<void> _showSessions(ArchangeldConnection backend) async {
    final picked = await showDialog<String>(
      context: context,
      builder: (_) => _SessionsDialog(
        backend: backend,
        openNames: _sessions.map((s) => s.name).toSet(),
        initial: _serverSessions,
      ),
    );
    if (picked != null && mounted) _openSession(backend, name: picked);
    if (mounted) _refreshServerSessions(backend);
  }

  @override
  Widget build(BuildContext context) {
    final backend = context.watch<ArchangeldConnection>();
    final app = context.watch<AppState>();

    final pendingDir = app.consumePendingTerminalDir();
    final pendingCmd = app.consumePendingTerminalCommand();

    if (pendingDir != null && backend.isPaired) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (!isSafeShellPath(pendingDir)) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('This folder name contains control characters; open it manually.')));
          return;
        }
        if (_sessions.isNotEmpty) {
          // Waits for the session to be connected, like a fresh tab does.
          _sessions[_tab].changeDirectory(pendingDir);
        } else {
          _openSession(backend, name: 'main', initialDir: pendingDir);
        }
      });
    } else if (pendingCmd != null && backend.isPaired) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _openSession(backend, initialCommand: pendingCmd);
      });
    }

    if (!backend.isPaired) {
      return _UnpairedPrompt(onPaired: () => setState(() {}));
    }

    if (_sessions.isEmpty) {
      if (!_bootstrapped && !_bootstrapping && pendingDir == null && pendingCmd == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _sessions.isEmpty) _bootstrap(backend);
        });
      } else if (_bootstrapped && pendingDir == null && pendingCmd == null) {
        // All tabs were detached: offer a way back in rather than auto-reopening.
        return _NoTabs(
          onNew: () => _openSession(backend),
          onSessions: () => _showSessions(backend),
        );
      }
      return const Center(
        child: CircularProgressIndicator(strokeWidth: 2, color: AxColors.accent),
      );
    }

    final currentSession = _sessions[_tab];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(10, 4, 10, 0),
          decoration: const BoxDecoration(color: AxColors.s1, border: Border(bottom: BorderSide(color: AxColors.line))),
          child: Row(
            children: [
              // Horizontally scrollable tab bar to prevent overflow on mobile
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < _sessions.length; i++)
                        _TermTab(
                          session: _sessions[i],
                          selected: i == _tab,
                          onTap: () => setState(() => _tab = i),
                          onClose: () => _detachSession(i, backend),
                        ),
                      const SizedBox(width: 4),
                      IconButton(
                        tooltip: 'New session',
                        icon: const Icon(Icons.add_rounded, size: 16, color: AxColors.fg3),
                        constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                        onPressed: () => _openSession(backend),
                      ),
                      IconButton(
                        tooltip: 'Sessions',
                        icon: const Icon(Icons.layers_outlined, size: 15, color: AxColors.fg3),
                        constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                        onPressed: () => _showSessions(backend),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Quick action buttons: Copy output, clear screen, end session
              IconButton(
                icon: const Icon(Icons.copy_rounded, size: 13, color: AxColors.fg3),
                tooltip: 'Copy buffer',
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: currentSession.output));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Terminal output copied to clipboard'), duration: Duration(seconds: 1)),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.cleaning_services_rounded, size: 13, color: AxColors.fg3),
                tooltip: 'Clear screen',
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                onPressed: () {
                  currentSession.clearOutput();
                  currentSession.sendInput('\x0c'); // Form feed / clear
                },
              ),
              IconButton(
                icon: const Icon(Icons.power_settings_new_rounded, size: 14, color: AxColors.bad),
                tooltip: 'End session',
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                onPressed: () => _endSession(_tab, backend),
              ),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text(backend.host ?? '', style: AxTextStyles.mono.copyWith(fontSize: 10, color: AxColors.fg3)),
              ),
            ],
          ),
        ),
        Expanded(child: _LivePane(key: ValueKey(currentSession), session: currentSession)),
      ],
    );
  }
}

Future<bool?> _confirmEnd(BuildContext context, String name) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AxColors.s1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AxRadius.lg), side: const BorderSide(color: AxColors.line)),
      title: Text('End session "$name"?', style: AxTextStyles.sans.copyWith(fontSize: 16, fontWeight: FontWeight.w600)),
      content: Text(
        'This stops everything running in this session.',
        style: AxTextStyles.sans.copyWith(fontSize: 13, color: AxColors.fg2, height: 1.4),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text('Cancel', style: AxTextStyles.sans.copyWith(color: AxColors.fg3)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AxColors.bad, foregroundColor: Colors.white),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('End session'),
        ),
      ],
    ),
  );
}

class _NoTabs extends StatelessWidget {
  final VoidCallback onNew;
  final VoidCallback onSessions;
  const _NoTabs({required this.onNew, required this.onSessions});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('No session open', style: AxTextStyles.sans.copyWith(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Detached sessions keep running on your server.', style: AxTextStyles.sans.copyWith(fontSize: 12.5, color: AxColors.fg2)),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            children: [
              FilledButton(onPressed: onNew, child: const Text('New session')),
              OutlinedButton(onPressed: onSessions, child: const Text('Sessions')),
            ],
          ),
        ],
      ),
    );
  }
}

/// Lists the sessions running on the server so one can be reattached or ended.
class _SessionsDialog extends StatefulWidget {
  final ArchangeldConnection backend;
  final Set<String> openNames;
  final List<TerminalSessionInfo> initial;
  const _SessionsDialog({required this.backend, required this.openNames, required this.initial});

  @override
  State<_SessionsDialog> createState() => _SessionsDialogState();
}

class _SessionsDialogState extends State<_SessionsDialog> {
  late List<TerminalSessionInfo> _list = widget.initial;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await TerminalSessionApi.list(widget.backend);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _failed = list == null;
      if (list != null) _list = list;
    });
  }

  Future<void> _end(TerminalSessionInfo s) async {
    final ok = await _confirmEnd(context, s.name);
    if (ok != true || !mounted) return;
    final err = await TerminalSessionApi.end(widget.backend, s.name);
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err), backgroundColor: AxColors.bad));
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return AlertDialog(
      backgroundColor: AxColors.s1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AxRadius.lg), side: const BorderSide(color: AxColors.line)),
      title: Text('Sessions', style: AxTextStyles.sans.copyWith(fontSize: 16, fontWeight: FontWeight.w600)),
      content: SizedBox(
        width: 380,
        child: _list.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  _loading ? 'Loading…' : (_failed ? "Couldn't load sessions from your server." : 'No sessions running yet.'),
                  style: AxTextStyles.sans.copyWith(fontSize: 12.5, color: AxColors.fg2),
                ),
              )
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final s in _list)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      minVerticalPadding: 8,
                      leading: Icon(Icons.terminal_rounded, size: 16, color: widget.openNames.contains(s.name) ? AxColors.accent : AxColors.fg3),
                      title: Text(s.name, style: AxTextStyles.mono.copyWith(fontSize: 13)),
                      subtitle: Text(
                        '${s.runningSince(now)}${s.attached ? ' · attached elsewhere' : ''}${widget.openNames.contains(s.name) ? ' · open' : ''}',
                        style: AxTextStyles.sans.copyWith(fontSize: 11, color: AxColors.fg3),
                      ),
                      trailing: IconButton(
                        tooltip: 'End session',
                        constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                        icon: const Icon(Icons.power_settings_new_rounded, size: 15, color: AxColors.bad),
                        onPressed: () => _end(s),
                      ),
                      onTap: () => Navigator.of(context).pop(s.name),
                    ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Close', style: AxTextStyles.sans.copyWith(color: AxColors.fg3)),
        ),
      ],
    );
  }
}

class _TermTab extends StatelessWidget {
  final TerminalSession session;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onClose;
  const _TermTab({required this.session, required this.selected, required this.onTap, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final dot = switch (session.status) {
          SessionStatus.connected => AxColors.accent,
          SessionStatus.connecting => AxColors.warn,
          SessionStatus.error => AxColors.bad,
          SessionStatus.closed => AxColors.fg3,
        };
        return GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: AxMotion.base,
            padding: const EdgeInsets.only(left: 11),
            margin: const EdgeInsets.only(right: 2),
            decoration: BoxDecoration(
              color: selected ? const Color(0xFF070807) : Colors.transparent,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 5, height: 5, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
                const SizedBox(width: 7),
                Text(session.label, style: AxTextStyles.mono.copyWith(fontSize: 11.5, color: selected ? AxColors.fg : AxColors.fg3)),
                IconButton(
                  tooltip: 'Detach',
                  constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.close_rounded, size: 13, color: AxColors.fg3),
                  onPressed: onClose,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Renders one session's output, captures keystrokes, and presents
/// a mobile accessory bar with full touchscreen software keyboard input support.
class _LivePane extends StatefulWidget {
  final TerminalSession session;
  const _LivePane({super.key, required this.session});

  @override
  State<_LivePane> createState() => _LivePaneState();
}

class _LivePaneState extends State<_LivePane> {
  final _scroll = ScrollController();
  final _focus = FocusNode();
  final _mobileInputController = TextEditingController();
  final _mobileInputFocus = FocusNode();
  bool _ctrlActive = false;
  bool _showMobileInput = false;

  @override
  void dispose() {
    _scroll.dispose();
    _focus.dispose();
    _mobileInputController.dispose();
    _mobileInputFocus.dispose();
    super.dispose();
  }

  void _scrollToBottomIfNeeded() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      // Only auto-scroll if user is already near the bottom (within 120 pixels)
      final max = _scroll.position.maxScrollExtent;
      final current = _scroll.position.pixels;
      if (max - current <= 120 || current == 0) {
        _scroll.jumpTo(max);
      }
    });
  }

  void _sendCtrlKey(String keyChar) {
    if (keyChar.isEmpty) return;
    final code = keyChar.toUpperCase().codeUnitAt(0);
    if (code >= 65 && code <= 90) {
      final ctrlCode = code - 64; // 'A' (65) -> 1, 'C' (67) -> 3
      widget.session.sendInput(String.fromCharCode(ctrlCode));
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;

    final key = event.logicalKey;
    String? toSend;

    final isCtrl = HardwareKeyboard.instance.isControlPressed || _ctrlActive;

    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      toSend = '\r';
    } else if (key == LogicalKeyboardKey.backspace) {
      toSend = '\x7f';
    } else if (key == LogicalKeyboardKey.tab) {
      toSend = '\t';
    } else if (key == LogicalKeyboardKey.escape) {
      toSend = '\x1b';
    } else if (key == LogicalKeyboardKey.arrowUp) {
      toSend = '\x1b[A';
    } else if (key == LogicalKeyboardKey.arrowDown) {
      toSend = '\x1b[B';
    } else if (key == LogicalKeyboardKey.arrowRight) {
      toSend = '\x1b[C';
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      toSend = '\x1b[D';
    } else if (isCtrl && key == LogicalKeyboardKey.keyC) {
      toSend = '\x03'; // Ctrl+C
    } else if (isCtrl && key == LogicalKeyboardKey.keyD) {
      toSend = '\x04'; // Ctrl+D
    } else if (isCtrl && key == LogicalKeyboardKey.keyZ) {
      toSend = '\x1a'; // Ctrl+Z
    } else if (isCtrl && key == LogicalKeyboardKey.keyL) {
      toSend = '\x0c'; // Ctrl+L
    } else if (event.character != null && event.character!.isNotEmpty) {
      if (_ctrlActive) {
        _sendCtrlKey(event.character!);
        setState(() => _ctrlActive = false);
        return KeyEventResult.handled;
      }
      toSend = event.character;
    }

    if (_ctrlActive && toSend != null) {
      setState(() => _ctrlActive = false);
    }

    if (toSend != null) {
      widget.session.sendInput(toSend);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _submitMobileInput() {
    final text = _mobileInputController.text;
    if (text.isNotEmpty) {
      widget.session.sendInput('$text\r');
      _mobileInputController.clear();
    } else {
      widget.session.sendInput('\r');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.session,
      builder: (context, _) {
        _scrollToBottomIfNeeded();
        return Focus(
          focusNode: _focus,
          autofocus: true,
          onKeyEvent: _onKey,
          child: Container(
            width: double.infinity,
            color: const Color(0xFF070807),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.session.notice != null)
                  Container(
                    color: AxColors.warn.withValues(alpha: 0.14),
                    padding: const EdgeInsets.only(left: 14, top: 2, bottom: 2),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded, size: 14, color: AxColors.warn),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(widget.session.notice!, style: AxTextStyles.mono.copyWith(fontSize: 11.5, color: AxColors.warn)),
                        ),
                        IconButton(
                          tooltip: 'Dismiss',
                          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                          icon: const Icon(Icons.close_rounded, size: 14, color: AxColors.warn),
                          onPressed: widget.session.dismissNotice,
                        ),
                      ],
                    ),
                  ),

                // Error or Reconnect Header
                if (widget.session.status == SessionStatus.error || widget.session.status == SessionStatus.closed)
                  Container(
                    color: widget.session.status == SessionStatus.error ? AxColors.bad.withValues(alpha: 0.15) : AxColors.s2,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    child: Row(
                      children: [
                        Icon(
                          widget.session.status == SessionStatus.error ? Icons.error_outline_rounded : Icons.info_outline_rounded,
                          size: 14,
                          color: widget.session.status == SessionStatus.error ? AxColors.bad : AxColors.fg2,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.session.status == SessionStatus.error
                                ? (widget.session.error ?? 'Connection error')
                                : 'Session closed (exit ${widget.session.exitCode ?? 0})',
                            style: AxTextStyles.mono.copyWith(
                              fontSize: 11.5,
                              color: widget.session.status == SessionStatus.error ? AxColors.bad : AxColors.fg2,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            backgroundColor: AxColors.wash,
                          ),
                          icon: const Icon(Icons.refresh_rounded, size: 12, color: AxColors.accent),
                          label: Text('Reconnect', style: AxTextStyles.sans.copyWith(fontSize: 11.5, color: AxColors.accent, fontWeight: FontWeight.bold)),
                          onPressed: () => widget.session.reconnect(),
                        ),
                      ],
                    ),
                  ),

                if (widget.session.status == SessionStatus.connecting)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Row(
                      children: [
                        const SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5, color: AxColors.warn)),
                        const SizedBox(width: 8),
                        Text('connecting to shell…', style: AxTextStyles.mono.copyWith(fontSize: 11.5, color: AxColors.fg3)),
                      ],
                    ),
                  ),

                // Main Terminal Scroll Output
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      _focus.requestFocus();
                      if (_isMobile && !_showMobileInput) {
                        setState(() => _showMobileInput = true);
                        _mobileInputFocus.requestFocus();
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: SingleChildScrollView(
                        controller: _scroll,
                        child: SelectableText(
                          widget.session.output.isEmpty && widget.session.status == SessionStatus.connected
                              ? (widget.session.noDataTimedOut
                                  ? 'Still nothing from your server. Check the tunnel is connected (top bar) or open Settings.'
                                  : 'Waiting for prompt…')
                              : widget.session.output,
                          style: AxTextStyles.mono.copyWith(fontSize: 12, height: 1.45, color: AxColors.fg),
                        ),
                      ),
                    ),
                  ),
                ),

                // Inline Mobile Direct Text Input Row (only on mobile when requested)
                if (_isMobile && _showMobileInput)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: const BoxDecoration(
                      color: AxColors.s2,
                      border: Border(top: BorderSide(color: AxColors.line)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.chevron_right_rounded, size: 16, color: AxColors.accent),
                        const SizedBox(width: 6),
                        Expanded(
                          child: TextField(
                            controller: _mobileInputController,
                            focusNode: _mobileInputFocus,
                            autocorrect: false,
                            enableSuggestions: false,
                            style: AxTextStyles.mono.copyWith(fontSize: 13, color: AxColors.fg),
                            decoration: InputDecoration(
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(vertical: 4),
                              border: InputBorder.none,
                              hintText: 'Type command or characters…',
                              hintStyle: AxTextStyles.mono.copyWith(fontSize: 12, color: AxColors.fg3),
                            ),
                            onSubmitted: (_) => _submitMobileInput(),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.send_rounded, size: 15, color: AxColors.accent),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: _submitMobileInput,
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.keyboard_hide_rounded, size: 16, color: AxColors.fg3),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () {
                            _mobileInputFocus.unfocus();
                            setState(() => _showMobileInput = false);
                          },
                        ),
                      ],
                    ),
                  ),

                // Virtual Keyboard Accessory Bar - shown exclusively on touch mobile platforms
                if (_isMobile) _buildAccessoryBar(),
              ],
            ),
          ),
        );
      },
    );
  }

  bool get _isMobile =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.android);

  Widget _buildAccessoryBar() {
    return Container(
      decoration: const BoxDecoration(
        color: AxColors.s1,
        border: Border(top: BorderSide(color: AxColors.line)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _AccessoryKey(
              label: _showMobileInput ? 'KBD ▼' : 'KBD ▲',
              onTap: () {
                setState(() => _showMobileInput = !_showMobileInput);
                if (_showMobileInput) {
                  _mobileInputFocus.requestFocus();
                } else {
                  _mobileInputFocus.unfocus();
                }
              },
            ),
            _AccessoryKey(label: 'ESC', onTap: () => widget.session.sendInput('\x1b')),
            _AccessoryKey(label: 'TAB', onTap: () => widget.session.sendInput('\t')),
            _AccessoryKey(
              label: 'CTRL',
              isActive: _ctrlActive,
              onTap: () => setState(() => _ctrlActive = !_ctrlActive),
            ),
            _AccessoryKey(label: 'CTRL+C', onTap: () => widget.session.sendInput('\x03'), isAccent: true),
            _AccessoryKey(label: 'CTRL+D', onTap: () => widget.session.sendInput('\x04')),
            _AccessoryKey(label: '▲', onTap: () => widget.session.sendInput('\x1b[A')),
            _AccessoryKey(label: '▼', onTap: () => widget.session.sendInput('\x1b[B')),
            _AccessoryKey(label: 'CLEAR', onTap: () {
              widget.session.clearOutput();
              widget.session.sendInput('\x0c');
            }),
            _AccessoryKey(label: 'PASTE', onTap: () async {
              final data = await Clipboard.getData('text/plain');
              if (data?.text != null && data!.text!.isNotEmpty) {
                widget.session.sendInput(data.text!);
              }
            }),
          ],
        ),
      ),
    );
  }
}

class _AccessoryKey extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool isActive;
  final bool isAccent;

  const _AccessoryKey({
    required this.label,
    required this.onTap,
    this.isActive = false,
    this.isAccent = false,
  });

  @override
  Widget build(BuildContext context) {
    Color bg = AxColors.s2;
    Color fg = AxColors.fg2;
    Border? border = Border.all(color: AxColors.line);

    if (isActive) {
      bg = AxColors.accent.withValues(alpha: 0.2);
      fg = AxColors.accent;
      border = Border.all(color: AxColors.accent);
    } else if (isAccent) {
      fg = AxColors.warn;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(5),
        child: Container(
          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(5),
            border: border,
          ),
          child: Text(
            label,
            style: AxTextStyles.mono.copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ),
      ),
    );
  }
}

class _UnpairedPrompt extends StatelessWidget {
  final VoidCallback onPaired;
  const _UnpairedPrompt({required this.onPaired});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: AxCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('No backend paired', style: AxTextStyles.sans.copyWith(fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(
                'Terminal needs a paired backend to open a real shell session. Run `archangeld pair <name>` on the server and paste (or scan) the code it prints.',
                style: AxTextStyles.sans.copyWith(fontSize: 12.5, color: AxColors.fg2, height: 1.5),
              ),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerLeft,
                child: GestureDetector(
                  onTap: () => _showPairDialog(context, onPaired),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                    decoration: BoxDecoration(
                      color: AxColors.wash,
                      borderRadius: BorderRadius.circular(AxRadius.pill),
                      border: Border.all(color: AxColors.accent.withValues(alpha: 0.22)),
                    ),
                    child: Text('Pair backend', style: AxTextStyles.sans.copyWith(fontSize: 12, fontWeight: FontWeight.w700, color: AxColors.accent)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPairDialog(BuildContext context, VoidCallback onPaired) {
    // ArchangeldConnection.pair() notifies listeners itself, and
    // TerminalScreen.build watches it - onPaired is just a belt-and-braces
    // rebuild trigger, the actual pairing happens in the shared dialog.
    showPairingDialog(context).then((_) => onPaired());
  }
}
