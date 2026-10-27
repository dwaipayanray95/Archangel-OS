// Pure helpers behind the "Run an app" form: validation and the exact strings
// sent to archangeld (port, folder and setting specs). No Flutter imports so
// they are trivially unit-testable.

/// Who may reach a published port.
enum PortVisibility {
  /// Bound to the secure-connection (tunnel) address: only paired devices.
  private,

  /// Bound to every network interface: anyone on the internet.
  public,
}

extension PortVisibilityLabels on PortVisibility {
  String get label => switch (this) {
    PortVisibility.private => 'Private — only your devices',
    PortVisibility.public => 'Public — anyone on the internet',
  };
}

/// One row of the "Ports" section.
class PortMapping {
  const PortMapping({this.containerPort = '', this.hostPort = '', this.visibility = PortVisibility.private});

  /// The port the app listens on inside, optionally with "/udp" (default tcp).
  final String containerPort;

  /// The port to reach it on from outside. Blank means "same as inside".
  final String hostPort;
  final PortVisibility visibility;

  bool get isBlank => containerPort.trim().isEmpty && hostPort.trim().isEmpty;
}

/// Checks a single port number (1-65535, digits only). Returns a plain
/// sentence on failure, null when fine.
String? validatePortNumber(String raw, {String what = 'Port'}) {
  final v = raw.trim();
  if (v.isEmpty) return '$what is required';
  if (!RegExp(r'^\d+$').hasMatch(v)) return '$what must be a number';
  final n = int.parse(v);
  if (n < 1 || n > 65535) return '$what must be between 1 and 65535';
  if (v != n.toString()) return '$what must not start with 0';
  return null;
}

/// Validates the app-side port, which may carry a "/tcp" or "/udp" suffix.
String? validateContainerPort(String raw) {
  var v = raw.trim();
  final slash = v.indexOf('/');
  if (slash >= 0) {
    final proto = v.substring(slash + 1).toLowerCase();
    if (proto != 'tcp' && proto != 'udp') return 'Use /tcp or /udp after the port';
    v = v.substring(0, slash);
  }
  return validatePortNumber(v, what: 'Port inside the app');
}

/// Validates the outside port; blank is fine (it defaults to the inside port).
String? validateHostPort(String raw) {
  if (raw.trim().isEmpty) return null;
  return validatePortNumber(raw, what: 'Port on your server');
}

/// Builds the backend port spec for [m], or null for a blank row.
///
/// Private (the default) is "hostPort:containerPort": the backend binds that
/// to the tunnel address. Public must be explicit:
/// "0.0.0.0:hostPort:containerPort". Assumes the row passed validation.
String? buildPortSpec(PortMapping m) {
  if (m.isBlank) return null;
  final inside = m.containerPort.trim();
  final insideNumber = inside.split('/').first;
  final host = m.hostPort.trim().isEmpty ? insideNumber : m.hostPort.trim();
  final spec = '$host:$inside';
  return m.visibility == PortVisibility.public ? '0.0.0.0:$spec' : spec;
}

List<String> buildPortSpecs(Iterable<PortMapping> rows) => [for (final r in rows) ?buildPortSpec(r)];

/// Folder row: a path on the server and where the app sees it.
class FolderMapping {
  const FolderMapping({this.hostPath = '', this.containerPath = ''});
  final String hostPath;
  final String containerPath;
  bool get isBlank => hostPath.trim().isEmpty && containerPath.trim().isEmpty;
}

String? validateFolderPath(String raw, {required String what}) {
  final v = raw.trim();
  if (v.isEmpty) return '$what is required';
  if (!v.startsWith('/')) return '$what must start with /';
  if (v.contains(':')) return '$what must not contain ":"';
  return null;
}

List<String> buildVolumeSpecs(Iterable<FolderMapping> rows) => [
  for (final r in rows)
    if (!r.isBlank) '${r.hostPath.trim()}:${r.containerPath.trim()}',
];

/// Setting row (environment variable).
class SettingEntry {
  const SettingEntry({this.key = '', this.value = ''});
  final String key;
  final String value;
  bool get isBlank => key.trim().isEmpty && value.isEmpty;
}

String? validateSettingKey(String raw) {
  final v = raw.trim();
  if (v.isEmpty) return 'Name is required';
  if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(v)) {
    return 'Use letters, numbers and _ only (not starting with a number)';
  }
  return null;
}

List<String> buildEnvSpecs(Iterable<SettingEntry> rows) => [
  for (final r in rows)
    if (!r.isBlank) '${r.key.trim()}=${r.value}',
];

/// App names follow Docker's rules: letters, numbers, `_`, `.`, `-`.
String? validateAppName(String raw) {
  final v = raw.trim();
  if (v.isEmpty) return null; // optional
  if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.-]*$').hasMatch(v)) {
    return 'Use letters, numbers, - _ . only, starting with a letter or number';
  }
  return null;
}

String? validateImage(String raw) {
  final v = raw.trim();
  if (v.isEmpty) return 'Enter the image to run, for example nginx';
  if (RegExp(r'\s').hasMatch(v)) return 'An image name has no spaces';
  return null;
}

/// Restart choices in plain words; values are Docker's restart policies.
const restartChoices = <(String, String)>[
  ('unless-stopped', 'Always restart unless I stop it'),
  ('always', 'Always restart, even if I stopped it'),
  ('on-failure', 'Restart only if it crashes'),
  ('no', 'Never restart on its own'),
];

/// Published (host) ports found in the backend's comma separated ports text
/// ("8080,443" or "—" when none), de-duplicated, in order.
List<int> publishedPorts(String raw) {
  final seen = <int>{};
  final out = <int>[];
  for (final part in raw.split(',')) {
    final n = int.tryParse(part.trim());
    if (n != null && n >= 1 && n <= 65535 && seen.add(n)) out.add(n);
  }
  return out;
}

/// The address of the server inside the secure connection, from the stored
/// "host:port" of the Archangel server. Null without a host.
String? serverAddress(String? hostWithPort) {
  final h = hostWithPort?.trim();
  if (h == null || h.isEmpty) return null;
  if (h.startsWith('[')) {
    final end = h.indexOf(']');
    return end > 0 ? h.substring(1, end) : null;
  }
  final colon = h.lastIndexOf(':');
  return colon > 0 ? h.substring(0, colon) : h;
}

/// An http address for the first published port, or null.
Uri? appOpenUri(String? hostWithPort, String portsText) {
  final addr = serverAddress(hostWithPort);
  final ports = publishedPorts(portsText);
  if (addr == null || ports.isEmpty) return null;
  return Uri(scheme: 'http', host: addr, port: ports.first);
}
