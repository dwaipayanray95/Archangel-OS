import 'package:flutter/material.dart';

import '../../../models/devops_model.dart';
import '../../components/status_badge.dart';

/// The four tabs of the Services screen.
enum ServicesTab {
  background('Background', 'background services'),
  scheduled('Scheduled', 'scheduled tasks'),
  web('Web addresses', 'web addresses'),
  deployments('Deployments', 'deployments');

  const ServicesTab(this.label, this.groupNameLower);
  final String label;
  final String groupNameLower;

  String get intro => switch (this) {
    ServicesTab.background => 'Programs that run all the time to keep things working, like your web server or database.',
    ServicesTab.scheduled => 'Jobs that run by themselves at set times, like nightly backups.',
    ServicesTab.web => 'The web addresses that point to your apps, and the secure (HTTPS) setup behind them.',
    ServicesTab.deployments => 'Saved setups that describe how an app is installed. You can look inside one or remove it.',
  };

  String get emptyText => switch (this) {
    ServicesTab.background => 'No background services found.',
    ServicesTab.scheduled => 'No scheduled tasks yet.',
    ServicesTab.web => 'No web addresses yet. Make an app public in Apps to get one.',
    ServicesTab.deployments => 'No saved deployments.',
  };
}

/// Status badge mapping per spec:
/// - ok == true -> ok, check icon, text = server status (e.g. "Running", "Last run OK", "HTTPS on")
/// - ok == false and status contains "fail" or "error" -> danger, error icon, server text (e.g. "Failed")
/// - otherwise -> neutral, stop icon, server text (e.g. "Stopped")
StatusBadge rowStatusBadge(DevRowModel row) {
  if (row.ok) {
    return StatusBadge.ok(row.status, icon: Icons.check_circle_outline);
  }
  final lower = row.status.toLowerCase();
  if (lower.contains('fail') || lower.contains('error')) {
    return StatusBadge.error(row.status, icon: Icons.error_outline);
  }
  return StatusBadge.neutral(row.status, icon: Icons.stop_circle_outlined);
}
