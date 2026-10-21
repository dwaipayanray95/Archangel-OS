import 'package:flutter/material.dart';
import '../services/local_kv_store.dart';
import '../ui/theme.dart';

const _kThemeModeKey = 'appearance_theme_mode';
const _kAccentKey = 'appearance_accent';
const _kLayoutKey = 'appearance_layout';
const _kUiScaleKey = 'appearance_ui_scale';

/// UI canvas scaling on desktop/wide displays.
enum AxUiScale {
  small70('Small (70%)', 0.70),
  default80('Default (80%)', 0.80),
  large90('Large (90%)', 0.90);

  const AxUiScale(this.label, this.factor);
  final String label;
  final double factor;

  static AxUiScale fromName(String? name) => AxUiScale.values.firstWhere((s) => s.name == name, orElse: () => AxUiScale.default80);
}

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

/// How the app is laid out on wide screens. Phones always use [simple].
///
/// - [simple]: one screen at a time with a sidebar.
/// - [desktop]: Desktop mode - draggable windows, a dock and a launcher.
enum AxLayout { simple, desktop }

/// Which start-up animation to play: the long one the first time the app
/// opens, the short wordmark one every other time.
enum BootKind { first, short }

/// The default theme mode: follow the operating system's light/dark setting.
const kDefaultThemeMode = ThemeMode.system;

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

  AxAccent _accentChoice = AxAccent.halo;
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

  /// Desktop mode is the main experience on tablets and computers (phones
  /// always use the bottom bar, whatever this says).
  AxLayout _layout = AxLayout.desktop;
  AxLayout get layout => _layout;
  set layout(AxLayout l) {
    if (_layout == l) return;
    _layout = l;
    notifyListeners();
    _save(_kLayoutKey, l.name);
  }

  AxUiScale _uiScale = AxUiScale.default80;
  AxUiScale get uiScale => _uiScale;
  double get uiScaleFactor => _uiScale.factor;
  set uiScale(AxUiScale s) {
    if (_uiScale == s) return;
    _uiScale = s;
    notifyListeners();
    _save(_kUiScaleKey, s.name);
  }

  int _bootReplay = 0;
  BootKind _bootReplayKind = BootKind.short;

  /// Bumped by [replayBoot]; the boot gate plays [bootReplayKind] again.
  int get bootReplay => _bootReplay;
  BootKind get bootReplayKind => _bootReplayKind;

  /// Plays the start-up animation again (Settings > Appearance).
  void replayBoot(BootKind kind) {
    _bootReplayKind = kind;
    _bootReplay++;
    notifyListeners();
  }

  /// Restores the saved theme mode and accent (call once at startup).
  Future<void> loadAppearance() async {
    try {
      final store = LocalKvStore.instance;
      final mode = await store.read(_kThemeModeKey);
      final accent = await store.read(_kAccentKey);
      final layout = await store.read(_kLayoutKey);
      final scale = await store.read(_kUiScaleKey);
      if (layout != null) {
        _layout = AxLayout.values.firstWhere((l) => l.name == layout, orElse: () => AxLayout.desktop);
      }
      if (mode != null) {
        _themeMode = ThemeMode.values.firstWhere((m) => m.name == mode, orElse: () => kDefaultThemeMode);
      }
      if (accent != null) _accentChoice = AxAccent.fromName(accent);
      if (scale != null) _uiScale = AxUiScale.fromName(scale);
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
