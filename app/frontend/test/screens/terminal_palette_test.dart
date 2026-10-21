import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:archangel/ui/screens/terminal/terminal_palette.dart';

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

  test('TerminalPalette returns correct instance for brightness', () {
    expect(TerminalPalette.of(Brightness.dark).isDark, isTrue);
    expect(TerminalPalette.of(Brightness.light).isDark, isFalse);
    expect(TerminalPalette.of(Brightness.dark).termBg, kTerminalBg);
    expect(TerminalPalette.of(Brightness.light).termBg, kTerminalLightBg);
  });
}
