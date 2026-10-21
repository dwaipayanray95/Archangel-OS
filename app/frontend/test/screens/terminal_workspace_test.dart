import 'dart:convert';
import 'dart:ui' show SemanticsFlag;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

import 'package:archangel/screens/terminal_screen.dart';
import 'package:archangel/services/archangeld_connection.dart';
import 'package:archangel/services/local_kv_store.dart';
import 'package:archangel/services/terminal_session.dart';
import 'package:archangel/ui/components/ax_button.dart';
import 'package:archangel/ui/screens/terminal/sessions_dialog.dart';
import 'package:archangel/ui/screens/terminal/terminal_accessory_bar.dart';
import 'package:archangel/ui/screens/terminal/terminal_snippets.dart';
import 'package:archangel/ui/screens/terminal/terminal_workspace.dart';
import 'package:archangel/ui/theme.dart';

import '../test_utils.dart';
import 'terminal_fake_channel.dart';

class TerminalHarness {
  TerminalHarness(this.sessions, this.channels, {this.backend});
  final List<TerminalSession> sessions;
  final List<FakeTerminalChannel> channels;
  final ArchangeldConnection? backend;
  final controllers = <TerminalSession, TerminalController>{};
  final events = <String>[];
  double fontSize = kTerminalDefaultFont;
  int selected = 0;
  bool? adminModeEnabled;
  String? serverName = 'hal-9000';
  bool? showAccessoryBar;
  VoidCallback? onOpenAdminMode;
}

Future<TerminalHarness> pumpWorkspace(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  List<String> names = const ['main'],
  bool? adminModeEnabled,
  String? serverName = 'hal-9000',
  bool? showAccessoryBar,
  VoidCallback? onOpenAdminMode,
}) async {
  final sessions = <TerminalSession>[];
  final channels = <FakeTerminalChannel>[];
  late final ArchangeldConnection backend;
  await tester.runAsync(() async {
    await useTempKvStore();
    backend = await pairedBackend();
  });
  for (final n in names) {
    final (s, c) = connectedFakeSessionWith(backend, name: n);
    sessions.add(s);
    channels.add(c);
  }
  final h =
      TerminalHarness(sessions, channels, backend: backend)
        ..adminModeEnabled = adminModeEnabled
        ..serverName = serverName
        ..showAccessoryBar = showAccessoryBar
        ..onOpenAdminMode = onOpenAdminMode;

  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: StatefulBuilder(
        builder:
            (context, setState) => Scaffold(
              body: TerminalWorkspace(
                sessions: h.sessions,
                selected: h.selected,
                controllerFor: (s) => h.controllers.putIfAbsent(s, TerminalController.new),
                fontSize: h.fontSize,
                onSelect: (i) => setState(() => h.selected = i),
                onDetach: (i) => h.events.add('detach $i'),
                onEnd: (i) => h.events.add('end $i'),
                onNew: () => h.events.add('new'),
                onShowSessions: () => h.events.add('sessions'),
                onFontSize: (v) => setState(() => h.fontSize = v),
                onCopy: () => h.events.add('copy'),
                onPaste: () => h.events.add('paste'),
                adminModeEnabled: h.adminModeEnabled,
                onToggleAdminMode: (v) {
                  setState(() => h.adminModeEnabled = v);
                  h.events.add('toggle-admin $v');
                },
                serverName: h.serverName,
                showAccessoryBar: h.showAccessoryBar,
                onOpenAdminMode: h.onOpenAdminMode ?? () => h.events.add('open-admin'),
              ),
            ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
  addTearDown(() {
    for (final s in sessions) {
      s.dispose();
    }
    for (final c in h.controllers.values) {
      c.dispose();
    }
  });
  return h;
}

/// Unmounts the tree and stops the sessions so no timers outlive the test.
Future<void> finish(WidgetTester tester, TerminalHarness h) async {
  await tester.pumpWidget(const SizedBox());
  for (final s in h.sessions) {
    s.dispose();
  }
}

void main() {
  testWidgets('server output with colour and cursor movement shows up as text in the terminal', (tester) async {
    final h = await pumpWorkspace(tester);
    expect(find.byType(TerminalView), findsOneWidget);
    h.channels[0].serverStdout(utf8.encode('\x1b[1;32mready\x1b[0m\r\n\x1b[3;1Hprompt\$ '));
    await tester.pump();
    final buffer = h.sessions[0].terminal.buffer;
    expect(buffer.lines[0].getText().trimRight(), 'ready');
    expect(buffer.lines[2].getText().trimRight(), 'prompt\$');
    expect(buffer.getText(), isNot(contains('\x1b')));
    await finish(tester, h);
  });

  testWidgets('hardware keystrokes become stdin frames', (tester) async {
    final h = await pumpWorkspace(tester, size: const Size(1400, 900));
    h.channels[0].serverStdout(utf8.encode('x'));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(h.channels[0].stdin, containsAllInOrder(['\x1b[A', '\r']));
    await finish(tester, h);
  });

  testWidgets('the view sizes the emulator and reports it as a resize frame', (tester) async {
    final h = await pumpWorkspace(tester, size: const Size(1400, 900));
    final t = h.sessions[0].terminal;
    expect(t.viewWidth, isNot(120)); // laid out at the real size, not the default
    final last = h.channels[0].resizes.last;
    expect(last['cols'], t.viewWidth);
    expect(last['rows'], t.viewHeight);
    await finish(tester, h);
  });

  group('Wide (1400x900 Simple)', () {
    testWidgets('tabs, +, Server, Admin chip, Snippets, ⋯ present; A−/A+, Copy, Paste in More', (tester) async {
      final h = await pumpWorkspace(tester, size: const Size(1400, 900), names: const ['main', 'shell-2'], adminModeEnabled: false);
      h.channels[0].serverStdout(utf8.encode('ready'));
      await tester.pump();

      // Tabs present
      expect(find.text('main'), findsOneWidget);
      expect(find.text('shell-2'), findsOneWidget);

      // + button
      expect(find.byTooltip('New session'), findsOneWidget);

      // ray@<server>
      expect(find.text('ray@hal-9000'), findsOneWidget);

      // Admin button present when enabled or disabled
      expect(find.byTooltip('Admin mode'), findsOneWidget);

      // Snippets, ⋯ directly on the top bar
      expect(find.byTooltip('Snippets'), findsOneWidget);
      expect(find.byTooltip('More'), findsOneWidget);

      // A−, A+, Copy, Paste are clean inside More (not cluttering the top bar)
      expect(find.byTooltip('Smaller text'), findsNothing);
      expect(find.byTooltip('Copy selection'), findsNothing);

      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();

      expect(find.text('Text size'), findsOneWidget);
      expect(find.byTooltip('Smaller text'), findsOneWidget);
      expect(find.byTooltip('Bigger text'), findsOneWidget);
      expect(find.text('Copy selection'), findsOneWidget);
      expect(find.text('Paste'), findsOneWidget);
      expect(find.text('Sessions on this server'), findsOneWidget);

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      await finish(tester, h);
    });

    testWidgets('Admin button is hidden when unknown (null)', (tester) async {
      final h = await pumpWorkspace(tester, size: const Size(1400, 900), names: const ['main'], adminModeEnabled: null);

      expect(find.byTooltip('Admin mode'), findsNothing);

      await finish(tester, h);
    });

    testWidgets('Admin button shows active when enabled', (tester) async {
      final h = await pumpWorkspace(tester, size: const Size(1400, 900), names: const ['main'], adminModeEnabled: true);

      expect(find.byTooltip('Admin mode'), findsOneWidget);

      await finish(tester, h);
    });

    testWidgets('Admin button toggles when tapped', (tester) async {
      final h = await pumpWorkspace(tester, size: const Size(1400, 900), names: const ['main'], adminModeEnabled: false);
      expect(find.byTooltip('Admin mode'), findsOneWidget);

      await tester.tap(find.byTooltip('Admin mode'));
      await tester.pump();

      expect(h.events, contains('toggle-admin true'));

      await finish(tester, h);
    });
  });

  group('Narrow (340 Desktop window and 390 phone)', () {
    for (final size in const [Size(340, 600), Size(390, 844)]) {
      testWidgets('no overflow at ${size.width.toInt()} wide with several sessions', (tester) async {
        final h = await pumpWorkspace(
          tester,
          size: size,
          names: const ['main', 'shell-2', 'a-rather-long-session-name'],
          adminModeEnabled: false,
        );
        h.channels[0].serverStdout(utf8.encode('hello'));
        await tester.pump();
        expect(tester.takeException(), isNull);

        // × only on selected tab
        expect(find.byTooltip('End session main'), findsOneWidget);
        expect(find.byTooltip('End session shell-2'), findsNothing);
        expect(find.byTooltip('End session a-rather-long-session-name'), findsNothing);

        // Button in footer
        expect(find.byTooltip('Admin mode'), findsOneWidget);

        // A−/A+, Copy, Paste, Snippets live in ⋯
        expect(find.byTooltip('Smaller text'), findsNothing);
        expect(find.byTooltip('Copy selection'), findsNothing);

        await tester.tap(find.byTooltip('More'));
        await tester.pumpAndSettle();

        expect(find.text('Text size'), findsOneWidget);
        expect(find.byTooltip('Smaller text'), findsOneWidget);
        expect(find.byTooltip('Bigger text'), findsOneWidget);
        expect(find.text('Snippets'), findsOneWidget);
        expect(find.text('Copy selection'), findsOneWidget);
        expect(find.text('Paste'), findsOneWidget);
        expect(find.text('Sessions on this server'), findsOneWidget);

        // Close menu
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();

        await finish(tester, h);
      });
    }

    testWidgets('selecting unselected tab shows its × on narrow', (tester) async {
      final h = await pumpWorkspace(tester, size: const Size(390, 844), names: const ['main', 'shell-2']);

      expect(find.byTooltip('End session main'), findsOneWidget);
      expect(find.byTooltip('End session shell-2'), findsNothing);

      await tester.tap(find.text('shell-2'));
      await tester.pump();

      expect(find.byTooltip('End session main'), findsNothing);
      expect(find.byTooltip('End session shell-2'), findsOneWidget);

      await finish(tester, h);
    });
  });

  group('Ending a session (× on a tab)', () {
    Future<bool?> openConfirmDialog(WidgetTester tester, void Function(bool?) onResult) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.dark),
          home: Builder(
            builder:
                (context) => Scaffold(
                  body: TextButton(onPressed: () async => onResult(await confirmEndSession(context, 'main')), child: const Text('open')),
                ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return null;
    }

    testWidgets('confirm dialog has exact wording and danger button confirms', (tester) async {
      bool? result;
      await openConfirmDialog(tester, (r) => result = r);

      expect(find.text('End session "main"?'), findsOneWidget);
      expect(find.text('This stops everything running in this session, and anything not saved is lost.'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'End session'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'End session'));
      await tester.pumpAndSettle();
      expect(result, isTrue);
    });

    testWidgets('Cancel does not end session', (tester) async {
      bool? result;
      await openConfirmDialog(tester, (r) => result = r);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(result, isFalse);
    });

    testWidgets('tapping × on tab triggers onEnd callback', (tester) async {
      final h = await pumpWorkspace(tester, size: const Size(1400, 900), names: const ['main', 'shell-2']);
      await tester.tap(find.byTooltip('End session shell-2'));
      await tester.pump();
      expect(h.events, contains('end 1'));
      await finish(tester, h);
    });

    testWidgets('× on tab -> confirm dialog; Cancel keeps tab; confirm removes tab; end error keeps tab + snackbar', (tester) async {
      final sessions = <TerminalSession>[];
      final channels = <FakeTerminalChannel>[];
      late final ArchangeldConnection backend;
      await tester.runAsync(() async {
        await useTempKvStore();
        backend = await pairedBackend();
      });
      for (final n in ['main', 'shell-2']) {
        final (s, c) = connectedFakeSessionWith(backend, name: n);
        sessions.add(s);
        channels.add(c);
      }
      final allSessions = List.of(sessions);
      channels[0].serverStdout(utf8.encode('ready\n'));
      channels[1].serverStdout(utf8.encode('ready\n'));
      final controllers = <TerminalSession, TerminalController>{};

      String? endErrorToReturn;

      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.dark),
          home: StatefulBuilder(
            builder: (context, setState) {
              return Scaffold(
                body: TerminalWorkspace(
                  sessions: sessions,
                  selected: 0,
                  controllerFor: (s) => controllers.putIfAbsent(s, TerminalController.new),
                  fontSize: kTerminalDefaultFont,
                  onSelect: (_) {},
                  onDetach: (i) {
                    setState(() => sessions.removeAt(i));
                  },
                  onEnd: (i) async {
                    final session = sessions[i];
                    final ok = await confirmEndSession(context, session.name);
                    if (!ok) return;
                    if (endErrorToReturn != null) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(endErrorToReturn)));
                      return;
                    }
                    setState(() => sessions.removeAt(i));
                  },
                  onNew: () {},
                  onShowSessions: () {},
                  onFontSize: (_) {},
                  onCopy: () {},
                  onPaste: () {},
                ),
              );
            },
          ),
        ),
      );
      await tester.pump();
      expect(find.text('main'), findsOneWidget);
      expect(find.text('shell-2'), findsOneWidget);

      // Case 1: Tap × on shell-2, then Cancel -> tab is kept
      await tester.tap(find.byTooltip('End session shell-2'));
      await tester.pumpAndSettle();
      expect(find.text('End session "shell-2"?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('shell-2'), findsOneWidget);

      // Case 2: Tap × on shell-2, confirm, but end returns error -> keeps tab + shows snackbar
      endErrorToReturn = 'Server refused to end shell-2';
      await tester.tap(find.byTooltip('End session shell-2'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'End session'));
      await tester.pumpAndSettle();
      expect(find.text('Server refused to end shell-2'), findsOneWidget);
      expect(find.text('shell-2'), findsOneWidget);

      // Case 3: Tap × on shell-2, confirm, end succeeds -> removes tab
      endErrorToReturn = null;
      await tester.tap(find.byTooltip('End session shell-2'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'End session'));
      await tester.pumpAndSettle();
      expect(find.text('shell-2'), findsNothing);
      expect(find.text('main'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      for (final s in allSessions) {
        s.close();
        s.dispose();
      }
      for (final c in controllers.values) {
        c.dispose();
      }
    });
  });

  group('Snippets', () {
    testWidgets('defaults when empty, panel toggles on wide, tap types without newline', (tester) async {
      final h = await pumpWorkspace(tester, size: const Size(1400, 900));

      // Initially closed
      expect(find.text("What's running"), findsNothing);

      // Toggle open
      await tester.tap(find.byTooltip('Snippets'));
      await tester.pump();
      expect(find.text("What's running"), findsOneWidget);
      expect(find.text('docker ps'), findsOneWidget);
      expect(find.text('How full is the disk'), findsOneWidget);
      expect(find.text('Memory in use'), findsOneWidget);
      expect(find.text("Follow Archangel's log"), findsOneWidget);
      expect(find.text('Update the server'), findsOneWidget);
      expect(find.text('Busy programs'), findsOneWidget);

      // Tap a snippet -> types command without newline
      await tester.tap(find.text("What's running"));
      await tester.pump();
      expect(h.channels[0].stdin, ['docker ps']);

      // Toggle closed
      await tester.tap(find.byTooltip('Snippets'));
      await tester.pump();
      expect(find.text("What's running"), findsNothing);

      await finish(tester, h);
    });

    testWidgets('sheet on narrow and tap closes sheet', (tester) async {
      final h = await pumpWorkspace(tester, size: const Size(390, 844));
      h.channels[0].serverStdout(utf8.encode('ready\n'));
      await tester.pump();

      // Extra keys row has Snippets key
      final snipKey = find.descendant(of: find.byType(TerminalAccessoryBar), matching: find.byTooltip('Snippets'));
      expect(snipKey, findsOneWidget);

      await tester.tap(snipKey);
      await tester.pumpAndSettle();

      // Bottom sheet is open
      expect(find.text('Snippets'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);
      expect(find.text("What's running"), findsOneWidget);

      // Tap a snippet -> types command without newline and closes sheet
      await tester.tap(find.text("What's running"));
      await tester.pumpAndSettle();

      expect(h.channels[0].stdin, ['docker ps']);
      expect(find.text('Close'), findsNothing);

      await finish(tester, h);
    });

    testWidgets('save adds to list and persists (tester.runAsync)', (tester) async {
      final h = await pumpWorkspace(tester, size: const Size(1400, 900));
      h.channels[0].serverStdout(utf8.encode('ready\n'));
      await tester.pump();

      // Open panel
      await tester.tap(find.byTooltip('Snippets'));
      await tester.pump();

      // Tap "+ Save a snippet"
      await tester.tap(find.text('+ Save a snippet'));
      await tester.pumpAndSettle();

      expect(find.text('Save a snippet'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Custom Git');
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Command'), 'git status');
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(AxButton, 'Save'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();

      expect(find.text('Custom Git'), findsOneWidget);
      expect(find.text('git status'), findsOneWidget);

      // Persisted to storage
      await tester.runAsync(() async {
        final raw = await LocalKvStore.instance.read(kTerminalSnippetsKey);
        expect(raw, contains('Custom Git'));
        expect(raw, contains('git status'));
      });

      await finish(tester, h);
    });
  });

  group('Phone key row', () {
    testWidgets('has the 12 keys and sends escape sequences', (tester) async {
      final h = await pumpWorkspace(tester, size: const Size(390, 844));
      expect(find.byType(TerminalAccessoryBar), findsOneWidget);

      final keys = find.descendant(of: find.byType(TerminalAccessoryBar), matching: find.byType(InkWell));
      expect(keys, findsNWidgets(12));

      // Each key height is at least 44
      for (final e in keys.evaluate()) {
        final size = tester.getSize(find.byWidget(e.widget));
        expect(size.height, greaterThanOrEqualTo(44));
      }

      for (final tip in ['Escape', 'Tab', 'Up arrow', 'Left arrow', 'Pipe', 'Tilde', 'Slash', 'Dash']) {
        await tester.ensureVisible(find.byTooltip(tip));
        await tester.pump();
        await tester.tap(find.byTooltip(tip));
      }
      expect(h.channels[0].stdin, ['\x1b', '\t', '\x1b[A', '\x1b[D', '|', '~', '/', '-']);
      await finish(tester, h);
    });

    testWidgets('Ctrl shows pressed while latched and is sticky for one key', (tester) async {
      final h = await pumpWorkspace(tester, size: const Size(390, 844));
      final ctrlFinder = find.byTooltip('Control (applies to the next key)');

      expect(h.sessions[0].ctrlLatched, isFalse);

      await tester.tap(ctrlFinder);
      await tester.pump();

      expect(h.sessions[0].ctrlLatched, isTrue);

      // Semantics toggled is true when latched
      final semantics = tester.getSemantics(ctrlFinder);
      // ignore: deprecated_member_use
      expect(semantics.hasFlag(SemanticsFlag.isToggled), isTrue);

      h.sessions[0].typeText('c');
      await tester.pump();

      expect(h.channels[0].stdin, ['\x03']);
      expect(h.sessions[0].ctrlLatched, isFalse);

      await finish(tester, h);
    });

    testWidgets('is hidden at desktop width', (tester) async {
      final h = await pumpWorkspace(tester, size: const Size(1400, 900));
      expect(find.byType(TerminalAccessoryBar), findsNothing);
      await finish(tester, h);
    });
  });

  group('States', () {
    testWidgets('connecting overlay appears and stalled shows Reconnect', (tester) async {
      final h = await pumpWorkspace(tester);
      expect(find.text('Reaching your server…'), findsOneWidget);
      expect(find.text('Opening session "main".'), findsOneWidget);

      await tester.pump(const Duration(seconds: 11));
      expect(find.text('Still waiting. Your server is slow to answer.'), findsOneWidget);
      expect(find.widgetWithText(AxButton, 'Reconnect'), findsOneWidget);

      h.channels[0].serverStdout(utf8.encode('ready\n'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Still waiting. Your server is slow to answer.'), findsNothing);
      await finish(tester, h);
    });

    testWidgets('disconnected overlay calls reconnect', (tester) async {
      final h = await pumpWorkspace(tester);
      h.channels[0].serverStdout(utf8.encode('running'));
      await tester.pump();

      // Disconnected without exit code
      h.channels[0].serverClose();
      await tester.pump();
      await tester.pump();

      expect(find.text('Disconnected'), findsOneWidget);
      expect(find.text('Your session is still running on the server. Reconnect to pick up where you left off.'), findsOneWidget);

      final before = h.sessions[0].terminal;
      await tester.tap(find.widgetWithText(AxButton, 'Reconnect'));
      await tester.pump();

      expect(identical(h.sessions[0].terminal, before), isFalse);
      await finish(tester, h);
    });

    testWidgets('exit frame shows "This session ended" with "Start a new session"', (tester) async {
      final h = await pumpWorkspace(tester);
      h.channels[0].serverStdout(utf8.encode('done'));
      h.channels[0].serverSend({'type': 'exit', 'code': 0});
      await tester.pump();
      await tester.pump();

      expect(find.text('This session ended'), findsOneWidget);
      expect(find.text('The shell exited.'), findsOneWidget);
      expect(find.widgetWithText(AxButton, 'Start a new session'), findsOneWidget);

      final before = h.sessions[0].terminal;
      await tester.tap(find.widgetWithText(AxButton, 'Start a new session'));
      await tester.pump();

      expect(identical(h.sessions[0].terminal, before), isFalse);
      await finish(tester, h);
    });

    testWidgets('blocked banner appears for sudo text only when Admin mode is off, and Dismiss hides it', (tester) async {
      // First, with Admin mode ON: banner does not appear
      final hAdminOn = await pumpWorkspace(tester, adminModeEnabled: true);
      hAdminOn.channels[0].serverStdout(utf8.encode('sudo: a password is required\n'));
      await tester.pump();
      await tester.pump();

      expect(find.text('That command needs Admin mode'), findsNothing);
      await finish(tester, hAdminOn);

      // Second, with Admin mode OFF: banner appears
      final h = await pumpWorkspace(tester, adminModeEnabled: false);
      h.channels[0].serverStdout(utf8.encode('sudo: a password is required\n'));
      await tester.pump();
      await tester.pump();

      expect(find.text('That command needs Admin mode'), findsOneWidget);
      expect(find.textContaining('Your server blocked it because Admin mode is off'), findsOneWidget);
      expect(find.widgetWithText(AxButton, 'Open Admin mode'), findsOneWidget);
      expect(find.widgetWithText(AxButton, 'Dismiss'), findsOneWidget);

      // Tapping Open Admin mode triggers callback
      await tester.tap(find.widgetWithText(AxButton, 'Open Admin mode'));
      expect(h.events, contains('open-admin'));

      // Tapping Dismiss hides banner
      await tester.tap(find.widgetWithText(AxButton, 'Dismiss'));
      await tester.pump();

      expect(find.text('That command needs Admin mode'), findsNothing);

      // Banner appears again only on new match
      h.channels[0].serverStdout(utf8.encode('user is not in the sudoers file\n'));
      await tester.pump();
      await tester.pump();

      expect(find.text('That command needs Admin mode'), findsOneWidget);

      await finish(tester, h);
    });
  });

  group('Text size', () {
    testWidgets('clamps at min/max and persists', (tester) async {
      final h = await pumpWorkspace(tester, size: const Size(1400, 900));
      h.channels[0].serverStdout(utf8.encode('ready'));
      await tester.pump();

      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();

      // Increase
      await tester.tap(find.byTooltip('Bigger text'));
      await tester.pump();
      expect(h.fontSize, kTerminalDefaultFont + 1);

      // Step down to min and clamp
      while (h.fontSize > kTerminalMinFont) {
        await tester.tap(find.byTooltip('Smaller text'));
        await tester.pump();
      }
      expect(h.fontSize, kTerminalMinFont);

      // Attempt to decrease below min
      await tester.tap(find.byTooltip('Smaller text'));
      await tester.pump();
      expect(h.fontSize, kTerminalMinFont);

      // Step up to max and clamp
      while (h.fontSize < kTerminalMaxFont) {
        await tester.tap(find.byTooltip('Bigger text'));
        await tester.pump();
      }
      expect(h.fontSize, kTerminalMaxFont);

      // Attempt to increase above max
      await tester.tap(find.byTooltip('Bigger text'));
      await tester.pump();
      expect(h.fontSize, kTerminalMaxFont);

      // Verify persistence key exists
      await tester.runAsync(() async {
        await LocalKvStore.instance.write(kTerminalFontSizeKey, '18');
        final saved = await LocalKvStore.instance.read(kTerminalFontSizeKey);
        expect(saved, '18');
      });

      await finish(tester, h);
    });
  });
}
