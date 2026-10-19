import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:archangel/ui/theme.dart';

/// WCAG 2.x relative luminance / contrast ratio of two opaque colours.
double _lum(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double contrast(Color a, Color b) {
  final la = _lum(a), lb = _lum(b);
  final hi = math.max(la, lb), lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

class _Pair {
  const _Pair(this.name, this.fg, this.bg, this.min);
  final String name;
  final Color fg;
  final Color bg;
  final double min;
}

/// Every foreground/background combination the design-system components
/// draw. Text needs 4.5:1; icons and borders that convey meaning need 3:1.
List<_Pair> pairsFor(AxPalette c) {
  const text = 4.5;
  const graphic = 3.0;
  final surfaces = {'bg': c.bg, 'surface': c.surface, 'surfaceAlt': c.surfaceAlt, 'surfaceHigh': c.surfaceHigh};
  return [
    for (final s in surfaces.entries) ...[
      _Pair('text on ${s.key}', c.text, s.value, text),
      _Pair('textMuted on ${s.key}', c.textMuted, s.value, text),
      _Pair('textSubtle on ${s.key}', c.textSubtle, s.value, text),
      _Pair('accent (links, ghost buttons, nav) on ${s.key}', c.accent, s.value, text),
      _Pair('success on ${s.key}', c.success, s.value, text),
      _Pair('warning on ${s.key}', c.warning, s.value, text),
      _Pair('danger on ${s.key}', c.danger, s.value, text),
      _Pair('info on ${s.key}', c.info, s.value, text),
      _Pair('outline (input borders, focus) on ${s.key}', c.outline, s.value, graphic),
    ],
    // Filled buttons.
    _Pair('onAccent on accent (primary button)', c.onAccent, c.accent, text),
    _Pair('onDanger on danger (danger button)', c.onDanger, c.danger, text),
    // Status badges and selected states sit on their washes.
    _Pair('accent on accentWash (selected tile, nav indicator)', c.accent, c.accentWash, text),
    _Pair('text on accentWash', c.text, c.accentWash, text),
    _Pair('textMuted on accentWash', c.textMuted, c.accentWash, text),
    _Pair('success on successWash (StatusBadge ok)', c.success, c.successWash, text),
    _Pair('warning on warningWash (StatusBadge warning)', c.warning, c.warningWash, text),
    _Pair('danger on dangerWash (StatusBadge error)', c.danger, c.dangerWash, text),
    _Pair('info on infoWash (StatusBadge info)', c.info, c.infoWash, text),
    _Pair('textMuted on surfaceHigh (StatusBadge neutral)', c.textMuted, c.surfaceHigh, text),
    // Selected card border and focus ring against the page.
    _Pair('accent border on bg', c.accent, c.bg, graphic),
    _Pair('text focus ring on surface', c.text, c.surface, graphic),
  ];
}

void main() {
  for (final brightness in Brightness.values) {
    for (final accent in AxAccent.values) {
      test('${brightness.name} theme, ${accent.name} accent: all token pairs meet WCAG', () {
        final palette = brightness == Brightness.dark ? AxPalette.dark(accent) : AxPalette.light(accent);
        final failures = <String>[];
        for (final p in pairsFor(palette)) {
          final ratio = contrast(p.fg, p.bg);
          if (ratio < p.min) failures.add('${p.name}: ${ratio.toStringAsFixed(2)} < ${p.min}');
        }
        expect(failures, isEmpty, reason: failures.join('\n'));
      });
    }
  }

  test('contrast helper matches known WCAG values', () {
    expect(contrast(Colors.black, Colors.white), closeTo(21, 0.01));
    expect(contrast(Colors.white, Colors.white), closeTo(1, 0.001));
  });
}
