import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archangel/services/credential_crypto.dart';
import 'package:archangel/services/ssh_credentials.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const passphrase = 'correct horse battery';
  const payload = {'host': '203.0.113.5', 'username': 'ubuntu', 'privateKeyPem': 'KEY'};

  setUp(() => pbkdf2IterationsOverride = 1000); // fast; production uses 600000
  tearDown(() => pbkdf2IterationsOverride = null);

  group('credential_crypto', () {
    test('round trips and records the iteration count in the envelope', () async {
      final bytes = await encryptJson(passphrase, payload);
      expect(jsonDecode(utf8.decode(bytes))['iterations'], 1000);
      expect(await decryptJson(passphrase, bytes), payload);
    });

    test('new encryptions default to 600000 iterations', () async {
      pbkdf2IterationsOverride = null;
      // Don't derive a key at full cost twice: just check what gets written.
      final bytes = await encryptJson(passphrase, payload);
      expect(jsonDecode(utf8.decode(bytes))['iterations'], 600000);
      expect(await decryptJson(passphrase, bytes), payload);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('an old envelope without "iterations" still decrypts (200000)', () async {
      pbkdf2IterationsOverride = 200000;
      final modern = await encryptJson(passphrase, payload);
      final map = jsonDecode(utf8.decode(modern)) as Map<String, dynamic>..remove('iterations');
      final legacy = Uint8List.fromList(utf8.encode(jsonEncode(map)));

      expect(await decryptJson(passphrase, legacy), payload);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('decrypt honours the stored count, not the current override', () async {
      final bytes = await encryptJson(passphrase, payload);
      pbkdf2IterationsOverride = 5;
      expect(await decryptJson(passphrase, bytes), payload);
    });

    test('wrong passphrase throws', () async {
      final bytes = await encryptJson(passphrase, payload);
      await expectLater(decryptJson('not the passphrase', bytes), throwsA(isA<WrongPassphraseException>()));
    });

    test('corrupted data throws the same error', () async {
      await expectLater(decryptJson(passphrase, Uint8List.fromList([1, 2, 3])), throwsA(isA<WrongPassphraseException>()));
    });
  });

  group('changeSshCredentialsPassphrase', () {
    late Directory dir;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('archangel_creds_test');
      sshCredentialsDirectoryOverride = () async => dir;
    });
    tearDown(() {
      sshCredentialsDirectoryOverride = null;
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    const creds = SavedSshCredentials(host: 'h', username: 'u', privateKeyPem: 'PEM');

    test('re-encrypts under the new passphrase; the old one then fails', () async {
      await saveSshCredentials(passphrase, creds);
      await changeSshCredentialsPassphrase(passphrase, 'a brand new passphrase');

      final loaded = await loadSavedSshCredentials('a brand new passphrase');
      expect(loaded?.privateKeyPem, 'PEM');
      await expectLater(loadSavedSshCredentials(passphrase), throwsA(isA<WrongPassphraseException>()));
    });

    test('a wrong current passphrase leaves the saved file untouched', () async {
      await saveSshCredentials(passphrase, creds);
      await expectLater(changeSshCredentialsPassphrase('wrong wrong', 'another passphrase'), throwsA(isA<WrongPassphraseException>()));
      expect((await loadSavedSshCredentials(passphrase))?.host, 'h');
    });

    test('throws when nothing is saved', () async {
      await clearSavedSshCredentials();
      await expectLater(changeSshCredentialsPassphrase(passphrase, 'another passphrase'), throwsA(isA<StateError>()));
    });
  });
}
