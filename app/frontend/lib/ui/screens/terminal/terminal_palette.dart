import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import '../../theme.dart';

/// Dark terminal background & foreground
const Color kTerminalBg = Color(0xFF0B0C0B);
const Color kTerminalFg = Color(0xFFE9EFE7);

/// Light (Pearl) terminal background & foreground
const Color kTerminalLightBg = Color(0xFFFAFAFC);
const Color kTerminalLightFg = Color(0xFF141726);

/// The console container palette (dark console in Dawn).
const Color kConBg = Color(0xFF0D0F1D);
const Color kConBarBg = Color(0xFF141729);
const Color kConTabSelectedBg = Color(0xFF1C2036);
const Color kConLine = Color(0x14FFFFFF); // rgba(255, 255, 255, 0.08)
const Color kConText = Color(0xFFE6E8F5);
const Color kConMuted = Color(0xFF9CA2C2);
const Color kConAccent = Color(0xFF8FE3D6);
const Color kConAccent2 = Color(0xFFC3B8FF);
const Color kConSnipsBg = Color(0xFF10132A);
const Color kConChipOffBg = Color(0x0FFFFFFF); // rgba(255, 255, 255, 0.06)
const Color kConChipOnBg = Color(0x24FFC66E); // rgba(255, 197, 107, 0.14)
const Color kConChipOnFg = Color(0xFFFFC66E);
const Color kConLiveDotGreen = Color(0xFF6EE7A8);
const Color kConLiveDotAmber = Color(0xFFFFC66E);
const Color kConLiveDotGrey = Color(0xFF7F8A7C);

/// Dawn (dark) ANSI Terminal Theme
const TerminalTheme kTerminalTheme = TerminalTheme(
  cursor: Color(0xFF7EE787),
  selection: Color(0x663B82F6),
  foreground: kTerminalFg,
  background: kTerminalBg,
  black: Color(0xFF7F8A7C),
  red: Color(0xFFFF7B72),
  green: Color(0xFF56D364),
  yellow: Color(0xFFE3B341),
  blue: Color(0xFF79B8FF),
  magenta: Color(0xFFD2A8FF),
  cyan: Color(0xFF56D4DD),
  white: Color(0xFFD0D7CE),
  brightBlack: Color(0xFF9AA596),
  brightRed: Color(0xFFFFA198),
  brightGreen: Color(0xFF7EE787),
  brightYellow: Color(0xFFF2CC60),
  brightBlue: Color(0xFFA5D6FF),
  brightMagenta: Color(0xFFE2C5FF),
  brightCyan: Color(0xFF8DE8EE),
  brightWhite: Color(0xFFFFFFFF),
  searchHitBackground: Color(0xFFF2CC60),
  searchHitBackgroundCurrent: Color(0xFF7EE787),
  searchHitForeground: Color(0xFF0B0C0B),
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

  static const TerminalPalette dark = TerminalPalette(
    brightness: Brightness.dark,
    bg: kConBg,
    barBg: kConBarBg,
    tabSelectedBg: kConTabSelectedBg,
    line: kConLine,
    text: kConText,
    textMuted: kConMuted,
    accent: kConAccent,
    accent2: kConAccent2,
    snipsBg: kConSnipsBg,
    chipOffBg: kConChipOffBg,
    chipOnBg: kConChipOnBg,
    chipOnFg: kConChipOnFg,
    liveDotGreen: kConLiveDotGreen,
    liveDotAmber: kConLiveDotAmber,
    liveDotGrey: kConLiveDotGrey,
    termBg: kTerminalBg,
    termFg: kTerminalFg,
    termTheme: kTerminalTheme,
  );

  static const TerminalPalette light = TerminalPalette(
    brightness: Brightness.light,
    bg: Color(0xFFF2F3F9),
    barBg: Color(0xFFECEEF6),
    tabSelectedBg: kTerminalLightBg,
    line: Color(0xFFDCDDEB),
    text: Color(0xFF141726),
    textMuted: Color(0xFF565C78),
    accent: Color(0xFF4B3FD1),
    accent2: Color(0xFF6B55FF),
    snipsBg: Color(0xFFF4F5FB),
    chipOffBg: Color(0x14000000),
    chipOnBg: Color(0x1F805300),
    chipOnFg: Color(0xFF805300),
    liveDotGreen: Color(0xFF11683F),
    liveDotAmber: Color(0xFF805300),
    liveDotGrey: Color(0xFF6D7190),
    termBg: kTerminalLightBg,
    termFg: kTerminalLightFg,
    termTheme: kTerminalLightTheme,
  );

  static TerminalPalette of(Brightness brightness) => brightness == Brightness.dark ? dark : light;
}

extension TerminalPaletteContext on BuildContext {
  TerminalPalette get terminalPalette => TerminalPalette.of(ax.brightness);
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
