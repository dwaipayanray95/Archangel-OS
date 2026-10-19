import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/archangeld_connection.dart';
import '../services/server_registry.dart';
import '../services/ssh_credentials.dart';
import '../services/ssh_transport.dart';
import '../services/vps_setup_service.dart';
import '../services/wireguard_controller.dart';
import '../theme/tokens.dart';
import 'host_key_dialog.dart';

/// Shown when the user taps "Uninstall backend" in Settings. Tears down
/// archangeld and WireGuard on the paired server entirely - see
/// VpsSetupService.uninstall's doc comment for exactly what is and isn't
/// removed. One-way: there is no rollback, only the confirmation step
/// below stands between a tap and an irreversible teardown.
Future<void> showUninstallDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => const UninstallDialog(),
  );
}

class UninstallDialog extends StatefulWidget {
  const UninstallDialog({super.key});

  @override
  State<UninstallDialog> createState() => _UninstallDialogState();
}

enum _UninstallStep { confirm, credentials, progress, done }

class _UninstallDialogState extends State<UninstallDialog> {
  _UninstallStep _step = _UninstallStep.confirm;
  final _confirmController = TextEditingController();

  final _hostController = TextEditingController();
  final _usernameController = TextEditingController(text: 'ubuntu');
  final _privateKeyController = TextEditingController();
  final _passphraseController = TextEditingController();
  bool _loadingSavedKey = true;
  bool _connecting = false;
  String? _connectError;

  SshTransport? _transport;
  final List<SetupProgress> _log = [];
  Object? _runError;
  bool _succeeded = false;

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
      }
      _loadingSavedKey = false;
    });
  }

  @override
  void dispose() {
    _confirmController.dispose();
    _hostController.dispose();
    _usernameController.dispose();
    _privateKeyController.dispose();
    _passphraseController.dispose();
    _transport?.close();
    super.dispose();
  }

  bool get _confirmTextValid {
    final text = _confirmController.text.trim();
    return text == 'UNINSTALL' || (text.isNotEmpty && text == _hostController.text.trim());
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
      if (!mounted) return;
      _transport = transport;
      setState(() {
        _connecting = false;
        _step = _UninstallStep.progress;
      });
      _runUninstall();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _connectError = 'Could not connect: $e';
      });
    }
  }

  // Each stage emits a "starting" event followed later by a "complete"
  // one for the same stage - replace the row in place instead of
  // appending a second one, so the log reads as a checklist that ticks
  // off item by item rather than showing both an empty and a filled
  // circle for the same step.
  void _appendOrUpdate(SetupProgress event) {
    if (_log.isNotEmpty && _log.last.stage == event.stage) {
      _log[_log.length - 1] = event;
    } else {
      _log.add(event);
    }
  }

  void _runUninstall() {
    final service = VpsSetupService(_transport!);
    service.uninstall(appPort: 8443, wgPort: 51820).listen(
      (event) => setState(() => _appendOrUpdate(event)),
      onError: (Object e) => setState(() => _runError = e),
      onDone: () async {
        if (!mounted) return;
        if (_runError == null) {
          // The server this device was paired to no longer exists -
          // clear local pairing state so the app doesn't keep showing
          // "paired" against a dead server.
          await removeActiveServer(
            registry: context.read<ServerRegistry>(),
            wg: context.read<WireGuardController>(),
            backend: context.read<ArchangeldConnection>(),
          );
          if (!mounted) return;
          setState(() {
            _succeeded = true;
            _step = _UninstallStep.done;
          });
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AxColors.s2,
      title: Text(
        'Uninstall backend',
        style: AxTextStyles.sans.copyWith(fontSize: 15, fontWeight: FontWeight.w700, color: AxColors.bad),
      ),
      content: SizedBox(
        width: 460,
        height: 360,
        child: switch (_step) {
          _UninstallStep.confirm => _buildConfirmStep(),
          _UninstallStep.credentials => _buildCredentialsStep(),
          _UninstallStep.progress => _buildProgressStep(),
          _UninstallStep.done => _buildDoneStep(),
        },
      ),
      actions: switch (_step) {
        _UninstallStep.confirm => [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AxColors.bad),
              onPressed: _confirmTextValid ? () => setState(() => _step = _UninstallStep.credentials) : null,
              child: const Text('Continue'),
            ),
          ],
        _UninstallStep.credentials => [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AxColors.bad),
              onPressed: _connecting || _loadingSavedKey ? null : _connect,
              child: _connecting ? const _MiniSpinner() : const Text('Connect & uninstall'),
            ),
          ],
        _UninstallStep.progress => [
            if (_runError != null) TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
          ],
        _UninstallStep.done => [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
          ],
      },
    );
  }

  Widget _buildConfirmStep() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This will stop and remove archangeld from your server, and tear down its '
            'WireGuard tunnel entirely. This device and every other device paired to this '
            'server will lose connectivity to it. This cannot be undone from the app - '
            'you would need to run the setup wizard again from scratch.',
            style: AxTextStyles.sans.copyWith(fontSize: 12, color: AxColors.bad, height: 1.5),
          ),
          const SizedBox(height: 6),
          Text(
            'The server\'s baseline OS setup (packages, swapfile, SSH access) is left untouched.',
            style: AxTextStyles.sans.copyWith(fontSize: 12, color: AxColors.fg2, height: 1.5),
          ),
          const SizedBox(height: 14),
          _label('Type UNINSTALL to continue'),
          _textField(_confirmController, hint: 'UNINSTALL', onChanged: (_) => setState(() {})),
        ],
      ),
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
            'This connects over SSH the same way the setup wizard did, to stop the service '
            'and remove it as root.',
            style: AxTextStyles.sans.copyWith(fontSize: 12, color: AxColors.fg2, height: 1.5),
          ),
          const SizedBox(height: 14),
          _label('Server public IP or hostname'),
          _textField(_hostController, hint: '203.0.113.5'),
          const SizedBox(height: 10),
          _label('SSH username'),
          _textField(_usernameController, hint: 'ubuntu'),
          const SizedBox(height: 10),
          _label('SSH private key'),
          _textField(_privateKeyController, hint: '-----BEGIN OPENSSH PRIVATE KEY-----', maxLines: 4, monospace: true),
          const SizedBox(height: 10),
          _label('SSH key passphrase (leave blank if none)'),
          _textField(_passphraseController, obscure: true),
          if (_connectError != null) ...[
            const SizedBox(height: 10),
            Text(_connectError!, style: AxTextStyles.mono.copyWith(fontSize: 11.5, color: AxColors.bad)),
          ],
        ],
      ),
    );
  }

  Widget _buildProgressStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_runError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text('Uninstall failed:\n$_runError', style: AxTextStyles.mono.copyWith(fontSize: 11.5, color: AxColors.bad)),
          ),
        Expanded(
          child: ListView.builder(
            itemCount: _log.length,
            itemBuilder: (context, i) {
              final entry = _log[i];
              final isActive = !entry.stageComplete && _runError == null;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isActive)
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AxColors.accent),
                      )
                    else
                      Icon(
                        entry.stageComplete ? Icons.check_circle : Icons.radio_button_unchecked,
                        size: 14,
                        color: entry.stageComplete ? AxColors.accent : AxColors.fg3,
                      ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(entry.message, style: AxTextStyles.mono.copyWith(fontSize: 12, color: AxColors.fg2))),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDoneStep() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, color: AxColors.accent, size: 40),
          const SizedBox(height: 12),
          Text(
            _succeeded ? 'archangeld and WireGuard have been removed from the server.' : 'Done.',
            style: AxTextStyles.sans.copyWith(fontSize: 13, fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(text, style: AxTextStyles.sans.copyWith(fontSize: 11, color: AxColors.fg3)),
      );

  Widget _textField(
    TextEditingController controller, {
    String? hint,
    int maxLines = 1,
    bool monospace = false,
    bool obscure = false,
    void Function(String)? onChanged,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      obscureText: obscure,
      onChanged: onChanged,
      style: monospace ? AxTextStyles.mono.copyWith(fontSize: 12) : AxTextStyles.sans.copyWith(fontSize: 13),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: AxTextStyles.sans.copyWith(fontSize: 12, color: AxColors.fg3),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        filled: true,
        fillColor: AxColors.s1,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AxColors.line)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AxColors.line)),
      ),
    );
  }
}

class _MiniSpinner extends StatelessWidget {
  const _MiniSpinner();
  @override
  Widget build(BuildContext context) => const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2));
}
