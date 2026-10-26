import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archangel/services/archangeld_connection.dart';
import 'package:archangel/services/files_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'test_utils.dart';

class _Seen {
  _Seen(this.request, this.body);
  final http.BaseRequest request;
  final List<int> body;
  Map<String, String> get q => request.url.queryParameters;
}

http.StreamedResponse _json(int status, Map<String, Object?> body) =>
    http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status, headers: {'content-type': 'application/json'});

const _listingJson = {'path': '/home/a', 'parent': '/home', 'entries': <Object>[], 'total_entries': 0, 'readable': true};

/// Builds a paired connection, a service using [handler] for uploads, and
/// runs [body] with the same client also serving top-level http calls (the
/// listing reload).
Future<void> _withService(
  Future<http.StreamedResponse> Function(http.BaseRequest req, List<int> body, int uploadNo) handler,
  Future<void> Function(FilesService svc, List<_Seen> uploads, List<http.BaseRequest> others) body,
) async {
  await useTempKvStore();
  final conn = ArchangeldConnection();
  await conn.pair(host: '10.10.0.1:8443', token: 'tok');
  final uploads = <_Seen>[];
  final others = <http.BaseRequest>[];
  final client = MockClient.streaming((req, stream) async {
    final bytes = <int>[];
    if (req.url.path == '/api/v1/files/upload') {
      final n = uploads.length;
      uploads.add(_Seen(req, bytes));
      await for (final c in stream) {
        bytes.addAll(c);
      }
      return handler(req, bytes, n);
    }
    others.add(req);
    await stream.drain<void>();
    return _json(200, _listingJson);
  });
  final svc = FilesService(client: client);
  svc.init(conn);
  await http.runWithClient(() => body(svc, uploads, others), () => client);
}

Future<UploadFileItem> _tempFile(String name, List<int> content) async {
  final dir = await Directory.systemTemp.createTemp('archangel_upload_test');
  addTearDown(() => dir.delete(recursive: true));
  final f = File('${dir.path}/$name');
  await f.writeAsBytes(content);
  return UploadFileItem(name: name, sizeBytes: content.length, path: f.path);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('connection builds the upload URI', () async {
    await useTempKvStore();
    final c = ArchangeldConnection();
    expect(() => c.filesUploadHttpUri('/d', 'a'), throwsStateError);
    await c.pair(host: '10.10.0.1:8443', token: 'tok');
    final u = c.filesUploadHttpUri('/home/a b', 'x y.txt');
    expect(u.path, '/api/v1/files/upload');
    expect(u.queryParameters, {'dir': '/home/a b', 'name': 'x y.txt'});
    expect(c.filesUploadHttpUri('/d', 'n', overwrite: true).queryParameters['overwrite'], 'true');
  });

  test('is unsupported until paired', () async {
    final svc = FilesService();
    expect(svc.supportsUpload, isFalse);
    final r = await svc.upload('/x', [const UploadFileItem(name: 'a')]);
    expect(r.supported, isFalse);

    await _withService((_, _, _) async => _json(200, {'success': true}), (svc, _, _) async {
      expect(svc.supportsUpload, isTrue);
    });
  });

  test('streams a file from disk with the right request and reloads the listing', () async {
    final content = List<int>.generate(300000, (i) => i % 251);
    final item = await _tempFile('big.bin', content);
    final progress = <UploadProgress>[];
    await _withService((_, _, _) async => _json(200, {'success': true, 'name': 'big.bin', 'size': content.length}), (
      svc,
      uploads,
      others,
    ) async {
      final r = await svc.upload('/home/a', [item], onProgress: progress.add);
      expect(r.ok, isTrue);
      expect(r.uploadedCount, 1);

      final u = uploads.single;
      expect(u.request.method, 'POST');
      expect(u.request.headers['X-Archangel-Token'], 'tok');
      expect(u.request.headers['Content-Type'], 'application/octet-stream');
      expect(u.request.contentLength, content.length);
      expect(u.q, {'dir': '/home/a', 'name': 'big.bin'});
      expect(Uint8List.fromList(u.body), Uint8List.fromList(content));

      expect(progress.first.bytesSent, 0);
      expect(progress.last.bytesSent, content.length);
      expect(progress.last.totalBytes, content.length);
      expect(progress.every((p) => p.currentFileName == 'big.bin' && p.fileIndex == 0 && p.totalFiles == 1), isTrue);

      expect(others.any((o) => o.url.path == '/api/v1/files/list'), isTrue, reason: 'listing refreshed');
    });
  });

  test('uploads several files in order, from bytes and from openRead', () async {
    await _withService((_, _, _) async => _json(200, {'success': true}), (svc, uploads, _) async {
      final r = await svc.upload('/d', [
        UploadFileItem(name: 'one.txt', bytes: Uint8List.fromList([1, 2, 3])),
        UploadFileItem(name: 'two.txt', sizeBytes: 2, openRead: () => Stream.value([9, 8])),
      ]);
      expect(r.ok, isTrue);
      expect(r.uploadedCount, 2);
      expect(uploads.map((u) => u.q['name']), ['one.txt', 'two.txt']);
      expect(uploads[0].body, [1, 2, 3]);
      expect(uploads[1].body, [9, 8]);
    });
  });

  UploadFileItem small(String name) => UploadFileItem(name: name, bytes: Uint8List.fromList([1]));

  http.StreamedResponse exists() => _json(409, {'success': false, 'message': 'A file with that name already exists'});

  test('name clash: Replace retries with overwrite=true', () async {
    await _withService((_, _, n) async => n == 0 ? exists() : _json(200, {'success': true}), (svc, uploads, _) async {
      final asked = <String>[];
      final r = await svc.upload(
        '/d',
        [small('a.txt')],
        onConflict: (name) async {
          asked.add(name);
          return UploadConflictChoice.replace;
        },
      );
      expect(asked, ['a.txt']);
      expect(r.ok, isTrue);
      expect(r.uploadedCount, 1);
      expect(uploads[0].q.containsKey('overwrite'), isFalse);
      expect(uploads[1].q['overwrite'], 'true');
    });
  });

  test('name clash: Keep both retries as "name (1).ext", then (2) if that clashes too', () async {
    await _withService((_, _, n) async => n < 2 ? exists() : _json(200, {'success': true}), (svc, uploads, _) async {
      final r = await svc.upload('/d', [small('a.txt')], onConflict: (_) async => UploadConflictChoice.keepBoth);
      expect(r.uploadedCount, 1);
      expect(uploads.map((u) => u.q['name']), ['a.txt', 'a (1).txt', 'a (2).txt']);
    });
  });

  test('name clash: Skip (or no callback) moves on to the next file', () async {
    await _withService((req, _, _) async => req.url.queryParameters['name'] == 'a.txt' ? exists() : _json(200, {'success': true}), (
      svc,
      uploads,
      _,
    ) async {
      final r = await svc.upload('/d', [small('a.txt'), small('b.txt')], onConflict: (_) async => UploadConflictChoice.skip);
      expect(r.ok, isTrue);
      expect(r.uploadedCount, 1);
      expect(r.skippedCount, 1);
      expect(r.processedCount, 2);
      expect(uploads.map((u) => u.q['name']), ['a.txt', 'b.txt']);

      final r2 = await svc.upload('/d', [small('a.txt')]);
      expect(r2.ok, isTrue);
      expect(r2.skippedCount, 1);
    });
  });

  test('an old server (plain 404) gets the update message; a real 404 keeps its own', () async {
    await _withService(
      (_, _, n) async => n == 0
          ? http.StreamedResponse(Stream.value(utf8.encode('404 page not found\n')), 404)
          : _json(404, {'success': false, 'message': "That folder doesn't exist"}),
      (svc, _, _) async {
        final r = await svc.upload('/d', [small('a.txt')]);
        expect(r.ok, isFalse);
        expect(r.error, 'Update your server to upload files (Settings → About → Update)');
        expect(r.error, kUploadNeedsUpdateMessage);

        final r2 = await svc.upload('/d', [small('a.txt')]);
        expect(r2.error, "That folder doesn't exist");
      },
    );
  });

  test('a failure stops the queue and reports how many files were finished', () async {
    await _withService(
      (req, _, _) async => req.url.queryParameters['name'] == 'b.txt'
          ? _json(413, {'success': false, 'message': 'That file is too big (limit 2.0 GB)'})
          : _json(200, {'success': true}),
      (svc, uploads, _) async {
        final r = await svc.upload('/d', [small('a.txt'), small('b.txt'), small('c.txt')]);
        expect(r.ok, isFalse);
        expect(r.error, 'b.txt: That file is too big (limit 2.0 GB)');
        expect(r.uploadedCount, 1);
        expect(r.processedCount, 1);
        expect(uploads.map((u) => u.q['name']), ['a.txt', 'b.txt']);
      },
    );
  });

  test('a clash with a folder or shortcut is an error, not a Replace prompt', () async {
    await _withService((_, _, _) async => _json(409, {'success': false, 'message': 'A folder with that name already exists'}), (
      svc,
      _,
      _,
    ) async {
      var asked = false;
      final r = await svc.upload(
        '/d',
        [small('docs')],
        onConflict: (_) async {
          asked = true;
          return UploadConflictChoice.replace;
        },
      );
      expect(asked, isFalse);
      expect(r.error, 'A folder with that name already exists');
    });
  });

  test('an unreachable server says so', () async {
    await _withService((_, _, _) async => throw const SocketException('down'), (svc, _, _) async {
      final r = await svc.upload('/d', [small('a.txt')]);
      expect(r.ok, isFalse);
      expect(r.error, "Your server didn't answer. Check that it's online, then try again.");
    });
  });

  test('cancelling before a file starts sends nothing more', () async {
    await _withService((_, _, _) async => _json(200, {'success': true}), (svc, uploads, _) async {
      final token = UploadCancelToken();
      final r = await svc.upload(
        '/d',
        [small('a.txt'), small('b.txt')],
        cancel: token,
        onProgress: (p) {
          if (p.fileIndex == 0 && p.bytesSent > 0) token.cancel();
        },
      );
      expect(r.cancelled, isTrue);
      expect(r.ok, isFalse);
      expect(r.error, isNull);
      expect(uploads.map((u) => u.q['name']), ['a.txt']);
      expect(r.processedCount, lessThanOrEqualTo(1));
    });
  });

  test('cancelling a request in flight aborts it', () async {
    await useTempKvStore();
    final conn = ArchangeldConnection();
    await conn.pair(host: '10.10.0.1:8443', token: 'tok');
    final client = _HangingClient();
    final svc = FilesService(client: client)..init(conn);
    final token = UploadCancelToken();
    final future = svc.upload('/d', [small('a.txt')], cancel: token);
    await client.started.future;
    token.cancel();
    final r = await future.timeout(const Duration(seconds: 3));
    expect(r.cancelled, isTrue);
    expect(r.error, isNull);
  });
}

/// A server that never answers; only the request's abort trigger ends it.
class _HangingClient extends http.BaseClient {
  final started = Completer<void>();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final c = Completer<http.StreamedResponse>();
    if (request is http.Abortable) {
      request.abortTrigger?.then((_) {
        if (!c.isCompleted) c.completeError(http.RequestAbortedException(request.url));
      });
    }
    started.complete();
    return c.future;
  }
}
