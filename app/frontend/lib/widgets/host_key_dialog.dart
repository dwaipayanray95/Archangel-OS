import 'package:flutter/material.dart';

import '../ui/ui.dart';

/// Trust-on-first-use host key confirmation dialog, shared between the
/// setup wizard and BackendUpdateDialog - both SSH into a server and
/// need the same "verify this fingerprint" / "server key changed!"
/// prompt (see ssh_transport.dart's HostKeyPrompt/KnownHosts for the
/// TOFU logic this renders for).
Future<bool> showHostKeyConfirmDialog(
  BuildContext context, {
  required String host,
  required String keyType,
  required String fingerprint,
  required bool isMismatch,
}) async {
  final accepted = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      final ax = context.ax;
      final c = ax.colors;
      return AlertDialog(
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ax.radii.lg),
          side: BorderSide(color: isMismatch ? c.danger : c.border),
        ),
        title: Row(
          children: [
            Icon(isMismatch ? Icons.warning_amber_rounded : Icons.verified_user_outlined, color: isMismatch ? c.danger : c.accent),
            SizedBox(width: ax.space.sm),
            Expanded(
              child: Text(
                isMismatch ? 'Server identity changed' : 'Check this is your server',
                style: ax.typo.title.copyWith(color: isMismatch ? c.danger : c.text),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isMismatch
                      ? 'This address previously showed a different identity. That can happen if the server was '
                            'rebuilt, but it can also mean someone is intercepting the connection. Only continue if you are certain.'
                      : 'This is the first time connecting to $host. Check that the fingerprint below matches the one '
                            'your cloud provider shows for this server (if it shows one) before continuing.',
                  style: ax.typo.body.copyWith(color: isMismatch ? c.danger : c.textMuted),
                ),
                SizedBox(height: ax.space.md),
                Text('$keyType fingerprint', style: ax.typo.caption.copyWith(color: c.textMuted)),
                SizedBox(height: ax.space.xs),
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(ax.space.md),
                  decoration: BoxDecoration(
                    color: c.surfaceAlt,
                    borderRadius: BorderRadius.circular(ax.radii.sm),
                    border: Border.all(color: c.border),
                  ),
                  child: SelectableText(fingerprint, style: ax.typo.mono.copyWith(color: c.text)),
                ),
              ],
            ),
          ),
        ),
        actionsOverflowButtonSpacing: ax.space.sm,
        actions: [
          AxButton.secondary(label: 'Cancel', onPressed: () => Navigator.of(context).pop(false)),
          isMismatch
              ? AxButton.danger(label: 'Trust anyway', onPressed: () => Navigator.of(context).pop(true))
              : AxButton(label: 'Trust this server', onPressed: () => Navigator.of(context).pop(true)),
        ],
      );
    },
  );
  return accepted ?? false;
}
