import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:archangel/data/app_state.dart';
import 'package:archangel/services/admin_mode_service.dart';
import 'package:archangel/services/archangeld_connection.dart';
import 'package:archangel/services/browser_service.dart';
import 'package:archangel/services/containers_service.dart';
import 'package:archangel/services/devices_service.dart';
import 'package:archangel/services/devops_service.dart';
import 'package:archangel/services/files_service.dart';
import 'package:archangel/services/local_kv_store.dart';
import 'package:archangel/services/monitoring_service.dart';
import 'package:archangel/services/prefs_sync_service.dart';
import 'package:archangel/services/update_check_service.dart';
import 'package:archangel/services/wireguard_controller.dart';
import 'package:archangel/services/server_registry.dart';
import 'package:archangel/ui/shell/archangel_shell.dart';
import 'package:archangel/ui/shell/desktop_prefs.dart';
import 'package:archangel/ui/theme.dart';

/// Pumps [ArchangelShell] directly, wrapped in the same providers
/// [ArchangelApp] uses, but bypassing the app's root router (which now
/// shows the first-run setup wizard when neither the tunnel nor the
/// backend is paired - see main.dart's `_RootRouter`). These tests are
/// about the shell's own rendering, not first-run routing, so they don't
/// need a real paired state.
Future<AppState> pumpAppShell(
  WidgetTester tester, {
  Size size = const Size(1400, 900),
  Brightness brightness = Brightness.dark,
  Future<void> Function(ServerRegistry registry)? seedRegistry,
  AxLayout layout = AxLayout.simple,
  DesktopPrefs? desktopPrefs,
  ArchangeldConnection? backend,
  BrowserService? browser,
}) async {
  final registry = ServerRegistry();
  final appState = AppState();
  // testWidgets runs in a FakeAsync zone; real file IO must go via runAsync.
  await tester.runAsync(() async {
    await useTempKvStore();
    if (seedRegistry != null) await seedRegistry(registry);
    // Most shell tests are about the sidebar; Desktop mode tests opt in.
    // (Set here: the setter saves, and a save queued in the fake zone would
    // hold up every later real-IO store call.)
    appState.layout = layout;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  });
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: appState),
        ChangeNotifierProvider<ServerRegistry>.value(value: registry),
        ChangeNotifierProvider<DesktopPrefs>.value(value: desktopPrefs ?? DesktopPrefs()),
        ChangeNotifierProvider(create: (_) => WireGuardController()),
        ChangeNotifierProvider<ArchangeldConnection>.value(value: backend ?? ArchangeldConnection()),
        // No transport and no timers: the shell never syncs in tests.
        ChangeNotifierProvider(create: (_) => PrefsSyncService(debounce: null, pollInterval: null)),
        ChangeNotifierProvider(create: (_) => MonitoringService()),
        ChangeNotifierProvider(create: (_) => FilesService()),
        ChangeNotifierProvider<BrowserService>.value(value: browser ?? BrowserService()),
        ChangeNotifierProvider(create: (_) => ContainersService()),
        ChangeNotifierProvider(create: (_) => DevopsService()),
        ChangeNotifierProvider(create: (_) => DevicesService()),
        ChangeNotifierProvider(create: (_) => AdminModeService()),
        ChangeNotifierProvider(create: (_) => UpdateCheckService()),
      ],
      child: Consumer<AppState>(
        builder: (context, app, _) =>
            MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(brightness, app.accentChoice), home: const ArchangelShell()),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
  return appState;
}

/// Points [LocalKvStore] at a fresh temp directory (path_provider has no
/// platform channel under `flutter test`) and clears its cache. Call from
/// `setUp`; the directory is removed on tearDown.
Future<Directory> useTempKvStore() async {
  final dir = await Directory.systemTemp.createTemp('archangel_kv_test');
  LocalKvStore.directoryOverride = () async => dir;
  LocalKvStore.instance.resetForTesting();
  addTearDown(() {
    LocalKvStore.directoryOverride = null;
    LocalKvStore.instance.resetForTesting();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return dir;
}
