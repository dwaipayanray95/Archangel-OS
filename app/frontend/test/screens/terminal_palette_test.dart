import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:archangel/ui/screens/terminal/terminal_palette.dart';
import 'package:archangel/ui/theme.dart';

double _lum(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _contrast(Color a, Color b) {
  final la = _lum(a), lb = _lum(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  group('Dawn (dark) terminal palette', () {
    test('every terminal text colour is >= 4.5:1 on the terminal background', () {
      final colors = terminalForegroundColors(kTerminalTheme);
      expect(colors, hasLength(17));
      for (final c in colors) {
        expect(_contrast(c, kTerminalBg), greaterThanOrEqualTo(4.5), reason: '#${c.toARGB32().toRadixString(16)}');
      }
    });

    test('cursor stands out from the background (>= 3:1)', () {
      expect(_contrast(kTerminalTheme.cursor, kTerminalBg), greaterThanOrEqualTo(3));
    });
  });

  group('Pearl (light) terminal palette', () {
    test('every terminal text colour is >= 4.5:1 on the terminal background', () {
      final colors = terminalForegroundColors(kTerminalLightTheme);
      expect(colors, hasLength(17));
      for (final c in colors) {
        expect(_contrast(c, kTerminalLightBg), greaterThanOrEqualTo(4.5), reason: '#${c.toARGB32().toRadixString(16)}');
      }
    });

    test('cursor stands out from the background (>= 3:1)', () {
      expect(_contrast(kTerminalLightTheme.cursor, kTerminalLightBg), greaterThanOrEqualTo(3));
    });
  });

  group('chrome follows the app tokens', () {
    for (final b in Brightness.values) {
      test('${b.name}: text and muted text are readable on the bar and the console', () {
        final c = b == Brightness.dark ? AxPalette.dark(AxAccent.halo) : AxPalette.light(AxAccent.halo);
        final tp = TerminalPalette.resolve(c, b);
        expect(tp.text, c.text);
        expect(tp.line, c.border);
        expect(tp.accent, c.accent);
        for (final bg in [tp.barBg, tp.tabSelectedBg, tp.snipsBg]) {
          expect(_contrast(tp.text, bg), greaterThanOrEqualTo(4.5));
          expect(_contrast(tp.textMuted, bg), greaterThanOrEqualTo(4.5));
        }
        expect(_contrast(tp.termFg, tp.termBg), greaterThanOrEqualTo(4.5));
      });
    }
  });

  testWidgets('the console palette switches live with the app theme', (tester) async {
    TerminalPalette? seen;
    Widget app(Brightness b) => MaterialApp(
      theme: buildTheme(b),
      home: Builder(
        builder: (context) {
          seen = context.terminalPalette;
          return const SizedBox();
        },
      ),
    );
    await tester.pumpWidget(app(Brightness.dark));
    expect(seen!.termBg, kTerminalBg);
    expect(seen!.termTheme, kTerminalTheme);
    await tester.pumpWidget(app(Brightness.light));
    await tester.pumpAndSettle();
    expect(seen!.termBg, kTerminalLightBg);
    expect(seen!.termTheme, kTerminalLightTheme);
  });

  test('TerminalPalette returns correct instance for brightness', () {
    expect(TerminalPalette.of(Brightness.dark).isDark, isTrue);
    expect(TerminalPalette.of(Brightness.light).isDark, isFalse);
    expect(TerminalPalette.of(Brightness.dark).termBg, kTerminalBg);
    expect(TerminalPalette.of(Brightness.light).termBg, kTerminalLightBg);
  });
}
