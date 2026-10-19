import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/server_registry.dart';
import '../services/ssh_credentials.dart';
import '../services/ssh_transport.dart';
import '../services/vps_setup_service.dart';
import '../ui/screens/settings/ssh_dialog_helpers.dart';
import '../ui/ui.dart';
import 'host_key_dialog.dart';
import 'passphrase_prompt_dialog.dart';

/// What the dialog does once it has an SSH connection - both modes need
/// the same host/user/key form, so they share this dialog.
enum SyncServerMode {
  /// Re-apply the systemd unit and permissions (leaves Admin mode as it is).
  sync,

  /// Turn Admin mode (passwordless sudo for the archangel user) back on -
  /// the one thing the app can't do over its own API.
  enableAdminMode,
}

/// Shown from Settings to let users synchronize or repair the server's
/// systemd service definition and sudoers configuration over SSH without
/// needing to touch a terminal or deploy script - or, with
/// [SyncServerMode.enableAdminMode], to turn Admin mode back on.
Future<void> showSyncServerConfigDialog(BuildContext context, {SyncServerMode mode = SyncServerMode.sync}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => SyncServerConfigDialog(mode: mode),
  );
}

class SyncServerConfigDialog extends StatefulWidget {
  final SyncServerMode mode;
  const SyncServerConfigDialog({super.key, this.mode = SyncServerMode.sync});

  @override
  State<SyncServerConfigDialog> createState() => _SyncServerConfigDialogState();
}

enum _Step { credentials, progress, done }

class _SyncServerConfigDialogState extends State<SyncServerConfigDialog> {
  _Step _step = _Step.credentials;

  final _creds = SshCredentialsController();
  bool _connecting = false;
  String? _connectError;

  SshTransport? _transport;
  final List<SetupProgress> _log = [];
  Object? _runError;

  @override
  void initState() {
    super.initState();
    prefillFromProfile(_creds, context.read<ServerRegistry>().active);
    _creds.addListener(_rebuild);
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _creds.dispose();
    _transport?.close();
    super.dispose();
  }

  Future<bool> _confirmHostKey({
    required String host,
    required String keyType,
    required String fingerprint,
    required bool isMismatch,
  }) async {
    if (!mounted) return false;
    return showHostKeyConfirmDialog(context, host: host, keyType: keyType, fingerprint: fingerprint, isMismatch: isMismatch);
  }

  Future<void> _connect() async {
    final problem = _creds.validate();
    if (problem != null) {
      setState(() => _connectError = problem);
      return;
    }
    final host = _creds.hostText;
    final username = _creds.usernameText;
    final privateKey = _creds.privateKeyText;

    setState(() {
      _connecting = true;
      _connectError = null;
    });

    try {
      final transport = await Dartssh2Transport.connect(
        host: host,
        port: 22,
        username: username,
        privateKeyPem: privateKey,
        passphrase: _creds.keyPassphraseOrNull,
        onUnknownHostKey: _confirmHostKey,
      );

      if (_creds.rememberKey) {
        if (mounted) {
          final savePassphrase = await promptForPassphrase(
            context,
            title: 'Set a passphrase',
            message: 'Choose a passphrase (at least 8 characters) to protect this key. You\'ll need it to unlock the key later - there\'s no way to recover it without the passphrase.',
            confirm: true,
          );
          if (savePassphrase != null) {
            await saveSshCredentials(savePassphrase, SavedSshCredentials(host: host, username: username, privateKeyPem: privateKey));
          }
        }
      } else {
        await clearSavedSshCredentials();
      }

      if (!mounted) {
        transport.close();
        return;
      }

      _transport = transport;
      setState(() {
        _connecting = false;
        _step = _Step.progress;
      });
      _runSync();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _connectError = 'Could not connect: $e';
      });
    }
  }

  bool get _isAdminMode => widget.mode == SyncServerMode.enableAdminMode;

  void _runSync() {
    final service = VpsSetupService(_transport!);
    final stream = _isAdminMode ? service.enableAdminMode() : service.syncServiceAndPermissions();
    stream.listen(
      (event) => setState(() => appendProgress(_log, event)),
      onError: (Object e) => setState(() => _runError = e),
      onDone: () {
        if (!mounted) return;
        if (_runError == null) setState(() => _step = _Step.done);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    return AlertDialog(
      scrollable: true,
      title: Text(_isAdminMode ? 'Turn on Admin mode' : 'Repair server permissions', style: ax.typo.title.copyWith(color: c.text)),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: switch (_step) {
          _Step.credentials => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _isAdminMode
                      ? 'Admin mode lets the terminal and Archangel run commands as root (sudo). '
                          'Turning it on needs your SSH key, because the app can only turn it off by itself.'
                      : 'Updates the server\'s service definition and permissions to the latest standard, '
                          'including persistent terminal sessions. Admin mode (sudo) is left as it is - on or off.',
                  style: ax.typo.body.copyWith(color: c.textMuted),
                ),
                SizedBox(height: ax.space.lg),
                SshCredentialsForm(
                  controller: _creds,
                  enabled: !_connecting,
                  errorText: _connectError,
                  onPickKeyFile: () => pickSshKeyFile(context),
                ),
              ],
            ),
          _Step.progress => SetupProgressLog(
              log: _log,
              error: _runError,
              errorTitle: _isAdminMode ? 'Could not turn on Admin mode' : 'Repair failed',
            ),
          _Step.done => SetupDoneView(
              title: _isAdminMode ? 'Admin mode is on' : 'Server configuration updated',
              message: _isAdminMode
                  ? 'The terminal and Archangel can run commands as root (sudo) again.'
                  : 'The service definition and the /home/archangel folder are set up. Persistent terminal sessions are live.',
            ),
        },
      ),
      actions: switch (_step) {
        _Step.credentials => [
            AxButton.ghost(label: 'Cancel', onPressed: () => Navigator.of(context).pop()),
            AxButton(
              label: _isAdminMode ? 'Connect & turn on' : 'Connect & repair',
              loading: _connecting,
              onPressed: _creds.restoring ? null : _connect,
            ),
          ],
        _Step.progress => [
            if (_runError != null) AxButton.ghost(label: 'Close', onPressed: () => Navigator.of(context).pop()),
          ],
        _Step.done => [AxButton.ghost(label: 'Close', onPressed: () => Navigator.of(context).pop())],
      },
    );
  }
}
