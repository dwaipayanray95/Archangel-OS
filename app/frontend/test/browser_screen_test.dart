import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:archangel/data/app_state.dart';
import 'package:archangel/ui/screens/browser/browser_chrome.dart';
import 'package:archangel/ui/screens/browser/web_view_host.dart';
import 'package:archangel/ui/shell/sidebar.dart';

import 'browser_test_utils.dart';
import 'test_utils.dart';

const _omnibox = ValueKey('browser-omnibox');

double _left(WidgetTester tester, Finder f) => tester.getTopLeft(f).dx;

Finder _iconButton(IconData icon) => find.widgetWithIcon(IconButton, icon);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  group('wide 1400x900, Simple layout (inside the shell)', () {
    testWidgets('tab strip, chrome row in order, omnibox, star and overflow menu', (tester) async {
      final harness = BrowserHarness(testBrowserService());
      AxWebControllers.factory = harness.make;
      addTearDown(() => AxWebControllers.factory = null);
      final app = await pumpAppShell(tester, backend: PairedConnection(), browser: harness.service);
      app.go(AxSection.browser);
      await _settle(tester);
      expect(tester.takeException(), isNull);

      expect(find.byType(AxSidebar), findsOneWidget);
      expect(find.descendant(of: find.byType(AxSidebar), matching: find.text('Browser')), findsOneWidget);

      // Tab strip: one tab and a "+".
      expect(find.byKey(const ValueKey('tab-t1')), findsOneWidget);
      expect(find.byTooltip('New tab'), findsOneWidget);
      expect(find.text('New tab'), findsOneWidget); // the tab's title

      // Chrome row, left to right: Back, Forward, Reload, omnibox, star, menu.
      final xs = [
        _left(tester, find.byTooltip('Back')),
        _left(tester, find.byTooltip('Forward')),
        _left(tester, find.byTooltip('Reload')),
        _left(tester, find.byKey(_omnibox)),
        _left(tester, find.byTooltip('Add bookmark')),
        _left(tester, find.byTooltip('More options')),
      ];
      expect(xs, orderedEquals([...xs]..sort()));
      expect(xs.toSet(), hasLength(6));

      // Everything on one row.
      final ys = [
        for (final t in ['Back', 'Forward', 'Reload', 'Add bookmark', 'More options']) tester.getCenter(find.byTooltip(t)).dy,
      ];
      for (final y in ys) {
        expect(y, closeTo(ys.first, 1));
      }
      expect(tester.getCenter(find.byKey(_omnibox)).dy, closeTo(ys.first, 1));

      // The star is inside the omnibox pill's right edge, the menu after it.
      expect(find.text('Search, or type an address'), findsOneWidget);

      await tester.tap(find.byTooltip('More options'));
      await _settle(tester);
      expect(find.text('History'), findsOneWidget);
      expect(find.text('Bookmarks'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('unpaired shows the usual empty state and builds no web view', (tester) async {
      final harness = BrowserHarness(testBrowserService());
      AxWebControllers.factory = harness.make;
      addTearDown(() => AxWebControllers.factory = null);
      final app = await pumpAppShell(tester);
      app.go(AxSection.browser);
      await _settle(tester);
      expect(find.text('Not connected to a server'), findsOneWidget);
      expect(find.text('Pair Archangel with a server to use the browser.'), findsOneWidget);
      expect(harness.controllers, isEmpty);
    });
  });

  group('no overflow', () {
    for (final (label, size) in [
      ('phone 390', const Size(390, 844)),
      ('Desktop window 340', const Size(340, 600)),
      ('tiny window 340x260', const Size(340, 260)),
      ('tablet 600', const Size(600, 800)),
      ('wide 1400', const Size(1400, 900)),
      ('wide 720 edge', const Size(720, 500)),
    ]) {
      testWidgets('empty tab at $label', (tester) async {
        await pumpBrowser(tester, size: size);
        expect(tester.takeException(), isNull);
        expect(find.text('Where to?'), findsOneWidget);
      });

      testWidgets('loaded page, http and long address at $label', (tester) async {
        await pumpBrowser(tester, size: size);
        await submitOmnibox(tester, 'http://a-rather-long-host-name.example.com/with/a/very/long/path/that/keeps/going?and=a&query=string');
        await _settle(tester);
        expect(tester.takeException(), isNull);
        expect(find.text('Not secure'), findsOneWidget);
      });
    }

    testWidgets('error, blocked and offline states at 340x260', (tester) async {
      final h = await pumpBrowser(tester, size: const Size(340, 260));
      await submitOmnibox(tester, 'example.com');
      h.first.setHistory(back: true);
      h.first.fail(AxWebErrorKind.certificate);
      await _settle(tester);
      expect(tester.takeException(), isNull);
      h.first.fail(AxWebErrorKind.offline);
      await _settle(tester);
      expect(tester.takeException(), isNull);
      await submitOmnibox(tester, 'file:///etc/passwd');
      await _settle(tester);
      expect(tester.takeException(), isNull);
    });
  });

  group('narrow chrome', () {
    for (final size in [const Size(390, 844), const Size(340, 600)]) {
      testWidgets('wraps to two rows at ${size.width.toInt()}, no tab strip', (tester) async {
        await pumpBrowser(tester, size: size);
        expect(find.byKey(const ValueKey('tab-t1')), findsNothing);
        expect(find.byTooltip('New tab'), findsNothing);

        final row1 = tester.getCenter(find.byKey(_omnibox)).dy;
        expect(tester.getCenter(find.byTooltip('Reload')).dy, closeTo(row1, 2));
        final row2 = tester.getCenter(find.byTooltip('Back')).dy;
        expect(row2, greaterThan(row1 + 20));
        for (final t in ['Forward', 'Add bookmark', 'More options', 'Show tabs']) {
          expect(tester.getCenter(find.byTooltip(t)).dy, closeTo(row2, 2), reason: t);
        }
        expect(tester.getCenter(find.byKey(const ValueKey('browser-tab-count'))).dy, closeTo(row2, 2));
        expect(find.text('1'), findsOneWidget);
        // The omnibox takes the width the reload button leaves.
        expect(tester.getRect(find.byKey(_omnibox)).right, lessThan(tester.getRect(find.byTooltip('Reload')).left + 1));
      });

      testWidgets('tab-count pill opens the tab list at ${size.width.toInt()}', (tester) async {
        final h = await pumpBrowser(tester, size: size);
        await submitOmnibox(tester, 'example.com');
        await tester.tap(find.byKey(const ValueKey('browser-tab-count')));
        await _settle(tester);
        expect(find.text('Tabs'), findsOneWidget);
        expect(find.byKey(const ValueKey('tab-row-t1')), findsOneWidget);
        expect(tester.getSize(find.byKey(const ValueKey('tab-row-t1'))).height, 54);
        expect(find.text('example.com'), findsNWidgets(2)); // title and host
        expect(find.widgetWithText(FilledButton, 'New tab'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.tap(find.widgetWithText(FilledButton, 'New tab'));
        await _settle(tester);
        expect(h.controllers, hasLength(2));
        expect(find.text('Where to?'), findsOneWidget);
        expect(find.text('2'), findsOneWidget);
      });
    }

    testWidgets('only the selected tab is mounted; switching reloads the last address', (tester) async {
      final h = await pumpBrowser(tester, size: const Size(390, 844));
      await submitOmnibox(tester, 'one.com');
      final one = h.controllers[0];
      expect(one.mounted, 1);

      await tester.tap(find.byKey(const ValueKey('browser-tab-count')));
      await _settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'New tab'));
      await _settle(tester);
      await submitOmnibox(tester, 'two.com');
      final two = h.controllers[1];
      expect(two.mounted, 1);
      expect(one.mounted, 0, reason: 'a background tab must not stay mounted on a narrow screen');
      expect(one.currentUrl.toString(), 'https://one.com'); // its address is kept

      await tester.tap(find.byKey(const ValueKey('browser-tab-count')));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('tab-row-t1')));
      await _settle(tester);
      expect(one.mounted, 1);
      expect(one.mountCount, 2, reason: 'the view is built again and shows the last address');
      expect(two.mounted, 0);
    });
  });

  group('omnibox', () {
    testWidgets('example.com loads https://example.com', (tester) async {
      final h = await pumpBrowser(tester);
      await submitOmnibox(tester, 'example.com');
      expect(h.first.loaded.single.toString(), 'https://example.com');
      expect(find.text('Not secure'), findsNothing);
    });

    testWidgets('words search DuckDuckGo', (tester) async {
      final h = await pumpBrowser(tester);
      await submitOmnibox(tester, 'hello world');
      expect(h.first.loaded.single.toString(), 'https://duckduckgo.com/?q=hello+world');
    });

    testWidgets('file:///etc/passwd shows the blocked state and loads nothing', (tester) async {
      final h = await pumpBrowser(tester);
      await submitOmnibox(tester, 'file:///etc/passwd');
      expect(h.first.loaded, isEmpty);
      expect(find.text("Archangel OS won't open that kind of link"), findsOneWidget);
      expect(find.text('It only opens web pages — addresses starting with http or https.'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Back'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Back'));
      await _settle(tester);
      expect(find.text("Archangel OS won't open that kind of link"), findsNothing);
      expect(find.text('Where to?'), findsOneWidget);
    });

    testWidgets('http://x.com loads and shows Not secure', (tester) async {
      final h = await pumpBrowser(tester);
      await submitOmnibox(tester, 'http://x.com');
      expect(h.first.loaded.single.toString(), 'http://x.com');
      expect(find.text('Not secure'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });

    testWidgets('an in-page link to a blocked scheme is refused too', (tester) async {
      final h = await pumpBrowser(tester);
      await submitOmnibox(tester, 'example.com');
      h.first.emit(AxWebNavigation(AxWebNavigationKind.started, Uri.parse('javascript:alert(1)')));
      await _settle(tester);
      expect(find.text("Archangel OS won't open that kind of link"), findsOneWidget);
      expect(h.first.stops, greaterThan(0));
      // Nothing was recorded for it.
      expect(h.first.loaded.map((u) => u.scheme), everyElement('https'));
    });

    testWidgets('focus shows the full address, all selected', (tester) async {
      await pumpBrowser(tester);
      await submitOmnibox(tester, 'https://example.com/docs/page');
      await tester.tap(find.byKey(_omnibox));
      await tester.pump();
      await tester.pump();
      final field = tester.widget<TextField>(find.byKey(_omnibox));
      expect(field.controller!.text, 'https://example.com/docs/page');
      expect(field.controller!.selection, const TextSelection(baseOffset: 0, extentOffset: 29));
    });

    testWidgets('the address is styled with the host in full colour and the rest muted', (tester) async {
      await pumpBrowser(tester);
      await submitOmnibox(tester, 'https://example.com/docs/page');
      final editable = tester.widget<EditableText>(find.descendant(of: find.byKey(_omnibox), matching: find.byType(EditableText)));
      final span = editable.controller.buildTextSpan(context: tester.element(find.byKey(_omnibox)), withComposing: false);
      final parts = span.children!.cast<TextSpan>();
      expect(parts.map((p) => p.text), ['https://', 'example.com', '/docs/page']);
      expect(parts[1].style!.color, isNot(parts[0].style!.color));
      expect(parts[0].style!.color, parts[2].style!.color);
    });
  });

  group('tabs', () {
    testWidgets('open, select and close', (tester) async {
      final h = await pumpBrowser(tester);
      await submitOmnibox(tester, 'one.com');
      await tester.tap(find.byTooltip('New tab'));
      await _settle(tester);
      expect(h.controllers, hasLength(2));
      expect(find.byKey(const ValueKey('tab-t2')), findsOneWidget);
      await submitOmnibox(tester, 'two.com');

      // Select the first tab again.
      await tester.tap(find.byKey(const ValueKey('tab-t1')));
      await _settle(tester);
      final field = tester.widget<TextField>(find.byKey(_omnibox));
      expect(field.controller!.text, 'https://one.com');

      // Both stay mounted on a wide window.
      expect(h.controllers[0].mounted, 1);
      expect(h.controllers[1].mounted, 1);

      // Close the selected tab: the other becomes the selected one.
      await tester.tap(find.byKey(const ValueKey('tab-close-t1')));
      await _settle(tester);
      expect(find.byKey(const ValueKey('tab-t1')), findsNothing);
      expect(h.controllers[0].disposed, isTrue);
      expect(tester.widget<TextField>(find.byKey(_omnibox)).controller!.text, 'https://two.com');
    });

    testWidgets('closing the last tab leaves one empty tab', (tester) async {
      final h = await pumpBrowser(tester);
      await submitOmnibox(tester, 'one.com');
      await tester.tap(find.byKey(const ValueKey('tab-close-t1')));
      await _settle(tester);
      expect(find.byKey(const ValueKey('tab-t1')), findsNothing);
      expect(find.byKey(const ValueKey('tab-t2')), findsOneWidget);
      expect(h.controllers, hasLength(2));
      expect(find.text('Where to?'), findsOneWidget);
    });

    testWidgets('twelve tabs is the cap: "+" is disabled with its tooltip', (tester) async {
      final h = await pumpBrowser(tester);
      for (var i = 0; i < 11; i++) {
        await tester.tap(find.widgetWithIcon(IconButton, Icons.add));
        await tester.pump();
      }
      await _settle(tester);
      expect(h.controllers, hasLength(12));
      expect(find.byTooltip("That's as many tabs as Archangel OS keeps open."), findsOneWidget);
      expect(find.byTooltip('New tab'), findsNothing);
      final plus = tester.widget<IconButton>(_iconButton(Icons.add));
      expect(plus.onPressed, isNull);
      expect(tester.takeException(), isNull);

      // Closing one brings "+" back.
      await tester.tap(find.byKey(const ValueKey('tab-close-t12')));
      await _settle(tester);
      expect(tester.widget<IconButton>(_iconButton(Icons.add)).onPressed, isNotNull);
    });

    testWidgets('narrow: "New tab" is disabled at the cap', (tester) async {
      final h = await pumpBrowser(tester, size: const Size(390, 844));
      for (var i = 0; i < 11; i++) {
        await tester.tap(find.byKey(const ValueKey('browser-tab-count')));
        await _settle(tester);
        await tester.tap(find.widgetWithText(FilledButton, 'New tab'));
        await _settle(tester);
      }
      expect(h.controllers, hasLength(12));
      await tester.tap(find.byKey(const ValueKey('browser-tab-count')));
      await _settle(tester);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'New tab')).onPressed, isNull);
      expect(find.byTooltip("That's as many tabs as Archangel OS keeps open."), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('back, forward, reload and progress', () {
    testWidgets('back and forward follow the controller', (tester) async {
      final h = await pumpBrowser(tester);
      await submitOmnibox(tester, 'example.com');
      expect(tester.widget<IconButton>(_iconButton(Icons.arrow_back)).onPressed, isNull);
      expect(tester.widget<IconButton>(_iconButton(Icons.arrow_forward)).onPressed, isNull);

      h.first.setHistory(back: true);
      await tester.pump();
      expect(tester.widget<IconButton>(_iconButton(Icons.arrow_back)).onPressed, isNotNull);
      expect(tester.widget<IconButton>(_iconButton(Icons.arrow_forward)).onPressed, isNull);

      h.first.setHistory(back: true, forward: true);
      await tester.pump();
      await tester.tap(find.byTooltip('Forward'));
      await tester.tap(find.byTooltip('Back'));
      expect(h.first.forwards, 1);
      expect(h.first.backs, 1);
    });

    testWidgets('Reload becomes Stop while loading, and the progress line goes away when done', (tester) async {
      final harness = BrowserHarness(testBrowserService())..autoFinish = false;
      await pumpBrowser(tester, harness: harness);
      final h = harness;
      await submitOmnibox(tester, 'example.com');
      expect(find.byTooltip('Stop'), findsOneWidget);
      expect(find.byTooltip('Reload'), findsNothing);
      expect(find.byIcon(Icons.close), findsWidgets);
      expect(find.byKey(const ValueKey('browser-progress')), findsOneWidget);

      h.first.setProgress(0.5);
      await tester.pump();
      final bar = tester.getSize(find.byKey(const ValueKey('browser-progress')));
      expect(bar.height, 2);
      final track = tester.getSize(find.byType(BrowserProgressLine)).width;
      expect(bar.width, closeTo(track * 0.5, 1));

      await tester.tap(find.byTooltip('Stop'));
      await tester.pump();
      expect(h.first.stops, 1);
      expect(find.byTooltip('Reload'), findsOneWidget);
      expect(find.byKey(const ValueKey('browser-progress')), findsNothing);

      h.first.setProgress(0.9);
      await tester.pump();
      expect(find.byKey(const ValueKey('browser-progress')), findsOneWidget);
      h.first.finishLoading();
      await tester.pump();
      expect(find.byKey(const ValueKey('browser-progress')), findsNothing, reason: 'removed, not left at 100%');
      expect(find.byTooltip('Reload'), findsOneWidget);
    });

    testWidgets('Reload reloads the page', (tester) async {
      final h = await pumpBrowser(tester);
      await submitOmnibox(tester, 'example.com');
      await tester.tap(find.byTooltip('Reload'));
      await tester.pump();
      expect(h.first.reloads, 1);
    });

    testWidgets('Reload is off before anything is loaded', (tester) async {
      await pumpBrowser(tester);
      expect(tester.widget<IconButton>(_iconButton(Icons.refresh)).onPressed, isNull);
    });
  });

  group('states', () {
    testWidgets('new tab: exact text and the most-visited chips (at most 6)', (tester) async {
      final svc = testBrowserService();
      for (var i = 0; i < 8; i++) {
        svc.recordVisit('https://site$i.com/page');
      }
      svc.recordVisit('https://site0.com/other');
      final h = await pumpBrowser(tester, service: svc);
      expect(find.text('Where to?'), findsOneWidget);
      expect(find.text('Type an address, or search. Pages open on this device.'), findsOneWidget);
      final chips = find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('site-'));
      expect(chips, findsNWidgets(6));
      expect(find.text('site0.com'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('site-site0.com')));
      await tester.pump();
      expect(h.first.loaded.single.toString(), 'https://site0.com/');
      await svc.flush();
    });

    testWidgets('load error: reasons, Try again, Go back only when there is a back', (tester) async {
      final h = await pumpBrowser(tester);
      await submitOmnibox(tester, 'example.com');

      Future<void> expectReason(AxWebErrorKind kind, String message) async {
        h.first.fail(kind);
        await tester.pump();
        expect(find.text("Couldn't open this page"), findsOneWidget);
        expect(find.text(message), findsOneWidget);
        expect(find.widgetWithText(FilledButton, 'Try again'), findsOneWidget);
      }

      await expectReason(AxWebErrorKind.notFound, "That address doesn't exist.");
      expect(find.text('Go back'), findsNothing);
      await expectReason(AxWebErrorKind.timeout, 'The connection timed out.');
      await expectReason(AxWebErrorKind.certificate, "That site's security certificate isn't valid.");
      await expectReason(AxWebErrorKind.other, 'Something went wrong loading that page.');

      h.first.setHistory(back: true);
      await tester.pump();
      expect(find.text('Go back'), findsOneWidget);
      await tester.tap(find.text('Go back'));
      await tester.pump();
      expect(h.first.backs, 1);
      expect(find.text("Couldn't open this page"), findsNothing);

      h.first.fail(AxWebErrorKind.timeout);
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Try again'));
      await tester.pump();
      expect(h.first.loaded.map((u) => u.toString()), ['https://example.com', 'https://example.com']);
      expect(find.text("Couldn't open this page"), findsNothing);
    });

    testWidgets('offline: exact text and Try again', (tester) async {
      final h = await pumpBrowser(tester);
      await submitOmnibox(tester, 'example.com');
      h.first.fail(AxWebErrorKind.offline);
      await tester.pump();
      expect(find.text("You're not connected to the internet"), findsOneWidget);
      expect(find.text('Check your connection, then try again.'), findsOneWidget);
      expect(find.text("Couldn't open this page"), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, 'Try again'));
      await tester.pump();
      expect(h.first.loaded, hasLength(2));
      expect(find.text("You're not connected to the internet"), findsNothing);
    });

    testWidgets('words never mention the web view or promise routing through the server', (tester) async {
      final h = await pumpBrowser(tester);
      final all = <String>[];
      void collect() => all.addAll(tester.widgetList<Text>(find.byType(Text)).map((t) => t.data ?? t.textSpan?.toPlainText() ?? ''));
      collect();
      await submitOmnibox(tester, 'file:///x');
      collect();
      await submitOmnibox(tester, 'example.com');
      h.first.fail(AxWebErrorKind.offline);
      await tester.pump();
      collect();
      final joined = all.join(' ').toLowerCase();
      for (final banned in ['webview', 'wkwebview', 'renderer', 'engine', 'through your server', 'vpn', 'tunnel', 'private browsing']) {
        expect(joined.contains(banned), isFalse, reason: banned);
      }
    });
  });

  group('history is recorded from navigation', () {
    testWidgets('a committed main-frame visit is recorded once; a reload within 60 s is not', (tester) async {
      var clock = DateTime.utc(2026, 10, 27, 12);
      final svc = testBrowserService(now: () => clock);
      final h = await pumpBrowser(tester, service: svc);
      await submitOmnibox(tester, 'example.com');
      expect(svc.history, hasLength(1));
      expect(svc.history.single.url, 'https://example.com');
      expect(svc.history.single.title, 'example.com');

      clock = clock.add(const Duration(seconds: 20));
      await tester.tap(find.byTooltip('Reload'));
      await tester.pump();
      expect(h.first.reloads, 1);
      expect(svc.history, hasLength(1));

      clock = clock.add(const Duration(minutes: 5));
      await tester.tap(find.byTooltip('Reload'));
      await tester.pump();
      expect(svc.history, hasLength(2));
      await svc.flush();
    });

    testWidgets('not recorded: redirects, subframes, blank pages, blocked links', (tester) async {
      final svc = testBrowserService();
      final h = await pumpBrowser(tester, service: svc);
      await submitOmnibox(tester, 'about:blank');
      h.first.navigateInPage(Uri.parse('https://ads.example.net/frame'), mainFrame: false);
      h.first.navigateInPage(Uri.parse('https://redirected.com/'), redirect: true);
      await submitOmnibox(tester, 'file:///etc/passwd');
      expect(svc.history, isEmpty);

      h.first.navigateInPage(Uri.parse('https://link.com/'));
      expect(svc.history.map((v) => v.url), ['https://link.com/']);
      await svc.flush();
    });

    testWidgets('the page title is saved once it arrives', (tester) async {
      final svc = testBrowserService();
      final harness = BrowserHarness(svc);
      await pumpBrowser(tester, service: svc, harness: harness);
      harness.first.titles['example.com'] = 'Example Domain';
      await submitOmnibox(tester, 'example.com');
      expect(svc.history.single.title, 'Example Domain');
      await svc.flush();
    });
  });
}
