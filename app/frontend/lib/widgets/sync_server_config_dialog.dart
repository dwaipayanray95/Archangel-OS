import 'package:flutter/material.dart';

import '../services/ssh_credentials.dart';
import '../services/ssh_transport.dart';
import '../services/vps_setup_service.dart';
import '../theme/tokens.dart';
import 'host_key_dialog.dart';
import 'passphrase_prompt_dialog.dart';

/// Shown from Settings to let users synchronize or repair the server's
/// systemd service definition and sudoers configuration over SSH without
/// needing to touch a terminal or deploy script.
Future<void> showSyncServerConfigDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => const SyncServerConfigDialog(),
  );
}

class SyncServerConfigDialog extends StatefulWidget {
  const SyncServerConfigDialog({super.key});

  @override
  State<SyncServerConfigDialog> createState() => _SyncServerConfigDialogState();
}

enum _Step { credentials, progress, done }

class _SyncServerConfigDialogState extends State<SyncServerConfigDialog> {
  _Step _step = _Step.credentials;

  final _hostController = TextEditingController();
  final _usernameController = TextEditingController(text: 'ubuntu');
  final _privateKeyController = TextEditingController();
  final _passphraseController = TextEditingController();
  bool _loadingSavedKey = true;
  bool _connecting = false;
  bool _rememberKey = false;
  String? _connectError;

  SshTransport? _transport;
  final List<SetupProgress> _log = [];
  Object? _runError;

  @override
  void initState() {
    super.initState();
    _restoreSavedKey();
  }

  Future<void> _restoreSavedKey() async {
    final creds = await unlockSavedSshCredentials(context);
    if (!mounted) return;
    setState(() {
      if (creds != null) {
        _hostController.text = creds.host;
        _usernameController.text = creds.username;
        _privateKeyController.text = creds.privateKeyPem;
        _rememberKey = true;
      }
      _loadingSavedKey = false;
    });
  }

  @override
  void dispose() {
    _hostController.dispose();
    _usernameController.dispose();
    _privateKeyController.dispose();
    _passphraseController.dispose();
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
    final host = _hostController.text.trim();
    final username = _usernameController.text.trim();
    final privateKey = _privateKeyController.text.trim();
    if (host.isEmpty || username.isEmpty || privateKey.isEmpty) {
      setState(() => _connectError = 'Host, SSH username, and private key are all required.');
      return;
    }

    setState(() {
      _connecting = true;
      _connectError = null;
    });

    try {
      final passphrase = _passphraseController.text;
      final transport = await Dartssh2Transport.connect(
        host: host,
        port: 22,
        username: username,
        privateKeyPem: privateKey,
        passphrase: passphrase.isEmpty ? null : passphrase,
        onUnknownHostKey: _confirmHostKey,
      );

      if (_rememberKey) {
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

  void _appendOrUpdate(SetupProgress event) {
    if (_log.isNotEmpty && _log.last.stage == event.stage) {
      _log[_log.length - 1] = event;
    } else {
      _log.add(event);
    }
  }

  void _runSync() {
    final service = VpsSetupService(_transport!);
    service.syncServiceAndPermissions().listen(
      (event) => setState(() => _appendOrUpdate(event)),
      onError: (Object e) => setState(() => _runError = e),
      onDone: () {
        if (!mounted) return;
        if (_runError == null) {
          setState(() {
            _step = _Step.done;
          });
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AxColors.s2,
      title: Text('Sync Server Permissions', style: AxTextStyles.sans.copyWith(fontSize: 15, fontWeight: FontWeight.w700)),
      content: SizedBox(
        width: 460,
        height: 360,
        child: switch (_step) {
          _Step.credentials => _buildCredentialsStep(),
          _Step.progress => _buildProgressStep(),
          _Step.done => _buildDoneStep(),
        },
      ),
      actions: switch (_step) {
        _Step.credentials => [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
            FilledButton(
              onPressed: _connecting || _loadingSavedKey ? null : _connect,
              child: _connecting ? const _MiniSpinner() : const Text('Connect & sync'),
            ),
          ],
        _Step.progress => [
            if (_runError != null) TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
          ],
        _Step.done => [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
          ],
      },
    );
  }

  Widget _buildCredentialsStep() {
    if (_loadingSavedKey) {
      return const Center(child: _MiniSpinner());
    }
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Updates the server systemd service definition and sudoers configuration to the latest Hybrid Cockpit standard. '
            'This enables persistent tmux sessions and gives the terminal full administrative power (sudo).',
            style: AxTextStyles.sans.copyWith(fontSize: 12, color: AxColors.fg2, height: 1.5),
          ),
          const SizedBox(height: 14),
          _label('Server public IP or hostname'),
          _textField(_hostController, hint: '203.0.113.5'),
          const SizedBox(height: 10),
          _label('SSH username'),
          _textField(_usernameController, hint: 'ubuntu'),
          const SizedBox(height: 10),
          _label('Private key (OpenSSH / PEM format)'),
          _textField(_privateKeyController, hint: '-----BEGIN OPENSSH PRIVATE KEY-----...', maxLines: 4),
          const SizedBox(height: 10),
          _label('Key passphrase (if encrypted)'),
          _textField(_passphraseController, hint: 'leave empty if unencrypted', obscureText: true),
          const SizedBox(height: 10),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text('Remember key for future updates', style: AxTextStyles.sans.copyWith(fontSize: 11.5)),
            value: _rememberKey,
            onChanged: (v) => setState(() => _rememberKey = v ?? false),
          ),
          if (_connectError != null) ...[
            const SizedBox(height: 8),
            Text(_connectError!, style: AxTextStyles.sans.copyWith(fontSize: 11.5, color: AxColors.bad)),
          ],
        ],
      ),
    );
  }

  Widget _buildProgressStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: ListView.builder(
            itemCount: _log.length,
            itemBuilder: (context, i) {
              final item = _log[i];
              final isLast = i == _log.length - 1;
              final showSpinner = isLast && !item.stageComplete && _runError == null;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (showSpinner)
                      const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.5, color: AxColors.accent))
                    else if (item.stageComplete)
                      const Icon(Icons.check_circle_rounded, size: 14, color: AxColors.accent)
                    else
                      const Icon(Icons.radio_button_unchecked_rounded, size: 14, color: AxColors.fg3),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        item.message,
                        style: AxTextStyles.mono.copyWith(fontSize: 11.5, color: item.stageComplete ? AxColors.fg : AxColors.fg2),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        if (_runError != null) ...[
          const SizedBox(height: 8),
          Text('Sync failed: $_runError', style: AxTextStyles.sans.copyWith(fontSize: 11.5, color: AxColors.bad)),
        ],
      ],
    );
  }

  Widget _buildDoneStep() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle_outline_rounded, size: 48, color: AxColors.accent),
          const SizedBox(height: 12),
          Text('Server Configuration Updated', style: AxTextStyles.sans.copyWith(fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(
            'The systemd unit, sudoers grants, and /home/archangel directory are configured. '
            'Persistent tmux sessions and sudo are now live.',
            textAlign: TextAlign.center,
            style: AxTextStyles.sans.copyWith(fontSize: 12, color: AxColors.fg2, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(text, style: AxTextStyles.sans.copyWith(fontSize: 11, color: AxColors.fg3)),
    );
  }

  Widget _textField(TextEditingController controller, {String? hint, int maxLines = 1, bool obscureText = false}) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      obscureText: obscureText,
      style: AxTextStyles.mono.copyWith(fontSize: 12),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: AxTextStyles.mono.copyWith(fontSize: 12, color: AxColors.fg3),
        filled: true,
        fillColor: AxColors.s1,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: AxColors.line)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: AxColors.line)),
      ),
    );
  }
}

class _MiniSpinner extends StatelessWidget {
  const _MiniSpinner();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.5, color: AxColors.accent));
  }
}
