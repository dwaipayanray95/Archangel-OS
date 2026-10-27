import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/archangeld_connection.dart';
import '../../services/pairing_bundle.dart';
import '../../services/server_registry.dart';
import '../../services/ssh_credentials.dart';
import '../../services/ssh_transport.dart';
import '../../services/vps_setup_service.dart';
import '../../services/wireguard_controller.dart';
import '../../ui/screens/setup/setup_hints.dart';
import '../../ui/screens/setup/setup_widgets.dart';
import '../../ui/ui.dart';
import '../../widgets/host_key_dialog.dart';
import '../../widgets/passphrase_prompt_dialog.dart';

export '../../ui/screens/setup/setup_hints.dart' show hintForSetupError;

/// The in-app "zero-SSH-by-hand" setup wizard, one question per screen:
/// server address, SSH key, device name, review, run, done. See
/// lib/services/vps_setup_service.dart for what actually runs on the
/// server - this screen is presentation plus wiring the resulting
/// PairingBundle into WireGuardController/ArchangeldConnection exactly the
/// same way the manual pairing dialog does.
class SetupWizardScreen extends StatefulWidget {
  const SetupWizardScreen({super.key, this.restoreSavedKey = true});

  /// Offer to unlock a previously saved SSH key when the wizard opens.
  final bool restoreSavedKey;

  @override
  State<SetupWizardScreen> createState() => _SetupWizardScreenState();
}

enum _Step { address, key, device, review, run, done }

// Three dot-separated non-negative integers, e.g. "10.10.0" - the first
// three octets of a WireGuard subnet. Rejecting anything else here
// before it ever reaches VpsSetupService is defense in depth: that
// service also writes config.yaml via SFTP rather than an interpolated
// shell heredoc specifically so a value that fails this check anyway
// can't do worse than fail cleanly.
final _wgSubnetPattern = RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}$');

bool _validSubnet(String s) {
  if (s.isEmpty) return true;
  if (!_wgSubnetPattern.hasMatch(s)) return false;
  return s.split('.').every((o) => int.parse(o) <= 255);
}

bool _validPort(String s) {
  if (s.isEmpty) return true;
  final n = int.tryParse(s);
  return n != null && n >= 1 && n <= 65535;
}

const _stepTitles = {
  _Step.address: 'Your server',
  _Step.key: 'SSH key',
  _Step.device: 'This device',
  _Step.review: 'Review',
  _Step.run: 'Setting up',
  _Step.done: 'Done',
};

class _SetupWizardScreenState extends State<SetupWizardScreen> {
  _Step _step = _Step.address;

  // Entered data lives in controllers owned by the state, so it survives
  // moving Back and forward between steps.
  final _ssh = SshCredentialsController();
  final _deviceNameController = TextEditingController(text: _defaultDeviceName());
  final _wgSubnetController = TextEditingController(text: '10.10.0');
  final _wgPortController = TextEditingController(text: '51820');
  final _appPortController = TextEditingController(text: '8443');

  SshTransport? _transport;
  StreamSubscription<SetupProgress>? _sub;
  final List<SetupProgress> _log = [];
  bool _connecting = false;
  bool _keySaveHandled = false;
  Object? _error;
  String? _failedStage;
  PairingBundle? _bundle;
  bool _pairing = false;
  String? _pairError;

  // Ticks once a second while a stage is running, so a long silent step
  // (e.g. baseline setup's apt update/upgrade, which can easily take
  // 30-90s with no output of its own) visibly shows the app is still
  // working instead of looking frozen.
  Timer? _elapsedTimer;
  int _elapsedSeconds = 0;

  static String _defaultDeviceName() {
    if (Platform.isMacOS) return 'mac';
    if (Platform.isWindows) return 'windows';
    if (Platform.isAndroid) return 'android';
    if (Platform.isLinux) return 'linux';
    return 'device';
  }

  @override
  void initState() {
    super.initState();
    for (final c in [
      _ssh.host,
      _ssh.username,
      _ssh.privateKey,
      _deviceNameController,
      _wgSubnetController,
      _wgPortController,
      _appPortController,
    ]) {
      c.addListener(_onEdited);
    }
    if (widget.restoreSavedKey) {
      // Restoring the key requires the passphrase that protects it - it
      // grants root on the VPS, so a device left unlocked shouldn't hand it
      // over just by opening this screen. unlockSavedSshCredentials caches
      // the decrypted value in memory for the app session.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _ssh.restoreSaved(context);
      });
    }
  }

  void _onEdited() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ssh.dispose();
    _deviceNameController.dispose();
    _wgSubnetController.dispose();
    _wgPortController.dispose();
    _appPortController.dispose();
    _transport?.close();
    _elapsedTimer?.cancel();
    super.dispose();
  }

  // ---- validation -------------------------------------------------------

  bool get _addressValid => _ssh.hostText.isNotEmpty && !_ssh.hostText.contains(RegExp(r'\s')) && _ssh.usernameText.isNotEmpty;
  bool get _keyValid => _ssh.privateKeyText.isNotEmpty;

  String? get _advancedError {
    if (!_validSubnet(_wgSubnetController.text.trim())) {
      return 'The private network must be three numbers separated by dots, like 10.10.0.';
    }
    if (!_validPort(_wgPortController.text.trim()) || !_validPort(_appPortController.text.trim())) {
      return 'Ports must be numbers between 1 and 65535.';
    }
    return null;
  }

  bool get _deviceValid => _advancedError == null;

  bool get _canNext => switch (_step) {
    _Step.address => _addressValid,
    _Step.key => _keyValid,
    _Step.device => _deviceValid,
    _ => true,
  };

  // ---- navigation -------------------------------------------------------

  bool get _running => _step == _Step.run && _error == null;

  void _next() {
    if (!_canNext) return;
    setState(() {
      _step = switch (_step) {
        _Step.address => _Step.key,
        _Step.key => _Step.device,
        _Step.device => _Step.review,
        _ => _step,
      };
    });
  }

  void _back() {
    if (_running) return;
    if (_step == _Step.run) {
      _stopRun();
      setState(() => _step = _Step.review);
      return;
    }
    if (_step == _Step.address || _step == _Step.done) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() {
      _step = switch (_step) {
        _Step.key => _Step.address,
        _Step.device => _Step.key,
        _Step.review => _Step.device,
        _ => _step,
      };
    });
  }

  void _stopRun() {
    _sub?.cancel();
    _sub = null;
    _elapsedTimer?.cancel();
    _transport?.close();
    _transport = null;
    _error = null;
    _failedStage = null;
    _connecting = false;
  }

  // ---- running ----------------------------------------------------------

  /// Shown the first time we connect to a host (routine) or whenever a
  /// previously-trusted host's key has changed (`isMismatch: true` -
  /// never auto-accept this case, it's the one that actually looks like
  /// an attacker). See ssh_transport.dart's HostKeyPrompt/KnownHosts.
  Future<bool> _confirmHostKey({
    required String host,
    required String keyType,
    required String fingerprint,
    required bool isMismatch,
  }) async {
    if (!mounted) return false;
    return showHostKeyConfirmDialog(context, host: host, keyType: keyType, fingerprint: fingerprint, isMismatch: isMismatch);
  }

  void _fail(String stage, Object error) {
    _elapsedTimer?.cancel();
    _transport?.close();
    _transport = null;
    if (!mounted) return;
    setState(() {
      _connecting = false;
      _error = error;
      _failedStage = normalizeSetupStage(stage);
    });
  }

  /// Connect over SSH, then run the setup stream. Safe to call again after a
  /// failure: the server-side steps are idempotent.
  Future<void> _start() async {
    _stopRun();
    setState(() {
      _step = _Step.run;
      _log.clear();
      _bundle = null;
      _pairError = null;
      _connecting = true;
      _elapsedSeconds = 0;
    });

    final host = _ssh.hostText;
    final username = _ssh.usernameText;
    final privateKey = _ssh.privateKeyText;

    try {
      final transport = await Dartssh2Transport.connect(
        host: host,
        port: 22,
        username: username,
        privateKeyPem: privateKey,
        passphrase: _ssh.keyPassphraseOrNull,
        onUnknownHostKey: _confirmHostKey,
      );

      if (!mounted) {
        transport.close();
        return;
      }

      if (_ssh.rememberKey) {
        if (!_keySaveHandled) {
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
          _keySaveHandled = true;
        }
      } else {
        await clearSavedSshCredentials();
      }

      if (!mounted) {
        transport.close();
        return;
      }
      _transport = transport;
      setState(() => _connecting = false);
      _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _elapsedSeconds++);
      });
      _runSetup();
    } catch (e) {
      _fail('connect', e);
    }
  }

  // Each stage emits a "starting" event followed later by a "complete"
  // one for the same stage - replace the row in place instead of
  // appending a second one.
  void _appendOrUpdate(SetupProgress event) {
    if (_log.isNotEmpty && _log.last.stage == event.stage) {
      _log[_log.length - 1] = event;
    } else {
      _log.add(event);
    }
  }

  void _runSetup() {
    final config = VpsSetupConfig(
      deviceName: _deviceNameController.text.trim().isEmpty ? _defaultDeviceName() : _deviceNameController.text.trim(),
      wgSubnet: _wgSubnetController.text.trim().isEmpty ? '10.10.0' : _wgSubnetController.text.trim(),
      wgPort: int.tryParse(_wgPortController.text.trim()) ?? 51820,
      appPort: int.tryParse(_appPortController.text.trim()) ?? 8443,
    );
    final service = VpsSetupService(_transport!);
    _sub = service
        .run(config)
        .listen(
          (event) {
            if (!mounted) return;
            setState(() {
              _appendOrUpdate(event);
              if (!event.stageComplete) _elapsedSeconds = 0;
            });
          },
          onError: (Object e) {
            final stage = e is VpsSetupException ? e.stage : (_log.isNotEmpty ? _log.last.stage : 'detect');
            _fail(stage, e);
          },
          onDone: () {
            _elapsedTimer?.cancel();
            _transport?.close();
            _transport = null;
            if (!mounted || _error != null) return;
            setState(() {
              _bundle = service.result;
              _step = _Step.done;
            });
          },
        );
  }

  Future<void> _enterArchangel() async {
    final bundle = _bundle;
    if (bundle == null || _pairing) return;

    setState(() {
      _pairing = true;
      _pairError = null;
    });

    try {
      final wg = context.read<WireGuardController>();
      final backend = context.read<ArchangeldConnection>();
      await pairNewServer(
        registry: context.read<ServerRegistry>(),
        wg: wg,
        backend: backend,
        bundle: bundle,
        sshHost: _ssh.hostText,
        sshUser: _ssh.usernameText.isEmpty ? 'ubuntu' : _ssh.usernameText,
      );
      if (!mounted) return;
      // _RootRouter swaps its own body to the app shell once isPaired becomes
      // true, but that's the bottom of this Navigator's stack - this
      // wizard was reached via Navigator.push from SetupLandingScreen, so
      // it stays on top of that swap until popped.
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _pairing = false;
        _pairError = '$e';
      });
    }
  }

  /// Lets the user pick a private key file. Returns its text, or null when
  /// cancelled or the file is rejected (with a message shown).
  Future<String?> _pickKeyFile() async {
    String? initialDirectory;
    if (Platform.isMacOS || Platform.isLinux || Platform.isWindows) {
      final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
      if (home != null) {
        final dir = Directory('$home${Platform.pathSeparator}.ssh');
        if (dir.existsSync()) initialDirectory = dir.path;
      }
    }
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
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    return null;
  }

  // ---- build ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final stepIndex = _Step.values.indexOf(_step);
    return PopScope(
      canPop: _step == _Step.address || _step == _Step.done,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: c.bg,
        appBar: AppBar(
          backgroundColor: c.bg,
          elevation: 0,
          scrolledUnderElevation: 0,
          automaticallyImplyLeading: false,
          leading: AxIconButton(
            icon: Icons.arrow_back,
            tooltip: _step == _Step.address ? 'Close setup' : 'Back',
            onPressed: _running ? null : _back,
          ),
          title: Text('Set up your server', style: ax.typo.title.copyWith(color: c.text)),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: kSetupMaxWidth),
                  child: _StepIndicator(index: stepIndex, total: _Step.values.length, title: _stepTitles[_step]!),
                ),
              ),
              Expanded(child: SetupFrame(child: _buildStep(context))),
              if (_step.index <= _Step.review.index) _buildNavBar(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavBar(BuildContext context) {
    final ax = context.ax;
    final isReview = _step == _Step.review;
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: ax.colors.border)),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kSetupMaxWidth),
          child: Padding(
            padding: EdgeInsets.all(ax.space.lg),
            child: Row(
              children: [
                AxButton.secondary(label: 'Back', icon: Icons.arrow_back, onPressed: _back),
                const Spacer(),
                if (isReview)
                  AxButton(label: 'Start setup', icon: Icons.play_arrow, onPressed: _start)
                else
                  AxButton(label: 'Next', icon: Icons.arrow_forward, onPressed: _canNext ? _next : null),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStep(BuildContext context) => switch (_step) {
    _Step.address => _buildAddress(context),
    _Step.key => _buildKey(context),
    _Step.device => _buildDevice(context),
    _Step.review => _buildReview(context),
    _Step.run => _buildRun(context),
    _Step.done => _buildDone(context),
  };

  Widget _field(
    BuildContext context, {
    required TextEditingController controller,
    required String label,
    String? hint,
    TextInputType? keyboardType,
    HelpTip? help,
  }) {
    final ax = context.ax;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: keyboardType,
            style: ax.typo.body.copyWith(color: ax.colors.text),
            decoration: InputDecoration(labelText: label, hintText: hint),
          ),
        ),
        ?help,
      ],
    );
  }

  Widget _buildAddress(BuildContext context) {
    final ax = context.ax;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SetupHeading(
          title: 'Where is your server?',
          subtitle: 'Enter the address your provider gave you and the user name you sign in with.',
        ),
        SizedBox(height: ax.space.xl),
        _field(
          context,
          controller: _ssh.host,
          label: 'Server address',
          hint: '203.0.113.5',
          keyboardType: TextInputType.url,
          help: const HelpTip(
            title: 'Server address',
            message:
                'The public IP address (like 203.0.113.5) or domain name of your server. '
                'Your hosting provider shows it on the server\'s page.',
          ),
        ),
        SizedBox(height: ax.space.md),
        _field(
          context,
          controller: _ssh.username,
          label: 'Username',
          hint: 'ubuntu',
          help: const HelpTip(
            title: 'Username',
            message:
                'The account you sign in to the server with. It is "ubuntu" on Ubuntu images, "opc" on some '
                'Oracle images, and "root" on some other providers. Your provider\'s server page usually says.',
          ),
        ),
      ],
    );
  }

  Widget _buildKey(BuildContext context) {
    final ax = context.ax;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SetupHeading(
          title: 'Your SSH key',
          subtitle:
              'Archangel signs in to your server with an SSH key. It is used only to set things up '
              'and is never sent anywhere else.',
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: AxButton.ghost(label: 'How do I get an SSH key?', icon: Icons.help_outline, onPressed: () => showSshKeyHelp(context)),
        ),
        SizedBox(height: ax.space.sm),
        SshCredentialsForm(controller: _ssh, showHost: false, showUsername: false, restoreSavedOnStart: false, onPickKeyFile: _pickKeyFile),
      ],
    );
  }

  Widget _buildDevice(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final error = _advancedError;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SetupHeading(
          title: 'Name this device',
          subtitle: 'The server keeps a list of devices that can connect. Pick a name you will recognise.',
        ),
        SizedBox(height: ax.space.xl),
        _field(
          context,
          controller: _deviceNameController,
          label: 'Device name',
          hint: _defaultDeviceName(),
          help: const HelpTip(
            title: 'Device name',
            message: 'A label for this phone or computer, shown in the list of devices that can reach your server.',
          ),
        ),
        SizedBox(height: ax.space.md),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: Material(
            type: MaterialType.transparency,
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.only(bottom: ax.space.md),
              iconColor: c.accent,
              collapsedIconColor: c.textMuted,
              title: Text('Advanced', style: ax.typo.label.copyWith(color: c.text)),
              subtitle: Text(
                'Ports and private network. The defaults are right for almost everyone.',
                style: ax.typo.caption.copyWith(color: c.textMuted),
              ),
              children: [
                _field(
                  context,
                  controller: _wgSubnetController,
                  label: 'Private network (first three numbers)',
                  hint: '10.10.0',
                  help: const HelpTip(
                    title: 'Private network',
                    message:
                        'Archangel creates a private network between your devices and your server (using WireGuard). '
                        'This is the address range it uses. Only change it if it clashes with another network you use.',
                  ),
                ),
                SizedBox(height: ax.space.md),
                _field(
                  context,
                  controller: _wgPortController,
                  label: 'Secure connection port (UDP)',
                  hint: '51820',
                  keyboardType: TextInputType.number,
                  help: const HelpTip(
                    title: 'Secure connection port',
                    message:
                        'The port your devices use to reach the server\'s private connection. '
                        'It must be open at your provider\'s firewall.',
                  ),
                ),
                SizedBox(height: ax.space.md),
                _field(
                  context,
                  controller: _appPortController,
                  label: 'Archangel server port',
                  hint: '8443',
                  keyboardType: TextInputType.number,
                  help: const HelpTip(
                    title: 'Archangel server port',
                    message:
                        'The port the Archangel server listens on. It is only reachable through your private '
                        'connection, never from the open internet.',
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
                          Expanded(
                            child: Text(error, style: ax.typo.body.copyWith(color: c.danger)),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReview(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final wgPort = _wgPortController.text.trim().isEmpty ? '51820' : _wgPortController.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SetupHeading(
          title: 'Here\'s what will happen',
          subtitle: 'Archangel will sign in to ${_ssh.hostText} as ${_ssh.usernameText} and:',
        ),
        SizedBox(height: ax.space.lg),
        AxCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SetupBullet(text: 'Install updates and turn on a firewall'),
              const SetupBullet(text: 'Set up a private, secure connection between your devices and the server'),
              const SetupBullet(text: 'Install Docker (for running apps) and a web server'),
              const SetupBullet(text: 'Install the Archangel server'),
              SetupBullet(
                text:
                    'Pair this device as "${_deviceNameController.text.trim().isEmpty ? _defaultDeviceName() : _deviceNameController.text.trim()}" '
                    'so you can manage the server from here',
              ),
            ],
          ),
        ),
        SizedBox(height: ax.space.md),
        Row(
          children: [
            Icon(Icons.schedule, size: 18, color: c.textMuted),
            SizedBox(width: ax.space.sm),
            Expanded(
              child: Text(
                'This takes about 5 to 10 minutes. Keep the app open. It is safe to run again if anything fails.',
                style: ax.typo.body.copyWith(color: c.textMuted),
              ),
            ),
          ],
        ),
        SizedBox(height: ax.space.lg),
        AxCard(
          semanticsLabel: 'Before you start',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.warning_amber_rounded, size: 18, color: c.warning),
                  SizedBox(width: ax.space.sm),
                  Expanded(
                    child: Text('Before you start', style: ax.typo.label.copyWith(color: c.warning)),
                  ),
                ],
              ),
              SizedBox(height: ax.space.sm),
              Text(
                'Open UDP port $wgPort in your hosting provider\'s network firewall (not the server\'s own firewall). '
                'Archangel cannot do this for you because it is a setting in your provider\'s control panel. '
                'The Archangel server port does not need to be opened: it is only reachable through the private connection.',
                style: ax.typo.body.copyWith(color: c.textMuted),
              ),
              SizedBox(height: ax.space.sm),
              Text(
                'Also: the user needs passwordless sudo (true for ubuntu on most providers), and the server must run '
                'Ubuntu or Debian on x86_64 or ARM.',
                style: ax.typo.body.copyWith(color: c.textMuted),
              ),
              ProviderFirewallHelp(port: int.tryParse(wgPort) ?? 51820),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRun(BuildContext context) {
    final ax = context.ax;
    final failed = _error != null;

    final done = <String>{};
    for (final e in _log) {
      if (e.stageComplete && e.stage != 'verify') done.add(e.stage);
    }
    if (!_connecting && !(failed && _failedStage == 'connect')) done.add('connect');
    final activeKey = failed
        ? null
        : (_connecting ? 'connect' : (_log.isEmpty ? null : (_log.last.stageComplete ? null : normalizeSetupStage(_log.last.stage))));
    final activeMessage = (activeKey != null && activeKey != 'connect' && _log.isNotEmpty) ? _log.last.message : null;

    final errorText = '${_error ?? ''}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SetupHeading(
          title: failed ? 'Setup stopped' : 'Setting up your server',
          subtitle: failed ? null : 'This takes about 5 to 10 minutes. Keep the app open.',
        ),
        SizedBox(height: ax.space.lg),
        AxCard(
          child: Column(
            children: [
              for (final (key, label) in kSetupStages)
                _StageRow(
                  label: label,
                  state: failed && _failedStage == key
                      ? _StageState.failed
                      : done.contains(key)
                      ? _StageState.done
                      : key == activeKey
                      ? _StageState.active
                      : _StageState.pending,
                  detail: key == activeKey ? (activeMessage == null ? null : '$activeMessage (${_elapsedSeconds}s)') : null,
                ),
            ],
          ),
        ),
        if (failed) ...[
          SizedBox(height: ax.space.lg),
          _FailureCard(stageLabel: setupStageLabel(_failedStage ?? 'connect'), error: errorText, onRetry: _start, onBack: _back),
        ],
      ],
    );
  }

  Widget _buildDone(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            padding: EdgeInsets.all(ax.space.md),
            decoration: BoxDecoration(color: c.successWash, borderRadius: BorderRadius.circular(ax.radii.md)),
            child: Icon(Icons.check_circle_outline, size: 32, color: c.success, semanticLabel: 'Success'),
          ),
        ),
        SizedBox(height: ax.space.lg),
        SetupHeading(
          title: 'Your server is ready',
          subtitle: 'This device is paired as "${_bundle?.name ?? ''}". The private secure connection and the Archangel server are set up.',
        ),
        SizedBox(height: ax.space.xl),
        Semantics(
          header: true,
          child: Text('What to try next', style: ax.typo.title.copyWith(color: c.text)),
        ),
        SizedBox(height: ax.space.sm),
        const SetupBullet(text: 'Check the Home screen to see how your server is doing.', icon: Icons.home_outlined),
        const SetupBullet(text: 'Run your first app from Apps.', icon: Icons.apps_outlined),
        const SetupBullet(text: 'Browse files or open a terminal on the server.', icon: Icons.folder_open_outlined),
        const SetupBullet(text: 'Add your other devices from Settings.', icon: Icons.devices_outlined),
        if (_pairError != null) ...[
          SizedBox(height: ax.space.lg),
          Semantics(
            liveRegion: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline, size: 18, color: c.danger),
                SizedBox(width: ax.space.sm),
                Expanded(
                  child: Text(
                    'The server is set up, but this device could not finish connecting to it. Tap "Open your server" to try again.\n$_pairError',
                    style: ax.typo.body.copyWith(color: c.danger),
                  ),
                ),
              ],
            ),
          ),
        ],
        SizedBox(height: ax.space.xl),
        AxButton(label: 'Open your server', icon: Icons.arrow_forward, expand: true, loading: _pairing, onPressed: _enterArchangel),
      ],
    );
  }
}

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.index, required this.total, required this.title});

  final int index;
  final int total;
  final String title;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    return Padding(
      padding: EdgeInsets.fromLTRB(ax.space.lg, ax.space.xs, ax.space.lg, ax.space.xs),
      child: Semantics(
        label: 'Step ${index + 1} of $total: $title',
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                for (var i = 0; i < total; i++) ...[
                  Expanded(
                    child: Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: i <= index ? c.accent : c.surfaceHigh,
                        borderRadius: BorderRadius.circular(ax.radii.pill),
                      ),
                    ),
                  ),
                  if (i < total - 1) SizedBox(width: ax.space.xs),
                ],
              ],
            ),
            SizedBox(height: ax.space.sm),
            Text('Step ${index + 1} of $total · $title', style: ax.typo.caption.copyWith(color: c.textMuted)),
          ],
        ),
      ),
    );
  }
}

enum _StageState { pending, active, done, failed }

class _StageRow extends StatelessWidget {
  const _StageRow({required this.label, required this.state, this.detail});

  final String label;
  final _StageState state;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final (Widget icon, Color textColor, String status) = switch (state) {
      _StageState.done => (Icon(Icons.check_circle, size: 20, color: c.success), c.text, 'done'),
      _StageState.failed => (Icon(Icons.error, size: 20, color: c.danger), c.danger, 'failed'),
      _StageState.active => (
        SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: c.accent)),
        c.text,
        'in progress',
      ),
      _StageState.pending => (Icon(Icons.radio_button_unchecked, size: 20, color: c.textSubtle), c.textMuted, 'waiting'),
    };
    return Semantics(
      container: true,
      label: '$label, $status',
      excludeSemantics: true,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: ax.space.sm - 1),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            icon,
            SizedBox(width: ax.space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: ax.typo.body.copyWith(color: textColor, fontWeight: state == _StageState.active ? FontWeight.w700 : null),
                  ),
                  if (detail != null)
                    Text(
                      detail!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: ax.typo.caption.copyWith(color: c.textMuted),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FailureCard extends StatelessWidget {
  const _FailureCard({required this.stageLabel, required this.error, required this.onRetry, required this.onBack});

  final String stageLabel;
  final String error;
  final VoidCallback onRetry;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    return AxCard(
      semanticsLabel: 'Setup failed at $stageLabel',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline, size: 20, color: c.danger),
              SizedBox(width: ax.space.sm),
              Expanded(
                child: Text('This step failed: $stageLabel', style: ax.typo.title.copyWith(color: c.danger)),
              ),
            ],
          ),
          SizedBox(height: ax.space.sm),
          Text(hintForSetupError(error), style: ax.typo.body.copyWith(color: c.text)),
          if (errorNeedsFirewallHelp(error)) ...[SizedBox(height: ax.space.sm), const ProviderFirewallHelp()],
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: Material(
              type: MaterialType.transparency,
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                iconColor: c.accent,
                collapsedIconColor: c.textMuted,
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                title: Text('Technical details', style: ax.typo.label.copyWith(color: c.text)),
                children: [
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(ax.space.md),
                    decoration: BoxDecoration(
                      color: c.surfaceAlt,
                      borderRadius: BorderRadius.circular(ax.radii.sm),
                      border: Border.all(color: c.border),
                    ),
                    child: SelectableText(error, style: ax.typo.mono.copyWith(color: c.textMuted)),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: ax.space.sm),
          Wrap(
            spacing: ax.space.sm,
            runSpacing: ax.space.sm,
            children: [
              AxButton(label: 'Try again', icon: Icons.refresh, onPressed: onRetry),
              AxButton.secondary(label: 'Back to edit', icon: Icons.arrow_back, onPressed: onBack),
            ],
          ),
        ],
      ),
    );
  }
}
