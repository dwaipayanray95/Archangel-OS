import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/server_registry.dart';
import '../services/ssh_credentials.dart';
import '../ui/screens/settings/ssh_dialog_helpers.dart';
import '../ui/ui.dart';
import 'passphrase_prompt_dialog.dart';

/// Lets the user view/replace/forget the SSH key "Remember this key"
/// saved (from the setup wizard or an update), without having to go through
/// an actual update/uninstall flow just to rotate it. Doesn't connect over
/// SSH at all - purely local secure-storage management.
Future<void> showManageSshKeyDialog(BuildContext context) {
  return showDialog<void>(context: context, builder: (context) => const ManageSshKeyDialog());
}

class ManageSshKeyDialog extends StatefulWidget {
  const ManageSshKeyDialog({super.key});

  @override
  State<ManageSshKeyDialog> createState() => _ManageSshKeyDialogState();
}

class _ManageSshKeyDialogState extends State<ManageSshKeyDialog> {
  final _creds = SshCredentialsController(rememberKey: true);

  bool _hadSavedKey = false;
  bool _checking = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    prefillFromProfile(_creds, context.read<ServerRegistry>().active);
    _creds.addListener(_rebuild);
    _checkSaved();
  }

  Future<void> _checkSaved() async {
    final has = await hasSavedSshCredentials();
    if (!mounted) return;
    setState(() {
      _hadSavedKey = has;
      _checking = false;
    });
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _creds.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final problem = _creds.validate();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    final host = _creds.hostText;
    final username = _creds.usernameText;
    final privateKey = _creds.privateKeyText;

    final passphrase = await promptForPassphrase(
      context,
      title: 'Set a passphrase',
      message:
          'Choose a passphrase (at least 8 characters) to protect this key. You\'ll need it to unlock the key later - there\'s no way to recover it without the passphrase.',
      confirm: true,
    );
    if (!mounted || passphrase == null) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    await saveSshCredentials(passphrase, SavedSshCredentials(host: host, username: username, privateKeyPem: privateKey));
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _forget() async {
    final ok = await showConfirmDialog(
      context,
      title: 'Forget the saved SSH key?',
      message:
          'The key is deleted from this device. The next time you update or repair your server you will have to enter it again. Your server is not changed.',
      confirmLabel: 'Forget key',
      danger: true,
    );
    if (!ok) return;
    await clearSavedSshCredentials();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    return AlertDialog(
      scrollable: true,
      title: Text('Saved SSH key', style: ax.typo.title.copyWith(color: c.text)),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: _checking
            ? Padding(
                padding: EdgeInsets.symmetric(vertical: ax.space.xl),
                child: const Center(child: CircularProgressIndicator()),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _hadSavedKey
                        ? 'A key is saved on this device (protected by your passphrase) so you don\'t have to enter it for updates. '
                              'Unlock it below to replace it, or forget it entirely.'
                        : 'No key is saved yet. Add one below so you don\'t have to enter it every time you update or repair your server.',
                    style: ax.typo.body.copyWith(color: c.textMuted),
                  ),
                  SizedBox(height: ax.space.lg),
                  SshCredentialsForm(
                    controller: _creds,
                    // Unlocking asks for the passphrase, so only do it when a key exists.
                    restoreSavedOnStart: _hadSavedKey,
                    showKeyPassphrase: false,
                    showRememberKey: false,
                    enabled: !_saving,
                    errorText: _error,
                    onPickKeyFile: () => pickSshKeyFile(context),
                  ),
                ],
              ),
      ),
      actions: _checking
          ? null
          : [
              if (_hadSavedKey) AxButton.ghost(label: 'Forget saved key', onPressed: _saving ? null : _forget),
              AxButton.ghost(label: 'Cancel', onPressed: () => Navigator.of(context).pop()),
              AxButton(label: 'Save', loading: _saving, onPressed: _creds.restoring ? null : _save),
            ],
    );
  }
}
