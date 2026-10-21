import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:xterm/xterm.dart';

import '../data/app_state.dart';
import '../services/admin_mode_service.dart';
import '../services/archangeld_connection.dart';
import '../services/local_kv_store.dart';
import '../services/server_registry.dart';
import '../services/terminal_session.dart';
import '../ui/ui.dart';
import '../ui/screens/terminal/sessions_dialog.dart';
import '../ui/screens/terminal/terminal_pane.dart';
import '../ui/screens/terminal/terminal_workspace.dart';
import '../widgets/pairing_dialog.dart';

/// LocalKvStore key for the terminal text size (shared by all sessions).
const String kTerminalFontSizeKey = 'terminal_font_size';

class TerminalScreen extends StatefulWidget {
  const TerminalScreen({super.key});

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  final List<TerminalSession> _sessions = [];
  final Map<TerminalSession, TerminalController> _controllers = {};
  List<TerminalSessionInfo> _serverSessions = const [];
  int _tab = 0;
  bool _bootstrapping = false;
  bool _bootstrapped = false;
  double _fontSize = kTerminalDefaultFont;
  String? _servicesHost;

  @override
  void initState() {
    super.initState();
    _loadFontSize();
  }

  @override
  void dispose() {
    for (final s in _sessions) {
      s.dispose();
    }
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadFontSize() async {
    try {
      final raw = await LocalKvStore.instance.read(kTerminalFontSizeKey);
      final v = raw == null ? null : double.tryParse(raw);
      if (v != null && mounted) {
        setState(() => _fontSize = v.clamp(kTerminalMinFont, kTerminalMaxFont));
      }
    } catch (_) {
      // Text size is a convenience; the default is fine if storage fails.
    }
  }

  void _setFontSize(double v) {
    final size = v.clamp(kTerminalMinFont, kTerminalMaxFont).toDouble();
    setState(() => _fontSize = size);
    LocalKvStore.instance.write(kTerminalFontSizeKey, size.toString()).catchError((_) {});
  }

  void _syncAdminMode(ArchangeldConnection backend) {
    final host = backend.isPaired ? backend.host : null;
    if (host == _servicesHost) return;
    _servicesHost = host;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AdminModeService>().init(backend);
    });
  }

  TerminalController _controllerFor(TerminalSession s) => _controllers.putIfAbsent(s, TerminalController.new);

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
    final controller = _controllers.remove(session);
    // The pane still references it until the next frame rebuilds without it.
    WidgetsBinding.instance.addPostFrameCallback((_) => controller?.dispose());
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
    final ok = await confirmEndSession(context, session.name);
    if (!ok || !mounted) return;
    final err = await TerminalSessionApi.end(backend, session.name);
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    final i = _sessions.indexOf(session);
    if (i >= 0) _detachSession(i, backend);
  }

  Future<void> _showSessions(ArchangeldConnection backend) async {
    final picked = await showDialog<String>(
      context: context,
      builder: (_) => SessionsDialog(backend: backend, openNames: _sessions.map((s) => s.name).toSet(), initial: _serverSessions),
    );
    if (picked != null && mounted) _openSession(backend, name: picked);
    if (mounted) _refreshServerSessions(backend);
  }

  void _copy() {
    final session = _sessions[_tab];
    final text = selectedTerminalText(session, _controllerFor(session));
    final messenger = ScaffoldMessenger.of(context);
    if (text == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Select some text first: drag across it (press and hold on a phone).'),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }
    Clipboard.setData(ClipboardData(text: text));
    messenger.showSnackBar(const SnackBar(content: Text('Copied'), duration: Duration(seconds: 1)));
  }

  Future<void> _paste() async {
    final session = _sessions[_tab];
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text != null && text.isNotEmpty) session.pasteText(text);
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
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('This folder name contains control characters; open it manually.')));
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
      return EmptyState(
        icon: Icons.terminal,
        title: 'Connect to your server first',
        message: 'The terminal opens a real shell on your server, so this device needs to be paired with it.',
        actionLabel: 'Pair with your server',
        // ArchangeldConnection.pair() notifies listeners itself, so this
        // screen rebuilds when pairing finishes.
        onAction: () => showPairingDialog(context),
      );
    }

    if (_sessions.isEmpty) {
      if (!_bootstrapped && !_bootstrapping && pendingDir == null && pendingCmd == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _sessions.isEmpty) _bootstrap(backend);
        });
      } else if (_bootstrapped && pendingDir == null && pendingCmd == null) {
        // All tabs were detached: offer a way back in rather than auto-reopening.
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                EmptyState(
                  icon: Icons.terminal,
                  title: 'No session open',
                  message: 'Detached sessions keep running on your server.',
                  actionLabel: 'New session',
                  onAction: () => _openSession(backend),
                ),
                AxButton.secondary(label: 'Sessions on this server', onPressed: () => _showSessions(backend)),
              ],
            ),
          ),
        );
      }
      return const LoadingState(message: 'Opening your terminal...');
    }

    final adminMode = context.watch<AdminModeService>();
    final registry = context.watch<ServerRegistry>();
    _syncAdminMode(backend);

    final currentSession = _sessions.isNotEmpty ? _sessions[_tab] : null;
    String? runningSince;
    if (currentSession != null) {
      final info = _serverSessions.where((s) => s.name == currentSession.name).firstOrNull;
      runningSince = info?.runningSince(DateTime.now());
    }

    return TerminalWorkspace(
      sessions: _sessions,
      selected: _tab,
      controllerFor: _controllerFor,
      fontSize: _fontSize,
      onSelect: (i) => setState(() => _tab = i),
      onDetach: (i) => _detachSession(i, backend),
      onEnd: (i) => _endSession(i, backend),
      onNew: () => _openSession(backend),
      onShowSessions: () => _showSessions(backend),
      onFontSize: _setFontSize,
      onCopy: _copy,
      onPaste: _paste,
      adminModeEnabled: adminMode.enabled,
      serverName: registry.active?.name,
      onOpenAdminMode: () => context.read<AppState>().go(AxSection.settings),
      runningSinceText: runningSince,
    );
  }
}
