import 'package:flutter/material.dart';

import '../services/credential_crypto.dart' show kMinPassphraseLength;
import '../ui/ui.dart';

/// Prompts for the passphrase that protects the saved SSH key (see
/// credential_crypto.dart / ssh_credentials.dart) - replaces the old
/// OS-biometric gate (LocalAuthService), since the passphrase here isn't
/// just a gate, it IS the encryption key material.
///
/// [confirm]: true when setting a NEW passphrase (first save, or replacing
/// an existing one) - requires typing it twice so a typo doesn't lock the
/// user out of their own data, and enforces [kMinPassphraseLength]. false
/// when unlocking an existing save - a single field, wrong entries are
/// caught by decryption failing (AES-GCM auth tag mismatch), not by this
/// dialog.
///
/// Returns the entered passphrase, or null if the user cancelled.
Future<String?> promptForPassphrase(BuildContext context, {required String title, required String message, bool confirm = false}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _PassphrasePromptDialog(title: title, message: message, confirm: confirm),
  );
}

/// Asks for the current passphrase plus a new one (twice). Returns
/// `(current, new)`, or null if cancelled. Whether `current` is correct
/// is checked by the caller (decryption fails otherwise).
Future<(String, String)?> promptToChangePassphrase(BuildContext context) {
  return showDialog<(String, String)>(context: context, builder: (context) => const _ChangePassphraseDialog());
}

/// Shared by both dialogs.
String? _validateNewPassphrase(String value, String confirmation) {
  if (value.length < kMinPassphraseLength) {
    return 'Passphrase must be at least $kMinPassphraseLength characters.';
  }
  if (value != confirmation) return "Passphrases don't match.";
  return null;
}

Widget _passphraseField(
  BuildContext context,
  TextEditingController controller, {
  required String label,
  bool autofocus = false,
  VoidCallback? onSubmit,
}) {
  final ax = context.ax;
  return TextField(
    controller: controller,
    autofocus: autofocus,
    obscureText: true,
    enableSuggestions: false,
    autocorrect: false,
    onSubmitted: onSubmit == null ? null : (_) => onSubmit(),
    style: ax.typo.body.copyWith(color: ax.colors.text),
    decoration: InputDecoration(labelText: label),
  );
}

Widget _errorLine(BuildContext context, String message) {
  final ax = context.ax;
  return Padding(
    padding: EdgeInsets.only(top: ax.space.md),
    child: Semantics(
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 18, color: ax.colors.danger),
          SizedBox(width: ax.space.sm),
          Expanded(child: Text(message, style: ax.typo.body.copyWith(color: ax.colors.danger))),
        ],
      ),
    ),
  );
}

class _PassphrasePromptDialog extends StatefulWidget {
  final String title;
  final String message;
  final bool confirm;
  const _PassphrasePromptDialog({required this.title, required this.message, required this.confirm});

  @override
  State<_PassphrasePromptDialog> createState() => _PassphrasePromptDialogState();
}

class _PassphrasePromptDialogState extends State<_PassphrasePromptDialog> {
  final _passphraseController = TextEditingController();
  final _confirmController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _passphraseController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _submit() {
    final passphrase = _passphraseController.text;
    if (widget.confirm) {
      final error = _validateNewPassphrase(passphrase, _confirmController.text);
      if (error != null) {
        setState(() => _error = error);
        return;
      }
    } else if (passphrase.isEmpty) {
      setState(() => _error = 'Enter your passphrase.');
      return;
    }
    Navigator.of(context).pop(passphrase);
  }

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    return AlertDialog(
      scrollable: true,
      title: Text(widget.title, style: ax.typo.title.copyWith(color: c.text)),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.message, style: ax.typo.body.copyWith(color: c.textMuted)),
            SizedBox(height: ax.space.lg),
            _passphraseField(context, _passphraseController, label: 'Passphrase', autofocus: true, onSubmit: _submit),
            if (widget.confirm) ...[
              SizedBox(height: ax.space.md),
              _passphraseField(context, _confirmController, label: 'Confirm passphrase', onSubmit: _submit),
            ],
            if (_error != null) _errorLine(context, _error!),
          ],
        ),
      ),
      actions: [
        AxButton.ghost(label: 'Cancel', onPressed: () => Navigator.of(context).pop()),
        AxButton(label: 'Continue', onPressed: _submit),
      ],
    );
  }
}

class _ChangePassphraseDialog extends StatefulWidget {
  const _ChangePassphraseDialog();

  @override
  State<_ChangePassphraseDialog> createState() => _ChangePassphraseDialogState();
}

class _ChangePassphraseDialogState extends State<_ChangePassphraseDialog> {
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_currentController.text.isEmpty) {
      setState(() => _error = 'Enter your current passphrase.');
      return;
    }
    final error = _validateNewPassphrase(_newController.text, _confirmController.text);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop((_currentController.text, _newController.text));
  }

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    return AlertDialog(
      scrollable: true,
      title: Text('Change passphrase', style: ax.typo.title.copyWith(color: c.text)),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Re-locks your saved SSH key under a new passphrase (at least $kMinPassphraseLength characters).',
              style: ax.typo.body.copyWith(color: c.textMuted),
            ),
            SizedBox(height: ax.space.lg),
            _passphraseField(context, _currentController, label: 'Current passphrase', autofocus: true),
            SizedBox(height: ax.space.md),
            _passphraseField(context, _newController, label: 'New passphrase'),
            SizedBox(height: ax.space.md),
            _passphraseField(context, _confirmController, label: 'Confirm new passphrase', onSubmit: _submit),
            if (_error != null) _errorLine(context, _error!),
          ],
        ),
      ),
      actions: [
        AxButton.ghost(label: 'Cancel', onPressed: () => Navigator.of(context).pop()),
        AxButton(label: 'Change passphrase', onPressed: _submit),
      ],
    );
  }
}
