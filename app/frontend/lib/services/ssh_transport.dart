import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import 'known_hosts.dart';

/// Called when a host's SSH key is either seen for the first time, or
/// doesn't match a previously trusted fingerprint for that host. Return
/// true to trust it (and, for a first-time host, remember it for next
/// time) or false to abort the connection. [isMismatch] distinguishes
/// "never seen this host before" from "this host's key changed since we
/// last trusted it" - callers should render the latter as a much
/// stronger warning, since it's the one that actually indicates a
/// possible attacker rather than routine first use.
typedef HostKeyPrompt =
    Future<bool> Function({required String host, required String keyType, required String fingerprint, required bool isMismatch});

/// The trust-on-first-use decision itself, factored out of
/// [Dartssh2Transport.connect]'s `SSHClient` wiring so it can be unit-
/// tested without a real SSH connection (dartssh2 gives no seam to fake
/// the handshake itself). See [HostKeyPrompt]'s doc comment for what
/// each case means.
Future<bool> resolveHostKeyTrust({
  required KnownHosts knownHosts,
  required String host,
  required String keyType,
  required String fingerprint,
  required HostKeyPrompt onUnknownHostKey,
}) async {
  final trusted = await knownHosts.get(host);
  if (trusted == fingerprint) return true;

  final accepted = await onUnknownHostKey(host: host, keyType: keyType, fingerprint: fingerprint, isMismatch: trusted != null);
  if (accepted) {
    await knownHosts.trust(host, fingerprint);
  }
  return accepted;
}

/// Result of one remote command execution.
class SshExecResult {
  final int exitCode;
  final String stdout;
  final String stderr;

  const SshExecResult({required this.exitCode, required this.stdout, required this.stderr});

  bool get ok => exitCode == 0;
}

/// Thin seam between [VpsSetupService]'s step sequencing/idempotency logic
/// and the actual SSH transport. Exists so that logic can be unit-tested
/// with a fake instead of a real network connection - this sandbox (and
/// most CI) has no real VPS to SSH into.
abstract class SshTransport {
  Future<SshExecResult> exec(String command);

  /// Uploads [content] to [remotePath] via SFTP, then `chmod`s it via a
  /// plain exec rather than SFTP's own attribute-setting API - simpler and
  /// avoids needing to construct SFTP file-mode bitmasks correctly.
  Future<void> uploadFile(String remotePath, Uint8List content, {String? chmod});

  Future<void> close();
}

/// Real implementation, backed by package:dartssh2.
class Dartssh2Transport implements SshTransport {
  final SSHClient _client;

  Dartssh2Transport._(this._client);

  /// Connects and authenticates with a pasted PEM private key.
  ///
  /// Host key verification uses trust-on-first-use (TOFU, the same model
  /// OpenSSH's own known_hosts uses): the first connection to [host] asks
  /// [onUnknownHostKey] to confirm the key and remembers its fingerprint
  /// via [KnownHosts]; every later connection compares against that
  /// stored fingerprint and calls [onUnknownHostKey] again with
  /// `isMismatch: true` if it's changed - which the caller must never
  /// auto-accept, since it's the one case that actually looks like an
  /// attacker rather than routine first use.
  static Future<Dartssh2Transport> connect({
    required String host,
    required int port,
    required String username,
    required String privateKeyPem,
    required HostKeyPrompt onUnknownHostKey,
    String? passphrase,
  }) async {
    final knownHosts = KnownHosts();
    final socket = await SSHSocket.connect(host, port, timeout: const Duration(seconds: 15));
    final client = SSHClient(
      socket,
      username: username,
      identities: SSHKeyPair.fromPem(privateKeyPem, passphrase),
      onVerifyHostKey: (type, fingerprintBytes) => resolveHostKeyTrust(
        knownHosts: knownHosts,
        host: host,
        keyType: type,
        fingerprint: utf8.decode(fingerprintBytes),
        onUnknownHostKey: onUnknownHostKey,
      ),
    );
    await client.authenticated;
    return Dartssh2Transport._(client);
  }

  @override
  Future<SshExecResult> exec(String command) async {
    final session = await _client.execute(command);
    final stdoutFuture = utf8.decoder.bind(session.stdout).join();
    final stderrFuture = utf8.decoder.bind(session.stderr).join();
    final stdout = await stdoutFuture;
    final stderr = await stderrFuture;
    final exitCode = await session.waitForExit(timeout: const Duration(minutes: 10)) ?? -1;
    return SshExecResult(exitCode: exitCode, stdout: stdout, stderr: stderr);
  }

  @override
  Future<void> uploadFile(String remotePath, Uint8List content, {String? chmod}) async {
    final sftp = await _client.sftp();
    final file = await sftp.open(remotePath, mode: SftpFileOpenMode.create | SftpFileOpenMode.write | SftpFileOpenMode.truncate);
    await file.writeBytes(content);
    await file.close();
    if (chmod != null) {
      final result = await exec('chmod $chmod ${_shellQuote(remotePath)}');
      if (!result.ok) {
        throw SshTransportException('chmod $chmod on $remotePath failed: ${result.stderr}');
      }
    }
  }

  @override
  Future<void> close() async {
    _client.close();
  }
}

String _shellQuote(String s) => "'${s.replaceAll("'", "'\\''")}'";

class SshTransportException implements Exception {
  final String message;
  const SshTransportException(this.message);
  @override
  String toString() => message;
}
