import 'package:flutter/material.dart';
import 'tokens.dart';

ThemeData buildAppTheme({Color accent = AxColors.accent}) {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: AxColors.bg,
    colorScheme: base.colorScheme.copyWith(
      surface: AxColors.bg,
      primary: accent,
      secondary: accent,
    ),
    textTheme: base.textTheme.apply(
      fontFamily: 'Inter',
      bodyColor: AxColors.fg,
      displayColor: AxColors.fg,
    ),
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    hoverColor: AxColors.s3,
    dividerColor: AxColors.line,
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStateProperty.all(AxColors.fg.withValues(alpha: 0.13)),
      radius: const Radius.circular(999),
      thickness: WidgetStateProperty.all(6),
    ),
  );
}
