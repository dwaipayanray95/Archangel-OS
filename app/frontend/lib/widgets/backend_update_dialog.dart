import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/archangeld_connection.dart';
import '../services/server_registry.dart';
import '../services/ssh_credentials.dart';
import '../services/ssh_transport.dart';
import '../services/update_check_service.dart';
import '../services/vps_setup_service.dart';
import '../ui/screens/settings/ssh_dialog_helpers.dart';
import '../ui/ui.dart';
import 'host_key_dialog.dart';
import 'passphrase_prompt_dialog.dart';

/// Shown when the user taps "Update" on the Archangel OS version in
/// Settings. Updates an already-set-up server's archangeld to the version
/// named by [targetVersion]/[releaseTag] (from UpdateCheckService's manifest)
/// over the same SSH machinery the first-run setup wizard uses - see
/// VpsSetupService.updateBackend's doc comment for why this goes over SSH
/// rather than a self-update HTTP endpoint (archangeld runs unprivileged
/// on purpose - it can't rewrite its own binary or restart itself).
Future<void> showBackendUpdateDialog(BuildContext context, {required String targetVersion, required String releaseTag}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => BackendUpdateDialog(targetVersion: targetVersion, releaseTag: releaseTag),
  );
}

class BackendUpdateDialog extends StatefulWidget {
  final String targetVersion;
  final String releaseTag;
  const BackendUpdateDialog({super.key, required this.targetVersion, required this.releaseTag});

  @override
  State<BackendUpdateDialog> createState() => _BackendUpdateDialogState();
}

enum _UpdateStep { credentials, progress, done }

class _BackendUpdateDialogState extends State<BackendUpdateDialog> {
  _UpdateStep _step = _UpdateStep.credentials;

  final _creds = SshCredentialsController();
  bool _connecting = false;
  bool _autoConnected = false;
  String? _connectError;

  SshTransport? _transport;
  final List<SetupProgress> _log = [];
  Object? _runError;

  @override
  void initState() {
    super.initState();
    prefillFromProfile(_creds, context.read<ServerRegistry>().active);
    _creds.addListener(_maybeAutoConnect);
  }

  /// Streamline: once the saved key has been unlocked, connect and update
  /// straight away (the user already entered their passphrase for it).
  void _maybeAutoConnect() {
    if (mounted) setState(() {});
    if (_autoConnected || !_creds.restoredFromSaved || _creds.restoring) return;
    _autoConnected = true;
    if (_creds.validate() == null) _connect();
  }

  @override
  void dispose() {
    _creds.removeListener(_maybeAutoConnect);
    _creds.dispose();
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
    final problem = _creds.validate();
    if (problem != null) {
      setState(() => _connectError = problem);
      return;
    }
    final host = _creds.hostText;
    final username = _creds.usernameText;
    final privateKey = _creds.privateKeyText;

    setState(() {
      _connecting = true;
      _connectError = null;
    });

    try {
      final transport = await Dartssh2Transport.connect(
        host: host,
        port: 22,
        username: username,
        privateKeyPem: privateKey,
        passphrase: _creds.keyPassphraseOrNull,
        onUnknownHostKey: _confirmHostKey,
      );

      if (!mounted) {
        transport.close();
        return;
      }

      // Only prompt to set a passphrase if this is a newly entered key, not one loaded from saved credentials.
      if (_creds.rememberKey) {
        if (!_creds.restoredFromSaved) {
          final savePassphrase = await promptForPassphrase(
            context,
            title: 'Set a passphrase',
            message:
                'Choose a passphrase (at least 8 characters) to protect this key. You\'ll need it to unlock the key later - there\'s no way to recover it without the passphrase.',
            confirm: true,
          );
          if (savePassphrase != null) {
            await saveSshCredentials(savePassphrase, SavedSshCredentials(host: host, username: username, privateKeyPem: privateKey));
          }
        }
      } else {
        await clearSavedSshCredentials();
      }

      if (!mounted) return;
      _transport = transport;
      setState(() {
        _connecting = false;
        _step = _UpdateStep.progress;
      });
      _runUpdate();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _connectError = 'Could not connect: $e';
      });
    }
  }

  void _runUpdate() {
    final backend = context.read<ArchangeldConnection>();
    final service = VpsSetupService(_transport!);
    service
        .updateBackend(
          targetVersion: widget.targetVersion,
          releaseTag: widget.releaseTag,
          githubRepoSlug: kGithubRepoSlug,
          fetchLiveVersion: () async {
            await backend.refreshBackendVersion();
            return backend.backendVersion;
          },
        )
        .listen(
          (event) => setState(() => appendProgress(_log, event)),
          onError: (Object e) => setState(() => _runError = e),
          onDone: () {
            if (!mounted) return;
            if (_runError == null) {
              setState(() => _step = _UpdateStep.done);
              // The update badge disappears once backend.backendVersion
              // (just refreshed above) matches the cached latest version.
              context.read<UpdateCheckService>().checkForUpdates(force: true);
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
      title: Text('Update your server to v${widget.targetVersion}', style: ax.typo.title.copyWith(color: c.text)),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: switch (_step) {
          _UpdateStep.credentials => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'This signs in to your server over SSH, the same way setup did, to install the new '
                'version and restart the Archangel service. Your connection from this app only drops for a moment.',
                style: ax.typo.body.copyWith(color: c.textMuted),
              ),
              SizedBox(height: ax.space.lg),
              SshCredentialsForm(
                controller: _creds,
                enabled: !_connecting,
                errorText: _connectError,
                onPickKeyFile: () => pickSshKeyFile(context),
              ),
            ],
          ),
          _UpdateStep.progress => SetupProgressLog(log: _log, error: _runError, errorTitle: 'Update failed'),
          _UpdateStep.done => SetupDoneView(title: 'Your server is now running v${widget.targetVersion}.'),
        },
      ),
      actions: switch (_step) {
        _UpdateStep.credentials => [
          AxButton.ghost(label: 'Cancel', onPressed: () => Navigator.of(context).pop()),
          AxButton(label: 'Connect & update', loading: _connecting, onPressed: _creds.restoring ? null : _connect),
        ],
        _UpdateStep.progress => [if (_runError != null) AxButton.ghost(label: 'Close', onPressed: () => Navigator.of(context).pop())],
        _UpdateStep.done => [AxButton.ghost(label: 'Close', onPressed: () => Navigator.of(context).pop())],
      },
    );
  }
}
