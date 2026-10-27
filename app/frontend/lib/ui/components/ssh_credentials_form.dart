import 'package:flutter/material.dart';

import '../../services/ssh_credentials.dart';
import '../theme.dart';
import 'ax_button.dart';
import 'help_tip.dart';

/// Holds the values of an [SshCredentialsForm]. The owning dialog/screen
/// creates one, reads it when the user presses Connect, and disposes it.
class SshCredentialsController extends ChangeNotifier {
  SshCredentialsController({String username = 'ubuntu', bool rememberKey = false})
    : username = TextEditingController(text: username),
      _rememberKey = rememberKey;

  final host = TextEditingController();
  final TextEditingController username;
  final privateKey = TextEditingController();

  /// Passphrase of the private key itself (blank for an unencrypted key).
  final keyPassphrase = TextEditingController();

  bool _rememberKey;

  /// Whether to save the key (encrypted under a passphrase the caller asks
  /// for) so the next management action doesn't need it pasted again.
  bool get rememberKey => _rememberKey;
  set rememberKey(bool v) {
    if (_rememberKey == v) return;
    _rememberKey = v;
    notifyListeners();
  }

  bool _restoring = false;
  bool get restoring => _restoring;

  /// True when the fields were filled from the saved key.
  bool restoredFromSaved = false;

  String get hostText => host.text.trim();
  String get usernameText => username.text.trim();
  String get privateKeyText => privateKey.text.trim();
  String? get keyPassphraseOrNull => keyPassphrase.text.isEmpty ? null : keyPassphrase.text;

  /// Plain-language problem with the current input, or null when it is
  /// complete. [needHost] is false for forms that don't ask for a host.
  String? validate({bool needHost = true}) {
    if (needHost && hostText.isEmpty) return 'Enter your server\'s address (an IP address like 203.0.113.5, or a name).';
    if (usernameText.isEmpty) return 'Enter the username you sign in to the server with.';
    if (privateKeyText.isEmpty) return 'Paste your private key - the long text that starts with "-----BEGIN".';
    return null;
  }

  SavedSshCredentials toSavedCredentials() => SavedSshCredentials(host: hostText, username: usernameText, privateKeyPem: privateKeyText);

  void fillFrom(SavedSshCredentials creds) {
    host.text = creds.host;
    username.text = creds.username.isEmpty ? 'ubuntu' : creds.username;
    privateKey.text = creds.privateKeyPem;
    _rememberKey = true;
    restoredFromSaved = true;
    notifyListeners();
  }

  /// Fills the form from the key saved earlier (asking for its passphrase
  /// once per app session via [unlockSavedSshCredentials]). Returns whether
  /// anything was restored. Never throws: no saved key, a cancelled prompt or
  /// a wrong passphrase all simply leave the form as it was.
  Future<bool> restoreSaved(BuildContext context) async {
    _restoring = true;
    notifyListeners();
    try {
      final creds = await unlockSavedSshCredentials(context);
      if (creds == null) return false;
      fillFrom(creds);
      return true;
    } catch (_) {
      return false;
    } finally {
      _restoring = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    host.dispose();
    username.dispose();
    privateKey.dispose();
    keyPassphrase.dispose();
    super.dispose();
  }
}

/// The one form for "how do I SSH into your server": address, username,
/// private key (paste, or load from a file when [onPickKeyFile] is given),
/// the key's own passphrase, and the remember-this-key switch. Used by
/// setup, update, sync, uninstall and Admin mode.
class SshCredentialsForm extends StatefulWidget {
  const SshCredentialsForm({
    super.key,
    required this.controller,
    this.showHost = true,
    this.showUsername = true,
    this.showKeyPassphrase = true,
    this.showRememberKey = true,
    this.restoreSavedOnStart = true,
    this.onPickKeyFile,
    this.errorText,
    this.enabled = true,
  });

  final SshCredentialsController controller;
  final bool showHost;

  /// Hide the username field when the caller already asked for it.
  final bool showUsername;

  /// Ask for the passphrase of an encrypted private key. Off for forms that
  /// only store the key rather than use it.
  final bool showKeyPassphrase;
  final bool showRememberKey;

  /// Restore the saved key when the form first appears.
  final bool restoreSavedOnStart;

  /// Platform hook that lets the user choose a key file and returns its
  /// text (null if cancelled). No file-picker dependency exists yet, so the
  /// "Load from file" button only appears when a caller supplies this.
  final Future<String?> Function()? onPickKeyFile;

  final String? errorText;
  final bool enabled;

  @override
  State<SshCredentialsForm> createState() => _SshCredentialsFormState();
}

class _SshCredentialsFormState extends State<SshCredentialsForm> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_rebuild);
    if (widget.restoreSavedOnStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.controller.restoreSaved(context);
      });
    }
  }

  @override
  void didUpdateWidget(SshCredentialsForm old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_rebuild);
      widget.controller.addListener(_rebuild);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  Future<void> _loadFile() async {
    final text = await widget.onPickKeyFile!();
    if (text != null && mounted) widget.controller.privateKey.text = text.trim();
  }

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final ctl = widget.controller;
    final enabled = widget.enabled && !ctl.restoring;
    final gap = SizedBox(height: ax.space.md);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (ctl.restoring)
          Padding(
            padding: EdgeInsets.only(bottom: ax.space.md),
            child: Semantics(
              liveRegion: true,
              child: Row(
                children: [
                  SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: c.accent)),
                  SizedBox(width: ax.space.sm),
                  Expanded(
                    child: Text('Unlocking your saved key...', style: ax.typo.body.copyWith(color: c.textMuted)),
                  ),
                ],
              ),
            ),
          )
        else if (ctl.restoredFromSaved)
          Padding(
            padding: EdgeInsets.only(bottom: ax.space.md),
            child: Row(
              children: [
                Icon(Icons.lock_open_outlined, size: 18, color: c.success),
                SizedBox(width: ax.space.sm),
                Expanded(
                  child: Text('Using your saved key.', style: ax.typo.body.copyWith(color: c.textMuted)),
                ),
              ],
            ),
          ),
        if (widget.showHost) ...[
          _field(
            context,
            controller: ctl.host,
            label: 'Server address',
            hint: '203.0.113.5',
            enabled: enabled,
            keyboardType: TextInputType.url,
            help: const HelpTip(
              title: 'Server address',
              message:
                  'The public IP address (like 203.0.113.5) or domain name of your server. '
                  'Your hosting provider shows it on the server\'s page.',
            ),
          ),
          gap,
        ],
        if (widget.showUsername) ...[
          _field(
            context,
            controller: ctl.username,
            label: 'Username',
            hint: 'ubuntu',
            enabled: enabled,
            help: const HelpTip(
              title: 'Username',
              message: 'The account you sign in to the server with over SSH. Most hosting providers use "ubuntu" or "root".',
            ),
          ),
          gap,
        ],
        _field(
          context,
          controller: ctl.privateKey,
          label: 'Private key',
          hint: '-----BEGIN OPENSSH PRIVATE KEY-----',
          enabled: enabled,
          maxLines: 5,
          mono: true,
          help: const HelpTip(
            title: 'Private key',
            message:
                'An SSH key is like a long password stored in a file. The "private" half stays on your computer. '
                'If you created the server with a key, open that file in a text editor and paste everything it contains. '
                'It is only used to connect to your server and is never sent anywhere else.',
          ),
        ),
        if (widget.onPickKeyFile != null)
          Align(
            alignment: Alignment.centerLeft,
            child: AxButton.ghost(label: 'Load from file', icon: Icons.folder_open_outlined, onPressed: enabled ? _loadFile : null),
          ),
        if (widget.showKeyPassphrase) ...[
          gap,
          _field(
            context,
            controller: ctl.keyPassphrase,
            label: 'Key passphrase (only if your key has one)',
            enabled: enabled,
            obscure: true,
            help: const HelpTip(
              title: 'Key passphrase',
              message: 'Some SSH keys are locked with their own password. If yours is, enter it here; otherwise leave this empty.',
            ),
          ),
        ],
        if (widget.showRememberKey) ...[
          gap,
          MergeSemantics(
            child: SwitchListTile(
              value: ctl.rememberKey,
              onChanged: enabled ? (v) => ctl.rememberKey = v : null,
              contentPadding: EdgeInsets.zero,
              title: Text('Remember this key on this device', style: ax.typo.body.copyWith(color: c.text)),
              subtitle: Text(
                'Saved encrypted with a passphrase you choose, so you don\'t have to paste it again.',
                style: ax.typo.caption.copyWith(color: c.textMuted),
              ),
            ),
          ),
        ],
        if (widget.errorText != null)
          Padding(
            padding: EdgeInsets.only(top: ax.space.md),
            child: Semantics(
              liveRegion: true,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline, size: 18, color: c.danger),
                  SizedBox(width: ax.space.sm),
                  Expanded(
                    child: Text(widget.errorText!, style: ax.typo.body.copyWith(color: c.danger)),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _field(
    BuildContext context, {
    required TextEditingController controller,
    required String label,
    required bool enabled,
    String? hint,
    int maxLines = 1,
    bool obscure = false,
    bool mono = false,
    TextInputType? keyboardType,
    Widget? help,
  }) {
    final ax = context.ax;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            enabled: enabled,
            maxLines: maxLines,
            obscureText: obscure,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: keyboardType,
            style: mono ? ax.typo.mono.copyWith(color: ax.colors.text) : ax.typo.body.copyWith(color: ax.colors.text),
            decoration: InputDecoration(labelText: label, hintText: hint, alignLabelWithHint: maxLines > 1),
          ),
        ),
        ?help,
      ],
    );
  }
}
