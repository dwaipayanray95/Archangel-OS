import 'dart:convert';
import 'package:http/http.dart' as http;

/// Outcome of a mutating backend call, with a message that's safe to show
/// the user as-is (the server's own explanation when it gave one).
class ApiActionResult {
  final bool success;
  final String message;
  const ApiActionResult({required this.success, required this.message});
}

/// The user-facing explanation from an archangeld error response.
///
/// The backend answers failures with `{"success":false,"message":"..."}`
/// (e.g. 403 "Admin mode is off - this action needs it", 503 "Docker is not
/// running on this server"), so that text beats a generic "Failed to X".
/// Falls back to a short plain-text body, then to [fallback].
String serverMessage(http.Response res, String fallback) {
  final body = res.body.trim();
  if (body.isEmpty) return fallback;
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map) {
      for (final key in const ['message', 'error']) {
        final v = decoded[key];
        if (v is String && v.trim().isNotEmpty) return v.trim();
      }
      return fallback;
    }
  } catch (_) {
    // Not JSON - fall through to the plain-text check.
  }
  if (body.length <= 200 && !body.startsWith('<')) return body;
  return fallback;
}
