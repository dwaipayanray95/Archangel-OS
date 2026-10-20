import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

/// Passphrase-derived encryption for data that shouldn't depend on the OS
/// Keychain/Credential Manager at all - used for the saved SSH private
/// key (see ssh_credentials.dart) instead of flutter_secure_storage.
///
/// Why: flutter_secure_storage on macOS is a thin wrapper over Keychain
/// Services, which gates every read/write behind the app's code-signing
/// identity via the Keychain Sharing entitlement. Without a stable
/// entitlement (which requires Xcode to set up), every dev rebuild gets
/// re-signed differently and macOS treats it as a new app, re-prompting
/// for Keychain access on every field. Deriving our own key from a passphrase
/// the user chooses sidesteps that dependency entirely, works
/// identically on every platform (no OS-specific secure-storage backend
/// to get right), and - unlike a hardcoded/app-embedded key, which would
/// just be obfuscation - is real encryption: the ciphertext is
/// unrecoverable without a passphrase only the user knows, which also means
/// it scales to multiple users of the same install, each with their own.
///
/// The passphrase itself is never stored anywhere - only its effect (the
/// derived key) is, transiently, in memory for as long as it takes to
/// encrypt/decrypt.
class WrongPassphraseException implements Exception {
  const WrongPassphraseException();
  @override
  String toString() => 'Incorrect passphrase, or the saved data is corrupted.';
}

/// Minimum length enforced by the passphrase prompts.
const kMinPassphraseLength = 8;

class _Envelope {
  final Uint8List salt;
  final Uint8List nonce;
  final Uint8List cipherText;
  final Uint8List mac;

  /// PBKDF2 iteration count the key was derived with. Envelopes written
  /// before this field existed used [_legacyPbkdf2Iterations].
  final int iterations;
  const _Envelope({required this.salt, required this.nonce, required this.cipherText, required this.mac, required this.iterations});

  Uint8List encode() {
    final map = {
      'salt': base64Encode(salt),
      'nonce': base64Encode(nonce),
      'cipherText': base64Encode(cipherText),
      'mac': base64Encode(mac),
      'iterations': iterations,
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(map)));
  }

  static _Envelope decode(Uint8List bytes) {
    final map = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    return _Envelope(
      salt: base64Decode(map['salt'] as String),
      nonce: base64Decode(map['nonce'] as String),
      cipherText: base64Decode(map['cipherText'] as String),
      mac: base64Decode(map['mac'] as String),
      iterations: _checkedIterations((map['iterations'] as num?)?.toInt() ?? _legacyPbkdf2Iterations),
    );
  }

  /// A damaged or tampered file could claim an absurd iteration count and
  /// hang the app deriving a key - treat that as an unreadable envelope.
  static int _checkedIterations(int n) {
    if (n < 1 || n > 10000000) throw const FormatException('implausible PBKDF2 iteration count');
    return n;
  }
}

/// Iteration count for newly written envelopes.
const _pbkdf2Iterations = 600000;

/// What envelopes without an `iterations` field were written with.
const _legacyPbkdf2Iterations = 200000;
const _keyBits = 256;

/// Tests only: lowers the iteration count used for NEW encryptions so they
/// run fast. Decryption always honours the count stored in the envelope.
@visibleForTesting
int? pbkdf2IterationsOverride;

final _aesGcm = AesGcm.with256bits();

Future<SecretKey> _deriveKey(String passphrase, List<int> salt, int iterations) {
  final pbkdf2 = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iterations, bits: _keyBits);
  return pbkdf2.deriveKey(secretKey: SecretKey(utf8.encode(passphrase)), nonce: salt);
}

/// Encrypts [plaintextJson] (any JSON-encodable map) under a key derived
/// from [passphrase], returning the bytes to write to disk. A fresh random salt
/// and nonce are generated every call - safe to call repeatedly with the
/// same passphrase.
Future<Uint8List> encryptJson(String passphrase, Map<String, dynamic> plaintextJson) async {
  final iterations = pbkdf2IterationsOverride ?? _pbkdf2Iterations;
  final salt = Uint8List.fromList(List<int>.generate(16, (_) => Random.secure().nextInt(256)));
  final secretKey = await _deriveKey(passphrase, salt, iterations);
  final plaintext = utf8.encode(jsonEncode(plaintextJson));
  final box = await _aesGcm.encrypt(plaintext, secretKey: secretKey);
  return _Envelope(
    salt: salt,
    nonce: Uint8List.fromList(box.nonce),
    cipherText: Uint8List.fromList(box.cipherText),
    mac: Uint8List.fromList(box.mac.bytes),
    iterations: iterations,
  ).encode();
}

/// Reverses [encryptJson]. Throws [WrongPassphraseException] if [passphrase] is wrong
/// or [envelopeBytes] has been tampered with/corrupted - AES-GCM's
/// authentication tag makes the two indistinguishable, which is
/// intentional (don't leak which one it was).
Future<Map<String, dynamic>> decryptJson(String passphrase, Uint8List envelopeBytes) async {
  try {
    final envelope = _Envelope.decode(envelopeBytes);
    final secretKey = await _deriveKey(passphrase, envelope.salt, envelope.iterations);
    final box = SecretBox(envelope.cipherText, nonce: envelope.nonce, mac: Mac(envelope.mac));
    final plaintext = await _aesGcm.decrypt(box, secretKey: secretKey);
    return jsonDecode(utf8.decode(plaintext)) as Map<String, dynamic>;
  } catch (_) {
    throw const WrongPassphraseException();
  }
}
