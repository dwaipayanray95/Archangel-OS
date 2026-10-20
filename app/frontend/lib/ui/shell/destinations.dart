import 'package:flutter/material.dart';

import '../../data/app_state.dart';
import '../../screens/containers_screen.dart';
import '../../screens/devops_screen.dart';
import '../../screens/files_screen.dart';
import '../../screens/monitoring_screen.dart';
import '../../screens/overview_screen.dart';
import '../../screens/settings_screen.dart';
import '../../screens/terminal_screen.dart';

const axSectionIcons = <AxSection, IconData>{
  AxSection.home: Icons.home_outlined,
  AxSection.apps: Icons.apps_rounded,
  AxSection.files: Icons.folder_outlined,
  AxSection.terminal: Icons.terminal_rounded,
  AxSection.activity: Icons.show_chart_rounded,
  AxSection.services: Icons.layers_outlined,
  AxSection.settings: Icons.settings_outlined,
};

const axSectionSelectedIcons = <AxSection, IconData>{
  AxSection.home: Icons.home_rounded,
  AxSection.apps: Icons.apps_rounded,
  AxSection.files: Icons.folder_rounded,
  AxSection.terminal: Icons.terminal_rounded,
  AxSection.activity: Icons.show_chart_rounded,
  AxSection.services: Icons.layers_rounded,
  AxSection.settings: Icons.settings_rounded,
};

/// The screen hosted by each destination. For now these are the existing
/// screens; the Phase 2 screen rewrites replace them one by one.
Widget buildDestination(AxSection section) => switch (section) {
  AxSection.home => const OverviewScreen(),
  AxSection.apps => const ContainersScreen(),
  AxSection.files => const FilesScreen(),
  AxSection.terminal => const TerminalScreen(),
  AxSection.activity => const MonitoringScreen(),
  AxSection.services => const DevopsScreen(),
  AxSection.settings => const SettingsScreen(),
};
