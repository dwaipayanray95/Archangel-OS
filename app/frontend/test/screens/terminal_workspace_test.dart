import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

import 'package:archangel/services/archangeld_connection.dart';
import 'package:archangel/services/terminal_session.dart';
import 'package:archangel/ui/screens/terminal/sessions_dialog.dart';
import 'package:archangel/ui/screens/terminal/terminal_accessory_bar.dart';
import 'package:archangel/ui/screens/terminal/terminal_workspace.dart';
import 'package:archangel/ui/theme.dart';

import '../test_utils.dart';
import 'terminal_fake_channel.dart';

class TerminalHarness {
  TerminalHarness(this.sessions, this.channels);
  final List<TerminalSession> sessions;
  final List<FakeTerminalChannel> channels;
  final controllers = <TerminalSession, TerminalController>{};
  final events = <String>[];
  double fontSize = kTerminalDefaultFont;
  int selected = 0;
}

Future<TerminalHarness> pumpWorkspace(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  List<String> names = const ['main'],
}) async {
  ignoreFontDownloadErrors();
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
  final h = TerminalHarness(sessions, channels);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(MaterialApp(
    theme: buildTheme(Brightness.dark),
    home: StatefulBuilder(
      builder: (context, setState) => Scaffold(
        body: TerminalWorkspace(
          sessions: sessions,
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
        ),
      ),
    ),
  ));
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

  group('accessory bar', () {
    testWidgets('is shown at phone width and sends proper escape sequences', (tester) async {
      final h = await pumpWorkspace(tester);
      expect(find.byType(TerminalAccessoryBar), findsOneWidget);

      // The bar scrolls sideways on a 390 dp screen; bring each key into view.
      for (final tip in ['Escape', 'Tab', 'Up arrow', 'Left arrow', 'Pipe', 'Tilde', 'Slash', 'Dash']) {
        await tester.ensureVisible(find.byTooltip(tip));
        await tester.pump();
        await tester.tap(find.byTooltip(tip));
      }
      expect(h.channels[0].stdin, ['\x1b', '\t', '\x1b[A', '\x1b[D', '|', '~', '/', '-']);
      await finish(tester, h);
    });

    testWidgets('Ctrl is sticky for exactly one key', (tester) async {
      final h = await pumpWorkspace(tester);
      await tester.tap(find.byTooltip('Control (applies to the next key)'));
      await tester.pump();
      expect(h.sessions[0].ctrlLatched, isTrue);
      h.sessions[0].typeText('c'); // as if from the soft keyboard
      await tester.pump();
      expect(h.channels[0].stdin, ['\x03']);
      expect(h.sessions[0].ctrlLatched, isFalse);
      await finish(tester, h);
    });

    testWidgets('every key is at least 48x48', (tester) async {
      final h = await pumpWorkspace(tester);
      final keys = find.descendant(of: find.byType(TerminalAccessoryBar), matching: find.byType(InkWell));
      expect(keys, findsNWidgets(11));
      for (final e in keys.evaluate()) {
        final size = tester.getSize(find.byWidget(e.widget));
        expect(size.width, greaterThanOrEqualTo(48));
        expect(size.height, greaterThanOrEqualTo(48));
      }
      await finish(tester, h);
    });

    testWidgets('is hidden at desktop width', (tester) async {
      final h = await pumpWorkspace(tester, size: const Size(1400, 900));
      expect(find.byType(TerminalAccessoryBar), findsNothing);
      await finish(tester, h);
    });
  });

  for (final size in const [Size(390, 844), Size(1400, 900)]) {
    testWidgets('no overflow at ${size.width.toInt()} wide with several sessions and a banner', (tester) async {
      final h = await pumpWorkspace(tester, size: size, names: const ['main', 'shell-2', 'a-rather-long-session-name']);
      h.channels[0].serverSend({'type': 'error', 'message': 'tmux is unavailable, so this session will not persist'});
      h.channels[0].serverStdout(utf8.encode('hello'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      // 3 chips x (select + detach)
      expect(find.byTooltip('Detach — keeps running'), findsNWidgets(3));
      await finish(tester, h);
    });
  }

  testWidgets('chrome actions call back; detach says it keeps running', (tester) async {
    final h = await pumpWorkspace(tester, size: const Size(1400, 900), names: const ['main', 'shell-2']);
    await tester.tap(find.byTooltip('New session'));
    await tester.tap(find.byTooltip('Sessions on this server'));
    await tester.tap(find.byTooltip('Copy selected text'));
    await tester.tap(find.byTooltip('Paste'));
    await tester.tap(find.byTooltip('End session'));
    await tester.tap(find.byTooltip('Detach — keeps running').last);
    expect(h.events, ['new', 'sessions', 'copy', 'paste', 'end 0', 'detach 1']);

    await tester.tap(find.byKey(const ValueKey('terminal-chip-shell-2')));
    await tester.pump();
    expect(h.selected, 1);
    await finish(tester, h);
  });

  testWidgets('text size buttons step the size and stop at the limits', (tester) async {
    final h = await pumpWorkspace(tester, size: const Size(1400, 900));
    await tester.tap(find.byTooltip('Larger text'));
    await tester.pump();
    expect(h.fontSize, kTerminalDefaultFont + 1);
    await tester.pump();
    await tester.tap(find.byTooltip('Smaller text'));
    await tester.pump();
    await tester.tap(find.byTooltip('Smaller text'));
    await tester.pump();
    expect(h.fontSize, kTerminalDefaultFont - 1);
    h.fontSize = kTerminalMinFont;
    await tester.tap(find.byTooltip('Larger text'));
    await tester.pump();
    h.fontSize = kTerminalMinFont;
    await finish(tester, h);
  });

  testWidgets('waiting message appears while there is no output, then clears', (tester) async {
    final h = await pumpWorkspace(tester);
    expect(find.byKey(const ValueKey('terminal-waiting')), findsOneWidget);
    await tester.pump(const Duration(seconds: 11));
    expect(find.textContaining('Still nothing from your server'), findsOneWidget);
    h.channels[0].serverStdout(utf8.encode('hi'));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('terminal-waiting')), findsNothing);
    await finish(tester, h);
  });

  testWidgets('closed session shows Reconnect, which starts a clean emulator', (tester) async {
    final h = await pumpWorkspace(tester);
    h.channels[0].serverStdout(utf8.encode('old'));
    h.channels[0].serverSend({'type': 'exit', 'code': 0});
    await tester.pump(); // frames are delivered in a microtask: one pump to deliver,
    await tester.pump(); // one to rebuild
    expect(find.text('This session ended (exit code 0).'), findsOneWidget);
    final before = h.sessions[0].terminal;
    await tester.tap(find.text('Reconnect'));
    await tester.pump();
    expect(identical(h.sessions[0].terminal, before), isFalse);
    expect(h.sessions[0].terminal.buffer.getText().trim(), isEmpty);
    await finish(tester, h);
  });

  group('end-session confirmation', () {
    Future<bool?> open(WidgetTester tester, void Function(bool?) onResult) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => onResult(await confirmEndSession(context, 'main')),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return null;
    }

    testWidgets('explains the consequence and only the danger button confirms', (tester) async {
      ignoreFontDownloadErrors();
      bool? result;
      await open(tester, (r) => result = r);
      expect(find.text('End session "main"?'), findsOneWidget);
      expect(find.textContaining('stops everything running'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'End session'));
      await tester.pumpAndSettle();
      expect(result, isTrue);
    });

    testWidgets('Cancel does not end it', (tester) async {
      ignoreFontDownloadErrors();
      bool? result;
      await open(tester, (r) => result = r);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(result, isFalse);
    });
  });
}
