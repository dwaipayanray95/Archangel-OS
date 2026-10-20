/// Robust semantic version comparison utility.
///
/// Handles versions like 'v0.5.4', '0.5.4', 'v0.3.15-beta.1', etc.
class SemVer implements Comparable<SemVer> {
  final int major;
  final int minor;
  final int patch;
  final String? preRelease;

  const SemVer({required this.major, required this.minor, required this.patch, this.preRelease});

  /// Parses a semver string like '0.5.4' or 'v0.3.15'.
  /// Returns null if string cannot be parsed.
  static SemVer? tryParse(String? raw) {
    if (raw == null) return null;
    var s = raw.trim();
    if (s.startsWith('v') || s.startsWith('V')) {
      s = s.substring(1);
    }
    if (s.isEmpty) return null;

    String? pre;
    final hyphenIdx = s.indexOf('-');
    if (hyphenIdx != -1) {
      pre = s.substring(hyphenIdx + 1);
      s = s.substring(0, hyphenIdx);
    }

    final parts = s.split('.');
    if (parts.isEmpty || parts.length > 3) return null;

    final major = int.tryParse(parts[0]);
    if (major == null || major < 0) return null;

    final minor = parts.length > 1 ? int.tryParse(parts[1]) : 0;
    if (minor == null || minor < 0) return null;

    final patch = parts.length > 2 ? int.tryParse(parts[2]) : 0;
    if (patch == null || patch < 0) return null;

    return SemVer(major: major, minor: minor, patch: patch, preRelease: pre);
  }

  @override
  int compareTo(SemVer other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    if (patch != other.patch) return patch.compareTo(other.patch);

    // If both have pre-releases or both don't
    if (preRelease == null && other.preRelease == null) return 0;
    // A version with pre-release is lower than one without
    if (preRelease == null && other.preRelease != null) return 1;
    if (preRelease != null && other.preRelease == null) return -1;

    return preRelease!.compareTo(other.preRelease!);
  }

  bool operator >(SemVer other) => compareTo(other) > 0;
  bool operator <(SemVer other) => compareTo(other) < 0;
  bool operator >=(SemVer other) => compareTo(other) >= 0;
  bool operator <=(SemVer other) => compareTo(other) <= 0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SemVer &&
          runtimeType == other.runtimeType &&
          major == other.major &&
          minor == other.minor &&
          patch == other.patch &&
          preRelease == other.preRelease;

  @override
  int get hashCode => Object.hash(major, minor, patch, preRelease);

  @override
  String toString() {
    final base = '$major.$minor.$patch';
    return preRelease != null ? '$base-$preRelease' : base;
  }
}

/// Returns true ONLY if [latest] is strictly newer than [current].
/// If either version cannot be parsed, or if [latest] <= [current], returns false.
bool isUpdateAvailable({required String? current, required String? latest}) {
  if (current == null || latest == null) return false;
  final cur = SemVer.tryParse(current);
  final lat = SemVer.tryParse(latest);
  if (cur == null || lat == null) return false;
  return lat > cur;
}
