import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../../services/server_registry.dart';
import '../../../services/ssh_transport.dart';
import '../../../services/vps_setup_service.dart';
import '../../components/ssh_credentials_form.dart';
import '../../theme.dart';

/// Opens an SSH connection; [Dartssh2Transport.connect] in the app, a fake in
/// tests.
typedef SshConnector = Future<SshTransport> Function({
  required String host,
  required int port,
  required String username,
  required String privateKeyPem,
  required HostKeyPrompt onUnknownHostKey,
  String? passphrase,
});

/// Lets the user pick a private key file for [SshCredentialsForm.onPickKeyFile].
/// Returns its text, or null when cancelled or the file is rejected (with a
/// message shown). Same behaviour as the setup wizard's picker.
Future<String?> pickSshKeyFile(BuildContext context) async {
  String? initialDirectory;
  if (Platform.isMacOS || Platform.isLinux || Platform.isWindows) {
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (home != null) {
      final dir = Directory('$home${Platform.pathSeparator}.ssh');
      if (dir.existsSync()) initialDirectory = dir.path;
    }
  }
  final messenger = ScaffoldMessenger.maybeOf(context);
  String? message;
  try {
    final file = await openFile(initialDirectory: initialDirectory);
    if (file == null) return null;
    if (await file.length() > 64 * 1024) {
      message = 'That file is too big to be a key. Pick the private key file (without .pub).';
    } else {
      final text = await file.readAsString();
      if (!text.contains('PRIVATE KEY')) {
        message = 'That doesn\'t look like a private key. Pick the file without .pub';
      } else {
        return text;
      }
    }
  } catch (e) {
    message = 'Could not read that file: $e';
  }
  messenger?.showSnackBar(SnackBar(content: Text(message)));
  return null;
}

/// Makes a form's address and username start from the active server's
/// profile ([ServerProfile.sshHost] / [ServerProfile.sshUser]). The saved
/// key restores into the form later and would overwrite them with whatever
/// was saved, possibly for another server, so the profile values are
/// re-applied then (an empty profile address leaves the saved one alone).
void prefillFromProfile(SshCredentialsController controller, ServerProfile? profile) {
  if (profile == null) return;
  void apply() {
    final host = profile.sshHost;
    if (host != null && host.isNotEmpty) controller.host.text = host;
    if (profile.sshUser.isNotEmpty) controller.username.text = profile.sshUser;
  }

  apply();
  var reapplied = false;
  controller.addListener(() {
    if (!reapplied && controller.restoredFromSaved && !controller.restoring) {
      reapplied = true;
      apply();
    }
  });
}

/// A stage's "starting" and "complete" events share a stage name; the
/// second replaces the first so the log reads as a checklist.
void appendProgress(List<SetupProgress> log, SetupProgress event) {
  if (log.isNotEmpty && log.last.stage == event.stage) {
    log[log.length - 1] = event;
  } else {
    log.add(event);
  }
}

/// The live checklist of an SSH job (update, sync, uninstall, Admin mode):
/// a spinner on the running step, a tick on finished ones, and the failure
/// underneath. Not scrollable itself - put it in a scrolling dialog body.
class SetupProgressLog extends StatelessWidget {
  const SetupProgressLog({super.key, required this.log, this.error, this.errorTitle = 'That did not work'});

  final List<SetupProgress> log;
  final Object? error;
  final String errorTitle;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final entry in log)
          Padding(
            padding: EdgeInsets.symmetric(vertical: ax.space.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!entry.stageComplete && error == null)
                  SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: c.accent))
                else
                  Icon(
                    entry.stageComplete ? Icons.check_circle : Icons.radio_button_unchecked,
                    size: 16,
                    color: entry.stageComplete ? c.success : c.textMuted,
                  ),
                SizedBox(width: ax.space.sm),
                Expanded(child: Text(entry.message, style: ax.typo.body.copyWith(color: entry.stageComplete ? c.text : c.textMuted))),
              ],
            ),
          ),
        if (error != null)
          Padding(
            padding: EdgeInsets.only(top: ax.space.md),
            child: Semantics(
              liveRegion: true,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline, size: 18, color: c.danger),
                  SizedBox(width: ax.space.sm),
                  Expanded(child: Text('$errorTitle: $error', style: ax.typo.body.copyWith(color: c.danger))),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// A finished-successfully panel for the last step of an SSH job dialog.
class SetupDoneView extends StatelessWidget {
  const SetupDoneView({super.key, required this.title, this.message});

  final String title;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.check_circle_outline, color: c.success, size: 44),
        SizedBox(height: ax.space.md),
        Text(title, textAlign: TextAlign.center, style: ax.typo.title.copyWith(color: c.text)),
        if (message != null) ...[
          SizedBox(height: ax.space.sm),
          Text(message!, textAlign: TextAlign.center, style: ax.typo.body.copyWith(color: c.textMuted)),
        ],
      ],
    );
  }
}
