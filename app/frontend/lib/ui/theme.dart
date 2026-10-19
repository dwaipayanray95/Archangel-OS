import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// The accent choices offered in Settings > Appearance. Each has a variant
/// tuned for the dark palette and one for the light palette so that accent
/// coloured text and icons meet the contrast targets on both.
enum AxAccent {
  green('Green', Color(0xFF7EE787), Color(0xFF1A7431)),
  amber('Amber', Color(0xFFE3B341), Color(0xFF855400)),
  ice('Blue', Color(0xFF79B8FF), Color(0xFF0B5CAD)),
  ember('Red', Color(0xFFE5806B), Color(0xFFB3261E));

  const AxAccent(this.label, this.dark, this.light);
  final String label;
  final Color dark;
  final Color light;

  static AxAccent fromName(String? name) =>
      AxAccent.values.firstWhere((a) => a.name == name, orElse: () => AxAccent.green);
}

/// Every colour the UI may use. Nothing outside the theme files hard-codes
/// colours; widgets read these through `context.ax.colors`.
///
/// Contrast contract (enforced by test/ui/contrast_test.dart, both themes):
/// `text`, `textMuted`, `textSubtle` >= 4.5:1 on `bg`, `surface`,
/// `surfaceAlt` and `surfaceHigh`; the status colours and `accent` >= 4.5:1
/// on those and on their own wash; `outline` (borders/icons that convey
/// meaning) >= 3:1; `border` is decorative only.
@immutable
class AxPalette {
  const AxPalette({
    required this.bg,
    required this.surface,
    required this.surfaceAlt,
    required this.surfaceHigh,
    required this.border,
    required this.outline,
    required this.text,
    required this.textMuted,
    required this.textSubtle,
    required this.accent,
    required this.onAccent,
    required this.accentWash,
    required this.success,
    required this.successWash,
    required this.warning,
    required this.warningWash,
    required this.danger,
    required this.onDanger,
    required this.dangerWash,
    required this.info,
    required this.infoWash,
    required this.scrim,
  });

  final Color bg;
  final Color surface;
  final Color surfaceAlt;
  final Color surfaceHigh;

  /// Decorative dividers and card edges (not relied on to convey meaning).
  final Color border;

  /// Borders, icons and focus rings that carry meaning (>= 3:1).
  final Color outline;

  final Color text;
  final Color textMuted;
  final Color textSubtle;

  final Color accent;
  final Color onAccent;
  final Color accentWash;

  final Color success;
  final Color successWash;
  final Color warning;
  final Color warningWash;

  /// Danger as text/icon colour on surfaces, and as a button fill with
  /// [onDanger] on top.
  final Color danger;
  final Color onDanger;
  final Color dangerWash;
  final Color info;
  final Color infoWash;
  final Color scrim;

  static AxPalette dark(AxAccent a) {
    const surface = Color(0xFF121412);
    final accent = a.dark;
    return AxPalette(
      bg: const Color(0xFF0B0C0B),
      surface: surface,
      surfaceAlt: const Color(0xFF181B18),
      surfaceHigh: const Color(0xFF212520),
      border: const Color(0xFF2B302A),
      outline: const Color(0xFF788275),
      text: const Color(0xFFE9EFE7),
      textMuted: const Color(0xFFA8B2A4),
      textSubtle: const Color(0xFF929C8F),
      accent: accent,
      onAccent: const Color(0xFF0B0C0B),
      accentWash: Color.alphaBlend(accent.withValues(alpha: 0.16), surface),
      success: const Color(0xFF7EE787),
      successWash: const Color(0xFF17301B),
      warning: const Color(0xFFE3B341),
      warningWash: const Color(0xFF332A0F),
      danger: const Color(0xFFEF8F7A),
      onDanger: const Color(0xFF0B0C0B),
      dangerWash: const Color(0xFF3A1B16),
      info: const Color(0xFF79B8FF),
      infoWash: const Color(0xFF15283D),
      scrim: const Color(0xB3040504),
    );
  }

  static AxPalette light(AxAccent a) {
    const surface = Color(0xFFFFFFFF);
    final accent = a.light;
    return AxPalette(
      bg: const Color(0xFFF5F7F4),
      surface: surface,
      surfaceAlt: const Color(0xFFEEF2EC),
      surfaceHigh: const Color(0xFFE3E9E0),
      border: const Color(0xFFD3DBD0),
      outline: const Color(0xFF677262),
      text: const Color(0xFF141A13),
      textMuted: const Color(0xFF3F4A3C),
      textSubtle: const Color(0xFF4F5A4B),
      accent: accent,
      onAccent: const Color(0xFFFFFFFF),
      accentWash: Color.alphaBlend(accent.withValues(alpha: 0.12), surface),
      success: const Color(0xFF1A7431),
      successWash: const Color(0xFFDDF1E0),
      warning: const Color(0xFF855400),
      warningWash: const Color(0xFFFBEFCF),
      danger: const Color(0xFFB3261E),
      onDanger: const Color(0xFFFFFFFF),
      dangerWash: const Color(0xFFFBE3DF),
      info: const Color(0xFF0B5CAD),
      infoWash: const Color(0xFFDCEBFA),
      scrim: const Color(0x99000000),
    );
  }
}

/// Spacing scale (dp).
class AxSpace {
  const AxSpace();
  final double xs = 4;
  final double sm = 8;
  final double md = 12;
  final double lg = 16;
  final double xl = 24;
  final double xxl = 32;
}

/// Corner radii (dp).
class AxRadii {
  const AxRadii();
  final double sm = 8;
  final double md = 12;
  final double lg = 16;
  final double pill = 999;
}

/// Type scale. Nothing is below 12 sp; body is 14 sp. Colours are applied by
/// the widgets using the palette; families come from the app text theme.
class AxType {
  const AxType();
  TextStyle get caption => const TextStyle(fontSize: 12, height: 1.35);
  TextStyle get body => const TextStyle(fontSize: 14, height: 1.45);
  TextStyle get label => const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.3);
  TextStyle get title => const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, height: 1.3);
  TextStyle get headline => const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, height: 1.25);
  TextStyle get mono => const TextStyle(fontSize: 13, fontFamily: 'monospace', height: 1.4);
}

/// The Archangel design tokens as a [ThemeExtension]; read with `context.ax`.
@immutable
class ArchangelTheme extends ThemeExtension<ArchangelTheme> {
  const ArchangelTheme({
    required this.brightness,
    required this.accentChoice,
    required this.colors,
  });

  factory ArchangelTheme.of(Brightness brightness, [AxAccent accent = AxAccent.green]) => ArchangelTheme(
        brightness: brightness,
        accentChoice: accent,
        colors: brightness == Brightness.dark ? AxPalette.dark(accent) : AxPalette.light(accent),
      );

  final Brightness brightness;
  final AxAccent accentChoice;
  final AxPalette colors;

  final AxSpace space = const AxSpace();
  final AxRadii radii = const AxRadii();
  final AxType typo = const AxType();

  @override
  ArchangelTheme copyWith({Brightness? brightness, AxAccent? accentChoice}) =>
      ArchangelTheme.of(brightness ?? this.brightness, accentChoice ?? this.accentChoice);

  @override
  ArchangelTheme lerp(ThemeExtension<ArchangelTheme>? other, double t) =>
      other is ArchangelTheme ? (t < 0.5 ? this : other) : this;
}

extension ArchangelThemeContext on BuildContext {
  /// The Archangel design tokens for the current theme.
  ArchangelTheme get ax {
    final ext = Theme.of(this).extension<ArchangelTheme>();
    assert(ext != null, 'ArchangelTheme missing - build the app theme with buildTheme()');
    return ext ?? ArchangelTheme.of(Theme.of(this).brightness);
  }
}

/// Minimum interactive size: 48 dp on touch platforms, 36 dp with a pointer.
double axMinTarget(BuildContext context) {
  switch (Theme.of(context).platform) {
    case TargetPlatform.android:
    case TargetPlatform.iOS:
    case TargetPlatform.fuchsia:
      return 48;
    case TargetPlatform.linux:
    case TargetPlatform.macOS:
    case TargetPlatform.windows:
      return 36;
  }
}

/// Builds the Material theme for [brightness] with the Archangel tokens
/// attached as an extension.
ThemeData buildTheme(Brightness brightness, [AxAccent accent = AxAccent.green]) {
  final ax = ArchangelTheme.of(brightness, accent);
  final c = ax.colors;
  final base = ThemeData(brightness: brightness, useMaterial3: true);
  final textTheme = GoogleFonts.manropeTextTheme(base.textTheme).apply(bodyColor: c.text, displayColor: c.text);
  return base.copyWith(
    extensions: [ax],
    scaffoldBackgroundColor: c.bg,
    canvasColor: c.bg,
    colorScheme: base.colorScheme.copyWith(
      brightness: brightness,
      primary: c.accent,
      onPrimary: c.onAccent,
      secondary: c.accent,
      onSecondary: c.onAccent,
      surface: c.surface,
      onSurface: c.text,
      error: c.danger,
      onError: c.onDanger,
      outline: c.outline,
      outlineVariant: c.border,
    ),
    textTheme: textTheme,
    splashFactory: InkRipple.splashFactory,
    dividerColor: c.border,
    dividerTheme: DividerThemeData(color: c.border, space: 1, thickness: 1),
    hoverColor: c.surfaceHigh,
    focusColor: c.accent.withValues(alpha: 0.2),
    dialogTheme: DialogThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ax.radii.lg),
        side: BorderSide(color: c.border),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surfaceAlt,
      labelStyle: TextStyle(color: c.textMuted, fontSize: 14),
      hintStyle: TextStyle(color: c.textSubtle, fontSize: 14),
      helperStyle: TextStyle(color: c.textMuted, fontSize: 12),
      errorStyle: TextStyle(color: c.danger, fontSize: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ax.radii.md),
        borderSide: BorderSide(color: c.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ax.radii.md),
        borderSide: BorderSide(color: c.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ax.radii.md),
        borderSide: BorderSide(color: c.accent, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ax.radii.md),
        borderSide: BorderSide(color: c.danger),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: c.accentWash,
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(color: s.contains(WidgetState.selected) ? c.accent : c.textMuted),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: s.contains(WidgetState.selected) ? c.text : c.textMuted,
        ),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: c.surface,
      indicatorColor: c.accentWash,
      selectedIconTheme: IconThemeData(color: c.accent),
      unselectedIconTheme: IconThemeData(color: c.textMuted),
      selectedLabelTextStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.text),
      unselectedLabelTextStyle: TextStyle(fontSize: 14, color: c.textMuted),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.surfaceHigh,
      contentTextStyle: TextStyle(color: c.text, fontSize: 14),
      behavior: SnackBarBehavior.floating,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: c.surfaceHigh,
        borderRadius: BorderRadius.circular(ax.radii.sm),
        border: Border.all(color: c.outline),
      ),
      textStyle: TextStyle(color: c.text, fontSize: 12),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStateProperty.all(c.text.withValues(alpha: 0.25)),
      radius: const Radius.circular(999),
      thickness: WidgetStateProperty.all(6),
    ),
  );
}
