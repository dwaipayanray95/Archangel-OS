import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('only in_app_web_controller.dart imports the web view plugin', () {
    final importers = [
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>())
        if (f.path.endsWith('.dart') && f.readAsStringSync().contains('package:flutter_inappwebview')) f.path,
    ];
    expect(importers, ['lib/ui/screens/browser/in_app_web_controller.dart']);
  });

  test('the screen files depend on the seam, not on the real controller', () {
    for (final path in [
      'lib/screens/browser_screen.dart',
      'lib/ui/screens/browser/browser_workspace.dart',
      'lib/ui/screens/browser/browser_tabs.dart',
      'lib/ui/screens/browser/browser_chrome.dart',
      'lib/ui/screens/browser/browser_tab_strip.dart',
      'lib/ui/screens/browser/browser_states.dart',
      'lib/ui/screens/browser/browser_lists.dart',
      'lib/ui/screens/browser/web_view_host.dart',
    ]) {
      final src = File(path).readAsStringSync();
      expect(src.contains('in_app_web_controller'), isFalse, reason: path);
      expect(src.contains('InAppWebView'), isFalse, reason: path);
    }
  });

  test('nothing in the browser touches cookies', () {
    for (final f in Directory('lib/ui/screens/browser').listSync().whereType<File>()) {
      final src = f.readAsStringSync();
      for (final api in ['CookieManager', 'getCookie', 'setCookie', 'deleteCookie']) {
        expect(src.contains(api), isFalse, reason: '${f.path} uses $api');
      }
    }
  });
}
