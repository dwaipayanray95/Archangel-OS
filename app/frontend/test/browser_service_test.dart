import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:archangel/services/browser_service.dart';
import 'package:archangel/services/local_kv_store.dart';

import 'browser_test_utils.dart';
import 'test_utils.dart';

// These are plain tests (not widget tests), so real file IO is fine here.

void main() {
  late DateTime clock;
  DateTime now() => clock;

  setUp(() => clock = DateTime.utc(2026, 10, 27, 12));

  BrowserService make(MemoryBrowserStore store, {Duration delay = const Duration(milliseconds: 20)}) =>
      BrowserService(store: store, now: now, writeDelay: delay);

  group('history', () {
    test('a visit is recorded once with url, title, host and times', () {
      final svc = make(MemoryBrowserStore());
      final id = svc.recordVisit('https://example.com/a', title: 'Example');
      expect(id, isNotNull);
      expect(svc.history, hasLength(1));
      final v = svc.history.single;
      expect(v.url, 'https://example.com/a');
      expect(v.title, 'Example');
      expect(v.host, 'example.com');
      expect(v.visitedAt, clock);
      expect(v.updatedAt, clock);
      expect(v.id, isNotEmpty);
      svc.dispose();
    });

    test('a reload of the same address within 60 s is not recorded, after 60 s it is', () {
      final svc = make(MemoryBrowserStore());
      svc.recordVisit('https://example.com/', title: 'A');
      clock = clock.add(const Duration(seconds: 59));
      expect(svc.recordVisit('https://example.com/', title: 'A'), isNull);
      expect(svc.history, hasLength(1));
      clock = clock.add(const Duration(seconds: 2));
      expect(svc.recordVisit('https://example.com/', title: 'A'), isNotNull);
      expect(svc.history, hasLength(2));
      svc.dispose();
    });

    test('a different address within 60 s is recorded', () {
      final svc = make(MemoryBrowserStore());
      svc.recordVisit('https://example.com/a');
      clock = clock.add(const Duration(seconds: 5));
      svc.recordVisit('https://example.com/b');
      expect(svc.history, hasLength(2));
      expect(svc.history.first.url, 'https://example.com/b'); // newest first
      svc.dispose();
    });

    test('the 2000 cap trims the oldest', () {
      final svc = make(MemoryBrowserStore());
      for (var i = 0; i < kBrowserHistoryCap + 5; i++) {
        clock = clock.add(const Duration(seconds: 1));
        svc.recordVisit('https://example.com/$i');
      }
      expect(svc.history, hasLength(kBrowserHistoryCap));
      expect(svc.history.first.url, 'https://example.com/${kBrowserHistoryCap + 4}');
      expect(svc.history.last.url, 'https://example.com/5');
      svc.dispose();
    });

    test('a late title updates the visit', () {
      final svc = make(MemoryBrowserStore());
      final id = svc.recordVisit('https://example.com/', title: null)!;
      expect(svc.history.single.title, 'example.com');
      clock = clock.add(const Duration(seconds: 3));
      svc.updateVisitTitle(id, 'Example Domain');
      expect(svc.history.single.title, 'Example Domain');
      expect(svc.history.single.updatedAt, clock);
      svc.dispose();
    });

    test('delete one, clear all', () {
      final svc = make(MemoryBrowserStore());
      final a = svc.recordVisit('https://a.com/')!;
      svc.recordVisit('https://b.com/');
      svc.deleteVisit(a);
      expect(svc.history.map((v) => v.host), ['b.com']);
      svc.clearHistory();
      expect(svc.history, isEmpty);
      svc.dispose();
    });

    test('most visited is one per site, busiest first', () {
      final svc = make(MemoryBrowserStore());
      for (final u in ['https://a.com/1', 'https://b.com/1', 'https://a.com/2', 'https://c.com/1', 'https://a.com/3', 'https://b.com/2']) {
        clock = clock.add(const Duration(seconds: 1));
        svc.recordVisit(u);
      }
      expect(svc.mostVisited().map((v) => v.host), ['a.com', 'b.com', 'c.com']);
      expect(svc.mostVisited(limit: 2), hasLength(2));
      svc.dispose();
    });

    test('writes are debounced into one', () async {
      final store = MemoryBrowserStore();
      final svc = make(store, delay: const Duration(milliseconds: 60));
      for (var i = 0; i < 5; i++) {
        clock = clock.add(const Duration(seconds: 1));
        svc.recordVisit('https://example.com/$i');
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(store.historyWrites, 0);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(store.historyWrites, 1);
      expect(store.history, hasLength(5));
      svc.dispose();
    });

    test('flush writes now', () async {
      final store = MemoryBrowserStore();
      final svc = make(store, delay: const Duration(hours: 1));
      svc.recordVisit('https://example.com/');
      await svc.flush();
      expect(store.historyWrites, 1);
      svc.dispose();
    });
  });

  group('bookmarks', () {
    test('add, find, toggle off', () {
      final store = MemoryBrowserStore();
      final svc = make(store);
      svc.addBookmark('https://example.com/', title: 'Example');
      expect(svc.isBookmarked('https://example.com/'), isTrue);
      expect(svc.bookmarks.single.title, 'Example');
      expect(svc.bookmarks.single.id, isNotEmpty);
      expect(store.bookmarkWrites, 1);
      svc.addBookmark('https://example.com/'); // no duplicates
      expect(svc.bookmarks, hasLength(1));
      svc.toggleBookmark('https://example.com/');
      expect(svc.isBookmarked('https://example.com/'), isFalse);
      svc.dispose();
    });

    test('a trailing slash is the same saved page', () {
      final svc = make(MemoryBrowserStore());
      svc.addBookmark('https://example.com', title: 'Example');
      expect(svc.isBookmarked('https://example.com/'), isTrue);
      expect(svc.isBookmarked('https://EXAMPLE.com'), isTrue);
      svc.addBookmark('https://example.com/');
      expect(svc.bookmarks, hasLength(1), reason: 'the web view reporting the slashed form must not add a second');
      svc.removeBookmark('https://example.com/');
      expect(svc.bookmarks, isEmpty);
      // A real path is still its own page.
      svc.addBookmark('https://example.com/news');
      expect(svc.isBookmarked('https://example.com/'), isFalse);
      svc.dispose();
    });
  });

  group('LocalBrowserStore', () {
    test('keeps history and bookmarks under browser_history and browser_bookmarks', () async {
      final dir = await useTempKvStore();
      expect(dir.existsSync(), isTrue);
      final kv = LocalKvStore.instance;
      final svc = BrowserService(store: LocalBrowserStore(kv), now: now, writeDelay: const Duration(hours: 1));
      svc.recordVisit('https://example.com/a', title: 'A');
      svc.addBookmark('https://example.com/b', title: 'B');
      await svc.flush();
      await Future<void>.delayed(const Duration(milliseconds: 50)); // the bookmark write is not awaited

      final rawHistory = await kv.read('browser_history');
      final rawBookmarks = await kv.read('browser_bookmarks');
      final h = (jsonDecode(rawHistory!) as List).single as Map;
      expect(h.keys, containsAll(['id', 'url', 'title', 'host', 'visitedAt', 'updatedAt']));
      final b = (jsonDecode(rawBookmarks!) as List).single as Map;
      expect(b.keys, containsAll(['id', 'url', 'title', 'addedAt', 'updatedAt']));

      // A new service reads them back.
      final again = BrowserService(store: LocalBrowserStore(kv), now: now);
      await again.load();
      expect(again.history.single.url, 'https://example.com/a');
      expect(again.bookmarks.single.title, 'B');
      svc.dispose();
      again.dispose();
    });

    test('unreadable saved data starts empty', () async {
      await useTempKvStore();
      await LocalKvStore.instance.write('browser_history', 'not json');
      await LocalKvStore.instance.write('browser_bookmarks', '{"oops": 1}');
      final svc = BrowserService(store: LocalBrowserStore(), now: now);
      await svc.load();
      expect(svc.history, isEmpty);
      expect(svc.bookmarks, isEmpty);
      svc.dispose();
    });

    test('visits recorded before load finishes are kept', () async {
      final store = MemoryBrowserStore();
      final first = make(store);
      first.recordVisit('https://old.com/');
      await first.flush();
      first.dispose();
      clock = clock.add(const Duration(hours: 1));
      final svc = make(store);
      svc.recordVisit('https://new.com/');
      await svc.load();
      expect(svc.history.map((v) => v.host), ['new.com', 'old.com']);
      svc.dispose();
    });
  });
}
