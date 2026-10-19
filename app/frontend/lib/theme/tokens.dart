// Design tokens ported 1:1 from the Claude Design mockup
// (Archangel.dc.html --ax-* CSS custom properties).
import 'package:flutter/material.dart';

class AxColors {
  AxColors._();

  static const bg = Color(0xFF0B0C0B);
  static const s1 = Color(0xFF121412);
  static const s2 = Color(0xFF181B18);
  static const s3 = Color(0xFF212520);
  static const s4 = Color(0xFF2B302A);
  static const line = Color(0x14E8F0E6); // rgba(232,240,230,0.08)
  static const line2 = Color(0x26E8F0E6); // rgba(232,240,230,0.15)
  static const fg = Color(0xFFE9EFE7);
  static const fg2 = Color(0xFF98A294);
  static const fg3 = Color(0xFF646D61);
  static const accent = Color(0xFF7EE787);
  static const accentD = Color(0xFF4BB85C);
  static const wash = Color(0x1C7EE787); // rgba(126,231,135,0.11)
  static const wash2 = Color(0x337EE787); // rgba(126,231,135,0.2)
  static const warn = Color(0xFFE3B341);
  static const warnWash = Color(0x21E3B341);
  static const bad = Color(0xFFE5806B);
  static const danger = bad;
  static const info = Color(0xFF79B8FF);

  static const accentOptions = <Color>[
    accent, // Signal green
    warn, // Amber
    info, // Ice
    bad, // Ember
  ];
}

class AxRadius {
  AxRadius._();
  static const sm = 8.0;
  static const md = 11.0;
  static const lg = 14.0;
  static const xl = 15.0;
  static const pill = 999.0;
}

class AxMotion {
  AxMotion._();
  static const fast = Duration(milliseconds: 160);
  static const base = Duration(milliseconds: 180);
  static const enter = Duration(milliseconds: 320);
  static const pop = Duration(milliseconds: 230);
  static const spring = Curves.easeOutCubic;
  // approximates cubic-bezier(.2,.9,.25,1)
  static const easeOutSoft = Cubic(0.2, 0.9, 0.25, 1.0);
  static const easeOutSnap = Cubic(0.3, 0.9, 0.3, 1.0);
}

class AxTextStyles {
  AxTextStyles._();

  static TextStyle mono = const TextStyle(fontFamily: 'IBMPlexMono', color: AxColors.fg);
  static TextStyle sans = const TextStyle(fontFamily: 'Inter', color: AxColors.fg);

  static TextStyle label = mono.copyWith(
    fontSize: 9.5,
    letterSpacing: 1.3,
    color: AxColors.fg3,
    fontWeight: FontWeight.w500,
  );

  static TextStyle mutedMono = mono.copyWith(
    fontSize: 11.5,
    color: AxColors.fg3,
  );

  static TextStyle h1 = sans.copyWith(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
  );

  static TextStyle h2 = sans.copyWith(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.2,
  );
}
