import 'package:flutter/material.dart';

import '../services/ssh_credentials.dart';
import '../theme/tokens.dart';
import 'passphrase_prompt_dialog.dart';

/// Lets the user view/replace/forget the SSH key "Remember this key"
/// saved (from the setup wizard or BackendUpdateDialog), without having
/// to go through an actual update/uninstall flow just to rotate it.
/// Doesn't connect over SSH at all - purely local secure-storage
/// management, same as setup_wizard_screen.dart's _restoreSavedKey but
/// editable instead of read-only.
Future<void> showManageSshKeyDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => const ManageSshKeyDialog(),
  );
}

class ManageSshKeyDialog extends StatefulWidget {
  const ManageSshKeyDialog({super.key});

  @override
  State<ManageSshKeyDialog> createState() => _ManageSshKeyDialogState();
}

class _ManageSshKeyDialogState extends State<ManageSshKeyDialog> {
  final _hostController = TextEditingController();
  final _usernameController = TextEditingController(text: 'ubuntu');
  final _privateKeyController = TextEditingController();

  bool _loading = true;
  bool _hadSavedKey = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final creds = await unlockSavedSshCredentials(context);
    if (!mounted) return;
    setState(() {
      if (creds != null) {
        _hostController.text = creds.host;
        _usernameController.text = creds.username;
        _privateKeyController.text = creds.privateKeyPem;
        _hadSavedKey = true;
      }
      _loading = false;
    });
  }

  @override
  void dispose() {
    _hostController.dispose();
    _usernameController.dispose();
    _privateKeyController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final host = _hostController.text.trim();
    final username = _usernameController.text.trim();
    final privateKey = _privateKeyController.text.trim();
    if (host.isEmpty || username.isEmpty || privateKey.isEmpty) {
      setState(() => _error = 'Host, SSH username, and private key are all required.');
      return;
    }

    final passphrase = await promptForPassphrase(
      context,
      title: 'Set a passphrase',
      message: 'Choose a passphrase (at least 8 characters) to protect this key. You\'ll need it to unlock the key later - there\'s no way to recover it without the passphrase.',
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
    await clearSavedSshCredentials();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AxColors.s2,
      title: Text('Manage SSH key', style: AxTextStyles.sans.copyWith(fontSize: 15, fontWeight: FontWeight.w700)),
      content: SizedBox(
        width: 460,
        child: _loading
            ? const Padding(padding: EdgeInsets.symmetric(vertical: 30), child: Center(child: _MiniSpinner()))
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _hadSavedKey
                          ? 'This key is used to skip re-entering credentials for backend updates and uninstall. Edit it below, or forget it entirely.'
                          : 'No key is currently saved. Paste one below to skip re-entering credentials next time you update or uninstall the backend.',
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
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Text(_error!, style: AxTextStyles.mono.copyWith(fontSize: 11.5, color: AxColors.bad)),
                    ],
                  ],
                ),
              ),
      ),
      actions: _loading
          ? null
          : [
              if (_hadSavedKey)
                TextButton(
                  onPressed: _saving ? null : _forget,
                  style: TextButton.styleFrom(foregroundColor: AxColors.bad),
                  child: const Text('Forget saved key'),
                ),
              TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving ? const _MiniSpinner() : const Text('Save'),
              ),
            ],
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(text, style: AxTextStyles.sans.copyWith(fontSize: 11, color: AxColors.fg3)),
      );

  Widget _textField(TextEditingController controller, {String? hint, int maxLines = 1, bool monospace = false}) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
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
