import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../models/file_entry.dart';
import 'api_error.dart';
import 'archangeld_connection.dart';

/// Returns [name] if free, else "name (1).ext", "name (2).ext", ... so a
/// download never overwrites an existing file. [exists] is asked per candidate.
String uniqueFileName(String name, bool Function(String candidate) exists) {
  // Only ever a bare file name: remote paths must not steer where we write.
  var base = name.split(RegExp(r'[\\/]')).last.trim();
  if (base.isEmpty || base == '.' || base == '..') base = 'download';
  if (!exists(base)) return base;
  final dot = base.lastIndexOf('.');
  final hasExt = dot > 0; // leading-dot files (".bashrc") have no extension
  final stem = hasExt ? base.substring(0, dot) : base;
  final ext = hasExt ? base.substring(dot) : '';
  var i = 1;
  while (exists('$stem ($i)$ext')) {
    i++;
  }
  return '$stem ($i)$ext';
}

class DownloadResult {
  final String? savedPath;
  final String? error;
  const DownloadResult.saved(String path) : savedPath = path, error = null;
  const DownloadResult.failed(String message) : savedPath = null, error = message;
  bool get ok => savedPath != null;
}

class FilesService extends ChangeNotifier {
  // Empty means "wherever the server's configured files_root is" - the
  // backend maps an empty path query param to that root itself (see
  // ListHandler). A hardcoded path like '/var/log' would 403 on first
  // load for anyone whose files_root doesn't happen to contain it.
  //
  // Only ever set to a path that has actually been LOADED successfully
  // (200, cache hit, or mock fallback) - never to a path a request is
  // merely attempting. A failed load leaves this at the last place the
  // user was actually standing, so breadcrumbs/sidebar selection don't
  // relabel a rejected destination as "current" - see loadDirectory.
  String _currentPath = '';
  String get currentPath => _currentPath;

  // The server's configured files_root, as reported by the listing
  // response the first time the root itself (path == '') is loaded
  // successfully - the frontend has no other way to know this string.
  // Used to label the sidebar's root entry with the real jail boundary
  // instead of a generic "Root".
  String? _rootPath;
  String? get rootPath => _rootPath;

  // Top-level subdirectories of whatever's currently listed - shown as
  // sidebar shortcuts. Derived straight from the current listing (never
  // a separately-tracked/stale list) so it can never point outside
  // files_root: it's built from entries the server itself just
  // returned for a path that was actually allowed.
  List<FileEntryModel> get quickJumpDirs => (_listing?.entries ?? const []).where((e) => e.isDir).take(8).toList();

  bool _showHidden = false;
  bool get showHidden => _showHidden;
  void toggleShowHidden() {
    _showHidden = !_showHidden;
    notifyListeners();
  }

  bool _loading = false;
  bool get loading => _loading;

  String? _error;
  String? get error => _error;

  // The folder the last load was *trying* to show. Differs from
  // [currentPath] after a failed load, so Retry re-asks for the place that
  // failed rather than the place the user is still standing.
  String _attemptedPath = '';
  String get attemptedPath => _attemptedPath;

  /// Tries the last attempted folder again (the Retry button on errors).
  Future<void> retry() => loadDirectory(_attemptedPath, forceRefresh: true);

  DirectoryListingModel? _listing;
  DirectoryListingModel? get listing => _listing;

  // In-memory directory cache: path -> listing (for instant navigation)
  final Map<String, DirectoryListingModel> _dirCache = {};

  // File preview cache and state
  String? _activePreviewPath;
  String? get activePreviewPath => _activePreviewPath;

  bool _previewLoading = false;
  bool get previewLoading => _previewLoading;

  FileContentResult? _fileContent;
  FileContentResult? get fileContent => _fileContent;

  ArchangeldConnection? _backend;

  void init(ArchangeldConnection backend) {
    _backend = backend;
    loadDirectory(_currentPath);
  }

  /// Forgets the previous server's folder, listing, caches and preview
  /// (server switch) - paths on one server mean nothing on another.
  void reset() {
    _currentPath = '';
    _attemptedPath = '';
    _rootPath = null;
    _listing = null;
    _dirCache.clear();
    _activePreviewPath = null;
    _previewLoading = false;
    _fileContent = null;
    _loading = false;
    _error = null;
    notifyListeners();
  }

  Future<void> loadDirectory(String path, {bool forceRefresh = false}) async {
    _attemptedPath = path;
    // Instant UI render from cache if available - a cache hit is a
    // successful load (of a path we've already been to), so it does
    // commit _currentPath.
    if (!forceRefresh && _dirCache.containsKey(path)) {
      _currentPath = path;
      _listing = _dirCache[path];
      _error = null;
      notifyListeners();
      return;
    }

    _loading = true;
    _error = null;
    notifyListeners();

    final backend = _backend;
    if (backend == null || !backend.isPaired || backend.token == null) {
      _currentPath = path;
      _listing = DirectoryListingModel(
        path: path,
        parent: path == '/' || path.isEmpty ? '/' : path.substring(0, path.lastIndexOf('/')),
        entries: const [],
        totalEntries: 0,
        readable: false,
        error: 'Backend is not connected',
      );
      _loading = false;
      notifyListeners();
      return;
    }

    try {
      final res = await http.get(backend.filesListHttpUri(path), headers: {'X-Archangel-Token': backend.token!});

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final newListing = DirectoryListingModel.fromJson(data);
        _currentPath = path;
        _listing = newListing;
        _dirCache[path] = newListing;
        _error = null;
        if (path.isEmpty) _rootPath = newListing.path;
      } else if (res.statusCode == 403) {
        // A rejected destination is never "where we are" - leave
        // _currentPath (and therefore breadcrumbs/sidebar selection)
        // at the last successfully loaded directory. _error alone
        // carries this failure to the content pane.
        _error = serverMessage(res, 'Permission denied');
      } else {
        _error = serverMessage(res, 'Failed to load directory (HTTP ${res.statusCode})');
      }
    } catch (e) {
      debugPrint('Error listing directory $path: $e');
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> openFilePreview(String path) async {
    _activePreviewPath = path;
    _previewLoading = true;
    _fileContent = null;
    notifyListeners();

    final backend = _backend;
    if (backend == null || !backend.isPaired || backend.token == null) {
      _fileContent = FileContentResult(
        path: path,
        name: path.split('/').last,
        sizeBytes: 0,
        lines: const ['(Backend not paired or token missing)'],
        lineCount: 1,
        truncated: false,
        isBinary: false,
        mimeType: 'text/plain',
      );
      _previewLoading = false;
      notifyListeners();
      return;
    }

    try {
      final res = await http.get(backend.filesReadHttpUri(path, lines: 400), headers: {'X-Archangel-Token': backend.token!});

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        _fileContent = FileContentResult.fromJson(data);
      } else {
        _fileContent = FileContentResult(
          path: path,
          name: path.split('/').last,
          sizeBytes: 0,
          lines: ['Error reading file: HTTP ${res.statusCode}'],
          lineCount: 1,
          truncated: false,
          isBinary: false,
          mimeType: 'text/plain',
        );
      }
    } catch (e) {
      debugPrint('Error reading file preview $path: $e');
      _fileContent = FileContentResult(
        path: path,
        name: path.split('/').last,
        sizeBytes: 0,
        lines: ['Error reading file: $e'],
        lineCount: 1,
        truncated: false,
        isBinary: false,
        mimeType: 'text/plain',
      );
    } finally {
      _previewLoading = false;
      notifyListeners();
    }
  }

  void closePreview() {
    _activePreviewPath = null;
    _fileContent = null;
    _previewLoading = false;
    notifyListeners();
  }

  Future<Uint8List?> downloadFileBytes(String path) async {
    final backend = _backend;
    if (backend == null || !backend.isPaired || backend.token == null) {
      return null;
    }
    try {
      final res = await http.get(backend.filesDownloadHttpUri(path), headers: {'X-Archangel-Token': backend.token!});
      if (res.statusCode == 200) {
        return res.bodyBytes;
      }
    } catch (e) {
      debugPrint('Error downloading file $path: $e');
    }
    return null;
  }

  /// Downloads [path] and writes it into the user's Downloads folder (or the
  /// app documents folder where there is none, e.g. Android), never
  /// overwriting an existing file.
  Future<DownloadResult> downloadToDisk(String path) async {
    final bytes = await downloadFileBytes(path);
    if (bytes == null) return const DownloadResult.failed('Could not fetch the file from your server');
    try {
      final dir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
      await dir.create(recursive: true);
      final fileName = uniqueFileName(path, (n) => File('${dir.path}${Platform.pathSeparator}$n').existsSync());
      final target = File('${dir.path}${Platform.pathSeparator}$fileName');
      await target.writeAsBytes(bytes, flush: true);
      return DownloadResult.saved(target.path);
    } catch (e) {
      debugPrint('Error saving download $path: $e');
      return DownloadResult.failed('Could not save the file: $e');
    }
  }
}
