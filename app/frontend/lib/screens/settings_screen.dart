import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/admin_mode_service.dart';
import '../services/app_version.dart';
import '../services/archangeld_connection.dart';
import '../services/devices_service.dart';
import '../services/update_check_service.dart';
import '../ui/screens/settings/settings_view.dart';

/// Settings: servers, devices, Admin mode, security, appearance, updates and
/// the danger zone, laid out by [SettingsView].
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
    final backend = context.watch<ArchangeldConnection>();
    _syncBackendServices(backend);
    return SettingsView(paired: backend.isPaired, version: AppVersion.current);
  }
}
