import 'dart:math' as math;

import '../../../models/system_metrics.dart';

/// Samples collected since the Activity screen was opened (not server
/// history), capped so memory stays bounded.
class LiveSamples {
  LiveSamples({this.capacity = 120});

  final int capacity;
  final List<double> cpu = [];
  final List<double> memory = [];
  final List<double> diskRead = [];
  final List<double> diskWrite = [];
  final List<double> netIn = [];
  final List<double> netOut = [];

  int get length => cpu.length;

  void add(SystemMetrics m) {
    _push(cpu, m.cpu.usagePercent);
    _push(memory, m.memory.usagePercent);
    _push(diskRead, m.disk.readBytesPerSec);
    _push(diskWrite, m.disk.writeBytesPerSec);
    _push(netIn, m.network.rxBytesPerSec);
    _push(netOut, m.network.txBytesPerSec);
  }

  void _push(List<double> list, double v) {
    list.add(v.isFinite ? v : 0);
    if (list.length > capacity) list.removeAt(0);
  }
}

/// Rounds [value] up to a "nice" axis maximum (1, 2 or 5 times a power of
/// ten) so a chart auto-scales without jumping on every sample. Never
/// returns less than [minimum].
double niceCeil(double value, {double minimum = 1024}) {
  final v = math.max(value, minimum);
  final exp = (math.log(v) / math.ln10).floor();
  final base = math.pow(10, exp).toDouble();
  for (final m in const [1.0, 2.0, 5.0, 10.0]) {
    if (v <= m * base) return m * base;
  }
  return 10 * base;
}

/// "1.5 MB/s", "320 KB/s", "0 B/s".
String formatRate(double bytesPerSec) {
  final v = bytesPerSec.isFinite ? bytesPerSec : 0.0;
  if (v >= 1024 * 1024 * 1024) return '${(v / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB/s';
  if (v >= 1024 * 1024) return '${(v / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  if (v >= 1024) return '${(v / 1024).toStringAsFixed(v >= 100 * 1024 ? 0 : 1)} KB/s';
  return '${v.round()} B/s';
}

String formatBytes(num bytes) {
  const gb = 1024 * 1024 * 1024;
  if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(bytes >= 10 * gb ? 0 : 1)} GB';
  if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${bytes.round()} B';
}

// ---- Process priority ------------------------------------------------------

/// The Linux "nice" range: 19 (politest, lowest priority) to -20 (highest).
const kNiceLowest = 19;
const kNiceHighest = -20;

/// The slider runs 0..39: 0 is "Lower priority" (nice 19), 39 is "Higher
/// priority" (nice -20), and 19 is "Normal" (nice 0).
const kPrioritySteps = 39;

/// Slider position (0 = lowest priority .. 39 = highest) to a nice value.
int niceFromSlider(num position) {
  final p = position.round().clamp(0, kPrioritySteps);
  return kNiceLowest - p;
}

/// A nice value (19 .. -20) to its slider position.
int sliderFromNice(int nice) => (kNiceLowest - nice.clamp(kNiceHighest, kNiceLowest)).clamp(0, kPrioritySteps);

/// Plain-language description of a nice value.
String priorityLabel(int nice) {
  if (nice >= 10) return 'Much lower than normal';
  if (nice > 0) return 'Lower than normal';
  if (nice == 0) return 'Normal';
  if (nice > -10) return 'Higher than normal';
  return 'Much higher than normal';
}

// ---- Processes -------------------------------------------------------------

enum ProcessSort { cpu, memory, name }

/// Filters by name / user / PID and sorts (biggest first, or A-Z for name).
List<LiveProcessInfo> filterAndSortProcesses(List<LiveProcessInfo> all, {String query = '', ProcessSort sort = ProcessSort.cpu}) {
  final q = query.trim().toLowerCase();
  final list =
      q.isEmpty
          ? List<LiveProcessInfo>.of(all)
          : all.where((p) => p.name.toLowerCase().contains(q) || p.user.toLowerCase().contains(q) || p.pid.toString() == q).toList();
  switch (sort) {
    case ProcessSort.cpu:
      list.sort((a, b) => b.cpu.compareTo(a.cpu));
    case ProcessSort.memory:
      list.sort((a, b) => (b.rssBytes > 0 || a.rssBytes > 0) ? b.rssBytes.compareTo(a.rssBytes) : b.mem.compareTo(a.mem));
    case ProcessSort.name:
      list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }
  return list;
}

/// What the one-letter Linux process state means, in plain words.
String processStateLabel(String state) {
  switch (state.isEmpty ? '' : state[0].toUpperCase()) {
    case 'R':
      return 'Working';
    case 'S':
      return 'Waiting';
    case 'D':
      return 'Waiting for disk';
    case 'T':
      return 'Paused';
    case 'Z':
      return 'Finished (not cleaned up)';
    case 'I':
      return 'Idle';
    default:
      return 'Unknown';
  }
}
