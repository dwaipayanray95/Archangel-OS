import 'package:flutter/material.dart';

import '../../../services/archangeld_connection.dart';
import '../../../services/terminal_session.dart';
import '../../components/ax_button.dart';
import '../../components/ax_icon_button.dart';
import '../../components/ax_list_tile.dart';
import '../../components/confirm_dialog.dart';
import '../../theme.dart';

/// Asks before ending a session: ending stops everything running in it.
Future<bool> confirmEndSession(BuildContext context, String name) => showConfirmDialog(
      context,
      title: 'End session "$name"?',
      message: 'This stops everything running in this session, and anything not saved is lost. '
          'To leave it running and come back later, use Detach instead.',
      confirmLabel: 'End session',
      danger: true,
    );

/// Lists the sessions running on the server so one can be reattached or ended.
/// Pops with the chosen session name.
class SessionsDialog extends StatefulWidget {
  const SessionsDialog({super.key, required this.backend, required this.openNames, required this.initial});

  final ArchangeldConnection backend;
  final Set<String> openNames;
  final List<TerminalSessionInfo> initial;

  @override
  State<SessionsDialog> createState() => _SessionsDialogState();
}

class _SessionsDialogState extends State<SessionsDialog> {
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
    final ok = await confirmEndSession(context, s.name);
    if (!ok || !mounted) return;
    final err = await TerminalSessionApi.end(widget.backend, s.name);
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final now = DateTime.now();
    return AlertDialog(
      title: Text('Sessions on this server', style: ax.typo.title.copyWith(color: c.text)),
      content: SizedBox(
        width: 420,
        child: _list.isEmpty
            ? Padding(
                padding: EdgeInsets.symmetric(vertical: ax.space.md),
                child: Text(
                  _loading
                      ? 'Loading...'
                      : (_failed ? "Couldn't load the sessions from your server." : 'No sessions are running yet.'),
                  style: ax.typo.body.copyWith(color: c.textMuted),
                ),
              )
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final s in _list)
                    AxListTile(
                      leading: Icon(Icons.terminal, color: widget.openNames.contains(s.name) ? c.accent : c.textMuted),
                      title: s.name,
                      subtitle: '${s.runningSince(now)}'
                          '${s.attached ? ' · open on another device' : ''}'
                          '${widget.openNames.contains(s.name) ? ' · open here' : ''}',
                      trailing: AxIconButton(
                        icon: Icons.power_settings_new,
                        tooltip: 'End session ${s.name}',
                        color: c.danger,
                        onPressed: () => _end(s),
                      ),
                      onTap: () => Navigator.of(context).pop(s.name),
                    ),
                ],
              ),
      ),
      actions: [AxButton.ghost(label: 'Close', onPressed: () => Navigator.of(context).pop())],
    );
  }
}
