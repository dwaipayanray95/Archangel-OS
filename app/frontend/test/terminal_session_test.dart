import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';
import 'package:archangel/services/terminal_session.dart';

import 'screens/terminal_fake_channel.dart';
import 'test_utils.dart';

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

String screenText(TerminalSession s) => s.terminal.buffer.getText();

void main() {
  group('nextSessionName', () {
    test('uses main first, then shell-N filling the first gap', () {
      expect(nextSessionName(const []), 'main');
      expect(nextSessionName(const ['main']), 'shell-2');
      expect(nextSessionName(const ['main', 'shell-2', 'shell-4']), 'shell-3');
      expect(nextSessionName(const ['work']), 'main');
    });

    test('generated names satisfy the server regex', () {
      expect(terminalSessionNameRe.hasMatch(nextSessionName(const ['main'])), isTrue);
    });
  });

  group('shellSingleQuote / cdCommandFor', () {
    test('wraps plain paths', () {
      expect(shellSingleQuote('/var/log'), "'/var/log'");
    });

    test("escapes embedded single quotes as '\\''", () {
      expect(shellSingleQuote("/tmp/it's"), "'/tmp/it'\\''s'");
    });

    test('neutralises shell metacharacters', () {
      expect(cdCommandFor(r'/a b/$(rm -rf x)'), "cd -- '/a b/\$(rm -rf x)'\n");
    });
  });

  group('isSafeShellPath', () {
    test('accepts normal and unicode paths', () {
      expect(isSafeShellPath('/var/log/my dir/é'), isTrue);
    });
    test('rejects C0 controls and DEL', () {
      expect(isSafeShellPath('/a\nb'), isFalse);
      expect(isSafeShellPath('/a\x00b'), isFalse);
      expect(isSafeShellPath('/a\x1bb'), isFalse);
      expect(isSafeShellPath('/a\x7fb'), isFalse);
    });
  });

  group('session JSON', () {
    test('parses the list payload', () {
      final list = parseTerminalSessions(
        '[{"name":"main","windows":2,"attached":true,"created_unix":1760000000},{"name":"shell-2","windows":1,"attached":false,"created_unix":0}]',
      );
      expect(list.map((s) => s.name), ['main', 'shell-2']);
      expect(list[0].windows, 2);
      expect(list[0].attached, isTrue);
      expect(list[0].created, isNotNull);
      expect(list[1].created, isNull);
    });

    test('tolerates garbage', () {
      expect(parseTerminalSessions('not json'), isEmpty);
      expect(parseTerminalSessions('{"a":1}'), isEmpty);
      expect(parseTerminalSessions('[1,{"windows":1}]'), isEmpty);
    });

    test('formatRunningSince', () {
      final now = DateTime(2026, 10, 19, 18, 0);
      expect(formatRunningSince(DateTime(2026, 10, 19, 9, 5), now), 'running since 09:05');
      expect(formatRunningSince(DateTime(2026, 10, 18, 14, 2), now), 'running since Oct 18, 14:02');
      expect(formatRunningSince(null, now), 'running');
    });
  });

  group('emulator', () {
    late TerminalSession session;
    late FakeTerminalChannel ch;

    setUp(() async {
      await useTempKvStore();
      (session, ch) = await connectedFakeSession();
      await settle();
    });
    tearDown(() => session.dispose());

    test('colour and cursor movement become buffer text, not escapes', () async {
      ch.serverStdout(utf8.encode('\x1b[31mred\x1b[0m plain\r\n\x1b[2;5Hxy'));
      await settle();
      final lines = session.terminal.buffer.lines;
      expect(lines[0].getText().trimRight(), 'red plain');
      expect(lines[1].getCodePoint(4), 'x'.codeUnitAt(0)); // row 2, col 5 (1-based)
      expect(lines[1].getCodePoint(5), 'y'.codeUnitAt(0));
      expect(screenText(session), isNot(contains('\x1b')));
      expect(session.hasOutput, isTrue);
      expect(session.status, SessionStatus.connected);
    });

    test('tmux style repaint is rendered in place', () async {
      // Clear, status line at the bottom row, prompt with charset resets.
      final bottom = session.terminal.viewHeight;
      ch.serverStdout(
        utf8.encode(
          '\x1b[H\x1b[2J\x1b(B\x1b[m\x1b[1;1Harchangel@mk1:~\$ '
          '\x1b[$bottom;1H\x1b[30;42m[main] 0:bash*\x1b(B\x1b[m\x1b[1;19H',
        ),
      );
      await settle();
      final text = screenText(session);
      expect(text, contains('archangel@mk1:~\$'));
      expect(text, contains('[main] 0:bash*'));
      expect(text, isNot(contains('(B')));
      expect(session.terminal.buffer.lines[0].getText().trimRight(), 'archangel@mk1:~\$');
    });

    test('a multibyte character split across frames decodes once', () async {
      final euro = utf8.encode('€'); // 3 bytes
      ch.serverStdout([...utf8.encode('a'), euro[0]]);
      await settle();
      ch.serverStdout([euro[1]]);
      await settle();
      ch.serverStdout([euro[2], ...utf8.encode('b')]);
      await settle();
      expect(session.terminal.buffer.lines[0].getText().trimRight(), 'a€b');
    });

    test('malformed bytes do not break later output', () async {
      ch.serverStdout([0xff, 0xfe, ...utf8.encode('ok')]);
      await settle();
      expect(screenText(session), contains('ok'));
    });

    test('keystrokes become base64 stdin frames', () async {
      session.terminal.textInput('ls\r');
      session.terminal.keyInput(TerminalKey.arrowUp);
      expect(ch.stdin, ['ls\r', '\x1b[A']);
      final frame = ch.sent.firstWhere((f) => f['type'] == 'stdin');
      expect(base64.decode(frame['data'] as String), utf8.encode('ls\r'));
    });

    test('sticky Ctrl turns the next character into a control code, once', () async {
      session.ctrlLatched = true;
      session.typeText('c');
      session.typeText('c');
      expect(ch.stdin, ['\x03', 'c']);
      expect(session.ctrlLatched, isFalse);
    });

    test('accessory keys use application cursor mode when requested', () async {
      session.pressKey(TerminalKey.arrowUp);
      ch.serverStdout(utf8.encode('\x1b[?1h\x1b=')); // what terminfo smkx sends
      await settle();
      session.pressKey(TerminalKey.arrowUp);
      expect(ch.stdin, ['\x1b[A', '\x1bOA']);
    });

    test('ctrlCharFor', () {
      expect(ctrlCharFor('a'), '\x01');
      expect(ctrlCharFor('D'), '\x04');
      expect(ctrlCharFor('['), '\x1b');
      expect(ctrlCharFor('1'), isNull);
      expect(ctrlCharFor('ab'), isNull);
    });

    test('emulator resize sends a resize frame', () async {
      ch.sent.clear();
      session.terminal.resize(100, 30);
      expect(ch.resizes, [
        {'type': 'resize', 'cols': 100, 'rows': 30},
      ]);
    });

    test('initial size is sent once the socket is ready', () {
      expect(ch.resizes.first, {'type': 'resize', 'cols': 120, 'rows': 32});
    });

    test('reconnect starts from a clean emulator', () async {
      ch.serverStdout(utf8.encode('old output'));
      await settle();
      final before = session.terminal;
      final epoch = session.terminalEpoch;
      session.reconnect();
      expect(identical(session.terminal, before), isFalse);
      expect(session.terminalEpoch, epoch + 1);
      expect(screenText(session).trim(), isEmpty);
      expect(session.hasOutput, isFalse);
    });

    test('exit frame closes the session; error frame is a notice, not output', () async {
      ch.serverSend({'type': 'error', 'message': 'persistence unavailable'});
      await settle();
      expect(session.notice, 'persistence unavailable');
      expect(screenText(session), isNot(contains('persistence')));
      ch.serverSend({'type': 'exit', 'code': 3});
      await settle();
      expect(session.status, SessionStatus.closed);
      expect(session.exitCode, 3);
    });

    test('input after dispose is ignored', () async {
      final t = session.terminal;
      session.dispose();
      t.textInput('x'); // callbacks were detached
      session.sendInput('y');
      expect(ch.stdin, isEmpty);
    });
  });
}
