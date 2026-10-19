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
}
