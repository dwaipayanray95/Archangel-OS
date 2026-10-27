import 'package:flutter_test/flutter_test.dart';

import 'package:archangel/ui/screens/browser/browser_url.dart';

Uri _load(String input) {
  final t = resolveOmniboxInput(input);
  expect(t, isA<OmniboxLoad>(), reason: input);
  return (t as OmniboxLoad).url;
}

void main() {
  group('omnibox input', () {
    test('an address with a scheme loads as typed', () {
      expect(_load('https://example.com/a?b=1').toString(), 'https://example.com/a?b=1');
      expect(_load('http://x.com').toString(), 'http://x.com');
    });

    test('a dot and no spaces gets https://', () {
      expect(_load('example.com').toString(), 'https://example.com');
      expect(_load('192.168.1.1:8080').toString(), 'https://192.168.1.1:8080');
      expect(_load('example.com:8080/docs').toString(), 'https://example.com:8080/docs');
      expect(_load('  example.com  ').toString(), 'https://example.com');
    });

    test('anything else is a DuckDuckGo search', () {
      expect(_load('hello world').toString(), 'https://duckduckgo.com/?q=hello+world');
      expect(_load('cats').toString(), 'https://duckduckgo.com/?q=cats');
      expect(_load('what is: a/b & c').toString(), 'https://duckduckgo.com/?q=what+is%3A+a%2Fb+%26+c');
      expect(_load('note: buy milk').toString(), startsWith('https://duckduckgo.com/?q='));
    });

    test('empty input does nothing', () {
      expect(resolveOmniboxInput('   '), isA<OmniboxEmpty>());
    });

    test('other kinds of link are blocked', () {
      for (final input in [
        'file:///etc/passwd',
        'javascript:alert(1)',
        'data:text/html,hi',
        'ftp://example.com',
        'mailto:a@b.com',
        'myapp://open',
      ]) {
        expect(resolveOmniboxInput(input), isA<OmniboxBlocked>(), reason: input);
      }
    });

    test('about:blank is allowed, other about: pages are not', () {
      expect(_load('about:blank').toString(), 'about:blank');
      expect(resolveOmniboxInput('about:config'), isA<OmniboxBlocked>());
    });
  });

  group('allowed addresses', () {
    test('only https, http and about:blank', () {
      expect(isAllowedBrowserUri(Uri.parse('https://example.com')), isTrue);
      expect(isAllowedBrowserUri(Uri.parse('http://example.com')), isTrue);
      expect(isAllowedBrowserUri(Uri.parse('about:blank')), isTrue);
      expect(isAllowedBrowserUri(Uri.parse('file:///etc/passwd')), isFalse);
      expect(isAllowedBrowserUri(Uri.parse('javascript:alert(1)')), isFalse);
      expect(isAllowedBrowserUri(Uri.parse('data:text/html,hi')), isFalse);
      expect(isAllowedBrowserUri(Uri.parse('https://')), isFalse);
    });
  });

  test('a half-typed address does nothing instead of looking refused', () {
    expect(resolveOmniboxInput('https://'), isA<OmniboxEmpty>());
    expect(resolveOmniboxInput('http://'), isA<OmniboxEmpty>());
    // Still refused, because it is genuinely not a web page.
    expect(resolveOmniboxInput('file://'), isA<OmniboxBlocked>());
  });

  test('splitUrlForDisplay separates the host', () {
    final p = splitUrlForDisplay('https://example.com/a/b?c=1');
    expect(p.prefix, 'https://');
    expect(p.host, 'example.com');
    expect(p.rest, '/a/b?c=1');
  });
}
