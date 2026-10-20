import 'package:flutter_test/flutter_test.dart';

import 'package:archangel/ui/screens/apps/app_catalog.dart';
import 'package:archangel/ui/screens/apps/app_specs.dart';

void main() {
  test('every preset passes the same checks as the form', () {
    final hostPorts = <String>{};
    for (final p in kAppCatalog.where((p) => !p.isCustom)) {
      expect(validateImage(p.image), isNull, reason: p.id);
      expect(validateAppName(p.id), isNull, reason: p.id);
      expect(validateContainerPort(p.containerPort!), isNull, reason: p.id);
      expect(validateHostPort(p.hostPort!), isNull, reason: p.id);
      expect(hostPorts.add(p.hostPort!), isTrue, reason: '${p.id} reuses port ${p.hostPort}');
      for (final f in p.folders) {
        expect(validateFolderPath(f.hostPath, what: 'host'), isNull, reason: p.id);
        expect(validateFolderPath(f.containerPath, what: 'app'), isNull, reason: p.id);
      }
    }
  });

  test('the catalog ends with exactly one "Something else"', () {
    expect(kAppCatalog.last.isCustom, isTrue);
    expect(kAppCatalog.where((p) => p.isCustom).length, 1);
  });
}
