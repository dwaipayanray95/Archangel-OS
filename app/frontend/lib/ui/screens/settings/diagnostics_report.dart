import 'dart:io';

import '../../../models/system_metrics.dart';
import '../../../services/app_version.dart';
import '../../shell/connection_state.dart';
import '../home/home_logic.dart';

/// "Ubuntu 24.04.1 LTS" -> "Ubuntu 24.04", "Debian GNU/Linux 12 (bookworm)" ->
/// "Debian 12". Anything we can't read comes back as it was, or "Unknown".
String plainOsName(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return 'Unknown';
  s = s.replaceAll(RegExp(r'\([^)]*\)'), '').replaceAll(RegExp(r'\bLTS\b'), '').replaceAll('GNU/Linux', '');
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  // Keep "major.minor" of the version and drop patch levels.
  s = s.replaceFirstMapped(RegExp(r'(\d+(?:\.\d+)?)(?:\.\d+)+'), (m) => m.group(1)!);
  return s.isEmpty ? 'Unknown' : s;
}

/// "2 hours", "3 days 4 hours": uptime in words.
String plainUptime(int seconds) {
  if (seconds < 60) return 'Just started';
  final days = seconds ~/ 86400;
  final hours = (seconds % 86400) ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  String unit(int n, String word) => '$n $word${n == 1 ? '' : 's'}';
  if (days > 0) return hours > 0 ? '${unit(days, 'day')} ${unit(hours, 'hour')}' : unit(days, 'day');
  if (hours > 0) return minutes > 0 ? '${unit(hours, 'hour')} ${unit(minutes, 'minute')}' : unit(hours, 'hour');
  return unit(minutes, 'minute');
}

/// "5 s ago", "3 min ago": how long ago something happened.
String plainAgo(Duration d) {
  final s = d.inSeconds < 0 ? 0 : d.inSeconds;
  if (s < 60) return '${s}s ago';
  if (s < 3600) return '${s ~/ 60} min ago';
  if (s < 86400) return '${s ~/ 3600} h ago';
  return '${s ~/ 86400} d ago';
}

/// "8 GB", "0.5 GB": a size in gigabytes without noise.
String plainGb(double gb) {
  if (gb >= 10) return '${gb.round()} GB';
  final one = gb.toStringAsFixed(1);
  return '${one.endsWith('.0') ? one.substring(0, one.length - 2) : one} GB';
}

/// "4 CPU cores · 8 GB memory · 80 GB disk".
String capacitySummary(SystemMetrics m) {
  final cores = m.cpu.cores.length;
  final parts = [
    if (cores > 0) '$cores CPU ${cores == 1 ? 'core' : 'cores'}',
    '${plainGb(m.memory.totalGb)} memory',
    '${plainGb(m.disk.totalGb)} disk',
  ];
  return parts.join(' · ');
}

final _secretPatterns = <RegExp>[
  RegExp(r'-----BEGIN [A-Z ]+-----[\s\S]*?-----END [A-Z ]+-----'),
  RegExp(r'(token|passphrase|password|secret|key)(\s*[=:]\s*)[^\s&,;]+', caseSensitive: false),
  RegExp(r'Bearer\s+\S+', caseSensitive: false),
  // Long key-like runs (base64 / hex / pairing bundles).
  RegExp(r'[A-Za-z0-9+/_\-]{32,}={0,2}'),
];

/// Removes anything that looks like a secret from [text]. [secrets] are exact
/// values to remove wherever they appear (the token, private keys...).
String redactSecrets(String text, {Iterable<String?> secrets = const []}) {
  var out = text;
  for (final s in secrets) {
    if (s != null && s.trim().length >= 4) out = out.replaceAll(s.trim(), '[hidden]');
  }
  for (final p in _secretPatterns) {
    out = out.replaceAllMapped(p, (m) => m.groupCount >= 2 && m.group(1) != null ? '${m.group(1)}${m.group(2)}[hidden]' : '[hidden]');
  }
  return out;
}

/// Builds the plain-text report people send to support. It holds versions,
/// systems and statuses only. It never takes the token, keys, the pairing
/// bundle or SSH details as input, and the free-text [recentErrors] are
/// scrubbed as well ([secrets] are removed from them by value).
String buildDiagnosticsReport({
  required DateTime now,
  required ConnectionPhase phase,
  required HealthStatus health,
  String? serverVersion,
  SystemMetrics? metrics,
  bool? adminMode,
  List<String> recentErrors = const [],
  Iterable<String?> secrets = const [],
}) {
  final b = StringBuffer();
  b.writeln('Archangel diagnostics');
  b.writeln('Created: ${now.toUtc().toIso8601String()}');
  b.writeln();
  b.writeln('Versions');
  b.writeln('  Archangel OS: ${AppVersion.full}');
  b.writeln('  Server program: ${serverVersion ?? 'unknown'}');
  b.writeln();
  b.writeln('Systems');
  b.writeln('  This device: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
  b.writeln('  Server: ${metrics == null ? 'unknown' : '${plainOsName(metrics.host.os)} (${metrics.host.arch})'}');
  if (metrics != null) {
    b.writeln('  Server size: ${capacitySummary(metrics)}');
    b.writeln('  Server running for: ${plainUptime(metrics.uptimeSeconds)}');
  }
  b.writeln();
  b.writeln('Status');
  b.writeln('  Connection: ${connectionText(phase)}');
  b.writeln('  Health: ${health.headline}');
  if (adminMode != null) b.writeln('  Admin mode: ${adminMode ? 'on' : 'off'}');
  b.writeln();
  b.writeln('Recent errors');
  final errors = recentErrors.where((e) => e.trim().isNotEmpty).toList();
  if (errors.isEmpty) {
    b.writeln('  None');
  } else {
    for (final e in errors) {
      b.writeln('  - ${redactSecrets(e.trim(), secrets: secrets)}');
    }
  }
  return b.toString();
}
