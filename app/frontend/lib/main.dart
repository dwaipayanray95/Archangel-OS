import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'services/server_registry.dart';
import 'ui/boot/boot_splash.dart';
import 'ui/components/ax_scaled_canvas.dart';
import 'ui/shell/archangel_shell.dart';
import 'ui/shell/desktop_prefs.dart';
import 'ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Launch in fullscreen mode like a game (immersive sticky on mobile/tablets)
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const ArchangelApp());
}

/// No Android-style stretch/glow overscroll: it clashes with the calm
/// Halo motion language.
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
        ChangeNotifierProvider(create: (_) => AppState()..loadAppearance()),
        ChangeNotifierProvider(create: (_) => DesktopPrefs()..load()),
        ChangeNotifierProvider(create: (_) => ServerRegistry()..load()),
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
        builder:
            (context, app, _) => MaterialApp(
              title: 'Archangel OS',
              debugShowCheckedModeBanner: false,
              theme: buildTheme(Brightness.light, app.accentChoice),
              darkTheme: buildTheme(Brightness.dark, app.accentChoice),
              themeMode: app.themeMode,
              scrollBehavior: _NoOverscrollBehavior(),
              // The start-up animation plays over everything while the app
              // bootstraps underneath, scaled for elegant desktop viewing.
              builder: (context, child) => AxScaledCanvas(scale: app.uiScale, child: BootGate(child: child ?? const SizedBox.shrink())),
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
    final registry = context.watch<ServerRegistry>();

    if (!wg.isBootstrapped || !backend.isLoaded || !registry.isLoaded) {
      return Scaffold(backgroundColor: context.ax.colors.bg, body: const Center(child: CircularProgressIndicator()));
    }

    if (registry.isEmpty && !wg.isPaired && !backend.isPaired) {
      return const SetupLandingScreen();
    }

    return const ArchangelShell();
  }
}
