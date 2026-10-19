import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/archangeld_connection.dart';
import '../services/server_registry.dart';
import '../services/ssh_transport.dart';
import '../services/vps_setup_service.dart';
import '../services/wireguard_controller.dart';
import '../ui/screens/settings/ssh_dialog_helpers.dart';
import '../ui/ui.dart';
import 'host_key_dialog.dart';

/// The word the user types to confirm an uninstall.
const kUninstallConfirmWord = 'UNINSTALL';

/// Shown when the user taps "Uninstall from server" in Settings. Tears down
/// archangeld and WireGuard on the active server entirely - see
/// VpsSetupService.uninstall's doc comment for exactly what is and isn't
/// removed. One-way: there is no rollback, only the confirmation step
/// below stands between a tap and an irreversible teardown.
///
/// [connector] exists for tests; the app uses real SSH.
Future<void> showUninstallDialog(BuildContext context, {SshConnector? connector}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => UninstallDialog(connector: connector),
  );
}

class UninstallDialog extends StatefulWidget {
  const UninstallDialog({super.key, this.connector});

  final SshConnector? connector;

  @override
  State<UninstallDialog> createState() => _UninstallDialogState();
}

enum _UninstallStep { confirm, credentials, progress, done }

class _UninstallDialogState extends State<UninstallDialog> {
  _UninstallStep _step = _UninstallStep.confirm;
  final _confirmController = TextEditingController();

  final _creds = SshCredentialsController();
  bool _connecting = false;
  String? _connectError;

  SshTransport? _transport;
  final List<SetupProgress> _log = [];
  Object? _runError;

  /// The server being uninstalled: the active profile at the time the
  /// dialog opened (its ports and SSH address are used throughout).
  late final ServerProfile? _profile = context.read<ServerRegistry>().active;

  @override
  void initState() {
    super.initState();
    prefillFromProfile(_creds, _profile);
    _creds.addListener(_rebuild);
    _confirmController.addListener(_rebuild);
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _confirmController.dispose();
    _creds.dispose();
    _transport?.close();
    super.dispose();
  }

  bool get _confirmTextValid => _confirmController.text.trim() == kUninstallConfirmWord;

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

    setState(() {
      _connecting = true;
      _connectError = null;
    });

    try {
      final connect = widget.connector ?? Dartssh2Transport.connect;
      final transport = await connect(
        host: _creds.hostText,
        port: 22,
        username: _creds.usernameText,
        privateKeyPem: _creds.privateKeyText,
        passphrase: _creds.keyPassphraseOrNull,
        onUnknownHostKey: _confirmHostKey,
      );
      if (!mounted) {
        transport.close();
        return;
      }
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

  void _runUninstall() {
    final service = VpsSetupService(_transport!);
    // The ports this server was installed with, not hard-coded defaults.
    service.uninstall(appPort: _profile?.appPort ?? 8443, wgPort: _profile?.wgPort ?? 51820).listen(
      (event) => setState(() => appendProgress(_log, event)),
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
          setState(() => _step = _UninstallStep.done);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    return AlertDialog(
      scrollable: true,
      title: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: c.danger),
          SizedBox(width: ax.space.sm),
          Expanded(child: Text('Uninstall from server', style: ax.typo.title.copyWith(color: c.danger))),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: switch (_step) {
          _UninstallStep.confirm => _buildConfirmStep(ax),
          _UninstallStep.credentials => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'This signs in to your server over SSH, the same way setup did, to stop Archangel and remove it.',
                  style: ax.typo.body.copyWith(color: c.textMuted),
                ),
                SizedBox(height: ax.space.lg),
                SshCredentialsForm(
                  controller: _creds,
                  showRememberKey: false,
                  enabled: !_connecting,
                  errorText: _connectError,
                  onPickKeyFile: () => pickSshKeyFile(context),
                ),
              ],
            ),
          _UninstallStep.progress => SetupProgressLog(log: _log, error: _runError, errorTitle: 'Uninstall failed'),
          _UninstallStep.done => const SetupDoneView(title: 'Archangel and its secure connection have been removed from the server.'),
        },
      ),
      actions: switch (_step) {
        _UninstallStep.confirm => [
            AxButton.ghost(label: 'Cancel', onPressed: () => Navigator.of(context).pop()),
            AxButton.danger(
              label: 'Continue',
              onPressed: _confirmTextValid ? () => setState(() => _step = _UninstallStep.credentials) : null,
            ),
          ],
        _UninstallStep.credentials => [
            AxButton.ghost(label: 'Cancel', onPressed: () => Navigator.of(context).pop()),
            AxButton.danger(label: 'Connect & uninstall', loading: _connecting, onPressed: _creds.restoring ? null : _connect),
          ],
        _UninstallStep.progress => [
            if (_runError != null) AxButton.ghost(label: 'Close', onPressed: () => Navigator.of(context).pop()),
          ],
        _UninstallStep.done => [AxButton.ghost(label: 'Close', onPressed: () => Navigator.of(context).pop())],
      },
    );
  }

  Widget _buildConfirmStep(ArchangelTheme ax) {
    final c = ax.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'This stops and removes Archangel from your server and shuts down its secure connection. '
          'This device and every other device paired to this server will lose access to it. '
          'It cannot be undone from the app - you would have to set the server up again from scratch.',
          style: ax.typo.body.copyWith(color: c.danger),
        ),
        SizedBox(height: ax.space.sm),
        Text(
          'The server itself (its system, files and SSH access) is left untouched.',
          style: ax.typo.body.copyWith(color: c.textMuted),
        ),
        SizedBox(height: ax.space.lg),
        TextField(
          controller: _confirmController,
          autofocus: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(labelText: 'Type "$kUninstallConfirmWord" to continue'),
        ),
      ],
    );
  }
}
