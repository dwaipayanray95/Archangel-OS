import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

import 'build_config.dart';
import 'pairing_bundle.dart';
import 'ssh_transport.dart';

/// Configuration for one VPS bootstrap run. Defaults match
/// infra/scripts/wireguard_setup.sh and app/backend/deploy.sh so a wizard
/// run with defaults produces the exact same server state a human running
/// those scripts by hand would.
class VpsSetupConfig {
  /// First three octets of the WireGuard tunnel subnet - the server
  /// always takes .1.
  final String wgSubnet;
  final int wgPort;
  final int appPort;

  /// Name given to this device's WireGuard peer + archangeld token -
  /// shows up in `wg show` and the token store.
  final String deviceName;

  /// "owner/repo" on GitHub to fetch the archangeld release binary from -
  /// see .github/workflows/release-backend.yml.
  final String githubRepoSlug;

  const VpsSetupConfig({
    required this.deviceName,
    this.wgSubnet = '10.10.0',
    this.wgPort = 51820,
    this.appPort = 8443,
    this.githubRepoSlug = kGithubRepoSlug,
  });
}

/// One line of progress for the setup wizard's UI to render - a stage
/// name (for grouping into a step list) plus a message (either a
/// human-readable status line or raw remote command output).
class SetupProgress {
  final String stage;
  final String message;
  final bool stageComplete;

  const SetupProgress(this.stage, this.message, {this.stageComplete = false});
}

/// Thrown when a step fails outright (as opposed to being skipped for
/// idempotency reasons, which is not an error).
class VpsSetupException implements Exception {
  final String stage;
  final String message;
  const VpsSetupException(this.stage, this.message);
  @override
  String toString() => '[$stage] $message';
}

/// Bootstraps a fresh Ubuntu/Debian VPS into a fully working, paired
/// Archangel server over one SSH connection: replicates
/// infra/scripts/install-archangel.sh + app/backend/deploy.sh +
/// `archangeld pair`, in that order, ending with a parsed [PairingBundle]
/// ready to hand to [WireGuardController.pair] and
/// [ArchangeldConnection.pair].
///
/// Reuses the real shell scripts (bundled as Flutter assets under
/// assets/setup_scripts/ - see pubspec.yaml) rather than reimplementing
/// their logic in Dart, since those scripts already carry hard-won fixes
/// for real incidents (empty-keyed WireGuard configs, the
/// iptables-persistent/ufw conflict, etc. - see infra/README.md §8).
/// NOTE: these are copies, not a shared file path (Flutter can't bundle
/// assets from outside the package root) - infra/scripts/ is canonical;
/// after changing anything there run scripts/sync_setup_assets.sh to re-copy.
///
/// Every step is safe to re-run against a server that's already
/// partially or fully set up: WireGuard setup is skipped if `wg0.conf`
/// already exists (re-running it would invalidate every already-paired
/// device), `config.yaml` is never overwritten if present, and every
/// other step (binary download, systemd install, firewall rules,
/// pairing) is naturally idempotent already.
class VpsSetupService {
  final SshTransport _ssh;

  VpsSetupService(this._ssh);

  static const _remoteScriptDir = '/tmp/archangel-setup';
  static const _assetNames = [
    'baseline_setup.sh',
    'wireguard_setup.sh',
    'allow_port_before_reject.sh',
    'ensure_boot_fw_fixup.sh',
    'archangel.service',
    'uninstall.sh',
  ];

  static const _sudoersGrant = 'archangel ALL=(ALL) NOPASSWD: ALL';

  /// Writes the Admin mode grant. Used by first-time setup, where Admin
  /// mode is on by default.
  static const _sudoersGrantScript = '''
echo "$_sudoersGrant" | sudo tee /etc/sudoers.d/archangel > /dev/null
sudo chmod 440 /etc/sudoers.d/archangel''';

  /// Re-applies the grant ONLY if it's already there, so syncing/updating an
  /// existing server never silently turns Admin mode back on after the user
  /// switched it off. `sudo test` because /etc/sudoers.d isn't searchable by
  /// non-root users (mode 0750), so a plain `[ -f ]` would always say no.
  /// Packages and boot ordering that newer archangeld versions rely on,
  /// re-applied on update/sync so servers set up before they existed catch
  /// up: tmux + dbus-user-session for persistent terminal sessions (run
  /// under the archangel user's systemd user manager), lingering so that
  /// manager runs without a login, and Docker starting after WireGuard so
  /// containers published on the tunnel address can bind at boot. Mirrors
  /// infra/scripts/baseline_setup.sh.
  static const _serverPrereqsScript = '''
if ! dpkg -s tmux >/dev/null 2>&1 || ! dpkg -s dbus-user-session >/dev/null 2>&1; then
  sudo apt-get update -qq
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq tmux dbus-user-session
fi
sudo loginctl enable-linger archangel || true
if [ -d /etc/systemd/system ] && command -v docker >/dev/null 2>&1; then
  sudo mkdir -p /etc/systemd/system/docker.service.d
  printf '[Unit]\\nAfter=wg-quick@wg0.service\\nWants=wg-quick@wg0.service\\n' | sudo tee /etc/systemd/system/docker.service.d/archangel-wg.conf > /dev/null
fi''';

  static const _sudoersRefreshScript = '''
if sudo test -f /etc/sudoers.d/archangel; then
$_sudoersGrantScript
fi''';

  PairingBundle? _result;

  /// The pairing bundle for this device, available once [run]'s stream
  /// has completed successfully.
  PairingBundle get result {
    final r = _result;
    if (r == null) throw StateError('VpsSetupService.run() has not completed successfully yet');
    return r;
  }

  Stream<SetupProgress> run(VpsSetupConfig config) async* {
    yield const SetupProgress('detect', 'Checking the server is a supported Ubuntu/Debian host...');
    final arch = await _detectArch();
    yield SetupProgress('detect', 'Detected architecture: $arch', stageComplete: true);

    yield const SetupProgress('upload', 'Uploading setup scripts...');
    await _uploadScripts();
    yield const SetupProgress('upload', 'Scripts uploaded.', stageComplete: true);

    yield const SetupProgress('baseline', 'Running baseline setup (packages, swap, firewall)...');
    await _runScript('baseline_setup.sh', stage: 'baseline');
    yield const SetupProgress('baseline', 'Baseline setup complete.', stageComplete: true);

    yield const SetupProgress('wireguard', 'Checking for an existing WireGuard setup...');
    final wgAlreadySetUp = (await _exec('test -f /etc/wireguard/wg0.conf')).ok;
    if (wgAlreadySetUp) {
      yield const SetupProgress(
        'wireguard',
        'WireGuard is already configured on this server - leaving it as-is (re-running it would invalidate every already-paired device).',
        stageComplete: true,
      );
    } else {
      yield const SetupProgress('wireguard', 'Setting up WireGuard...');
      await _runScript('wireguard_setup.sh', stage: 'wireguard');
      yield const SetupProgress('wireguard', 'WireGuard configured.', stageComplete: true);
    }

    yield const SetupProgress('binary', 'Downloading the latest archangeld release...');
    yield* _installBinary(arch, config);
    yield const SetupProgress('binary', 'archangeld installed.', stageComplete: true);

    yield const SetupProgress('config', 'Writing server configuration...');
    final publicIp = await _writeConfigIfAbsent(config);
    yield const SetupProgress('config', 'Configuration ready.', stageComplete: true);

    yield const SetupProgress('service', 'Installing and starting the archangel service...');
    await _installService();
    yield const SetupProgress('service', 'Service is running.', stageComplete: true);

    yield const SetupProgress('firewall', 'Opening the app port to the WireGuard interface...');
    await _openAppPort(config);
    yield const SetupProgress('firewall', 'Firewall configured.', stageComplete: true);

    yield SetupProgress('pair', 'Pairing this device (server public IP: $publicIp)...');
    final bundle = await _pair(config);
    _result = bundle;
    yield const SetupProgress('pair', 'Paired.', stageComplete: true);
  }

  Future<String> _detectArch() async {
    final unameResult = await _exec('uname -m');
    if (!unameResult.ok) {
      throw VpsSetupException('detect', 'Could not run `uname -m` on the server: ${unameResult.stderr}');
    }
    final arch = switch (unameResult.stdout.trim()) {
      'x86_64' => 'amd64',
      'aarch64' || 'arm64' => 'arm64',
      final other => throw VpsSetupException(
          'detect',
          'Unsupported server architecture "$other" - only x86_64/aarch64 servers are supported.',
        ),
    };

    final aptResult = await _exec('command -v apt-get');
    if (!aptResult.ok) {
      throw const VpsSetupException(
        'detect',
        'This wizard only supports Ubuntu/Debian servers (apt-get was not found on this host).',
      );
    }
    return arch;
  }

  Future<void> _uploadScripts() async {
    await _exec('mkdir -p $_remoteScriptDir');
    for (final name in _assetNames) {
      final data = await rootBundle.load('assets/setup_scripts/$name');
      final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      final remotePath = '$_remoteScriptDir/$name';
      final isScript = name.endsWith('.sh');
      await _ssh.uploadFile(remotePath, bytes, chmod: isScript ? '755' : '644');
    }
  }

  Future<void> _runScript(String name, {required String stage}) async {
    final result = await _exec('bash $_remoteScriptDir/$name');
    if (!result.ok) {
      throw VpsSetupException(stage, 'exit ${result.exitCode}: ${result.stderr.isNotEmpty ? result.stderr : result.stdout}');
    }
  }

  Stream<SetupProgress> _installBinary(String arch, VpsSetupConfig config) async* {
    final baseUrl = 'https://github.com/${config.githubRepoSlug}/releases/latest/download';
    final url = '$baseUrl/archangeld-$arch';
    final prepScript = '''
set -e
sudo id -u archangel >/dev/null 2>&1 || sudo useradd --system --create-home --home-dir /home/archangel --shell /bin/bash archangel
sudo mkdir -p /home/archangel /opt/archangel /etc/archangel
sudo chown archangel:archangel /home/archangel
sudo chown root:archangel /etc/archangel
sudo chmod 750 /etc/archangel
if sudo test -f /opt/archangel/archangeld; then
$_sudoersRefreshScript
else
$_sudoersGrantScript
fi
''';
    final prepResult = await _exec(prepScript);
    if (!prepResult.ok) {
      throw VpsSetupException('binary', 'Failed to prepare the archangel user and directories - exit ${prepResult.exitCode}: ${prepResult.stderr}');
    }

    final downloadResult = await _exec('sudo curl -fsSL "$url" -o /opt/archangel/archangeld.download');
    if (!downloadResult.ok) {
      throw VpsSetupException(
        'binary',
        'Failed to install archangeld (checked $url) - exit ${downloadResult.exitCode}: ${downloadResult.stderr}',
      );
    }

    final verified = await _verifyChecksum(
      sumsUrl: '$baseUrl/SHA256SUMS',
      arch: arch,
      filePath: '/opt/archangel/archangeld.download',
      stage: 'binary',
    );
    yield verified ? _checksumOk : _checksumSkipped;

    final installResult = await _exec('''
set -e
sudo mv /opt/archangel/archangeld.download /opt/archangel/archangeld
sudo chmod 755 /opt/archangel/archangeld
sudo chown root:root /opt/archangel/archangeld
''');
    if (!installResult.ok) {
      throw VpsSetupException('binary', 'Failed to install archangeld - exit ${installResult.exitCode}: ${installResult.stderr}');
    }
  }

  static const _checksumOk = SetupProgress('verify', 'Checksum verified.', stageComplete: true);
  static const _checksumSkipped = SetupProgress('verify', 'Release has no checksums - skipped verification', stageComplete: true);

  /// Downloads the release's SHA256SUMS from [sumsUrl] and checks the
  /// already-downloaded [filePath] against the `archangeld-<arch>` line.
  ///
  /// Returns true if verified, false if the release simply has no
  /// SHA256SUMS (HTTP 404 - releases from before checksums existed).
  /// Throws [VpsSetupException] (and deletes [filePath]) on a mismatch,
  /// a missing entry, or any other failure fetching the sums - an
  /// unreachable/erroring checksum file is not the same as an old release,
  /// so it must not silently downgrade to "unverified".
  Future<bool> _verifyChecksum({
    required String sumsUrl,
    required String arch,
    required String filePath,
    required String stage,
  }) async {
    final sumsPath = '$filePath.SHA256SUMS';
    final fetch = await _exec('sudo rm -f "$sumsPath"; sudo curl -sSL -o "$sumsPath" -w \'%{http_code}\' "$sumsUrl"');
    final httpCode = fetch.stdout.trim();
    if (fetch.ok && httpCode == '404') {
      await _exec('sudo rm -f "$sumsPath"');
      return false;
    }
    if (!fetch.ok || httpCode != '200') {
      await _exec('sudo rm -f "$sumsPath" "$filePath"');
      throw VpsSetupException(
        stage,
        'Could not download the release checksums ($sumsUrl) - HTTP ${httpCode.isEmpty ? 'unknown' : httpCode}'
        '${fetch.stderr.isNotEmpty ? ': ${fetch.stderr}' : ''}',
      );
    }

    final name = 'archangeld-$arch';
    final verifyScript = '''
LINE=\$(grep " $name\\\$" "$sumsPath") || { echo "SHA256SUMS has no entry for $name" >&2; exit 1; }
echo "\$LINE" | sed 's|$name\$|$filePath|' | sudo sha256sum -c -
''';
    final verify = await _exec(verifyScript);
    await _exec('sudo rm -f "$sumsPath"');
    if (!verify.ok) {
      await _exec('sudo rm -f "$filePath"');
      throw VpsSetupException(
        stage,
        'Checksum verification failed - the downloaded $name does not match the published SHA256SUMS, so it was discarded. '
        '${verify.stderr.isNotEmpty ? verify.stderr : verify.stdout}',
      );
    }
    return true;
  }

  /// Returns the server's detected public IP (queried either way, since
  /// it's needed for the pairing bundle's WireGuard endpoint even when
  /// config.yaml already exists and is left untouched).
  Future<String> _writeConfigIfAbsent(VpsSetupConfig config) async {
    final ipResult = await _exec("curl -s -4 ifconfig.me || curl -s -4 icanhazip.com");
    final publicIp = ipResult.stdout.trim();
    if (publicIp.isEmpty) {
      throw const VpsSetupException('config', 'Could not detect the server\'s public IP address.');
    }

    final alreadyExists = (await _exec('test -f /etc/archangel/config.yaml')).ok;
    if (alreadyExists) {
      return publicIp;
    }

    final wgServerIp = '${config.wgSubnet}.1';
    final configYaml = '''
bind_addr: "$wgServerIp"
port: ${config.appPort}
public_endpoint: "$publicIp:${config.wgPort}"
files_root: "/home/archangel"
''';

    // Uploaded via SFTP (raw bytes, no shell parsing of the content at
    // all) rather than spliced into a heredoc - config.yaml's content
    // includes config.wgSubnet, a free-text field from the wizard's
    // "Advanced" section. A value containing a line that reads exactly
    // the heredoc's own delimiter would terminate it early and run
    // whatever followed as arbitrary shell as root - the same class of
    // bug the setup scripts themselves already avoid by being uploaded,
    // not inlined. Move the uploaded file into place with a second,
    // fixed (non-interpolated) command.
    final tmpPath = '$_remoteScriptDir/config.yaml';
    await _ssh.uploadFile(tmpPath, Uint8List.fromList(utf8.encode(configYaml)));

    final script = '''
set -e
sudo mv $tmpPath /etc/archangel/config.yaml
sudo chown root:archangel /etc/archangel/config.yaml
sudo chmod 640 /etc/archangel/config.yaml
''';
    final result = await _exec(script);
    if (!result.ok) {
      throw VpsSetupException('config', 'Failed to write config.yaml: ${result.stderr}');
    }
    return publicIp;
  }

  Future<void> _installService() async {
    final script = '''
set -e
sudo mv $_remoteScriptDir/archangel.service /etc/systemd/system/archangel.service
sudo systemctl daemon-reload
sudo systemctl enable --now archangel
sudo systemctl restart archangel
sleep 1
sudo systemctl is-active --quiet archangel
''';
    final result = await _exec(script);
    if (!result.ok) {
      throw VpsSetupException(
        'service',
        'archangel service failed to start - exit ${result.exitCode}: ${result.stderr}\n'
            'Check `sudo systemctl status archangel` and `sudo journalctl -u archangel -n 50` on the server.',
      );
    }
  }

  Future<void> _openAppPort(VpsSetupConfig config) async {
    final script = '''
set -e
sudo ufw allow in on wg0 to any port ${config.appPort} proto tcp || true
bash $_remoteScriptDir/allow_port_before_reject.sh ${config.appPort} tcp
bash $_remoteScriptDir/ensure_boot_fw_fixup.sh ${config.appPort} tcp
''';
    final result = await _exec(script);
    if (!result.ok) {
      throw VpsSetupException('firewall', 'Failed to open the app port: ${result.stderr}');
    }
  }

  Future<PairingBundle> _pair(VpsSetupConfig config) async {
    final result = await _exec('sudo /opt/archangel/archangeld pair ${_shellQuote(config.deviceName)} --raw');
    if (!result.ok) {
      throw VpsSetupException('pair', 'archangeld pair failed - exit ${result.exitCode}: ${result.stderr}');
    }
    try {
      return PairingBundle.parse(result.stdout.trim());
    } on FormatException catch (e) {
      throw VpsSetupException('pair', 'Got a pairing bundle back but could not parse it: ${e.message}');
    }
  }

  /// Updates an already-running archangeld to [targetVersion], downloading
  /// the binary from the specific release tagged [releaseTag] - NOT
  /// "latest": a -b/-f release's other component may not have its
  /// binary attached to whatever release GitHub currently calls
  /// "latest" at all (see UpdateCheckService.backendTag's doc comment).
  ///
  /// Keeps the previous binary as `archangeld.bak` and, if the new one
  /// doesn't come up correctly, automatically restores it. "Came up
  /// correctly" is checked via [fetchLiveVersion] - a caller-supplied
  /// poll of the app's own authenticated /health endpoint - rather than
  /// just trusting `systemctl is-active`, since a process can be
  /// "active" (running) while still serving the wrong version or about
  /// to crash-loop moments later.
  Stream<SetupProgress> updateBackend({
    required String targetVersion,
    required String releaseTag,
    required String githubRepoSlug,
    required Future<String?> Function() fetchLiveVersion,
    Duration pollInterval = const Duration(seconds: 2),
  }) async* {
    yield const SetupProgress('detect', 'Checking server architecture...');
    final arch = await _detectArch();
    yield SetupProgress('detect', 'Detected architecture: $arch', stageComplete: true);

    yield const SetupProgress('backup', 'Backing up the current binary...');
    final backupResult = await _exec('sudo cp -f /opt/archangel/archangeld /opt/archangel/archangeld.bak');
    if (!backupResult.ok) {
      throw VpsSetupException('backup', 'Could not back up the current binary: ${backupResult.stderr}');
    }
    yield const SetupProgress('backup', 'Backup created.', stageComplete: true);

    yield SetupProgress('download', 'Downloading archangeld v$targetVersion...');
    final baseUrl = 'https://github.com/$githubRepoSlug/releases/download/$releaseTag';
    final url = '$baseUrl/archangeld-$arch';
    // Downloaded to a staging path in root-owned /opt/archangel (not
    // world-writable /tmp, so nothing else on the box can swap the file
    // between verification and install), checksum-verified and version-checked
    // BEFORE it's moved into /opt/archangel/archangeld, so a bad/corrupt
    // download never overwrites the last-known-good binary in the first
    // place - the backup above is the second line of defense (a
    // restart-time failure the version check itself can't catch, e.g. the
    // binary runs fine standalone but crashes under real config/load).
    final fetchResult = await _exec('sudo curl -fsSL "$url" -o /opt/archangel/archangeld.new');
    if (!fetchResult.ok) {
      throw VpsSetupException(
        'download',
        'Failed to download/verify archangeld v$targetVersion (checked $url) - exit ${fetchResult.exitCode}: ${fetchResult.stderr}',
      );
    }
    final verified = await _verifyChecksum(
      sumsUrl: '$baseUrl/SHA256SUMS',
      arch: arch,
      filePath: '/opt/archangel/archangeld.new',
      stage: 'download',
    );
    yield verified ? _checksumOk : _checksumSkipped;

    final downloadScript = '''
set -e
sudo chmod 755 /opt/archangel/archangeld.new
sudo chown root:root /opt/archangel/archangeld.new
NEW_VERSION=\$(/opt/archangel/archangeld.new version 2>/dev/null | awk '{print \$2}' | sed 's/^v//')
if [ "\$NEW_VERSION" != "$targetVersion" ]; then
  echo "downloaded binary reports version '\$NEW_VERSION', expected $targetVersion" >&2
  exit 1
fi
sudo mv /opt/archangel/archangeld.new /opt/archangel/archangeld
''';
    final downloadResult = await _exec(downloadScript);
    if (!downloadResult.ok) {
      throw VpsSetupException(
        'download',
        'Failed to download/verify archangeld v$targetVersion (checked $url) - exit ${downloadResult.exitCode}: ${downloadResult.stderr}',
      );
    }
    yield const SetupProgress('download', 'Downloaded and verified.', stageComplete: true);

    yield const SetupProgress('sync', 'Updating service definition and permissions...');
    // Upload and sync the latest bundled archangel.service asset
    await _uploadScripts();
    final syncScript = '''
set -e
sudo id -u archangel >/dev/null 2>&1 || sudo useradd --system --create-home --home-dir /home/archangel --shell /bin/bash archangel
sudo mkdir -p /home/archangel /opt/archangel /etc/archangel
sudo chown -R archangel:archangel /home/archangel
sudo usermod -d /home/archangel -s /bin/bash archangel || true
$_sudoersRefreshScript
$_serverPrereqsScript
sudo cp -f $_remoteScriptDir/archangel.service /etc/systemd/system/archangel.service

# If config.yaml has empty files_root, update it to /home/archangel
if [ -f /etc/archangel/config.yaml ]; then
  if grep -q 'files_root: ""' /etc/archangel/config.yaml || grep -q "files_root: ''" /etc/archangel/config.yaml; then
    sudo sed -i 's|files_root: .*|files_root: "/home/archangel"|' /etc/archangel/config.yaml
  fi
fi

# Ensure Docker Engine & Compose are installed during backend updates
if ! command -v docker >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com | sh
  sudo systemctl enable --now docker
fi
sudo usermod -aG docker archangel || true

# Ensure Caddy reverse proxy is installed and ports 80/443 are allowed
if ! command -v caddy >/dev/null 2>&1; then
  sudo apt-get update -qq
  sudo apt-get install -y -qq debian-keyring debian-archive-keyring apt-transport-https curl
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg --yes
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list > /dev/null
  sudo apt-get update -qq
  sudo apt-get install -y -qq caddy
  sudo systemctl enable --now caddy
fi

if [ -d /etc/caddy ]; then
  sudo chown -R root:archangel /etc/caddy
  sudo chmod 775 /etc/caddy
fi

if command -v ufw >/dev/null 2>&1 && sudo ufw status | grep -q "Status: active"; then
  sudo ufw allow 80/tcp > /dev/null
  sudo ufw allow 443/tcp > /dev/null
fi

sudo systemctl daemon-reload
''';
    final syncResult = await _exec(syncScript);
    if (!syncResult.ok) {
      throw VpsSetupException('sync', 'Failed to sync service configuration: ${syncResult.stderr}');
    }
    yield const SetupProgress('sync', 'Service and permissions up to date.', stageComplete: true);

    yield const SetupProgress('restart', 'Restarting the archangel service...');
    final restartResult = await _exec('sudo systemctl restart archangel');
    if (!restartResult.ok) {
      await _rollbackBinary();
      throw VpsSetupException(
        'restart',
        'Failed to restart the service after updating - rolled back to the previous binary: ${restartResult.stderr}',
      );
    }

    String? liveVersion;
    for (var attempt = 0; attempt < 10; attempt++) {
      await Future.delayed(pollInterval);
      liveVersion = await fetchLiveVersion();
      if (liveVersion == targetVersion) break;
    }

    if (liveVersion != targetVersion) {
      yield SetupProgress(
        'restart',
        'New version did not come up correctly (saw "${liveVersion ?? 'no response'}") - rolling back...',
      );
      await _rollbackBinary();
      throw VpsSetupException(
        'restart',
        'archangeld v$targetVersion failed its post-update health check (reported "${liveVersion ?? 'nothing'}") '
            '- rolled back to the previous binary and restarted it.',
      );
    }

    yield SetupProgress('restart', 'archangeld v$targetVersion is running.', stageComplete: true);
  }

  /// Synchronizes the latest systemd service unit, sudoers permissions,
  /// and home directory without needing to download a new binary.
  Stream<SetupProgress> syncServiceAndPermissions() async* {
    yield const SetupProgress('upload', 'Uploading service definition and assets...');
    await _uploadScripts();
    yield const SetupProgress('upload', 'Assets uploaded.', stageComplete: true);

    yield const SetupProgress('sync', 'Applying service configuration and sudo permissions...');
    final syncScript = '''
set -e
sudo id -u archangel >/dev/null 2>&1 || sudo useradd --system --create-home --home-dir /home/archangel --shell /bin/bash archangel
sudo mkdir -p /home/archangel /opt/archangel /etc/archangel
sudo chown -R archangel:archangel /home/archangel
sudo usermod -d /home/archangel -s /bin/bash archangel || true
$_sudoersRefreshScript
$_serverPrereqsScript
sudo cp -f $_remoteScriptDir/archangel.service /etc/systemd/system/archangel.service

# If config.yaml has empty files_root, update it to /home/archangel
if [ -f /etc/archangel/config.yaml ]; then
  if grep -q 'files_root: ""' /etc/archangel/config.yaml || grep -q "files_root: ''" /etc/archangel/config.yaml; then
    sudo sed -i 's|files_root: .*|files_root: "/home/archangel"|' /etc/archangel/config.yaml
  fi
fi

sudo systemctl daemon-reload
sudo systemctl restart archangel
''';
    final syncResult = await _exec(syncScript);
    if (!syncResult.ok) {
      throw VpsSetupException('sync', 'Failed to update service and permissions: ${syncResult.stderr}');
    }
    yield const SetupProgress('sync', 'Service unit and permissions updated.', stageComplete: true);
  }

  /// Turns Admin mode (the archangel user's passwordless sudo) back on.
  /// Admin mode can be switched off from the app, but never on - granting
  /// root needs SSH access, which is what makes this a stream over an
  /// [SshTransport] rather than an API call. The grant is validated with
  /// `visudo` and removed again if it doesn't parse, so a bad write can
  /// never leave sudo broken.
  Stream<SetupProgress> enableAdminMode() async* {
    yield const SetupProgress('admin', 'Granting the archangel user sudo access...');
    final result = await _exec('''
set -e
$_sudoersGrantScript
if ! sudo visudo -cf /etc/sudoers.d/archangel; then
  sudo rm -f /etc/sudoers.d/archangel
  echo "sudoers validation failed - grant removed" >&2
  exit 1
fi
''');
    if (!result.ok) {
      throw VpsSetupException('admin', 'Failed to enable Admin mode: ${result.stderr.isNotEmpty ? result.stderr : result.stdout}');
    }
    yield const SetupProgress('admin', 'Admin mode is on.', stageComplete: true);
  }

  Future<void> _rollbackBinary() async {
    await _exec('sudo mv -f /opt/archangel/archangeld.bak /opt/archangel/archangeld && sudo systemctl restart archangel');
  }

  /// Reverses [run]: stops and removes archangeld (service, binary,
  /// config, token store) and tears down WireGuard (interface, config,
  /// keys, firewall port) - see infra/scripts/uninstall.sh, uploaded and
  /// run the same way every other script in this class is. One-way by
  /// design (no backup/rollback, unlike [updateBackend]) - the caller is
  /// expected to have already gotten explicit confirmation before calling
  /// this. Does not touch this device's local pairing state; that's the
  /// caller's responsibility once this stream completes, since the
  /// server this device was paired to no longer exists.
  Stream<SetupProgress> uninstall({required int appPort, required int wgPort}) async* {
    yield const SetupProgress('upload', 'Uploading the uninstall script...');
    await _uploadScripts();
    yield const SetupProgress('upload', 'Script uploaded.', stageComplete: true);

    yield const SetupProgress('remove', 'Stopping archangeld and WireGuard, and removing them from this server...');
    final result = await _exec('bash $_remoteScriptDir/uninstall.sh $appPort $wgPort');
    if (!result.ok) {
      throw VpsSetupException(
        'remove',
        'exit ${result.exitCode}: ${result.stderr.isNotEmpty ? result.stderr : result.stdout}',
      );
    }
    yield const SetupProgress('remove', 'archangeld and WireGuard removed.', stageComplete: true);
  }

  Future<SshExecResult> _exec(String command) => _ssh.exec(command);
}

String _shellQuote(String s) => "'${s.replaceAll("'", "'\\''")}'";
