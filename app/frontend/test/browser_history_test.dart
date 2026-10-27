import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:archangel/services/browser_service.dart';
import 'package:archangel/ui/ui.dart';

import 'browser_test_utils.dart';
import 'test_utils.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _openMenu(WidgetTester tester, String entry) async {
  await tester.tap(find.byTooltip('More options'));
  await _settle(tester);
  await tester.tap(find.text(entry));
  await _settle(tester);
}

/// A service holding three visits: one today, one yesterday, one in 2025.
BrowserService _seeded() {
  final n = DateTime.now();
  var clock = DateTime(2025, 9, 2, 9, 41);
  final svc = testBrowserService(now: () => clock);
  svc.recordVisit('https://old.example.org/page', title: 'Old page');
  clock = DateTime(n.year, n.month, n.day, 12).subtract(const Duration(days: 1));
  svc.recordVisit('https://yesterday.example.org/', title: 'Yesterday page');
  clock = DateTime(n.year, n.month, n.day, 9, 5);
  svc.recordVisit('https://today.example.org/', title: 'Today page');
  return svc;
}

void main() {
  group('history', () {
    testWidgets('groups by Today / Yesterday / date, newest first', (tester) async {
      final svc = _seeded();
      await pumpBrowser(tester, service: svc);
      await _openMenu(tester, 'History');

      expect(find.text('History'), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Yesterday'), findsOneWidget);
      expect(find.text('2 Sep 2025'), findsOneWidget);
      expect(find.text('Today page'), findsOneWidget);
      expect(find.text('today.example.org · 09:05'), findsOneWidget);
      expect(find.text('old.example.org · 09:41'), findsOneWidget);

      final today = tester.getTopLeft(find.text('Today page')).dy;
      final yesterday = tester.getTopLeft(find.text('Yesterday page')).dy;
      final old = tester.getTopLeft(find.text('Old page')).dy;
      expect(today, lessThan(yesterday));
      expect(yesterday, lessThan(old));
      expect(tester.takeException(), isNull);
      await svc.flush();
    });

    testWidgets('filter field narrows the list', (tester) async {
      final svc = _seeded();
      await pumpBrowser(tester, service: svc);
      await _openMenu(tester, 'History');
      await tester.enterText(find.widgetWithText(TextField, 'Filter history'), 'yester');
      await tester.pumpAndSettle();
      expect(find.text('Yesterday page'), findsOneWidget);
      expect(find.text('Today page'), findsNothing);
      expect(find.text('Old page'), findsNothing);

      await tester.enterText(find.widgetWithText(TextField, 'Filter history'), 'zzz');
      await tester.pumpAndSettle();
      expect(find.text('Nothing matches "zzz"'), findsOneWidget);
      await svc.flush();
    });

    testWidgets('delete a row', (tester) async {
      final svc = _seeded();
      await pumpBrowser(tester, service: svc);
      await _openMenu(tester, 'History');
      final row = find.ancestor(of: find.text('Yesterday page'), matching: find.byType(InkWell)).first;
      await tester.tap(find.descendant(of: row, matching: find.byTooltip('Delete from history')));
      await _settle(tester);
      expect(find.text('Yesterday page'), findsNothing);
      expect(find.text('Yesterday'), findsNothing);
      expect(svc.history, hasLength(2));
      await svc.flush();
    });

    testWidgets('Clear history asks first, and Cancel keeps everything', (tester) async {
      final svc = _seeded();
      await pumpBrowser(tester, service: svc);
      await _openMenu(tester, 'History');

      await tester.tap(find.widgetWithText(FilledButton, 'Clear history'));
      await _settle(tester);
      expect(find.byType(ConfirmDialog), findsOneWidget);
      expect(find.text('Clear history?'), findsOneWidget);
      expect(find.text("This removes every page Archangel OS remembers you visiting on this device. It can't be undone."), findsOneWidget);
      expect(svc.history, hasLength(3), reason: 'nothing is removed before the person confirms');

      await tester.tap(find.text('Cancel'));
      await _settle(tester);
      expect(find.byType(ConfirmDialog), findsNothing);
      expect(svc.history, hasLength(3));

      await tester.tap(find.widgetWithText(FilledButton, 'Clear history'));
      await _settle(tester);
      await tester.tap(find.descendant(of: find.byType(ConfirmDialog), matching: find.text('Clear history')));
      await _settle(tester);
      expect(svc.history, isEmpty);
      expect(find.text('No history yet'), findsOneWidget);
      expect(find.text('Pages you visit will show up here.'), findsOneWidget);
      await svc.flush();
    });

    testWidgets('tapping a row opens that page in the current tab', (tester) async {
      final svc = _seeded();
      final h = await pumpBrowser(tester, service: svc);
      await _openMenu(tester, 'History');
      await tester.tap(find.text('Yesterday page'));
      await _settle(tester);
      expect(h.first.loaded.single.toString(), 'https://yesterday.example.org/');
      expect(find.text('History'), findsNothing);
      await svc.flush();
    });

    testWidgets('narrow: Clear history is an icon button, no overflow at 340 and 390', (tester) async {
      for (final w in [340.0, 390.0]) {
        final svc = _seeded();
        await pumpBrowser(tester, service: svc, size: Size(w, 700), key: ValueKey('h$w'));
        await _openMenu(tester, 'History');
        expect(find.byTooltip('Clear history'), findsOneWidget);
        expect(find.widgetWithText(FilledButton, 'Clear history'), findsNothing);
        expect(tester.takeException(), isNull, reason: '$w');
        await tester.tap(find.byTooltip('Back to the page'));
        await _settle(tester);
        expect(find.text('Where to?'), findsOneWidget);
        await svc.flush();
      }
    });

    testWidgets('history stays mounted behind the list on a wide window', (tester) async {
      final svc = _seeded();
      final h = await pumpBrowser(tester, service: svc);
      await submitOmnibox(tester, 'example.com');
      await _openMenu(tester, 'History');
      expect(h.first.mounted, 1);
      expect(h.first.mountCount, 1);
      await tester.tap(find.byTooltip('Back to the page'));
      await _settle(tester);
      expect(h.first.mountCount, 1, reason: 'the page was not rebuilt');
      await svc.flush();
    });
  });

  group('bookmarks', () {
    testWidgets('the star toggles and the tooltip follows', (tester) async {
      final svc = testBrowserService();
      await pumpBrowser(tester, service: svc);
      // Nothing to bookmark on a new tab.
      expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.star_border_rounded)).onPressed, isNull);

      await submitOmnibox(tester, 'example.com');
      expect(find.byIcon(Icons.star_border_rounded), findsOneWidget);
      await tester.tap(find.byTooltip('Add bookmark'));
      await tester.pump();
      expect(find.byTooltip('Remove bookmark'), findsOneWidget);
      expect(find.byIcon(Icons.star_rounded), findsOneWidget);
      expect(svc.isBookmarked('https://example.com'), isTrue);
      expect(svc.bookmarks.single.title, 'example.com');

      await tester.tap(find.byTooltip('Remove bookmark'));
      await tester.pump();
      expect(find.byTooltip('Add bookmark'), findsOneWidget);
      expect(svc.bookmarks, isEmpty);
      await svc.flush();
    });

    testWidgets('a bookmark survives a fresh State and shows in the list', (tester) async {
      final svc = testBrowserService();
      await pumpBrowser(tester, service: svc, key: const ValueKey('first'));
      await submitOmnibox(tester, 'example.com');
      await tester.tap(find.byTooltip('Add bookmark'));
      await tester.pump();

      // A new key gives the screen a fresh State (new tabs, same service).
      await pumpBrowser(tester, harness: BrowserHarness(svc), key: const ValueKey('second'));
      await tester.pump();
      expect(find.text('Where to?'), findsOneWidget);
      await submitOmnibox(tester, 'example.com');
      expect(find.byTooltip('Remove bookmark'), findsOneWidget);

      await _openMenu(tester, 'Bookmarks');
      expect(find.text('Bookmarks'), findsOneWidget);
      expect(find.byKey(ValueKey('bookmark-${svc.bookmarks.single.id}')), findsOneWidget);
      expect(find.text('example.com'), findsNWidgets(2)); // title and host
      expect(tester.takeException(), isNull);
      await svc.flush();
    });

    testWidgets('filter, open and delete in the bookmarks list', (tester) async {
      final svc = testBrowserService();
      svc.addBookmark('https://alpha.example.com/', title: 'Alpha site');
      svc.addBookmark('https://beta.example.com/', title: 'Beta site');
      final h = await pumpBrowser(tester, service: svc);
      await _openMenu(tester, 'Bookmarks');

      expect(find.text('Alpha site'), findsOneWidget);
      expect(find.text('Beta site'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'Filter bookmarks'), 'alp');
      await tester.pumpAndSettle();
      expect(find.text('Beta site'), findsNothing);

      await tester.tap(find.byTooltip('Delete bookmark'));
      await _settle(tester);
      expect(svc.bookmarks.map((b) => b.title), ['Beta site']);
      expect(find.text('Nothing matches "alp"'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'Filter bookmarks'), '');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Beta site'));
      await _settle(tester);
      expect(h.first.loaded.single.toString(), 'https://beta.example.com/');
    });

    testWidgets('empty list text', (tester) async {
      await pumpBrowser(tester);
      await _openMenu(tester, 'Bookmarks');
      expect(find.text('No bookmarks yet'), findsOneWidget);
      expect(find.text('Tap the star next to the address to keep a page here.'), findsOneWidget);
    });

    testWidgets('narrow: the star is in the second row and the list fits at 340', (tester) async {
      final svc = testBrowserService();
      svc.addBookmark(
        'https://a-rather-long-host-name.example.com/with/a/long/path',
        title: 'A very long title that cannot possibly fit on one line',
      );
      await pumpBrowser(tester, service: svc, size: const Size(340, 600));
      await _openMenu(tester, 'Bookmarks');
      expect(tester.takeException(), isNull);
    });

    testWidgets('saved with the real store: written inside runAsync, read back', (tester) async {
      await tester.runAsync(() async {
        await useTempKvStore();
        final first = BrowserService(now: () => DateTime(2026, 10, 27, 12), writeDelay: Duration.zero);
        first.addBookmark('https://example.com/', title: 'Example');
        first.recordVisit('https://example.com/', title: 'Example');
        await first.flush();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        first.dispose();

        final second = BrowserService();
        await second.load();
        expect(second.bookmarks.single.url, 'https://example.com/');
        expect(second.history.single.title, 'Example');
        second.dispose();
      });
    });
  });
}
