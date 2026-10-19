import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:archangel/services/known_hosts.dart';
import 'test_utils.dart';
import 'package:archangel/services/ssh_transport.dart';

/// KnownHosts is backed by flutter_secure_storage, whose platform channel
/// has no implementation in a bare test environment (no real
/// Keychain/Keystore to call into) - fake it in-memory so these tests
/// exercise resolveHostKeyTrust's real logic against a real KnownHosts
/// instance rather than a hand-rolled substitute.
void _fakeSecureStorage() {
  final store = <String, String>{};
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
    switch (call.method) {
      case 'read':
        return store[call.arguments['key']];
      case 'write':
        store[call.arguments['key'] as String] = call.arguments['value'] as String;
        return null;
      case 'delete':
        store.remove(call.arguments['key']);
        return null;
      case 'containsKey':
        return store.containsKey(call.arguments['key']);
      default:
        return null;
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _fakeSecureStorage();
  setUp(useTempKvStore);

  group('resolveHostKeyTrust', () {
    test('trusts a first-time host only after the prompt accepts, and remembers it', () async {
      final knownHosts = KnownHosts();
      var promptCalls = 0;

      final accepted = await resolveHostKeyTrust(
        knownHosts: knownHosts,
        host: 'first-time.example',
        keyType: 'ssh-ed25519',
        fingerprint: 'SHA256:abc123',
        onUnknownHostKey: ({required host, required keyType, required fingerprint, required isMismatch}) async {
          promptCalls++;
          expect(isMismatch, isFalse, reason: 'a host never seen before is not a mismatch');
          return true;
        },
      );

      expect(accepted, isTrue);
      expect(promptCalls, 1);
      expect(await knownHosts.get('first-time.example'), 'SHA256:abc123');
    });

    test('does not remember a first-time host that the prompt rejects', () async {
      final knownHosts = KnownHosts();

      final accepted = await resolveHostKeyTrust(
        knownHosts: knownHosts,
        host: 'rejected.example',
        keyType: 'ssh-ed25519',
        fingerprint: 'SHA256:abc123',
        onUnknownHostKey: ({required host, required keyType, required fingerprint, required isMismatch}) async => false,
      );

      expect(accepted, isFalse);
      expect(await knownHosts.get('rejected.example'), isNull);
    });

    test('auto-accepts a matching fingerprint on a known host without prompting', () async {
      final knownHosts = KnownHosts();
      await knownHosts.trust('known.example', 'SHA256:same');
      var promptCalls = 0;

      final accepted = await resolveHostKeyTrust(
        knownHosts: knownHosts,
        host: 'known.example',
        keyType: 'ssh-ed25519',
        fingerprint: 'SHA256:same',
        onUnknownHostKey: ({required host, required keyType, required fingerprint, required isMismatch}) async {
          promptCalls++;
          return true;
        },
      );

      expect(accepted, isTrue);
      expect(promptCalls, 0, reason: 'a matching fingerprint must never re-prompt');
    });

    test('flags a changed fingerprint as a mismatch and never auto-accepts it', () async {
      final knownHosts = KnownHosts();
      await knownHosts.trust('changed.example', 'SHA256:old');
      bool? sawMismatch;

      final accepted = await resolveHostKeyTrust(
        knownHosts: knownHosts,
        host: 'changed.example',
        keyType: 'ssh-ed25519',
        fingerprint: 'SHA256:new',
        onUnknownHostKey: ({required host, required keyType, required fingerprint, required isMismatch}) async {
          sawMismatch = isMismatch;
          return false; // the caller (real UI) must default to safe/reject
        },
      );

      expect(sawMismatch, isTrue);
      expect(accepted, isFalse);
      // The old, still-trusted fingerprint must survive a rejected mismatch.
      expect(await knownHosts.get('changed.example'), 'SHA256:old');
    });
  });
}
