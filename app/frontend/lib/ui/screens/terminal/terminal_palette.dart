import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

/// The terminal's own colour palette. A terminal is always dark (programs
/// assume a dark or light background of their choosing, and the 16 ANSI
/// colours must stay distinguishable), so this does not follow the app
/// theme. Every foreground colour here reaches >= 4.5:1 on [kTerminalBg];
/// test/screens/terminal_palette_test.dart enforces it.
const Color kTerminalBg = Color(0xFF0B0C0B);
const Color kTerminalFg = Color(0xFFE9EFE7);

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
