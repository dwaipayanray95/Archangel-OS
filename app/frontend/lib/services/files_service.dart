import 'dart:async';
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

class UploadFileItem {
  final String name;
  final int sizeBytes;
  final Uint8List? bytes;
  final String? path;

  /// Opens the content as a stream (e.g. a picked file, which on Android is
  /// not a plain path). Needs [sizeBytes]. Wins over [bytes] and [path].
  final Stream<List<int>> Function()? openRead;
  const UploadFileItem({required this.name, this.sizeBytes = 0, this.bytes, this.path, this.openRead});
}

class UploadProgress {
  final int fileIndex;
  final int totalFiles;
  final String currentFileName;
  final int bytesSent;
  final int totalBytes;
  const UploadProgress({
    required this.fileIndex,
    required this.totalFiles,
    required this.currentFileName,
    this.bytesSent = 0,
    this.totalBytes = 0,
  });
}

/// What to do when the server already has a file with the same name.
enum UploadConflictChoice { replace, skip, keepBoth }

/// Lets the UI stop an upload in progress (the Cancel button).
class UploadCancelToken {
  final Completer<void> _done = Completer<void>();
  bool get isCancelled => _done.isCompleted;
  Future<void> get whenCancelled => _done.future;
  void cancel() {
    if (!_done.isCompleted) _done.complete();
  }
}

/// Shown when the server answers 404 to the upload route: it is too old.
const String kUploadNeedsUpdateMessage = 'Update your server to upload files (Settings → About → Update)';

class UploadResult {
  final bool ok;
  final bool supported;
  final bool cancelled;
  final int uploadedCount;
  final int skippedCount;

  /// How many files from the start of the list are finished (uploaded or
  /// skipped). After a failure or cancel, "try again" resumes after these.
  final int processedCount;
  final String? error;
  const UploadResult.unsupported([this.error = 'Upload is not supported yet'])
    : ok = false,
      supported = false,
      cancelled = false,
      uploadedCount = 0,
      skippedCount = 0,
      processedCount = 0;
  const UploadResult.success(this.uploadedCount, {this.skippedCount = 0})
    : ok = true,
      supported = true,
      cancelled = false,
      processedCount = uploadedCount + skippedCount,
      error = null;
  const UploadResult.failed(this.error, {this.uploadedCount = 0, this.skippedCount = 0, this.processedCount = 0})
    : ok = false,
      supported = true,
      cancelled = false;
  const UploadResult.cancelled({this.uploadedCount = 0, this.skippedCount = 0, this.processedCount = 0})
    : ok = false,
      supported = true,
      cancelled = true,
      error = null;
}

class PrivateLinkResult {
  final bool ok;
  final bool supported;
  final String? url;
  final String? error;
  const PrivateLinkResult.unsupported([this.error = 'Private link is not supported yet']) : ok = false, supported = false, url = null;
  const PrivateLinkResult.success(this.url) : ok = true, supported = true, error = null;
  const PrivateLinkResult.failed(this.error) : ok = false, supported = true, url = null;
}

class FilesService extends ChangeNotifier {
  /// [client] is only used for uploads (a test seam); other calls use the
  /// default client.
  FilesService({http.Client? client}) : _client = client;

  final http.Client? _client;

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

  /// Uploads need a paired server. Servers that are too old answer 404 to
  /// the upload route, which [upload] turns into [kUploadNeedsUpdateMessage].
  bool get supportsUpload {
    final b = _backend;
    return b != null && b.isPaired && b.token != null;
  }

  bool get supportsPrivateLink => false;

  /// Uploads [files] into [dir], one after another, streaming each from disk
  /// (never fully loaded into memory). Reports progress per file, stops when
  /// [cancel] is cancelled, and asks [onConflict] when the server already has
  /// a file with that name (no callback means skip). Reloads the listing
  /// afterwards. Stops at the first failure and says how many files were
  /// finished ([UploadResult.processedCount]) so a retry can resume.
  Future<UploadResult> upload(
    String dir,
    List<UploadFileItem> files, {
    void Function(UploadProgress progress)? onProgress,
    UploadCancelToken? cancel,
    Future<UploadConflictChoice> Function(String name)? onConflict,
  }) async {
    final backend = _backend;
    if (!supportsUpload || backend == null) return const UploadResult.unsupported();

    var uploaded = 0;
    var skipped = 0;
    var processed = 0;
    UploadResult? result;
    try {
      for (var i = 0; i < files.length; i++) {
        if (cancel?.isCancelled ?? false) {
          result = UploadResult.cancelled(uploadedCount: uploaded, skippedCount: skipped, processedCount: processed);
          break;
        }
        final item = files[i];
        var name = item.name;
        var overwrite = false;
        final taken = <String>{};
        _SendOutcome? failure;
        var skip = false;
        for (var attempt = 0; attempt < 100; attempt++) {
          final out = await _sendOne(backend, dir, item, name, overwrite, i, files.length, onProgress, cancel);
          if (out.kind == _SendKind.ok) break;
          if (out.kind == _SendKind.conflict) {
            final choice = onConflict == null ? UploadConflictChoice.skip : await onConflict(name);
            if (cancel?.isCancelled ?? false) {
              failure = const _SendOutcome.cancelled();
              break;
            }
            if (choice == UploadConflictChoice.replace) {
              overwrite = true;
              continue;
            }
            if (choice == UploadConflictChoice.keepBoth) {
              taken.add(name);
              name = uniqueFileName(item.name, taken.contains);
              overwrite = false;
              continue;
            }
            skip = true;
            break;
          }
          failure = out;
          break;
        }
        if (failure != null) {
          result = failure.kind == _SendKind.cancelled
              ? UploadResult.cancelled(uploadedCount: uploaded, skippedCount: skipped, processedCount: processed)
              : UploadResult.failed(
                  files.length > 1 ? '${item.name}: ${failure.message}' : failure.message,
                  uploadedCount: uploaded,
                  skippedCount: skipped,
                  processedCount: processed,
                );
          break;
        }
        if (skip) {
          skipped++;
        } else {
          uploaded++;
        }
        processed++;
      }
      result ??= UploadResult.success(uploaded, skippedCount: skipped);
    } finally {
      // Whatever happened, the folder may have changed.
      _dirCache.clear();
      if (uploaded > 0) await loadDirectory(_currentPath, forceRefresh: true);
    }
    return result;
  }

  Future<_SendOutcome> _sendOne(
    ArchangeldConnection backend,
    String dir,
    UploadFileItem item,
    String name,
    bool overwrite,
    int index,
    int total,
    void Function(UploadProgress progress)? onProgress,
    UploadCancelToken? cancel,
  ) async {
    final Stream<List<int>> source;
    final int size;
    try {
      if (item.openRead != null) {
        size = item.sizeBytes;
        source = item.openRead!();
      } else if (item.bytes != null) {
        size = item.bytes!.length;
        source = Stream.value(item.bytes!);
      } else if (item.path != null) {
        final f = File(item.path!);
        size = await f.length();
        source = f.openRead();
      } else {
        return _SendOutcome.error("Couldn't read ${item.name}");
      }
    } catch (_) {
      return _SendOutcome.error("Couldn't read ${item.name}");
    }

    void report(int sent) =>
        onProgress?.call(UploadProgress(fileIndex: index, totalFiles: total, currentFileName: name, bytesSent: sent, totalBytes: size));

    final abort = Completer<void>();
    if (cancel != null) {
      unawaited(
        cancel.whenCancelled.then((_) {
          if (!abort.isCompleted) abort.complete();
        }),
      );
    }

    final client = _client ?? http.Client();
    try {
      final req = http.AbortableStreamedRequest(
        'POST',
        backend.filesUploadHttpUri(dir, name, overwrite: overwrite),
        abortTrigger: abort.future,
      );
      req.headers['X-Archangel-Token'] = backend.token!;
      req.headers['Content-Type'] = 'application/octet-stream';
      req.contentLength = size;

      var stop = false;
      var sent = 0;
      Stream<List<int>> counted() async* {
        await for (final chunk in source) {
          if (stop) return;
          sent += chunk.length;
          yield chunk;
          report(sent);
        }
      }

      report(0);
      final sending = client.send(req);
      // addStream applies back-pressure, so progress follows the network
      // rather than the disk. Errors here surface through [sending].
      unawaited(
        req.sink.addStream(counted()).then<void>((_) => req.sink.close()).catchError((Object _) {
          try {
            req.sink.close();
          } catch (_) {}
        }),
      );

      final streamed = await sending;
      stop = true; // the server may answer (e.g. 409) before reading everything
      final res = await http.Response.fromStream(streamed);
      if (res.statusCode == 200) return const _SendOutcome.ok();
      if (res.statusCode == 404 && !_isUploadApiBody(res.body)) return const _SendOutcome.error(kUploadNeedsUpdateMessage);
      if (res.statusCode == 409 && serverMessage(res, '').toLowerCase().contains('file with that name already exists')) {
        return const _SendOutcome.conflict();
      }
      if (res.statusCode == 413) return _SendOutcome.error(serverMessage(res, 'That file is too big to upload'));
      return _SendOutcome.error(serverMessage(res, 'Upload failed (HTTP ${res.statusCode})'));
    } on http.RequestAbortedException {
      return const _SendOutcome.cancelled();
    } catch (e) {
      if (cancel?.isCancelled ?? false) return const _SendOutcome.cancelled();
      debugPrint('Error uploading $name to $dir: $e');
      return const _SendOutcome.error("Your server didn't answer. Check that it's online, then try again.");
    } finally {
      if (_client == null) client.close();
    }
  }

  /// True when [body] is archangeld's own JSON error (`{"success":false,...}`),
  /// as opposed to the router's plain "404 page not found" from an old server.
  static bool _isUploadApiBody(String body) {
    try {
      final d = jsonDecode(body);
      return d is Map && d.containsKey('success');
    } catch (_) {
      return false;
    }
  }

  /// Private-link placeholder: reports unsupported until backend endpoints land.
  Future<PrivateLinkResult> privateLink(String path) async {
    return const PrivateLinkResult.unsupported();
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

enum _SendKind { ok, conflict, cancelled, error }

class _SendOutcome {
  final _SendKind kind;
  final String message;
  const _SendOutcome.ok() : kind = _SendKind.ok, message = '';
  const _SendOutcome.conflict() : kind = _SendKind.conflict, message = '';
  const _SendOutcome.cancelled() : kind = _SendKind.cancelled, message = '';
  const _SendOutcome.error(this.message) : kind = _SendKind.error;
}
