import 'package:flutter/material.dart';

/// The accent choices offered in Settings > Appearance. Each has a variant
/// tuned for the dark palette and one for the light palette so that accent
/// coloured text and icons meet the contrast targets on both.
enum AxAccent {
  /// The Archangel OS default: indigo on Pearl (light), teal on Dawn (dark).
  halo('Halo', Color(0xFF8FE3D6), Color(0xFF4B3FD1)),
  green('Green', Color(0xFF7EE787), Color(0xFF1A7431)),
  amber('Amber', Color(0xFFE3B341), Color(0xFF855400)),
  ice('Blue', Color(0xFF79B8FF), Color(0xFF0B5CAD)),
  ember('Red', Color(0xFFE5806B), Color(0xFFB3261E));

  const AxAccent(this.label, this.dark, this.light);
  final String label;
  final Color dark;
  final Color light;

  static AxAccent fromName(String? name) => AxAccent.values.firstWhere((a) => a.name == name, orElse: () => AxAccent.halo);
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
    required this.glass,
    required this.glassStrong,
    required this.glassBorder,
    required this.wallA,
    required this.wallB,
    required this.wallC,
    required this.orbA,
    required this.orbB,
    required this.orbC,
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

  /// Translucent fill for cards that sit on the wallpaper (Halo glass).
  final Color glass;

  /// Denser glass for bars, windows, docks and dialogs that need to stay
  /// readable over moving content.
  final Color glassStrong;

  /// The bright hairline around glass surfaces (decorative).
  final Color glassBorder;

  /// Wallpaper glow colours (top-left, bottom-right, centre highlight).
  final Color wallA;
  final Color wallB;
  final Color wallC;

  /// Light orbs used by the start-up animation.
  final Color orbA;
  final Color orbB;
  final Color orbC;

  /// Dawn Halo: deep navy with violet and teal light.
  static AxPalette dark(AxAccent a) {
    const surface = Color(0xFF151829);
    final accent = a.dark;
    return AxPalette(
      bg: const Color(0xFF0B0D1A),
      surface: surface,
      surfaceAlt: const Color(0xFF1B1E33),
      surfaceHigh: const Color(0xFF24273F),
      border: const Color(0xFF2C304B),
      outline: const Color(0xFF7C82A6),
      text: const Color(0xFFF4F5FB),
      textMuted: const Color(0xFFC2C6DC),
      textSubtle: const Color(0xFFA9AECB),
      accent: accent,
      onAccent: const Color(0xFF0B0D1A),
      accentWash: Color.alphaBlend(accent.withValues(alpha: 0.16), surface),
      success: const Color(0xFF6EE7A8),
      successWash: const Color(0xFF15302A),
      warning: const Color(0xFFFFC56B),
      warningWash: const Color(0xFF33291A),
      danger: const Color(0xFFFF9A8F),
      onDanger: const Color(0xFF0B0D1A),
      dangerWash: const Color(0xFF3A1E26),
      info: const Color(0xFFA8C0FF),
      infoWash: const Color(0xFF1D2547),
      scrim: const Color(0xB3050610),
      glass: const Color(0x14FFFFFF),
      glassStrong: const Color(0xE6161A2E),
      glassBorder: const Color(0x24FFFFFF),
      wallA: const Color(0xFF4E3FD0),
      wallB: const Color(0xFF0B8F8F),
      wallC: const Color(0x3A966EFF),
      orbA: const Color(0xFF6B55FF),
      orbB: const Color(0xFF19B8B0),
      orbC: const Color(0xFFC26BFF),
    );
  }

  /// Pearl Halo: soft pearl with lavender and mint light.
  static AxPalette light(AxAccent a) {
    const surface = Color(0xFFFFFFFF);
    final accent = a.light;
    return AxPalette(
      bg: const Color(0xFFF2F3F9),
      surface: surface,
      surfaceAlt: const Color(0xFFF4F4FA),
      surfaceHigh: const Color(0xFFE8E8F3),
      border: const Color(0xFFDCDDEB),
      outline: const Color(0xFF6D7190),
      text: const Color(0xFF141726),
      textMuted: const Color(0xFF4A5068),
      textSubtle: const Color(0xFF565C78),
      accent: accent,
      onAccent: const Color(0xFFFFFFFF),
      accentWash: Color.alphaBlend(accent.withValues(alpha: 0.12), surface),
      success: const Color(0xFF11683F),
      successWash: const Color(0xFFE3F5EC),
      warning: const Color(0xFF805300),
      warningWash: const Color(0xFFFFF1D6),
      danger: const Color(0xFFB3261E),
      onDanger: const Color(0xFFFFFFFF),
      dangerWash: const Color(0xFFFDE7E5),
      info: const Color(0xFF2457C5),
      infoWash: const Color(0xFFE4ECFF),
      scrim: const Color(0x66141726),
      glass: const Color(0xA6FFFFFF),
      glassStrong: const Color(0xE6FFFFFF),
      glassBorder: const Color(0xF2FFFFFF),
      wallA: const Color(0xFFD9D2FF),
      wallB: const Color(0xFFC6F0E8),
      wallC: const Color(0xA6FFD6E8),
      orbA: const Color(0xFF7D6BFF),
      orbB: const Color(0xFF3CCFC0),
      orbC: const Color(0xFFFF9BC8),
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
  final double sm = 10;
  final double md = 14;
  final double lg = 20;
  final double xl = 26;
  final double pill = 999;
}

/// Type scale. Nothing is below 12 sp; body is 14 sp. Colours are applied by
/// the widgets using the palette; families come from the app text theme.
/// Bundled font families (see pubspec.yaml `fonts:`): Inter for interface
/// text, IBM Plex Mono for the terminal, code and numbers.
const kUiFontFamily = 'Inter';
const kMonoFontFamily = 'IBMPlexMono';

class AxType {
  const AxType();
  TextStyle get caption => const TextStyle(fontFamily: kUiFontFamily, fontSize: 12, height: 1.35);
  TextStyle get body => const TextStyle(fontFamily: kUiFontFamily, fontSize: 14, height: 1.45);
  TextStyle get label => const TextStyle(fontFamily: kUiFontFamily, fontSize: 14, fontWeight: FontWeight.w600, height: 1.3);
  TextStyle get title =>
      const TextStyle(fontFamily: kUiFontFamily, fontSize: 16, fontWeight: FontWeight.w600, height: 1.3, letterSpacing: -0.16);
  TextStyle get headline =>
      const TextStyle(fontFamily: kUiFontFamily, fontSize: 24, fontWeight: FontWeight.w600, height: 1.2, letterSpacing: -0.48);

  /// The big plain-English sentence (Home's health line, wizard titles).
  TextStyle get display =>
      const TextStyle(fontFamily: kUiFontFamily, fontSize: 28, fontWeight: FontWeight.w600, height: 1.18, letterSpacing: -0.6);
  TextStyle get mono => const TextStyle(fontSize: 13, fontFamily: kMonoFontFamily, height: 1.4);

  /// Numbers on metric cards: IBM Plex Mono, tabular.
  TextStyle get metric => const TextStyle(
    fontSize: 24,
    fontFamily: kMonoFontFamily,
    fontWeight: FontWeight.w500,
    height: 1.1,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}

/// The Archangel design tokens as a [ThemeExtension]; read with `context.ax`.
@immutable
class ArchangelTheme extends ThemeExtension<ArchangelTheme> {
  const ArchangelTheme({required this.brightness, required this.accentChoice, required this.colors});

  factory ArchangelTheme.of(Brightness brightness, [AxAccent accent = AxAccent.halo]) => ArchangelTheme(
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
  ArchangelTheme lerp(ThemeExtension<ArchangelTheme>? other, double t) => other is ArchangelTheme ? (t < 0.5 ? this : other) : this;
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
ThemeData buildTheme(Brightness brightness, [AxAccent accent = AxAccent.halo]) {
  final ax = ArchangelTheme.of(brightness, accent);
  final c = ax.colors;
  final base = ThemeData(brightness: brightness, useMaterial3: true, fontFamily: kUiFontFamily);
  final textTheme = base.textTheme.apply(fontFamily: kUiFontFamily, bodyColor: c.text, displayColor: c.text);
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
        borderRadius: BorderRadius.circular(ax.radii.xl),
        side: BorderSide(color: c.border),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(ax.radii.xl))),
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
      backgroundColor: Colors.transparent,
      elevation: 0,
      height: 68,
      surfaceTintColor: Colors.transparent,
      indicatorColor: c.accentWash,
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(color: s.contains(WidgetState.selected) ? c.accent : c.textMuted)),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: s.contains(WidgetState.selected) ? c.text : c.textMuted),
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
