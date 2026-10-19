import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:archangel/data/app_state.dart';
import 'package:archangel/services/archangeld_connection.dart';
import 'package:archangel/services/containers_service.dart';
import 'package:archangel/services/devops_service.dart';
import 'package:archangel/services/files_service.dart';
import 'package:archangel/services/local_kv_store.dart';
import 'package:archangel/services/monitoring_service.dart';
import 'package:archangel/services/update_check_service.dart';
import 'package:archangel/services/wireguard_controller.dart';
import 'package:archangel/theme/app_theme.dart';
import 'package:archangel/widgets/app_shell.dart';

/// Pumps [AppShell] directly, wrapped in the same providers
/// [ArchangelApp] uses, but bypassing the app's root router (which now
/// shows the first-run setup wizard when neither the tunnel nor the
/// backend is paired - see main.dart's `_RootRouter`). These tests are
/// about AppShell's own rendering, not first-run routing, so they don't
/// need a real paired state.
Future<AppState> pumpAppShell(WidgetTester tester, {Size size = const Size(1400, 900)}) async {
  await useTempKvStore();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);

  final appState = AppState();
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: appState),
        ChangeNotifierProvider(create: (_) => WireGuardController()),
        ChangeNotifierProvider(create: (_) => ArchangeldConnection()),
        ChangeNotifierProvider(create: (_) => MonitoringService()),
        ChangeNotifierProvider(create: (_) => FilesService()),
        ChangeNotifierProvider(create: (_) => ContainersService()),
        ChangeNotifierProvider(create: (_) => DevopsService()),
        ChangeNotifierProvider(create: (_) => UpdateCheckService()),
      ],
      child: Consumer<AppState>(
        builder: (context, app, _) => MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(accent: app.accent),
          home: const AppShell(),
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
  addTearDown(() async {
    LocalKvStore.directoryOverride = null;
    LocalKvStore.instance.resetForTesting();
    if (await dir.exists()) await dir.delete(recursive: true);
  });
  return dir;
}
