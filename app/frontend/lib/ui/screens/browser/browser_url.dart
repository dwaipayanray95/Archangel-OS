/// Turning what someone types into something the browser opens, and the one
/// rule for which addresses it opens at all.
library;

/// The search page used for anything that is not an address.
const kBrowserSearchBase = 'https://duckduckgo.com/?q=';

/// Only web pages open: `https`, `http` and `about:blank`. This covers typing
/// and links inside pages alike.
bool isAllowedBrowserUri(Uri uri) {
  final scheme = uri.scheme.toLowerCase();
  if (scheme == 'https' || scheme == 'http') return uri.host.isNotEmpty;
  return scheme == 'about' && uri.path == 'blank';
}

bool isBlankUri(Uri? uri) => uri == null || uri.scheme == 'about';

bool isInsecureUri(Uri? uri) => uri != null && uri.scheme.toLowerCase() == 'http';

/// What to do with the omnibox text.
sealed class OmniboxTarget {
  const OmniboxTarget();
}

/// Nothing typed.
class OmniboxEmpty extends OmniboxTarget {
  const OmniboxEmpty();
}

/// Open [url] (an address, or a search).
class OmniboxLoad extends OmniboxTarget {
  const OmniboxLoad(this.url);
  final Uri url;
}

/// A kind of link the browser does not open.
class OmniboxBlocked extends OmniboxTarget {
  const OmniboxBlocked(this.input);
  final String input;
}

final _schemePattern = RegExp(r'^([a-zA-Z][a-zA-Z0-9+.\-]*):(.*)$', dotAll: true);
final _portPattern = RegExp(r'^\d+(/.*)?$');

/// Schemes that are never a search phrase, even without `//`.
const _opaqueSchemes = {'about', 'javascript', 'data', 'mailto', 'tel', 'sms', 'blob', 'view-source', 'file', 'intent'};

OmniboxTarget resolveOmniboxInput(String raw) {
  final input = raw.trim();
  if (input.isEmpty) return const OmniboxEmpty();

  final m = _schemePattern.firstMatch(input);
  if (m != null) {
    final scheme = m.group(1)!.toLowerCase();
    final rest = m.group(2)!;
    final hostAndPort = _portPattern.hasMatch(rest); // example.com:8080
    final looksLikeScheme = rest.startsWith('//') || _opaqueSchemes.contains(scheme) || !input.contains(RegExp(r'\s'));
    if (!hostAndPort && looksLikeScheme) {
      final uri = Uri.tryParse(input);
      // A web address with nothing after the scheme ("https://") is being
      // typed, not a kind of link we refuse: do nothing yet.
      if (uri != null && (scheme == 'http' || scheme == 'https') && uri.host.isEmpty) return const OmniboxEmpty();
      if (uri == null || !isAllowedBrowserUri(uri)) return OmniboxBlocked(input);
      return OmniboxLoad(uri);
    }
  }

  if (!input.contains(RegExp(r'\s')) && input.contains('.')) {
    final uri = Uri.tryParse('https://$input');
    if (uri != null && uri.host.isNotEmpty) return OmniboxLoad(uri);
  }

  return OmniboxLoad(Uri.parse('$kBrowserSearchBase${Uri.encodeQueryComponent(input)}'));
}

/// An address split for the omnibox: what comes before the host, the host
/// itself and the rest.
({String prefix, String host, String rest}) splitUrlForDisplay(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.host.isEmpty) return (prefix: '', host: url, rest: '');
  final start = url.indexOf(uri.host);
  if (start < 0) return (prefix: '', host: url, rest: '');
  final end = start + uri.host.length;
  return (prefix: url.substring(0, start), host: uri.host, rest: url.substring(end));
}
