import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import '../../theme.dart';

/// Dawn (dark) console: deep navy, the same navy as the prototype's console.
const Color kTerminalBg = Color(0xFF0D0F1D);
const Color kTerminalFg = Color(0xFFE6E8F5);

/// Pearl (light) console: soft pearl.
const Color kTerminalLightBg = Color(0xFFFAFAFC);
const Color kTerminalLightFg = Color(0xFF141726);

/// Dawn (dark) ANSI Terminal Theme
const TerminalTheme kTerminalTheme = TerminalTheme(
  cursor: Color(0xFF8FE3D6),
  selection: Color(0x663B82F6),
  foreground: kTerminalFg,
  background: kTerminalBg,
  black: Color(0xFF8A91B0),
  red: Color(0xFFFF7B72),
  green: Color(0xFF56D364),
  yellow: Color(0xFFE3B341),
  blue: Color(0xFF79B8FF),
  magenta: Color(0xFFD2A8FF),
  cyan: Color(0xFF56D4DD),
  white: Color(0xFFD0D4E8),
  brightBlack: Color(0xFF9AA1BF),
  brightRed: Color(0xFFFFA198),
  brightGreen: Color(0xFF7EE787),
  brightYellow: Color(0xFFF2CC60),
  brightBlue: Color(0xFFA5D6FF),
  brightMagenta: Color(0xFFE2C5FF),
  brightCyan: Color(0xFF8DE8EE),
  brightWhite: Color(0xFFFFFFFF),
  searchHitBackground: Color(0xFFF2CC60),
  searchHitBackgroundCurrent: Color(0xFF7EE787),
  searchHitForeground: Color(0xFF0D0F1D),
);

/// Pearl (light) ANSI Terminal Theme
const TerminalTheme kTerminalLightTheme = TerminalTheme(
  cursor: Color(0xFF4B3FD1),
  selection: Color(0x334B3FD1),
  foreground: kTerminalLightFg,
  background: kTerminalLightBg,
  black: Color(0xFF24292F),
  red: Color(0xFFCF222E),
  green: Color(0xFF116329),
  yellow: Color(0xFF7D4E00),
  blue: Color(0xFF0969DA),
  magenta: Color(0xFF8250DF),
  cyan: Color(0xFF1B7C83),
  white: Color(0xFF57606A),
  brightBlack: Color(0xFF59636E),
  brightRed: Color(0xFFA40E26),
  brightGreen: Color(0xFF1A7F37),
  brightYellow: Color(0xFF633C01),
  brightBlue: Color(0xFF0550AE),
  brightMagenta: Color(0xFF6639BA),
  brightCyan: Color(0xFF0E636A),
  brightWhite: Color(0xFF141726),
  searchHitBackground: Color(0xFFFFDF5D),
  searchHitBackgroundCurrent: Color(0xFFFFC66E),
  searchHitForeground: Color(0xFF141726),
);

/// Palette encapsulating container and terminal colors for Dawn (dark) and Pearl (light).
@immutable
class TerminalPalette {
  const TerminalPalette({
    required this.brightness,
    required this.bg,
    required this.barBg,
    required this.tabSelectedBg,
    required this.line,
    required this.text,
    required this.textMuted,
    required this.accent,
    required this.accent2,
    required this.snipsBg,
    required this.chipOffBg,
    required this.chipOnBg,
    required this.chipOnFg,
    required this.liveDotGreen,
    required this.liveDotAmber,
    required this.liveDotGrey,
    required this.termBg,
    required this.termFg,
    required this.termTheme,
  });

  final Brightness brightness;
  final Color bg;
  final Color barBg;
  final Color tabSelectedBg;
  final Color line;
  final Color text;
  final Color textMuted;
  final Color accent;
  final Color accent2;
  final Color snipsBg;
  final Color chipOffBg;
  final Color chipOnBg;
  final Color chipOnFg;
  final Color liveDotGreen;
  final Color liveDotAmber;
  final Color liveDotGrey;
  final Color termBg;
  final Color termFg;
  final TerminalTheme termTheme;

  bool get isDark => brightness == Brightness.dark;

  /// The console for [brightness]. The terminal colours are fixed per theme;
  /// the chrome around them is taken from the app tokens [c], so it always
  /// follows the active theme and accent.
  factory TerminalPalette.resolve(AxPalette c, Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final termBg = dark ? kTerminalBg : kTerminalLightBg;
    return TerminalPalette(
      brightness: brightness,
      bg: termBg,
      barBg: dark ? c.surface : c.surfaceAlt,
      tabSelectedBg: dark ? c.surfaceHigh : c.surface,
      line: c.border,
      text: c.text,
      textMuted: c.textMuted,
      accent: c.accent,
      accent2: c.info,
      snipsBg: dark ? c.surface : c.surfaceAlt,
      chipOffBg: c.surfaceAlt,
      chipOnBg: c.warningWash,
      chipOnFg: c.warning,
      liveDotGreen: c.success,
      liveDotAmber: c.warning,
      liveDotGrey: c.outline,
      termBg: termBg,
      termFg: dark ? kTerminalFg : kTerminalLightFg,
      termTheme: dark ? kTerminalTheme : kTerminalLightTheme,
    );
  }

  static final TerminalPalette dark = TerminalPalette.resolve(AxPalette.dark(AxAccent.halo), Brightness.dark);
  static final TerminalPalette light = TerminalPalette.resolve(AxPalette.light(AxAccent.halo), Brightness.light);

  /// The default-accent palette for [brightness].
  static TerminalPalette of(Brightness brightness) => brightness == Brightness.dark ? dark : light;
}

extension TerminalPaletteContext on BuildContext {
  TerminalPalette get terminalPalette => TerminalPalette.resolve(ax.colors, ax.brightness);
}

/// Every text colour of [kTerminalTheme], for the contrast test.
List<Color> terminalForegroundColors(TerminalTheme t) => [
  t.foreground,
  t.black,
  t.red,
  t.green,
  t.yellow,
  t.blue,
  t.magenta,
  t.cyan,
  t.white,
  t.brightBlack,
  t.brightRed,
  t.brightGreen,
  t.brightYellow,
  t.brightBlue,
  t.brightMagenta,
  t.brightCyan,
  t.brightWhite,
];
