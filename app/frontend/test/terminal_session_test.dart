import 'package:flutter_test/flutter_test.dart';
import 'package:archangel/services/terminal_session.dart';

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

  group('output buffer', () {
    test('caps retained output, trimming from the start', () {
      final s = TerminalSession(label: 'x');
      s.debugAppend('A' * (terminalOutputCap - 10));
      s.debugAppend('B' * 30);
      expect(s.output.length, terminalOutputCap);
      expect(s.output.endsWith('B' * 30), isTrue);
      expect(s.output.startsWith('A'), isTrue);
      s.dispose();
    });
    test('backspace edits tail and chunk', () {
      final s = TerminalSession(label: 'x');
      s.debugAppend('abc');
      s.debugAppend('\b\bX');
      expect(s.output, 'aX');
      s.debugAppend('ab\x7f');
      expect(s.output, 'aXa');
      s.debugAppend('\b\b\b\b');
      expect(s.output, '');
      s.dispose();
    });
  });

  group('session JSON', () {
    test('parses the list payload', () {
      final list = parseTerminalSessions(
          '[{"name":"main","windows":2,"attached":true,"created_unix":1760000000},{"name":"shell-2","windows":1,"attached":false,"created_unix":0}]');
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
}
