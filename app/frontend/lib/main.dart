import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'data/app_state.dart';
import 'screens/setup/setup_landing_screen.dart';
import 'services/admin_mode_service.dart';
import 'services/archangeld_connection.dart';
import 'services/containers_service.dart';
import 'services/devices_service.dart';
import 'services/devops_service.dart';
import 'services/files_service.dart';
import 'services/monitoring_service.dart';
import 'services/update_check_service.dart';
import 'services/wireguard_controller.dart';
import 'theme/app_theme.dart';
import 'theme/tokens.dart';
import 'widgets/app_shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ArchangelApp());
}

/// No Android-style stretch/glow overscroll — it clashes with this design's
/// own motion language and the dark cockpit aesthetic's custom scrollbar.
class _NoOverscrollBehavior extends MaterialScrollBehavior {
  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) => child;
}

class ArchangelApp extends StatelessWidget {
  const ArchangelApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppState()),
        ChangeNotifierProvider(create: (_) => WireGuardController()..bootstrap()),
        ChangeNotifierProvider(create: (_) => ArchangeldConnection()..load()),
        ChangeNotifierProvider(create: (_) => MonitoringService()),
        ChangeNotifierProvider(create: (_) => FilesService()),
        ChangeNotifierProvider(create: (_) => ContainersService()),
        ChangeNotifierProvider(create: (_) => DevopsService()),
        ChangeNotifierProvider(create: (_) => DevicesService()),
        ChangeNotifierProvider(create: (_) => AdminModeService()),
        ChangeNotifierProvider(create: (_) => UpdateCheckService()..loadCache()),
      ],
      child: Consumer<AppState>(
        builder: (context, app, _) => MaterialApp(
          title: 'Archangel',
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(accent: app.accent),
          scrollBehavior: _NoOverscrollBehavior(),
          home: const _RootRouter(),
        ),
      ),
    );
  }
}

/// Decides between the setup wizard (neither the tunnel nor the backend
/// is paired yet) and the main app shell, once both controllers have
/// finished loading their saved state. Watching both controllers means
/// finishing the wizard (which calls WireGuardController.pair /
/// ArchangeldConnection.pair) automatically swaps this to the app shell
/// with no manual navigation required.
class _RootRouter extends StatelessWidget {
  const _RootRouter();

  @override
  Widget build(BuildContext context) {
    final wg = context.watch<WireGuardController>();
    final backend = context.watch<ArchangeldConnection>();

    if (!wg.isBootstrapped || !backend.isLoaded) {
      return Scaffold(
        backgroundColor: AxColors.bg,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (!wg.isPaired && !backend.isPaired) {
      return const SetupLandingScreen();
    }

    return const AppShell();
  }
}
