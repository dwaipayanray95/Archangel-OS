import 'package:flutter/material.dart';

import '../services/credential_crypto.dart' show kMinPassphraseLength;
import '../theme/tokens.dart';

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
Future<String?> promptForPassphrase(
  BuildContext context, {
  required String title,
  required String message,
  bool confirm = false,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _PassphrasePromptDialog(title: title, message: message, confirm: confirm),
  );
}

/// Asks for the current passphrase plus a new one (twice). Returns
/// `(current, new)`, or null if cancelled. Whether `current` is correct
/// is checked by the caller (decryption fails otherwise).
Future<(String, String)?> promptToChangePassphrase(BuildContext context) {
  return showDialog<(String, String)>(
    context: context,
    builder: (context) => const _ChangePassphraseDialog(),
  );
}

/// Shared by both dialogs.
String? _validateNewPassphrase(String value, String confirmation) {
  if (value.length < kMinPassphraseLength) {
    return 'Passphrase must be at least $kMinPassphraseLength characters.';
  }
  if (value != confirmation) return "Passphrases don't match.";
  return null;
}

InputDecoration _fieldDecoration(String hint) {
  return InputDecoration(
    hintText: hint,
    hintStyle: AxTextStyles.sans.copyWith(fontSize: 12, color: AxColors.fg3),
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
    filled: true,
    fillColor: AxColors.s1,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AxColors.line)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AxColors.line)),
  );
}

Widget _passphraseField(TextEditingController controller, {required String hint, bool autofocus = false, VoidCallback? onSubmit}) {
  return TextField(
    controller: controller,
    autofocus: autofocus,
    obscureText: true,
    enableSuggestions: false,
    autocorrect: false,
    onSubmitted: onSubmit == null ? null : (_) => onSubmit(),
    style: AxTextStyles.sans.copyWith(fontSize: 13),
    decoration: _fieldDecoration(hint),
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
    return AlertDialog(
      backgroundColor: AxColors.s2,
      title: Text(widget.title, style: AxTextStyles.sans.copyWith(fontSize: 15, fontWeight: FontWeight.w700)),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.message, style: AxTextStyles.sans.copyWith(fontSize: 12, color: AxColors.fg2, height: 1.5)),
            const SizedBox(height: 14),
            _passphraseField(_passphraseController, hint: 'Passphrase', autofocus: true, onSubmit: _submit),
            if (widget.confirm) ...[
              const SizedBox(height: 10),
              _passphraseField(_confirmController, hint: 'Confirm passphrase', onSubmit: _submit),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: AxTextStyles.mono.copyWith(fontSize: 11.5, color: AxColors.bad)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Continue')),
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
    return AlertDialog(
      backgroundColor: AxColors.s2,
      title: Text('Change passphrase', style: AxTextStyles.sans.copyWith(fontSize: 15, fontWeight: FontWeight.w700)),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Re-encrypts your saved SSH key under a new passphrase (at least $kMinPassphraseLength characters).',
              style: AxTextStyles.sans.copyWith(fontSize: 12, color: AxColors.fg2, height: 1.5),
            ),
            const SizedBox(height: 14),
            _passphraseField(_currentController, hint: 'Current passphrase', autofocus: true),
            const SizedBox(height: 10),
            _passphraseField(_newController, hint: 'New passphrase'),
            const SizedBox(height: 10),
            _passphraseField(_confirmController, hint: 'Confirm new passphrase', onSubmit: _submit),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: AxTextStyles.mono.copyWith(fontSize: 11.5, color: AxColors.bad)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Change passphrase')),
      ],
    );
  }
}
