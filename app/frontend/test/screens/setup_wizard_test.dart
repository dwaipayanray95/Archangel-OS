import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:archangel/screens/setup/setup_landing_screen.dart';
import 'package:archangel/screens/setup/setup_wizard_screen.dart';
import 'package:archangel/ui/screens/setup/setup_hints.dart';
import 'package:archangel/ui/theme.dart';


Future<void> _pump(WidgetTester tester, Widget home, {Brightness brightness = Brightness.dark, Size size = const Size(400, 900)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(MaterialApp(theme: buildTheme(brightness), home: home));
  await tester.pump(const Duration(milliseconds: 100));
}

bool _nextEnabled(WidgetTester tester) {
  final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Next'));
  return button.onPressed != null;
}

void main() {
  group('landing', () {
    for (final b in Brightness.values) {
      testWidgets('shows the three options (${b.name})', (tester) async {
        await _pump(tester, const SetupLandingScreen(), brightness: b);
        expect(find.text('Do you have a server?'), findsOneWidget);
        expect(find.text('Yes, set it up for me'), findsOneWidget);
        expect(find.text('I have a pairing code'), findsOneWidget);
        expect(find.textContaining('Not yet'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('"Not yet" opens the guide screen', (tester) async {
      await _pump(tester, const SetupLandingScreen());
      await tester.tap(find.textContaining('Not yet'));
      await tester.pumpAndSettle();
      expect(find.text('What is a server?'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Hetzner'), 200);
      expect(find.text('Oracle Cloud Always Free'), findsOneWidget);
      expect(find.text('Open guide'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  group('wizard', () {
    testWidgets('Next is disabled until required fields are valid; Back keeps values', (tester) async {
      await _pump(tester, const SetupWizardScreen(restoreSavedKey: false));
      expect(find.textContaining('Step 1 of 6'), findsOneWidget);
      expect(_nextEnabled(tester), isFalse);

      // Username defaults to "ubuntu"; the address is still empty.
      await tester.enterText(find.widgetWithText(TextField, 'Server address'), '203.0.113.5');
      await tester.pump();
      expect(_nextEnabled(tester), isTrue);

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Step 2 of 6'), findsOneWidget);
      expect(find.text('How do I get an SSH key?'), findsOneWidget);
      expect(_nextEnabled(tester), isFalse);

      await tester.enterText(find.widgetWithText(TextField, 'Private key'), '-----BEGIN OPENSSH PRIVATE KEY-----\nabc');
      await tester.pump();
      expect(_nextEnabled(tester), isTrue);

      // Back to step 1: values are still there.
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Step 1 of 6'), findsOneWidget);
      expect(find.text('203.0.113.5'), findsWidgets);

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('-----BEGIN OPENSSH PRIVATE KEY-----\nabc'), findsOneWidget);

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Step 3 of 6'), findsOneWidget);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Here\'s what will happen'), findsOneWidget);
      expect(find.text('Start setup'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('invalid advanced values disable Next', (tester) async {
      await _pump(tester, const SetupWizardScreen(restoreSavedKey: false));
      await tester.enterText(find.widgetWithText(TextField, 'Server address'), 'example.com');
      await tester.pump();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Private key'), 'PRIVATE KEY');
      await tester.pump();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Advanced'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Private network (first three numbers)'), 'nope');
      await tester.pump();
      expect(_nextEnabled(tester), isFalse);
      expect(find.textContaining('three numbers'), findsWidgets);
    });
  });

  group('hintForSetupError', () {
    test('auth failures', () {
      for (final e in ['SSHAuthFailError: All authentication methods failed', 'Permission denied (publickey)']) {
        final h = hintForSetupError(e);
        expect(h, contains('refused your key'));
        expect(h, contains('opc'));
      }
    });
    test('connection problems', () {
      for (final e in ['SocketException: Connection refused', 'TimeoutException after 0:00:10', 'No route to host']) {
        expect(hintForSetupError(e), contains('port 22'));
      }
    });
    test('tunnel step mentions UDP 51820', () {
      final h = hintForSetupError('[wireguard] wg-quick failed');
      expect(h, contains('UDP port 51820'));
      expect(errorNeedsFirewallHelp('[wireguard] x'), isTrue);
      expect(errorNeedsFirewallHelp('[detect] Unsupported'), isFalse);
    });
    test('sudo, unsupported, key format and fallback', () {
      expect(hintForSetupError('sudo: a password is required'), contains('passwordless sudo'));
      expect(hintForSetupError('[detect] Unsupported server architecture "mips"'), contains('not supported'));
      expect(hintForSetupError('Failed to decrypt private key'), contains('passphrase'));
      final generic = hintForSetupError('???');
      expect(generic, isNotEmpty);
      expect(generic, contains('Technical details'));
    });
    test('stage labels', () {
      expect(setupStageLabel('verify'), setupStageLabel('binary'));
      expect(setupStageLabel('connect'), 'Connecting to your server');
    });
  });
}
