import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/archangeld_connection.dart';
import '../services/ssh_credentials.dart';
import '../services/ssh_transport.dart';
import '../services/update_check_service.dart';
import '../services/vps_setup_service.dart';
import '../theme/tokens.dart';
import 'host_key_dialog.dart';
import 'passphrase_prompt_dialog.dart';

/// Shown when the user taps "Update now" on the Backend row in Settings.
/// Updates an already-set-up server's archangeld to the version named by
/// [targetVersion]/[releaseTag] (from UpdateCheckService's manifest) over
/// the same SSH machinery the first-run setup wizard uses - see
/// VpsSetupService.updateBackend's doc comment for why this goes over SSH
/// rather than a self-update HTTP endpoint (archangeld runs unprivileged
/// on purpose - it can't rewrite its own binary or restart itself).
Future<void> showBackendUpdateDialog(
  BuildContext context, {
  required String targetVersion,
  required String releaseTag,
}) {
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

  final _hostController = TextEditingController();
  final _usernameController = TextEditingController(text: 'ubuntu');
  final _privateKeyController = TextEditingController();
  final _passphraseController = TextEditingController();
  bool _loadingSavedKey = true;
  bool _connecting = false;
  bool _rememberKey = false;
  bool _credsLoadedFromSaved = false;
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
    if (creds != null) {
      setState(() {
        _hostController.text = creds.host;
        _usernameController.text = creds.username;
        _privateKeyController.text = creds.privateKeyPem;
        _rememberKey = true;
        _credsLoadedFromSaved = true;
        _loadingSavedKey = false;
      });
      // Streamline: user entered passphrase and has saved credentials ready, immediately connect & update!
      await _connect();
    } else {
      setState(() {
        _loadingSavedKey = false;
      });
    }
  }

  @override
  void dispose() {
    _hostController.dispose();
    _usernameController.dispose();
    _privateKeyController.dispose();
    _passphraseController.dispose();
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

      if (!mounted) {
        transport.close();
        return;
      }

      // Only prompt to set/confirm passphrase if this is a newly entered key, not if we loaded it from saved credentials
      if (_rememberKey) {
        if (!_credsLoadedFromSaved) {
          final savePassphrase = await promptForPassphrase(
            context,
            title: 'Set a passphrase',
            message: 'Choose a passphrase (at least 8 characters) to protect this key. You\'ll need it to unlock the key later - there\'s no way to recover it without the passphrase.',
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
          (event) => setState(() => _appendOrUpdate(event)),
          onError: (Object e) => setState(() => _runError = e),
          onDone: () {
            if (!mounted) return;
            if (_runError == null) {
              setState(() {
                _succeeded = true;
                _step = _UpdateStep.done;
              });
              // The UpdateCheckService badge disappears once
              // backend.backendVersion (just refreshed by the poll
              // above) matches its own cached latestBackend - no
              // separate action needed here.
              context.read<UpdateCheckService>().checkForUpdates(force: true);
            }
          },
        );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AxColors.s2,
      title: Text('Update backend to v${widget.targetVersion}', style: AxTextStyles.sans.copyWith(fontSize: 15, fontWeight: FontWeight.w700)),
      content: SizedBox(
        width: 460,
        height: 360,
        child: switch (_step) {
          _UpdateStep.credentials => _buildCredentialsStep(),
          _UpdateStep.progress => _buildProgressStep(),
          _UpdateStep.done => _buildDoneStep(),
        },
      ),
      actions: switch (_step) {
        _UpdateStep.credentials => [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
            FilledButton(
              onPressed: _connecting || _loadingSavedKey ? null : _connect,
              child: _connecting ? const _MiniSpinner() : const Text('Connect & update'),
            ),
          ],
        _UpdateStep.progress => [
            if (_runError != null) TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
          ],
        _UpdateStep.done => [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
          ],
      },
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
            'This connects over SSH the same way the setup wizard did, to install the new '
            'binary and restart the service as root. Your app connection to archangeld itself '
            'is unaffected other than a brief restart.',
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
          const SizedBox(height: 8),
          Row(
            children: [
              Checkbox(
                value: _rememberKey,
                onChanged: (v) => setState(() => _rememberKey = v ?? false),
              ),
              Expanded(
                child: Text(
                  'Remember this key for future server management from the app',
                  style: AxTextStyles.sans.copyWith(fontSize: 12, color: AxColors.fg2),
                ),
              ),
            ],
          ),
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
            child: Text('Update failed:\n$_runError', style: AxTextStyles.mono.copyWith(fontSize: 11.5, color: AxColors.bad)),
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
            _succeeded ? 'archangeld v${widget.targetVersion} is running.' : 'Done.',
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

  Widget _textField(TextEditingController controller, {String? hint, int maxLines = 1, bool monospace = false, bool obscure = false}) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      obscureText: obscure,
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
