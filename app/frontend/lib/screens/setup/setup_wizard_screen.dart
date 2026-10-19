import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/archangeld_connection.dart';
import '../../services/pairing_bundle.dart';
import '../../services/ssh_credentials.dart';
import '../../services/ssh_transport.dart';
import '../../services/vps_setup_service.dart';
import '../../services/wireguard_controller.dart';
import '../../theme/tokens.dart';
import '../../widgets/archangel_mark.dart';
import '../../widgets/ax_widgets.dart';
import '../../widgets/host_key_dialog.dart';
import '../../widgets/passphrase_prompt_dialog.dart';

/// The in-app "zero-SSH-by-hand" first-run wizard: connect → progress →
/// done. See lib/services/vps_setup_service.dart for what actually runs
/// on the server - this screen is purely presentation plus wiring the
/// resulting PairingBundle into WireGuardController/ArchangeldConnection
/// exactly the same way the manual pairing dialog does.
class SetupWizardScreen extends StatefulWidget {
  const SetupWizardScreen({super.key});

  @override
  State<SetupWizardScreen> createState() => _SetupWizardScreenState();
}

enum _WizardStep { connect, progress, done }

// Three dot-separated non-negative integers, e.g. "10.10.0" - the first
// three octets of a WireGuard subnet. Rejecting anything else here
// before it ever reaches VpsSetupService is defense in depth: that
// service also now writes config.yaml via SFTP rather than an
// interpolated shell heredoc specifically so a value that fails this
// check anyway can't do worse than fail cleanly.
final _wgSubnetPattern = RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}$');

class _SetupWizardScreenState extends State<SetupWizardScreen> {
  _WizardStep _step = _WizardStep.connect;

  final _hostController = TextEditingController();
  final _usernameController = TextEditingController(text: 'ubuntu');
  final _privateKeyController = TextEditingController();
  final _passphraseController = TextEditingController();
  final _deviceNameController = TextEditingController(text: _defaultDeviceName());
  bool _rememberKey = false;
  bool _connecting = false;
  String? _connectError;

  bool _firewallHelpOpen = false;
  bool _advancedOpen = false;
  final _wgSubnetController = TextEditingController(text: '10.10.0');
  final _wgPortController = TextEditingController(text: '51820');
  final _appPortController = TextEditingController(text: '8443');

  SshTransport? _transport;
  final List<SetupProgress> _log = [];
  Object? _runError;
  PairingBundle? _bundle;
  bool _pairing = false;
  String? _pairError;

  // Ticks once a second while a stage is running, so a long silent step
  // (e.g. baseline setup's apt update/upgrade, which can easily take
  // 30-90s with no output of its own) visibly shows the app is still
  // working instead of looking frozen. Reset to 0 whenever a new
  // (not-yet-complete) stage starts - see the reset in _runSetup's
  // listener below.
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
    _restoreSavedKey();
  }

  Future<void> _restoreSavedKey() async {
    // Restoring the key requires the passphrase that protects it - it grants
    // root on the VPS, so a device left unlocked shouldn't hand it over
    // just by opening this screen. unlockSavedSshCredentials caches the
    // decrypted value in memory for the app session, so if it was
    // already unlocked elsewhere this run, this won't prompt again.
    final creds = await unlockSavedSshCredentials(context);
    if (!mounted || creds == null) return;
    setState(() {
      _hostController.text = creds.host;
      _usernameController.text = creds.username;
      _privateKeyController.text = creds.privateKeyPem;
      _rememberKey = true;
    });
  }

  @override
  void dispose() {
    _hostController.dispose();
    _usernameController.dispose();
    _privateKeyController.dispose();
    _passphraseController.dispose();
    _deviceNameController.dispose();
    _wgSubnetController.dispose();
    _wgPortController.dispose();
    _appPortController.dispose();
    _transport?.close();
    _elapsedTimer?.cancel();
    super.dispose();
  }

  Future<void> _connect() async {
    final host = _hostController.text.trim();
    final username = _usernameController.text.trim();
    final privateKey = _privateKeyController.text.trim();
    if (host.isEmpty || username.isEmpty || privateKey.isEmpty) {
      setState(() => _connectError = 'Host, SSH username, and private key are all required.');
      return;
    }

    final wgSubnet = _wgSubnetController.text.trim();
    if (wgSubnet.isNotEmpty && !_wgSubnetPattern.hasMatch(wgSubnet)) {
      setState(() => _connectError = 'WireGuard subnet must be three dot-separated numbers, e.g. 10.10.0');
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

      if (_rememberKey) {
        final savePassphrase = await promptForPassphrase(
          context,
          title: 'Set a passphrase',
          message: 'Choose a passphrase (at least 8 characters) to protect this key. You\'ll need it to unlock the key later - there\'s no way to recover it without the passphrase.',
          confirm: true,
        );
        if (savePassphrase != null) {
          await saveSshCredentials(savePassphrase, SavedSshCredentials(host: host, username: username, privateKeyPem: privateKey));
        }
      } else {
        await clearSavedSshCredentials();
      }

      if (!mounted) return;
      _transport = transport;
      setState(() {
        _connecting = false;
        _step = _WizardStep.progress;
      });
      _elapsedSeconds = 0;
      _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _elapsedSeconds++);
      });
      _runSetup();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _connectError = 'Could not connect: $e';
      });
    }
  }

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

  void _runSetup() {
    final config = VpsSetupConfig(
      deviceName: _deviceNameController.text.trim().isEmpty ? _defaultDeviceName() : _deviceNameController.text.trim(),
      wgSubnet: _wgSubnetController.text.trim().isEmpty ? '10.10.0' : _wgSubnetController.text.trim(),
      wgPort: int.tryParse(_wgPortController.text.trim()) ?? 51820,
      appPort: int.tryParse(_appPortController.text.trim()) ?? 8443,
    );
    final service = VpsSetupService(_transport!);
    service.run(config).listen(
      (event) => setState(() {
        _appendOrUpdate(event);
        if (!event.stageComplete) _elapsedSeconds = 0;
      }),
      onError: (Object e) {
        _elapsedTimer?.cancel();
        setState(() => _runError = e);
      },
      onDone: () {
        _elapsedTimer?.cancel();
        if (_runError == null) {
          setState(() {
            _bundle = service.result;
            _step = _WizardStep.done;
          });
        }
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
      await wg.pair(bundle.tunnel.toWgQuickConfig());
      await backend.pair(host: bundle.host, token: bundle.token);
      if (!mounted) return;
      // _RootRouter swaps its own body to AppShell once isPaired becomes
      // true, but that's the bottom of this Navigator's stack - this
      // wizard was reached via Navigator.push from SetupLandingScreen, so
      // it stays on top of that swap until popped. Without this, the
      // screen just sits on "Server ready" forever even though pairing
      // fully succeeded and AppShell is already active underneath.
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _pairing = false;
        _pairError = 'Could not finish pairing: $e. The server is set up - tap to try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AxColors.bg,
      appBar: AppBar(
        backgroundColor: AxColors.bg,
        elevation: 0,
        title: Text('Set up a new server', style: AxTextStyles.sans.copyWith(fontSize: 15, fontWeight: FontWeight.w700)),
      ),
      body: switch (_step) {
        _WizardStep.connect => _buildConnectStep(),
        _WizardStep.progress => _buildProgressStep(),
        _WizardStep.done => _buildDoneStep(),
      },
    );
  }

  Widget _buildConnectStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AxCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: AxColors.warn, size: 18),
                      const SizedBox(width: 8),
                      Text('Before you start', style: AxTextStyles.sans.copyWith(fontSize: 13, fontWeight: FontWeight.w700, color: AxColors.warn)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '• Open UDP 51820 (WireGuard) at your cloud provider\'s network firewall '
                    'level (e.g. an OCI VCN Security List or AWS Security Group) - this is '
                    'separate from the server\'s own firewall and this wizard cannot open it '
                    'for you. The archangeld port below does NOT need to be opened there - it '
                    'only ever listens on the WireGuard interface, never the public internet.\n\n'
                    '• The SSH key you paste below must already be authorized on the server '
                    '(the cloud-init user\'s authorized_keys) - this wizard connects with it, '
                    'it doesn\'t add it for you.\n\n'
                    '• The SSH user needs passwordless sudo (true by default for "ubuntu" on '
                    'OCI/AWS/most providers, not guaranteed on a custom image).\n\n'
                    '• Only Ubuntu/Debian on x86_64 or aarch64 is supported.\n\n'
                    'Safe to re-run against a server that\'s already partially or fully set up.',
                    style: AxTextStyles.sans.copyWith(fontSize: 12, color: AxColors.fg2, height: 1.5),
                  ),
                  const SizedBox(height: 4),
                  // Wrapped in its own transparent Material: ExpansionTile's
                  // header is a ListTile, which paints its background/ink
                  // on the nearest Material ancestor - without this it
                  // reaches past AxCard's own opaque background (an
                  // AnimatedContainer, not a Material) to whatever Material
                  // is further up, which Flutter flags as a real bug (ink
                  // effects would be invisible, hidden under AxCard's paint).
                  Material(
                    type: MaterialType.transparency,
                    child: ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      initiallyExpanded: _firewallHelpOpen,
                      onExpansionChanged: (v) => setState(() => _firewallHelpOpen = v),
                      title: Text(
                        'How do I open this port? (step-by-step)',
                        style: AxTextStyles.sans.copyWith(fontSize: 12.5, fontWeight: FontWeight.w600, color: AxColors.warn),
                      ),
                      children: const [
                      _FirewallHowTo(
                        provider: 'Oracle Cloud (OCI)',
                        steps: [
                          'Console → Networking → Virtual Cloud Networks → open your VCN.',
                          'Click the Subnet your instance is in, then its attached Security List.',
                          'Add Ingress Rule: Source CIDR 0.0.0.0/0, IP Protocol UDP, Destination Port Range 51820.',
                          'Save Changes - takes effect immediately, no restart needed.',
                        ],
                      ),
                      _FirewallHowTo(
                        provider: 'AWS (EC2)',
                        steps: [
                          'EC2 Console → Instances → select your instance → Security tab.',
                          'Click the security group listed there.',
                          'Edit inbound rules → Add rule: Type "Custom UDP", Port range 51820, Source 0.0.0.0/0 (or your IP for tighter access).',
                          'Save rules.',
                        ],
                      ),
                      _FirewallHowTo(
                        provider: 'DigitalOcean',
                        steps: [
                          'Control panel → Networking → Firewalls.',
                          'Create (or edit) a firewall and attach it to your droplet.',
                          'Add an inbound rule: Type UDP, Port 51820, Sources: All IPv4/All IPv6 (or restrict as needed).',
                          'Save.',
                        ],
                      ),
                      _FirewallHowTo(
                        provider: 'Any other provider',
                        steps: [
                          'Find the "network firewall" / "security group" / "cloud firewall" section '
                              'in your provider\'s console - it\'s always separate from anything '
                              'configured on the server itself (ufw, iptables, etc.).',
                          'Add an inbound/ingress rule allowing UDP traffic on port 51820 from any source (0.0.0.0/0).',
                          'Save/apply the change.',
                        ],
                      ),
                    ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _label('Server public IP or hostname'),
            _textField(_hostController, hint: '203.0.113.5'),
            const SizedBox(height: 12),
            _label('SSH username'),
            _textField(_usernameController, hint: 'ubuntu'),
            const SizedBox(height: 12),
            _label('SSH private key'),
            _textField(_privateKeyController, hint: '-----BEGIN OPENSSH PRIVATE KEY-----', maxLines: 6, mono: true),
            const SizedBox(height: 12),
            _label('SSH key passphrase (leave blank if none)'),
            _textField(_passphraseController, hint: '', obscure: true),
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
            const SizedBox(height: 12),
            _label('Device name'),
            _textField(_deviceNameController, hint: 'mac'),
            const SizedBox(height: 8),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              initiallyExpanded: _advancedOpen,
              onExpansionChanged: (v) => setState(() => _advancedOpen = v),
              title: Text('Advanced', style: AxTextStyles.sans.copyWith(fontSize: 12.5, color: AxColors.fg2)),
              children: [
                _label('WireGuard subnet'),
                _textField(_wgSubnetController, hint: '10.10.0'),
                const SizedBox(height: 12),
                _label('WireGuard port'),
                _textField(_wgPortController, hint: '51820'),
                const SizedBox(height: 12),
                _label('archangeld port'),
                _textField(_appPortController, hint: '8443'),
              ],
            ),
            if (_connectError != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_connectError!, style: AxTextStyles.mono.copyWith(fontSize: 11.5, color: AxColors.bad)),
              ),
            const SizedBox(height: 20),
            SizedBox(
              height: 44,
              child: FilledButton(
                onPressed: _connecting ? null : _connect,
                child: _connecting
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Connect and set up'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressStep() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_runError != null)
            AxCard(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Setup failed', style: AxTextStyles.sans.copyWith(fontSize: 13, fontWeight: FontWeight.w700, color: AxColors.bad)),
                  const SizedBox(height: 6),
                  Text('$_runError', style: AxTextStyles.mono.copyWith(fontSize: 11.5, color: AxColors.bad)),
                ],
              ),
            ),
          Expanded(
            child: ListView.builder(
              itemCount: _log.length,
              itemBuilder: (context, i) {
                final entry = _log[i];
                // The actively-running stage is the last, not-yet-complete
                // entry, as long as nothing has failed - show a spinner and
                // an elapsed-time counter there instead of a static hollow
                // circle, so a long silent step (apt update/upgrade can
                // easily run 30-90s with no output) still visibly shows
                // the app is working rather than looking frozen.
                final isActive = i == _log.length - 1 && !entry.stageComplete && _runError == null;
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
                      Expanded(
                        child: Text(
                          isActive ? '${entry.message} (${_elapsedSeconds}s)' : entry.message,
                          style: AxTextStyles.mono.copyWith(fontSize: 12, color: AxColors.fg2),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDoneStep() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ArchangelMark(size: 30, tile: true),
              const SizedBox(height: 16),
              Text('Server ready', style: AxTextStyles.sans.copyWith(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(
                'Paired as "${_bundle?.name ?? ''}" - your WireGuard tunnel and backend connection are configured.',
                textAlign: TextAlign.center,
                style: AxTextStyles.sans.copyWith(fontSize: 13, color: AxColors.fg2, height: 1.5),
              ),
              if (_pairError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_pairError!, textAlign: TextAlign.center, style: AxTextStyles.mono.copyWith(fontSize: 11.5, color: AxColors.bad)),
                ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: FilledButton(
                  onPressed: _pairing ? null : _enterArchangel,
                  child: _pairing
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Enter Archangel'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(text, style: AxTextStyles.sans.copyWith(fontSize: 11, color: AxColors.fg3)),
      );

  Widget _textField(TextEditingController controller, {required String hint, int maxLines = 1, bool mono = false, bool obscure = false}) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      obscureText: obscure,
      style: (mono ? AxTextStyles.mono : AxTextStyles.sans).copyWith(fontSize: 12.5),
      decoration: InputDecoration(
        filled: true,
        fillColor: AxColors.s1,
        hintText: hint,
        hintStyle: (mono ? AxTextStyles.mono : AxTextStyles.sans).copyWith(fontSize: 12, color: AxColors.fg3),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
    );
  }
}

/// One provider's numbered steps inside the "Before you start" card's
/// "How do I open this port?" expander - every cloud provider's own
/// network-firewall UI is different, and this is the one prerequisite the
/// wizard genuinely cannot do for the user (see the SSH-can't-reach-it note
/// above it), so it's worth spelling out rather than just naming the
/// concept and leaving people to go find the menu themselves.
class _FirewallHowTo extends StatelessWidget {
  final String provider;
  final List<String> steps;
  const _FirewallHowTo({required this.provider, required this.steps});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(provider, style: AxTextStyles.sans.copyWith(fontSize: 12, fontWeight: FontWeight.w700, color: AxColors.fg)),
          const SizedBox(height: 4),
          for (var i = 0; i < steps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 18,
                    child: Text('${i + 1}.', style: AxTextStyles.mono.copyWith(fontSize: 11.5, color: AxColors.fg3)),
                  ),
                  Expanded(
                    child: Text(steps[i], style: AxTextStyles.sans.copyWith(fontSize: 11.5, color: AxColors.fg2, height: 1.4)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
