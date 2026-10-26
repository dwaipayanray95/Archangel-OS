import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:archangel/services/app_version.dart';

void main() {
  test('the fallback constants match version: in pubspec.yaml (bump with scripts/bump_version.sh)', () {
    final line = File('pubspec.yaml').readAsLinesSync().firstWhere((l) => l.startsWith('version: '));
    final m = RegExp(r'^version: (\d+\.\d+\.\d+)\+(\d+)$').firstMatch(line);
    expect(m, isNotNull, reason: 'pubspec version must look like X.Y.Z+N, got "$line"');
    expect(AppVersion.fallbackVersion, m!.group(1));
    expect(AppVersion.fallbackBuild, int.parse(m.group(2)!));
  });

  test('full shows the version and build', () {
    expect(AppVersion.full, '${AppVersion.current} (build ${AppVersion.build})');
  });
}
