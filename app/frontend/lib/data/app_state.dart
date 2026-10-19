import 'package:flutter/material.dart';
import '../services/local_kv_store.dart';
import '../theme/tokens.dart';
import '../ui/theme.dart';

const _kThemeModeKey = 'appearance_theme_mode';
const _kAccentKey = 'appearance_accent';

/// The app's destinations, in navigation order. On phones the last three
/// live behind the "More" tab.
enum AxSection { home, apps, files, terminal, activity, services, settings }

const axSectionLabels = <AxSection, String>{
  AxSection.home: 'Home',
  AxSection.apps: 'Apps',
  AxSection.files: 'Files',
  AxSection.terminal: 'Terminal',
  AxSection.activity: 'Activity',
  AxSection.services: 'Services',
  AxSection.settings: 'Settings',
};

/// Destinations shown under "More" on phones.
const axMoreSections = <AxSection>[AxSection.activity, AxSection.services, AxSection.settings];

/// The default theme mode. Legacy screens still paint with the dark-only
/// [AxColors] constants, so this stays dark until every screen has moved to
/// `context.ax`; then it becomes [ThemeMode.system].
const kDefaultThemeMode = ThemeMode.dark;

/// Root app state: active section, accent color, palette/notif overlays.
/// Kept deliberately simple (ChangeNotifier) — this is a single-user app
/// with no need for a heavier state management layer yet.
class AppState extends ChangeNotifier {
  AxSection _section = AxSection.home;
  AxSection get section => _section;
  set section(AxSection s) {
    if (_section == s) return;
    _section = s;
    notifyListeners();
  }

  AxAccent _accentChoice = AxAccent.green;
  AxAccent get accentChoice => _accentChoice;
  set accentChoice(AxAccent a) {
    if (_accentChoice == a) return;
    _accentChoice = a;
    notifyListeners();
    _save(_kAccentKey, a.name);
  }

  /// Accent as a plain colour (dark-palette variant) for legacy screens.
  Color get accent => _accentChoice.dark;
  set accent(Color c) {
    final match = AxAccent.values.where((a) => a.dark == c || a.light == c);
    if (match.isNotEmpty) {
      accentChoice = match.first;
    }
  }

  ThemeMode _themeMode = kDefaultThemeMode;
  ThemeMode get themeMode => _themeMode;
  set themeMode(ThemeMode m) {
    if (_themeMode == m) return;
    _themeMode = m;
    notifyListeners();
    _save(_kThemeModeKey, m.name);
  }

  /// Restores the saved theme mode and accent (call once at startup).
  Future<void> loadAppearance() async {
    try {
      final store = LocalKvStore.instance;
      final mode = await store.read(_kThemeModeKey);
      final accent = await store.read(_kAccentKey);
      if (mode != null) {
        _themeMode = ThemeMode.values.firstWhere((m) => m.name == mode, orElse: () => kDefaultThemeMode);
      }
      if (accent != null) _accentChoice = AxAccent.fromName(accent);
      notifyListeners();
    } catch (_) {
      // Appearance is a convenience; defaults are fine if storage fails.
    }
  }

  void _save(String key, String value) {
    LocalKvStore.instance.write(key, value).catchError((_) {});
  }

  bool _paletteOpen = false;
  bool get paletteOpen => _paletteOpen;
  void openPalette() {
    _paletteOpen = true;
    notifyListeners();
  }

  void closePalette() {
    _paletteOpen = false;
    notifyListeners();
  }

  bool _notifOpen = false;
  bool get notifOpen => _notifOpen;
  void toggleNotif() {
    _notifOpen = !_notifOpen;
    notifyListeners();
  }

  void closeNotif() {
    if (!_notifOpen) return;
    _notifOpen = false;
    notifyListeners();
  }

  String? _pendingTerminalDir;
  String? get pendingTerminalDir => _pendingTerminalDir;
  String? consumePendingTerminalDir() {
    final d = _pendingTerminalDir;
    _pendingTerminalDir = null;
    return d;
  }

  String? _pendingTerminalCommand;
  String? get pendingTerminalCommand => _pendingTerminalCommand;
  String? consumePendingTerminalCommand() {
    final cmd = _pendingTerminalCommand;
    _pendingTerminalCommand = null;
    return cmd;
  }

  void openTerminalInDir(String dir) {
    _pendingTerminalDir = dir;
    go(AxSection.terminal);
  }

  void openTerminalWithCommand(String command) {
    _pendingTerminalCommand = command;
    go(AxSection.terminal);
  }

  void go(AxSection s) {
    section = s;
    _paletteOpen = false;
    _notifOpen = false;
    notifyListeners();
  }
}
