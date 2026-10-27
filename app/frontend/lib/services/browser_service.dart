import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'local_kv_store.dart';

const kBrowserHistoryKey = 'browser_history';
const kBrowserBookmarksKey = 'browser_bookmarks';

/// History keeps this many visits; the oldest are trimmed.
const int kBrowserHistoryCap = 2000;

/// A reload of the same address inside this window is not a new visit.
const Duration kBrowserReloadWindow = Duration(seconds: 60);

/// History writes wait this long so scrolling a busy site does not thrash the file.
const Duration kBrowserWriteDelay = Duration(seconds: 2);

/// One page the person visited. [id] and [updatedAt] are part of the stored
/// shape now so a syncing store (phase 2) can use them without a migration.
@immutable
class BrowserVisit {
  const BrowserVisit({
    required this.id,
    required this.url,
    required this.title,
    required this.host,
    required this.visitedAt,
    required this.updatedAt,
  });

  final String id;
  final String url;
  final String title;
  final String host;
  final DateTime visitedAt;
  final DateTime updatedAt;

  BrowserVisit copyWith({String? title, DateTime? updatedAt}) =>
      BrowserVisit(id: id, url: url, title: title ?? this.title, host: host, visitedAt: visitedAt, updatedAt: updatedAt ?? this.updatedAt);

  Map<String, Object> toJson() => {
    'id': id,
    'url': url,
    'title': title,
    'host': host,
    'visitedAt': visitedAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  static BrowserVisit? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'];
    final url = j['url'];
    final visited = DateTime.tryParse('${j['visitedAt']}');
    if (id is! String || url is! String || visited == null) return null;
    return BrowserVisit(
      id: id,
      url: url,
      title: j['title'] is String ? j['title'] as String : '',
      host: j['host'] is String ? j['host'] as String : (Uri.tryParse(url)?.host ?? ''),
      visitedAt: visited,
      updatedAt: DateTime.tryParse('${j['updatedAt']}') ?? visited,
    );
  }
}

/// One saved page.
@immutable
class BrowserBookmark {
  const BrowserBookmark({required this.id, required this.url, required this.title, required this.addedAt, required this.updatedAt});

  final String id;
  final String url;
  final String title;
  final DateTime addedAt;
  final DateTime updatedAt;

  String get host => Uri.tryParse(url)?.host ?? '';

  Map<String, Object> toJson() => {
    'id': id,
    'url': url,
    'title': title,
    'addedAt': addedAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  static BrowserBookmark? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'];
    final url = j['url'];
    final added = DateTime.tryParse('${j['addedAt']}');
    if (id is! String || url is! String || added == null) return null;
    return BrowserBookmark(
      id: id,
      url: url,
      title: j['title'] is String ? j['title'] as String : '',
      addedAt: added,
      updatedAt: DateTime.tryParse('${j['updatedAt']}') ?? added,
    );
  }
}

/// Where history and bookmarks live. Phase 1 stores them on this device
/// ([LocalBrowserStore]); phase 2 can add a syncing store without touching
/// the screen.
abstract class BrowserStore {
  Future<List<BrowserVisit>> loadHistory();
  Future<void> saveHistory(List<BrowserVisit> visits);
  Future<List<BrowserBookmark>> loadBookmarks();
  Future<void> saveBookmarks(List<BrowserBookmark> bookmarks);
}

/// Stores each list as one JSON string in [LocalKvStore].
class LocalBrowserStore implements BrowserStore {
  LocalBrowserStore([LocalKvStore? kv]) : _kv = kv ?? LocalKvStore.instance;

  final LocalKvStore _kv;

  Future<List<T>> _read<T>(String key, T? Function(Object?) parse) async {
    final raw = await _kv.read(key);
    if (raw == null) return [];
    try {
      final j = jsonDecode(raw);
      if (j is! List) return [];
      return [
        for (final item in j)
          if (parse(item) case final T v) v,
      ];
    } catch (_) {
      return []; // unreadable: start empty rather than fail
    }
  }

  @override
  Future<List<BrowserVisit>> loadHistory() => _read(kBrowserHistoryKey, BrowserVisit.fromJson);

  @override
  Future<void> saveHistory(List<BrowserVisit> visits) => _kv.write(kBrowserHistoryKey, jsonEncode([for (final v in visits) v.toJson()]));

  @override
  Future<List<BrowserBookmark>> loadBookmarks() => _read(kBrowserBookmarksKey, BrowserBookmark.fromJson);

  @override
  Future<void> saveBookmarks(List<BrowserBookmark> bookmarks) =>
      _kv.write(kBrowserBookmarksKey, jsonEncode([for (final b in bookmarks) b.toJson()]));
}

/// The browser's history and bookmarks, kept on this device.
///
/// History is newest first and capped at [kBrowserHistoryCap]. It never
/// holds cookies or page content, only addresses and titles.
class BrowserService extends ChangeNotifier {
  BrowserService({BrowserStore? store, DateTime Function()? now, this.writeDelay = kBrowserWriteDelay})
    : _store = store ?? LocalBrowserStore(),
      _now = now ?? DateTime.now;

  final BrowserStore _store;
  final DateTime Function() _now;

  /// How long history writes wait after the last change.
  final Duration writeDelay;

  List<BrowserVisit> _history = [];
  List<BrowserBookmark> _bookmarks = [];
  Timer? _writeTimer;
  bool _historyDirty = false;
  bool _disposed = false;
  int _seq = 0;
  final _random = math.Random();

  /// Visits, newest first.
  List<BrowserVisit> get history => List.unmodifiable(_history);

  /// Bookmarks, newest first.
  List<BrowserBookmark> get bookmarks => List.unmodifiable(_bookmarks);

  String _newId() => '${_now().microsecondsSinceEpoch.toRadixString(36)}${_random.nextInt(1 << 20).toRadixString(36)}-${_seq++}';

  /// Reads the saved lists (call once at start-up). Anything recorded before
  /// the read finishes is kept.
  Future<void> load() async {
    try {
      final savedHistory = await _store.loadHistory();
      final savedBookmarks = await _store.loadBookmarks();
      if (_disposed) return;
      final known = {for (final v in _history) v.id};
      _history = [
        ..._history,
        for (final v in savedHistory)
          if (known.add(v.id)) v,
      ]..sort((a, b) => b.visitedAt.compareTo(a.visitedAt));
      if (_history.length > kBrowserHistoryCap) _history = _history.sublist(0, kBrowserHistoryCap);
      final knownMarks = {for (final b in _bookmarks) b.id};
      _bookmarks = [
        ..._bookmarks,
        for (final b in savedBookmarks)
          if (knownMarks.add(b.id)) b,
      ]..sort((a, b) => b.addedAt.compareTo(a.addedAt));
      notifyListeners();
    } catch (_) {
      // History is a convenience: start empty if storage fails.
    }
  }

  // ---- history ----

  /// Records a main-frame visit. Returns the visit's id, or null when it was
  /// skipped (a reload of the same address within [kBrowserReloadWindow]).
  String? recordVisit(String url, {String? title}) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return null;
    final now = _now();
    for (final v in _history) {
      if (now.difference(v.visitedAt) >= kBrowserReloadWindow) break;
      if (v.url == url) return null;
    }
    final visit = BrowserVisit(
      id: _newId(),
      url: url,
      title: (title == null || title.trim().isEmpty) ? uri.host : title.trim(),
      host: uri.host,
      visitedAt: now,
      updatedAt: now,
    );
    _history = [visit, ..._history];
    if (_history.length > kBrowserHistoryCap) _history = _history.sublist(0, kBrowserHistoryCap);
    _changedHistory();
    return visit.id;
  }

  /// A page's title usually arrives after it commits.
  void updateVisitTitle(String id, String title) {
    final t = title.trim();
    if (t.isEmpty) return;
    final i = _history.indexWhere((v) => v.id == id);
    if (i < 0 || _history[i].title == t) return;
    _history = [..._history]..[i] = _history[i].copyWith(title: t, updatedAt: _now());
    _changedHistory();
  }

  void deleteVisit(String id) {
    final before = _history.length;
    _history = [
      for (final v in _history)
        if (v.id != id) v,
    ];
    if (_history.length != before) _changedHistory();
  }

  void clearHistory() {
    if (_history.isEmpty) return;
    _history = [];
    _changedHistory();
  }

  /// The addresses visited most, one per site, for the new-tab page.
  List<BrowserVisit> mostVisited({int limit = 6}) {
    final counts = <String, int>{};
    final latest = <String, BrowserVisit>{};
    for (final v in _history) {
      counts[v.host] = (counts[v.host] ?? 0) + 1;
      latest.putIfAbsent(v.host, () => v); // history is newest first
    }
    final hosts = counts.keys.toList()..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    return [for (final h in hosts.take(limit)) latest[h]!];
  }

  void _changedHistory() {
    _historyDirty = true;
    notifyListeners();
    _writeTimer?.cancel();
    _writeTimer = null;
    if (writeDelay == Duration.zero) {
      unawaited(flush());
    } else {
      _writeTimer = Timer(writeDelay, flush);
    }
  }

  /// Writes history now if it changed (otherwise waits for the delay).
  Future<void> flush() async {
    _writeTimer?.cancel();
    _writeTimer = null;
    if (!_historyDirty) return;
    _historyDirty = false;
    try {
      await _store.saveHistory(_history);
    } catch (_) {
      _historyDirty = true; // try again with the next change
    }
  }

  // ---- bookmarks ----

  bool isBookmarked(String url) => _bookmarks.any((b) => b.url == url);

  void addBookmark(String url, {String? title}) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty || isBookmarked(url)) return;
    final now = _now();
    _bookmarks = [
      BrowserBookmark(
        id: _newId(),
        url: url,
        title: (title == null || title.trim().isEmpty) ? uri.host : title.trim(),
        addedAt: now,
        updatedAt: now,
      ),
      ..._bookmarks,
    ];
    _changedBookmarks();
  }

  void removeBookmark(String url) {
    final before = _bookmarks.length;
    _bookmarks = [
      for (final b in _bookmarks)
        if (b.url != url) b,
    ];
    if (_bookmarks.length != before) _changedBookmarks();
  }

  void toggleBookmark(String url, {String? title}) => isBookmarked(url) ? removeBookmark(url) : addBookmark(url, title: title);

  void deleteBookmarkById(String id) {
    final before = _bookmarks.length;
    _bookmarks = [
      for (final b in _bookmarks)
        if (b.id != id) b,
    ];
    if (_bookmarks.length != before) _changedBookmarks();
  }

  void _changedBookmarks() {
    notifyListeners();
    _store.saveBookmarks(_bookmarks).catchError((_) {});
  }

  @override
  void dispose() {
    _disposed = true;
    _writeTimer?.cancel();
    if (_historyDirty) {
      _historyDirty = false;
      _store.saveHistory(_history).catchError((_) {});
    }
    super.dispose();
  }
}
