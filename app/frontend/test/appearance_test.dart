import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:archangel/data/app_state.dart';
import 'package:archangel/ui/theme.dart';
import 'test_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await useTempKvStore();
  });

  test('theme mode and accent persist across restarts', () async {
    final a = AppState();
    expect(a.themeMode, kDefaultThemeMode);
    expect(a.accentChoice, AxAccent.halo);
    a.themeMode = ThemeMode.dark;
    a.accentChoice = AxAccent.ice;
    // Writes are fire-and-forget; give the file IO a moment.
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final b = AppState();
    await b.loadAppearance();
    expect(b.themeMode, ThemeMode.dark);
    expect(b.accentChoice, AxAccent.ice);
    expect(b.accent, AxAccent.ice.dark);
  });

  test('the legacy colour setter maps onto the accent choices', () {
    final a = AppState();
    a.accent = AxAccent.amber.dark;
    expect(a.accentChoice, AxAccent.amber);
  });

  test('unknown stored values fall back to defaults', () async {
    final a = AppState();
    await a.loadAppearance();
    expect(a.themeMode, kDefaultThemeMode);
  });

  test('buildTheme attaches the tokens for each brightness', () {
    for (final b in Brightness.values) {
      final t = buildTheme(b, AxAccent.amber);
      final ax = t.extension<ArchangelTheme>()!;
      expect(ax.brightness, b);
      expect(t.brightness, b);
      expect(ax.colors.accent, b == Brightness.dark ? AxAccent.amber.dark : AxAccent.amber.light);
    }
  });

  group('start-up sound', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('is on by default on computers and off on phones', () {
      for (final on in [TargetPlatform.macOS, TargetPlatform.windows, TargetPlatform.linux]) {
        debugDefaultTargetPlatformOverride = on;
        expect(AppState().startupSound, isTrue, reason: '$on');
      }
      for (final off in [TargetPlatform.android, TargetPlatform.iOS]) {
        debugDefaultTargetPlatformOverride = off;
        expect(AppState().startupSound, isFalse, reason: '$off');
      }
    });

    test('the choice persists across restarts', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final a = AppState()..startupSound = false;
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final b = AppState();
      await b.loadAppearance();
      expect(b.startupSound, isFalse);
      b.startupSound = true;
      await Future<void>.delayed(const Duration(milliseconds: 100));
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final c = AppState();
      await c.loadAppearance();
      expect(c.startupSound, isTrue, reason: 'a saved choice beats the platform default');
      expect(a.startupSound, isFalse);
    });
  });
}
