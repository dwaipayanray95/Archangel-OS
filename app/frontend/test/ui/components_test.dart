import 'dart:ui' show SemanticsFlag;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:archangel/ui/ui.dart';

Widget _host(Widget child, {Brightness brightness = Brightness.dark, TargetPlatform? platform}) {
  final theme = buildTheme(brightness);
  return MaterialApp(
    theme: platform == null ? theme : theme.copyWith(platform: platform),
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  group('ConfirmDialog', () {
    Future<bool?> open(WidgetTester tester, {String? typeToConfirm, bool danger = true}) async {
      bool? result;
      await tester.pumpWidget(_host(Builder(
        builder: (context) => AxButton(
          label: 'Open',
          onPressed: () async {
            result = await showConfirmDialog(
              context,
              title: 'Remove web-app?',
              message: 'The app and its data on the server will be deleted. This cannot be undone.',
              confirmLabel: 'Remove',
              danger: danger,
              typeToConfirm: typeToConfirm,
            );
          },
        ),
      )));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      return result;
    }

    FilledButton confirmButton(WidgetTester tester) =>
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Remove'));

    testWidgets('shows title and consequence; confirm returns true', (tester) async {
      bool? result;
      await tester.pumpWidget(_host(Builder(
        builder: (context) => AxButton(
          label: 'Open',
          onPressed: () async => result = await showConfirmDialog(context,
              title: 'Reboot?', message: 'Your server will be unavailable for a minute.', confirmLabel: 'Reboot'),
        ),
      )));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Reboot?'), findsOneWidget);
      expect(find.text('Your server will be unavailable for a minute.'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Reboot'));
      await tester.pumpAndSettle();
      expect(result, isTrue);
    });

    testWidgets('cancel returns false', (tester) async {
      bool? result;
      await tester.pumpWidget(_host(Builder(
        builder: (context) => AxButton(
          label: 'Open',
          onPressed: () async => result = await showConfirmDialog(context, title: 'Stop?', message: 'm', confirmLabel: 'Stop'),
        ),
      )));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(result, isFalse);
    });

    testWidgets('type-to-confirm keeps the button disabled until the text matches', (tester) async {
      await open(tester, typeToConfirm: 'web-app');
      expect(confirmButton(tester).onPressed, isNull);

      await tester.enterText(find.byType(TextField), 'web');
      await tester.pump();
      expect(confirmButton(tester).onPressed, isNull);

      await tester.enterText(find.byType(TextField), 'web-app');
      await tester.pump();
      expect(confirmButton(tester).onPressed, isNotNull);

      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      await tester.pumpAndSettle();
      expect(find.text('Remove web-app?'), findsNothing);
    });

    testWidgets('without typeToConfirm there is no text field and confirm is enabled', (tester) async {
      await open(tester);
      expect(find.byType(TextField), findsNothing);
      expect(confirmButton(tester).onPressed, isNotNull);
    });
  });

  group('LoadingState', () {
    testWidgets('shows the message, then an actionable still-waiting message after the delay', (tester) async {
      var retried = 0;
      await tester.pumpWidget(_host(LoadingState(
        message: 'Loading apps...',
        stillWaitingAfter: const Duration(milliseconds: 500),
        onRetry: () => retried++,
      )));
      expect(find.text('Loading apps...'), findsOneWidget);
      expect(find.text('Still waiting...'), findsNothing);

      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Still waiting...'), findsOneWidget);
      expect(find.textContaining('server may be offline'), findsOneWidget);
      expect(find.text('Loading apps...'), findsNothing);

      await tester.tap(find.text('Try again'));
      expect(retried, 1);
    });

    testWidgets('defaults to 10 seconds', (tester) async {
      await tester.pumpWidget(_host(const LoadingState()));
      await tester.pump(const Duration(seconds: 9));
      expect(find.text('Still waiting...'), findsNothing);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Still waiting...'), findsOneWidget);
    });

    testWidgets('disposing before the delay leaves no pending timer', (tester) async {
      await tester.pumpWidget(_host(const LoadingState()));
      await tester.pumpWidget(_host(const SizedBox()));
      // Fails the test on teardown if a timer is still pending.
    });
  });

  group('StatusBadge', () {
    testWidgets('always shows text and an icon, for every status', (tester) async {
      await tester.pumpWidget(_host(const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          StatusBadge.ok('Running'),
          StatusBadge.warning('Disk almost full'),
          StatusBadge.error('Stopped'),
          StatusBadge.info('Update available'),
          StatusBadge.neutral('Unknown'),
        ],
      )));
      for (final t in ['Running', 'Disk almost full', 'Stopped', 'Update available', 'Unknown']) {
        expect(find.text(t), findsOneWidget);
      }
      expect(find.byType(Icon), findsNWidgets(5));
    });

    testWidgets('exposes its label to screen readers', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_host(const StatusBadge.error('Stopped')));
      expect(find.bySemanticsLabel('Stopped'), findsOneWidget);
      handle.dispose();
    });
  });

  group('touch targets and semantics', () {
    testWidgets('AxButton and AxIconButton are >= 48dp on Android and >= 36dp on desktop', (tester) async {
      Future<void> check(TargetPlatform p, double min) async {
        await tester.pumpWidget(_host(
          Column(mainAxisSize: MainAxisSize.min, children: [
            AxButton(label: 'Go', onPressed: () {}),
            AxIconButton(icon: Icons.refresh, tooltip: 'Refresh', onPressed: () {}),
          ]),
          platform: p,
        ));
        await tester.pump();
        final button = tester.getSize(find.byType(FilledButton));
        final icon = tester.getSize(find.byType(IconButton));
        expect(button.height, greaterThanOrEqualTo(min));
        expect(button.width, greaterThanOrEqualTo(min));
        expect(icon.height, greaterThanOrEqualTo(min));
        expect(icon.width, greaterThanOrEqualTo(min));
      }

      await check(TargetPlatform.android, 48);
      await check(TargetPlatform.linux, 36);
    });

    testWidgets('AxIconButton tooltip is its accessible name', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_host(AxIconButton(icon: Icons.refresh, tooltip: 'Refresh list', onPressed: () {})));
      final node = tester.getSemantics(find.byType(IconButton));
      expect('${node.label} ${node.tooltip}', contains('Refresh list'));
      handle.dispose();
    });

    testWidgets('AxButton announces its label and disabled state', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_host(const AxButton(label: 'Save', onPressed: null)));
      final node = tester.getSemantics(find.bySemanticsLabel('Save'));
      // ignore: deprecated_member_use
      expect(node.hasFlag(SemanticsFlag.isButton), isTrue);
      handle.dispose();
    });

    testWidgets('AxListTile is at least one touch target tall and taps', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_host(
        AxListTile(title: 'Settings', subtitle: 'Everything', onTap: () => taps++),
        platform: TargetPlatform.android,
      ));
      expect(tester.getSize(find.byType(ListTile)).height, greaterThanOrEqualTo(48));
      await tester.tap(find.text('Settings'));
      expect(taps, 1);
    });
  });

  group('state views', () {
    testWidgets('ErrorState offers Retry and an optional explanation', (tester) async {
      var retried = 0;
      await tester.pumpWidget(_host(ErrorState(
        message: 'We could not reach your server.',
        onRetry: () => retried++,
        helpText: 'The secure connection to your server is probably off.',
      )));
      expect(find.text('We could not reach your server.'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      expect(retried, 1);
      await tester.tap(find.text('What does this mean?'));
      await tester.pumpAndSettle();
      expect(find.text('The secure connection to your server is probably off.'), findsOneWidget);
    });

    testWidgets('EmptyState shows its action', (tester) async {
      var tapped = false;
      await tester.pumpWidget(_host(EmptyState(
        title: 'No apps yet',
        message: 'Run your first app.',
        actionLabel: 'Run an app',
        onAction: () => tapped = true,
      )));
      await tester.tap(find.text('Run an app'));
      expect(tapped, isTrue);
    });

    testWidgets('HelpTip opens an explanation sheet', (tester) async {
      await tester.pumpWidget(_host(const HelpTip(title: 'Private key', message: 'Like a long password in a file.')));
      await tester.tap(find.byTooltip('What is Private key?'));
      await tester.pumpAndSettle();
      expect(find.text('Like a long password in a file.'), findsOneWidget);
    });

    testWidgets('AxPage renders title, subtitle and actions', (tester) async {
      await tester.pumpWidget(_host(AxPage(
        title: 'Apps',
        subtitle: 'What runs on your server',
        actions: [AxButton(label: 'Run an app', onPressed: () {})],
        child: const Text('body'),
      )));
      expect(find.text('Apps'), findsOneWidget);
      expect(find.text('What runs on your server'), findsOneWidget);
      expect(find.text('Run an app'), findsOneWidget);
      expect(find.text('body'), findsOneWidget);
    });
  });

  group('SshCredentialsForm', () {
    testWidgets('defaults the username to ubuntu and validates plain-language', (tester) async {
      final ctl = SshCredentialsController();
      addTearDown(ctl.dispose);
      await tester.pumpWidget(_host(SingleChildScrollView(child: SshCredentialsForm(controller: ctl, restoreSavedOnStart: false))));
      expect(ctl.usernameText, 'ubuntu');
      expect(ctl.validate(), contains('address'));
      ctl.host.text = '203.0.113.5';
      expect(ctl.validate(), contains('private key'));
      ctl.privateKey.text = '-----BEGIN OPENSSH PRIVATE KEY-----';
      expect(ctl.validate(), isNull);
      expect(ctl.validate(needHost: false), isNull);
    });

    testWidgets('shows the load-from-file button only when a picker is supplied and fills the key', (tester) async {
      final ctl = SshCredentialsController();
      addTearDown(ctl.dispose);
      await tester.pumpWidget(_host(SingleChildScrollView(child: SshCredentialsForm(controller: ctl, restoreSavedOnStart: false))));
      expect(find.text('Load from file'), findsNothing);

      await tester.pumpWidget(_host(SingleChildScrollView(
        child: SshCredentialsForm(controller: ctl, restoreSavedOnStart: false, onPickKeyFile: () async => '  KEYDATA \n'),
      )));
      await tester.tap(find.text('Load from file'));
      await tester.pump();
      expect(ctl.privateKeyText, 'KEYDATA');
    });

    testWidgets('remember switch and error text', (tester) async {
      final ctl = SshCredentialsController();
      addTearDown(ctl.dispose);
      await tester.pumpWidget(_host(SingleChildScrollView(
        child: SshCredentialsForm(controller: ctl, restoreSavedOnStart: false, errorText: 'Could not connect'),
      )));
      expect(find.text('Could not connect'), findsOneWidget);
      expect(ctl.rememberKey, isFalse);
      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(ctl.rememberKey, isTrue);
    });

    testWidgets('can hide host, key passphrase and remember switch', (tester) async {
      final ctl = SshCredentialsController();
      addTearDown(ctl.dispose);
      await tester.pumpWidget(_host(SingleChildScrollView(
        child: SshCredentialsForm(
          controller: ctl,
          restoreSavedOnStart: false,
          showHost: false,
          showKeyPassphrase: false,
          showRememberKey: false,
        ),
      )));
      expect(find.text('Server address'), findsNothing);
      expect(find.byType(Switch), findsNothing);
      expect(find.byType(TextField), findsNWidgets(2)); // username + key
    });

    testWidgets('restoring with nothing saved leaves the form as it was and does not throw', (tester) async {
      final ctl = SshCredentialsController();
      addTearDown(ctl.dispose);
      await tester.pumpWidget(_host(SingleChildScrollView(child: SshCredentialsForm(controller: ctl))));
      await tester.pump();
      // The restore does real file IO (which fails here: no path_provider
      // plugin under flutter test); let it finish outside fake async.
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(ctl.restoring, isFalse);
      expect(ctl.hostText, isEmpty);
    });
  });
}
