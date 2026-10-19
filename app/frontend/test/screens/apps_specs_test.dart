import 'package:flutter_test/flutter_test.dart';

import 'package:archangel/ui/screens/apps/app_specs.dart';

void main() {
  group('buildPortSpec', () {
    test('private (default) is hostPort:containerPort', () {
      expect(buildPortSpec(const PortMapping(containerPort: '80', hostPort: '8080')), '8080:80');
    });

    test('public is explicit 0.0.0.0:hostPort:containerPort', () {
      expect(
        buildPortSpec(const PortMapping(containerPort: '80', hostPort: '8080', visibility: PortVisibility.public)),
        '0.0.0.0:8080:80',
      );
    });

    test('blank host port falls back to the container port', () {
      expect(buildPortSpec(const PortMapping(containerPort: '3001')), '3001:3001');
      expect(
        buildPortSpec(const PortMapping(containerPort: '53/udp', visibility: PortVisibility.public)),
        '0.0.0.0:53:53/udp',
      );
    });

    test('blank rows are skipped', () {
      expect(buildPortSpec(const PortMapping()), isNull);
      expect(
        buildPortSpecs(const [PortMapping(), PortMapping(containerPort: '80', hostPort: '81')]),
        ['81:80'],
      );
    });
  });

  group('validation', () {
    test('ports must be 1-65535', () {
      expect(validatePortNumber('1'), isNull);
      expect(validatePortNumber('65535'), isNull);
      expect(validatePortNumber('0'), isNotNull);
      expect(validatePortNumber('65536'), isNotNull);
      expect(validatePortNumber('-1'), isNotNull);
      expect(validatePortNumber('80a'), isNotNull);
      expect(validatePortNumber(''), isNotNull);
      expect(validatePortNumber('080'), isNotNull);
    });

    test('container port accepts /tcp and /udp only', () {
      expect(validateContainerPort('80/udp'), isNull);
      expect(validateContainerPort('80/TCP'), isNull);
      expect(validateContainerPort('80/sctp'), isNotNull);
      expect(validateContainerPort('99999'), isNotNull);
    });

    test('host port may be blank', () {
      expect(validateHostPort(''), isNull);
      expect(validateHostPort('70000'), isNotNull);
    });

    test('image, name, folders and settings', () {
      expect(validateImage(''), isNotNull);
      expect(validateImage('nginx'), isNull);
      expect(validateImage('my image'), isNotNull);
      expect(validateAppName(''), isNull);
      expect(validateAppName('web-1'), isNull);
      expect(validateAppName('-bad'), isNotNull);
      expect(validateFolderPath('/srv/data', what: 'x'), isNull);
      expect(validateFolderPath('data', what: 'x'), isNotNull);
      expect(validateSettingKey('TZ'), isNull);
      expect(validateSettingKey('1TZ'), isNotNull);
    });
  });

  group('other specs', () {
    test('volumes and env', () {
      expect(
        buildVolumeSpecs(const [FolderMapping(hostPath: '/srv/a', containerPath: '/data'), FolderMapping()]),
        ['/srv/a:/data'],
      );
      expect(buildEnvSpecs(const [SettingEntry(key: 'TZ', value: 'UTC'), SettingEntry()]), ['TZ=UTC']);
    });
  });

  group('open link', () {
    test('uses the connection host and first published port', () {
      expect(serverAddress('10.8.0.1:8443'), '10.8.0.1');
      expect(appOpenUri('10.8.0.1:8443', '8080,443').toString(), 'http://10.8.0.1:8080');
    });

    test('no published port means no link', () {
      expect(appOpenUri('10.8.0.1:8443', '\u2014'), isNull);
      expect(appOpenUri(null, '80'), isNull);
    });
  });
}
