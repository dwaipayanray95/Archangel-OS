import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/app_state.dart';
import '../services/archangeld_connection.dart';
import '../services/browser_service.dart';
import '../ui/screens/browser/browser_workspace.dart';
import '../ui/screens/browser/web_view_host.dart';
import '../ui/ui.dart';

/// Browser: pages open on this device, in tabs.
class BrowserScreen extends StatelessWidget {
  const BrowserScreen({super.key, this.controllerFactory});

  /// Makes each tab's controller; defaults to the one installed at start-up.
  final AxWebControllerFactory? controllerFactory;

  @override
  Widget build(BuildContext context) {
    final backend = context.watch<ArchangeldConnection>();
    if (!backend.isPaired) {
      return AxPage(
        title: 'Browser',
        child: EmptyState(
          icon: Icons.cloud_off_rounded,
          title: 'Not connected to a server',
          message: 'Pair Archangel with a server to use the browser.',
          actionLabel: 'Connect a server',
          onAction: () => context.read<AppState>().go(AxSection.settings),
        ),
      );
    }
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: BrowserWorkspace(service: context.read<BrowserService>(), controllerFactory: controllerFactory),
      ),
    );
  }
}
