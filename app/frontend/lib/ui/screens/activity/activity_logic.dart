import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../../models/system_metrics.dart';
import '../../components/status_badge.dart';

/// The overall server status shown in the Hero status card.
enum ServerActivityState { calm, busy, struggling }

class ServerStatusInfo {
  final ServerActivityState state;
  final String title;
  final String line;
  final IconData icon;
  final AxStatus status;

  const ServerStatusInfo({required this.state, required this.title, required this.line, required this.icon, required this.status});
}

/// Computes the 10-second rolling average of CPU or memory from history.
double calculate10sAverage(List<double> history, double fallback) {
  if (history.isEmpty) return fallback;
  // History points are collected every ~2 s, so 10 s is the last 5 readings.
  final sampleCount = math.min(5, history.length);
  final slice = history.sublist(history.length - sampleCount);
  if (slice.isEmpty) return fallback;
  final sum = slice.fold<double>(0.0, (prev, v) => prev + v);
  return sum / slice.length;
}

/// Computes the server status card info based on 10s CPU and memory averages.
///
/// Cut-offs per spec:
/// - calm: CPU < 60 and memory < 75
/// - busy: otherwise
/// - struggling: CPU >= 90 or memory >= 95
ServerStatusInfo calculateServerStatus(double cpu, double memory) {
  if (cpu >= 90 || memory >= 95) {
    return const ServerStatusInfo(
      state: ServerActivityState.struggling,
      title: 'Your server is struggling',
      line: "It's close to its limits, so things may feel slow. The busiest programs are below.",
      icon: Icons.error_outline,
      status: AxStatus.error,
    );
  }
  if (cpu < 60 && memory < 75) {
    return const ServerStatusInfo(
      state: ServerActivityState.calm,
      title: 'Your server is calm',
      line: 'Everything is running comfortably. Nothing needs your attention.',
      icon: Icons.verified_user_outlined,
      status: AxStatus.ok,
    );
  }
  return const ServerStatusInfo(
    state: ServerActivityState.busy,
    title: 'Your server is busy',
    line: "It's working hard right now. That's fine for a while. If it stays busy, check the programs below.",
    icon: Icons.show_chart,
    status: AxStatus.warning,
  );
}

class MeaningInfo {
  final String label;
  final AxStatus status;
  final IconData icon;

  const MeaningInfo({required this.label, required this.status, required this.icon});
}

/// Meaning for CPU: < 50 "Plenty free" (ok) · 50–85 "Working hard" (warn) · >= 85 "Maxed out" (error)
MeaningInfo cpuMeaning(double cpu) {
  if (cpu < 50) {
    return const MeaningInfo(label: 'Plenty free', status: AxStatus.ok, icon: Icons.check_circle_outline);
  }
  if (cpu < 85) {
    return const MeaningInfo(label: 'Working hard', status: AxStatus.warning, icon: Icons.warning_amber_rounded);
  }
  return const MeaningInfo(label: 'Maxed out', status: AxStatus.error, icon: Icons.error_outline);
}

/// Meaning for Memory: < 75 "Comfortable" · 75–95 "Running low" (warn) · >= 95 "Almost full" (error)
MeaningInfo memoryMeaning(double memPercent) {
  if (memPercent < 75) {
    return const MeaningInfo(label: 'Comfortable', status: AxStatus.ok, icon: Icons.check_circle_outline);
  }
  if (memPercent < 95) {
    return const MeaningInfo(label: 'Running low', status: AxStatus.warning, icon: Icons.warning_amber_rounded);
  }
  return const MeaningInfo(label: 'Almost full', status: AxStatus.error, icon: Icons.error_outline);
}

/// Meaning for Disk: < 70 "Plenty of space" · 70–90 "Getting full" (warn) · >= 90 "Almost full" (error)
MeaningInfo diskMeaning(double diskPercent) {
  if (diskPercent < 70) {
    return const MeaningInfo(label: 'Plenty of space', status: AxStatus.ok, icon: Icons.check_circle_outline);
  }
  if (diskPercent < 90) {
    return const MeaningInfo(label: 'Getting full', status: AxStatus.warning, icon: Icons.warning_amber_rounded);
  }
  return const MeaningInfo(label: 'Almost full', status: AxStatus.error, icon: Icons.error_outline);
}

/// Meaning for Network: < 2 MB/s "Quiet" · else "Normal" (both ok)
MeaningInfo networkMeaning(double bytesPerSec) {
  final mbPerSec = bytesPerSec / (1024 * 1024);
  if (mbPerSec < 2.0) {
    return const MeaningInfo(label: 'Quiet', status: AxStatus.ok, icon: Icons.check_circle_outline);
  }
  return const MeaningInfo(label: 'Normal', status: AxStatus.ok, icon: Icons.check_circle_outline);
}

/// "1.5 MB/s", "320 KB/s", "0 B/s".
String formatRate(double bytesPerSec) {
  final v = bytesPerSec.isFinite ? bytesPerSec : 0.0;
  if (v >= 1024 * 1024 * 1024) return '${(v / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB/s';
  if (v >= 1024 * 1024) return '${(v / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  if (v >= 1024) return '${(v / 1024).toStringAsFixed(v >= 100 * 1024 ? 0 : 1)} KB/s';
  return '${v.round()} B/s';
}

/// "2.1 GB", "4 GB", "100 GB".
String formatBytes(num bytes) {
  const gb = 1024 * 1024 * 1024;
  if (bytes >= gb) {
    final val = bytes / gb;
    return val >= 10 || val.truncateToDouble() == val ? '${val.toStringAsFixed(0)} GB' : '${val.toStringAsFixed(1)} GB';
  }
  if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${bytes.round()} B';
}

/// Detailed long uptime formatted as "12 days, 3 hours" or "5 hours, 20 minutes".
String formatUptimeLong(int seconds) {
  if (seconds <= 0) return '—';
  final days = seconds ~/ 86400;
  final hours = (seconds % 86400) ~/ 3600;
  final mins = (seconds % 3600) ~/ 60;
  if (days > 0) {
    final dStr = '$days ${days == 1 ? 'day' : 'days'}';
    final hStr = '$hours ${hours == 1 ? 'hour' : 'hours'}';
    return '$dStr, $hStr';
  }
  if (hours > 0) {
    final hStr = '$hours ${hours == 1 ? 'hour' : 'hours'}';
    final mStr = '$mins ${mins == 1 ? 'minute' : 'minutes'}';
    return '$hStr, $mStr';
  }
  return '$mins ${mins == 1 ? 'minute' : 'minutes'}';
}

/// Filters by name / user in the server process list and sorts by CPU or Memory descending.
List<LiveProcessInfo> filterAndSortPrograms(List<LiveProcessInfo> processes, {String query = '', required bool sortByMemory}) {
  final q = query.trim().toLowerCase();
  final filtered =
      q.isEmpty
          ? List<LiveProcessInfo>.of(processes)
          : processes.where((p) => p.name.toLowerCase().contains(q) || p.user.toLowerCase().contains(q)).toList();
  if (sortByMemory) {
    filtered.sort((a, b) => (b.rssBytes > 0 || a.rssBytes > 0) ? b.rssBytes.compareTo(a.rssBytes) : b.mem.compareTo(a.mem));
  } else {
    filtered.sort((a, b) => b.cpu.compareTo(a.cpu));
  }
  return filtered;
}

/// Programs that keep the server reachable. Stopping one can cut the person
/// off from their own server, so the stop dialogs make them type its name.
const List<String> kCriticalProcessNames = ['systemd', 'sshd', 'archangeld', 'wg-quick', 'wireguard', 'dockerd', 'containerd'];

/// True for PID 1 and for programs whose name contains one of
/// [kCriticalProcessNames] (case-insensitive, so `sshd: user@pts/0` counts).
bool isCriticalProcess(int pid, String name) {
  if (pid == 1) return true;
  final n = name.toLowerCase();
  return kCriticalProcessNames.any(n.contains);
}
