import 'package:flutter/material.dart';

import '../../../models/devops_model.dart';
import '../../ui.dart';

/// The four tabs of the Services screen, with their plain-language labels.
enum ServicesTab {
  services('Background services'),
  timers('Scheduled tasks'),
  web('Web addresses'),
  scripts('Scripts');

  const ServicesTab(this.label);
  final String label;
}

/// A script name must end in .sh and use only letters, digits, dot, dash and
/// underscore. Returns an explanation of what is wrong, or null when valid.
String? validateScriptName(String raw) {
  final name = raw.trim();
  if (name.isEmpty) return 'Give the script a name, for example deploy.sh.';
  if (!name.endsWith('.sh')) return 'The name must end with .sh, for example deploy.sh.';
  if (name.length > 64) return 'Use 64 characters or fewer.';
  if (name == '.sh') return 'Add a name before .sh, for example deploy.sh.';
  if (name.startsWith('.') || name.startsWith('-')) return 'The name can’t start with a dot or a dash.';
  if (name.contains('..')) return 'The name can’t contain two dots in a row.';
  if (!RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(name)) {
    return 'Use only letters, numbers, dots, dashes and underscores (no spaces or slashes).';
  }
  return null;
}

/// True when a refusal means Admin mode has to be switched on first.
bool isAdminModeRefusal(String? message, int? status) => status == 403 || (message?.toLowerCase().contains('admin mode') ?? false);

/// The status pill for a row: always icon + words.
StatusBadge rowBadge(ServicesTab tab, DevRowModel row) {
  final raw = row.status.toLowerCase();
  final failed = raw.contains('fail') || raw.contains('error') || raw.contains('dead');
  switch (tab) {
    case ServicesTab.services:
      if (row.ok) return const StatusBadge.ok('Running');
      if (failed) return const StatusBadge.error('Failed');
      return const StatusBadge.neutral('Stopped', icon: Icons.stop_circle_outlined);
    case ServicesTab.timers:
      if (row.ok) return const StatusBadge.ok('Scheduled');
      return failed ? const StatusBadge.error('Failed') : const StatusBadge.warning('Not scheduled');
    case ServicesTab.web:
      if (row.ok) return const StatusBadge.ok('Online');
      return failed ? const StatusBadge.error('Not working') : const StatusBadge.warning('Not checked');
    case ServicesTab.scripts:
      if (row.ok) return const StatusBadge.ok('Ready');
      return failed ? const StatusBadge.error('Last run failed') : const StatusBadge.neutral('Not run yet');
  }
}

/// Second line of a row: details from the server, plus its raw status when
/// something is not fine.
String rowDetails(DevRowModel row) {
  final parts = <String>[if (row.meta.isNotEmpty) row.meta, if (!row.ok && row.status.isNotEmpty && row.status != row.meta) row.status];
  return parts.join(' - ');
}
