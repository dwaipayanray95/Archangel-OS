import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:archangel/data/app_state.dart';
import 'package:archangel/services/admin_mode_service.dart';
import 'package:archangel/services/archangeld_connection.dart';
import 'package:archangel/services/containers_service.dart';
import 'package:archangel/services/devices_service.dart';
import 'package:archangel/services/devops_service.dart';
import 'package:archangel/services/files_service.dart';
import 'package:archangel/services/local_kv_store.dart';
import 'package:archangel/services/monitoring_service.dart';
import 'package:archangel/services/update_check_service.dart';
import 'package:archangel/services/wireguard_controller.dart';
import 'package:archangel/services/server_registry.dart';
import 'package:archangel/ui/shell/archangel_shell.dart';
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
  Future<void> Function(ServerRegistry registry)? seedRegistry,
}) async {
  ignoreFontDownloadErrors();
  final registry = ServerRegistry();
  // testWidgets runs in a FakeAsync zone; real file IO must go via runAsync.
  await tester.runAsync(() async {
    await useTempKvStore();
    if (seedRegistry != null) await seedRegistry(registry);
  });
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);

  final appState = AppState();
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: appState),
        ChangeNotifierProvider<ServerRegistry>.value(value: registry),
        ChangeNotifierProvider(create: (_) => WireGuardController()),
        ChangeNotifierProvider(create: (_) => ArchangeldConnection()),
        ChangeNotifierProvider(create: (_) => MonitoringService()),
        ChangeNotifierProvider(create: (_) => FilesService()),
        ChangeNotifierProvider(create: (_) => ContainersService()),
        ChangeNotifierProvider(create: (_) => DevopsService()),
        ChangeNotifierProvider(create: (_) => DevicesService()),
        ChangeNotifierProvider(create: (_) => AdminModeService()),
        ChangeNotifierProvider(create: (_) => UpdateCheckService()),
      ],
      child: Consumer<AppState>(
        builder: (context, app, _) => MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.dark, app.accentChoice),
          home: const ArchangelShell(),
        ),
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

/// google_fonts tries to download Manrope the first time a style is used; with
/// no network (and real async via `runAsync`) that surfaces as a test failure
/// even though rendering simply falls back to the default font. Swallow just
/// those reports for the rest of the current test.
void ignoreFontDownloadErrors() {
  final original = FlutterError.onError;
  FlutterError.onError = (details) {
    final text = details.exception.toString();
    if (text.contains('Failed to load font') || text.contains('google_fonts was unable to load font')) return;
    original?.call(details);
  };
  addTearDown(() => FlutterError.onError = original);
}
