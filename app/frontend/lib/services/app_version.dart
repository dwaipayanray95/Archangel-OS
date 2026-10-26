/// The one version of Archangel OS (app and server program share it).
///
/// The source of truth is `version:` in `app/frontend/pubspec.yaml`
/// (`MAJOR.MINOR.PATCH+BUILD`). Release builds (and CI) pass it in:
///
/// ```sh
/// flutter build macos --release --dart-define=APP_VERSION=0.8.0 --dart-define=APP_BUILD=2
/// ```
///
/// A plain `flutter run` passes nothing, so it shows the fallback constants
/// below instead. `scripts/bump_version.sh` rewrites both the pubspec and
/// these two constants, and `test/app_version_test.dart` fails if they ever
/// drift apart.
class AppVersion {
  AppVersion._();

  /// Semver part, e.g. `0.8.0`.
  static const String current = String.fromEnvironment('APP_VERSION', defaultValue: fallbackVersion);

  /// Build number, e.g. `2`. Goes up by one on every release.
  static const int build = int.fromEnvironment('APP_BUILD', defaultValue: fallbackBuild);

  /// "0.8.0 (build 2)".
  static String get full => '$current (build $build)';

  // Used when no --dart-define is given (local `flutter run`, tests).
  // Kept in step with pubspec.yaml by scripts/bump_version.sh.
  static const String fallbackVersion = '0.8.0';
  static const int fallbackBuild = 2;
}
