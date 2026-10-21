import 'package:flutter_test/flutter_test.dart';
import 'package:archangel/services/files_service.dart';

void main() {
  group('uniqueFileName', () {
    test('returns the name untouched when free', () {
      expect(uniqueFileName('report.txt', (_) => false), 'report.txt');
    });

    test('adds (1), (2) before the extension', () {
      final taken = {'report.txt', 'report (1).txt'};
      expect(uniqueFileName('report.txt', taken.contains), 'report (2).txt');
    });

    test('handles no extension and dotfiles', () {
      expect(uniqueFileName('Makefile', {'Makefile'}.contains), 'Makefile (1)');
      expect(uniqueFileName('.bashrc', {'.bashrc'}.contains), '.bashrc (1)');
    });

    test('keeps only the last path segment', () {
      expect(uniqueFileName('/etc/../x/passwd', (_) => false), 'passwd');
      expect(uniqueFileName('..', (_) => false), 'download');
    });
  });

  group('FilesService placeholders', () {
    test('reports unsupported for upload and privateLink by default', () async {
      final svc = FilesService();
      expect(svc.supportsUpload, isFalse);
      expect(svc.supportsPrivateLink, isFalse);

      final up = await svc.upload('/home', [const UploadFileItem(name: 'test.txt')]);
      expect(up.ok, isFalse);
      expect(up.supported, isFalse);

      final link = await svc.privateLink('/home/test.txt');
      expect(link.ok, isFalse);
      expect(link.supported, isFalse);
    });
  });
}
