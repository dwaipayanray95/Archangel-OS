/// Central version helper for the Archangel frontend.
///
/// [current] (frontend/app version) and [archangel] (overall project
/// version) are kept in sync with the repo root's `VERSION` file's
/// `FRONTEND` and `ARCHANGEL` lines by `app/frontend/scripts/sync_version.sh`
/// (run by hand after bumping VERSION, and by CI before every build) -
/// not read dynamically at runtime, since Flutter's asset bundler doesn't
/// resolve the symlink approach that was tried here first (confirmed:
/// `flutter build` hard-fails on a symlinked asset on every platform,
/// not just Windows).
class AppVersion {
  AppVersion._();

  static const String current = '0.6.0';
  static const String archangel = '0.7.0';
}
