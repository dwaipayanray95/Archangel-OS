import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/admin_mode_service.dart';
import '../services/app_version.dart';
import '../services/archangeld_connection.dart';
import '../services/devices_service.dart';
import '../services/update_check_service.dart';
import '../ui/screens/settings/devices_admin_sections.dart';
import '../ui/screens/settings/other_sections.dart';
import '../ui/screens/settings/servers_section.dart';
import '../ui/screens/settings/this_server_section.dart';
import '../ui/ui.dart';

/// Settings: servers, this server, devices, Admin mode, security, appearance,
/// updates and the danger zone - one plain-language card each.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  /// The backend host the devices/Admin-mode services were last pointed at,
  /// so they (re)load when pairing changes while this screen is open.
  String? _servicesHost;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<UpdateCheckService>().checkForUpdates();
    });
  }

  void _syncBackendServices(ArchangeldConnection backend) {
    final host = backend.isPaired ? backend.host : null;
    if (host == _servicesHost) return;
    _servicesHost = host;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<DevicesService>().init(backend);
      context.read<AdminModeService>().init(backend);
    });
  }

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final backend = context.watch<ArchangeldConnection>();
    _syncBackendServices(backend);
    final gap = SizedBox(height: ax.space.lg);

    return AxPage(
      title: 'Settings',
      subtitle: 'Archangel v${AppVersion.archangel}',
      maxContentWidth: 760,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ServersSection(),
          gap,
          const ThisServerSection(),
          if (backend.isPaired) ...[gap, const DevicesSection(), gap, const AdminModeSection()],
          gap,
          const SecuritySection(),
          gap,
          const AppearanceSection(),
          gap,
          const UpdatesSection(),
          gap,
          const DangerZoneSection(),
        ],
      ),
    );
  }
}
