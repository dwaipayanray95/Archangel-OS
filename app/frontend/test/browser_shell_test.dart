import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:archangel/data/app_state.dart';
import 'package:archangel/screens/browser_screen.dart';
import 'package:archangel/ui/screens/browser/web_view_host.dart';
import 'package:archangel/ui/shell/desktop_customize.dart';
import 'package:archangel/ui/shell/desktop_prefs.dart';
import 'package:archangel/ui/shell/more_page.dart';
import 'package:archangel/ui/shell/sidebar.dart';
import 'package:archangel/ui/shell/destinations.dart';

import 'browser_test_utils.dart';
import 'test_utils.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

BrowserHarness _install() {
  final harness = BrowserHarness(testBrowserService());
  AxWebControllers.factory = harness.make;
  addTearDown(() => AxWebControllers.factory = null);
  return harness;
}

void main() {
  const phone = Size(390, 844);

  group('the Browser destination', () {
    test('sits after Terminal, so the phone bottom bar keeps its first four positions', () {
      expect(AxSection.values.indexOf(AxSection.browser), AxSection.values.indexOf(AxSection.terminal) + 1);
      expect(AxSection.values.take(4), [AxSection.home, AxSection.apps, AxSection.files, AxSection.terminal]);
      expect(axSectionLabels[AxSection.browser], 'Browser');
      expect(axSectionIcons[AxSection.browser], isNotNull);
      expect(axSectionSelectedIcons[AxSection.browser], isNotNull);
      expect(axMoreSections, contains(AxSection.browser));
    });

    test('saved Desktop mode arrangements load by name: old ones lack Browser, unknown names are ignored', () {
      final prefs = DesktopPrefs()
        ..applyJson({
          'pinned': ['home', 'files', 'settings', 'no-such-app'],
        });
      expect(prefs.pinned, [AxSection.home, AxSection.files, AxSection.settings]);
      expect(prefs.isPinned(AxSection.browser), isFalse);
      prefs.togglePin(AxSection.browser);
      expect(prefs.toJson()['pinned'], contains('browser'));
      expect(DesktopPrefs().pinned, contains(AxSection.browser)); // new installs pin everything
    });

    testWidgets('phone: it lives under More; the bottom bar is unchanged', (tester) async {
      final harness = _install();
      await pumpAppShell(tester, size: phone, backend: PairedConnection(), browser: harness.service);
      expect(find.descendant(of: find.byType(NavigationBar), matching: find.text('Browser')), findsNothing);

      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('More')));
      await _settle(tester);
      expect(find.byType(MorePage), findsOneWidget);
      expect(find.byKey(const ValueKey('more-browser')), findsOneWidget);
      expect(find.text('Open web pages in tabs. Pages open on this device.'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('more-browser')));
      await _settle(tester);
      expect(find.byType(BrowserScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('browser-tab-count')), findsOneWidget);
      expect(tester.takeException(), isNull);

      // The status strip's back arrow returns to More, like the other More pages.
      await tester.tap(find.byTooltip('Back to More'));
      await _settle(tester);
      expect(find.byKey(const ValueKey('more-browser')), findsOneWidget);
      expect(harness.controllers, hasLength(1));
    });

    testWidgets('phone: not paired shows the usual empty state', (tester) async {
      final harness = _install();
      final app = await pumpAppShell(tester, size: phone);
      app.go(AxSection.browser);
      await _settle(tester);
      expect(find.text('Not connected to a server'), findsOneWidget);
      expect(harness.controllers, isEmpty);
      await tester.tap(find.text('Connect a server'));
      await _settle(tester);
      expect(app.section, AxSection.settings);
    });

    testWidgets('sidebar: Browser sits between Terminal and Activity and opens the screen', (tester) async {
      final harness = _install();
      await pumpAppShell(tester, backend: PairedConnection(), browser: harness.service);
      final y = {for (final s in AxSection.values) s: tester.getTopLeft(find.byKey(ValueKey('side-${s.name}'))).dy};
      expect(y[AxSection.terminal]!, lessThan(y[AxSection.browser]!));
      expect(y[AxSection.browser]!, lessThan(y[AxSection.activity]!));
      await tester.tap(find.byKey(const ValueKey('side-browser')));
      await _settle(tester);
      expect(find.byType(AxSidebar), findsOneWidget);
      expect(find.byType(BrowserScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('command palette lists it under Sections and jumps there', (tester) async {
      final harness = _install();
      final app = await pumpAppShell(tester, backend: PairedConnection(), browser: harness.service);
      app.openPalette();
      await _settle(tester);
      await tester.enterText(find.byType(TextField).last, 'brow');
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Browser'), findsWidgets);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await _settle(tester);
      expect(app.section, AxSection.browser);
      expect(app.paletteOpen, isFalse);
    });

    testWidgets('Desktop mode: dock icon, launcher entry, customise switch, and a working window', (tester) async {
      final harness = _install();
      final prefs = DesktopPrefs();
      final app = await pumpAppShell(
        tester,
        layout: AxLayout.desktop,
        desktopPrefs: prefs,
        backend: PairedConnection(),
        browser: harness.service,
      );
      await _settle(tester);
      expect(find.byKey(const ValueKey('dock-browser')), findsOneWidget);

      // The launcher lists it.
      await tester.tap(find.byTooltip('All apps'));
      await _settle(tester);
      expect(find.text('Open web pages'), findsOneWidget);
      await tester.tap(find.text('Open web pages'));
      await _settle(tester);
      expect(find.byKey(const ValueKey('win-browser')), findsOneWidget);
      expect(app.section, AxSection.browser);
      expect(find.byType(BrowserScreen), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Customise can pin and unpin it.
      await tester.tap(find.byTooltip('Archangel OS menu'));
      await _settle(tester);
      await tester.tap(find.text('Customize Desktop…'));
      await _settle(tester);
      expect(find.byType(DesktopCustomizeDialog), findsOneWidget);
      final pin = find.byKey(const ValueKey('pin-browser'));
      await tester.ensureVisible(pin);
      await tester.tap(pin);
      await _settle(tester);
      expect(prefs.isPinned(AxSection.browser), isFalse);
    });

    testWidgets('Desktop mode: opening the browser from another screen raises its window', (tester) async {
      final harness = _install();
      final app = await pumpAppShell(tester, layout: AxLayout.desktop, backend: PairedConnection(), browser: harness.service);
      app.go(AxSection.browser);
      await _settle(tester);
      expect(find.byKey(const ValueKey('win-browser')), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(find.byType(BrowserScreen), findsOneWidget);
    });
  });
}
