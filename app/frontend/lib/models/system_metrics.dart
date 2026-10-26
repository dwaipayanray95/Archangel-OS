class CoreMetric {
  final int id;
  final double usagePercent;
  final double? mhz;

  const CoreMetric({required this.id, required this.usagePercent, this.mhz});

  factory CoreMetric.fromJson(Map<String, dynamic> json) {
    return CoreMetric(
      id: (json['id'] as num?)?.toInt() ?? 0,
      usagePercent: (json['usage_percent'] as num?)?.toDouble() ?? 0.0,
      mhz: (json['mhz'] as num?)?.toDouble(),
    );
  }

  String get speedLabel {
    if (mhz == null || mhz! <= 0) return '';
    if (mhz! >= 1000) {
      return '${(mhz! / 1000.0).toStringAsFixed(1)} GHz';
    }
    return '${mhz!.round()} MHz';
  }
}

class CPUMetrics {
  final double usagePercent;
  final List<CoreMetric> cores;
  final List<double> history;

  const CPUMetrics({required this.usagePercent, required this.cores, required this.history});

  factory CPUMetrics.fromJson(Map<String, dynamic> json) {
    final coresList = (json['cores'] as List<dynamic>?)?.map((e) => CoreMetric.fromJson(e as Map<String, dynamic>)).toList() ?? [];
    final hist = (json['history'] as List<dynamic>?)?.map((e) => (e as num).toDouble()).toList() ?? [];
    return CPUMetrics(usagePercent: (json['usage_percent'] as num?)?.toDouble() ?? 0.0, cores: coresList, history: hist);
  }
}

class MemoryMetrics {
  final int totalBytes;
  final int usedBytes;
  final int availableBytes;
  final int freeBytes;
  final int buffersBytes;
  final int cachedBytes;
  final int swapTotalBytes;
  final int swapUsedBytes;
  final double usagePercent;
  final List<double> history;

  const MemoryMetrics({
    required this.totalBytes,
    required this.usedBytes,
    required this.availableBytes,
    this.freeBytes = 0,
    this.buffersBytes = 0,
    this.cachedBytes = 0,
    this.swapTotalBytes = 0,
    this.swapUsedBytes = 0,
    required this.usagePercent,
    required this.history,
  });

  factory MemoryMetrics.fromJson(Map<String, dynamic> json) {
    final hist = (json['history'] as List<dynamic>?)?.map((e) => (e as num).toDouble()).toList() ?? [];
    return MemoryMetrics(
      totalBytes: (json['total_bytes'] as num?)?.toInt() ?? 0,
      usedBytes: (json['used_bytes'] as num?)?.toInt() ?? 0,
      availableBytes: (json['available_bytes'] as num?)?.toInt() ?? 0,
      freeBytes: (json['free_bytes'] as num?)?.toInt() ?? 0,
      buffersBytes: (json['buffers_bytes'] as num?)?.toInt() ?? 0,
      cachedBytes: (json['cached_bytes'] as num?)?.toInt() ?? 0,
      swapTotalBytes: (json['swap_total_bytes'] as num?)?.toInt() ?? 0,
      swapUsedBytes: (json['swap_used_bytes'] as num?)?.toInt() ?? 0,
      usagePercent: (json['usage_percent'] as num?)?.toDouble() ?? 0.0,
      history: hist,
    );
  }

  double get totalGb => totalBytes / (1024 * 1024 * 1024);
  double get usedGb => usedBytes / (1024 * 1024 * 1024);
  double get availableGb => availableBytes / (1024 * 1024 * 1024);
  double get freeGb => freeBytes / (1024 * 1024 * 1024);
  double get cachedGb => (cachedBytes + buffersBytes) / (1024 * 1024 * 1024);
  double get swapUsedGb => swapUsedBytes / (1024 * 1024 * 1024);
  double get swapTotalGb => swapTotalBytes / (1024 * 1024 * 1024);

  // App / System memory (total used minus cache/buffers)
  double get appUsedGb {
    final cacheAndBuffers = cachedBytes + buffersBytes;
    if (usedBytes > cacheAndBuffers) {
      return (usedBytes - cacheAndBuffers) / (1024 * 1024 * 1024);
    }
    return usedGb;
  }
}

class MountMetric {
  final String mountPoint;
  final String device;
  final int totalBytes;
  final int usedBytes;
  final int freeBytes;
  final int availableBytes;

  const MountMetric({
    required this.mountPoint,
    required this.device,
    required this.totalBytes,
    required this.usedBytes,
    this.freeBytes = 0,
    this.availableBytes = 0,
  });

  factory MountMetric.fromJson(Map<String, dynamic> json) {
    return MountMetric(
      mountPoint: json['mount_point'] as String? ?? '/',
      device: json['device'] as String? ?? '',
      totalBytes: (json['total_bytes'] as num?)?.toInt() ?? 0,
      usedBytes: (json['used_bytes'] as num?)?.toInt() ?? 0,
      freeBytes: (json['free_bytes'] as num?)?.toInt() ?? 0,
      availableBytes: (json['available_bytes'] as num?)?.toInt() ?? 0,
    );
  }

  double get usagePercent => totalBytes > 0 ? (usedBytes / totalBytes) * 100.0 : 0.0;
  double get totalGb => totalBytes / (1024 * 1024 * 1024);
  double get usedGb => usedBytes / (1024 * 1024 * 1024);
  double get freeGb => (freeBytes > 0 ? freeBytes : (totalBytes > usedBytes ? totalBytes - usedBytes : 0)) / (1024 * 1024 * 1024);
  double get availableGb => (availableBytes > 0 ? availableBytes : freeBytes) / (1024 * 1024 * 1024);
}

class DiskMetrics {
  final double readBytesPerSec;
  final double writeBytesPerSec;
  final int totalBytes;
  final int usedBytes;
  final int freeBytes;
  final int availableBytes;
  final double usagePercent;
  final List<MountMetric> mounts;
  final List<double> history;

  const DiskMetrics({
    required this.readBytesPerSec,
    required this.writeBytesPerSec,
    required this.totalBytes,
    required this.usedBytes,
    this.freeBytes = 0,
    this.availableBytes = 0,
    required this.usagePercent,
    required this.mounts,
    required this.history,
  });

  factory DiskMetrics.fromJson(Map<String, dynamic> json) {
    final mountsList = (json['mounts'] as List<dynamic>?)?.map((e) => MountMetric.fromJson(e as Map<String, dynamic>)).toList() ?? [];
    final hist = (json['history'] as List<dynamic>?)?.map((e) => (e as num).toDouble()).toList() ?? [];
    return DiskMetrics(
      readBytesPerSec: (json['read_bytes_per_sec'] as num?)?.toDouble() ?? 0.0,
      writeBytesPerSec: (json['write_bytes_per_sec'] as num?)?.toDouble() ?? 0.0,
      totalBytes: (json['total_bytes'] as num?)?.toInt() ?? 0,
      usedBytes: (json['used_bytes'] as num?)?.toInt() ?? 0,
      freeBytes: (json['free_bytes'] as num?)?.toInt() ?? 0,
      availableBytes: (json['available_bytes'] as num?)?.toInt() ?? 0,
      usagePercent: (json['usage_percent'] as num?)?.toDouble() ?? 0.0,
      mounts: mountsList,
      history: hist,
    );
  }

  double get readMbPerSec => readBytesPerSec / (1024 * 1024);
  double get writeMbPerSec => writeBytesPerSec / (1024 * 1024);
  double get totalMbPerSec => readMbPerSec + writeMbPerSec;
  double get totalGb => totalBytes / (1024 * 1024 * 1024);
  double get usedGb => usedBytes / (1024 * 1024 * 1024);
  double get freeGb => (freeBytes > 0 ? freeBytes : (totalBytes > usedBytes ? totalBytes - usedBytes : 0)) / (1024 * 1024 * 1024);
  double get availableGb => (availableBytes > 0 ? availableBytes : freeBytes) / (1024 * 1024 * 1024);
}

class StorageItem {
  final String name;
  final String path;
  final int bytes;
  final String description;
  final String version;

  const StorageItem({required this.name, this.path = '', required this.bytes, this.description = '', this.version = ''});

  factory StorageItem.fromJson(Map<String, dynamic> json) => StorageItem(
    name: json['name'] as String? ?? '',
    path: json['path'] as String? ?? '',
    bytes: (json['bytes'] as num?)?.toInt() ?? 0,
    description: json['description'] as String? ?? '',
    version: json['version'] as String? ?? '',
  );
}

class DiskBreakdown {
  final List<StorageItem> folders;
  final List<StorageItem> packages;

  const DiskBreakdown({required this.folders, required this.packages});

  factory DiskBreakdown.fromJson(Map<String, dynamic> json) => DiskBreakdown(
    folders: (json['folders'] as List<dynamic>?)?.map((e) => StorageItem.fromJson(e as Map<String, dynamic>)).toList() ?? const [],
    packages: (json['packages'] as List<dynamic>?)?.map((e) => StorageItem.fromJson(e as Map<String, dynamic>)).toList() ?? const [],
  );
}

class NetInterfaceMetric {
  final String name;
  final double rxBytesPerSec;
  final double txBytesPerSec;

  const NetInterfaceMetric({required this.name, required this.rxBytesPerSec, required this.txBytesPerSec});

  factory NetInterfaceMetric.fromJson(Map<String, dynamic> json) {
    return NetInterfaceMetric(
      name: json['name'] as String? ?? 'eth0',
      rxBytesPerSec: (json['rx_bytes_per_sec'] as num?)?.toDouble() ?? 0.0,
      txBytesPerSec: (json['tx_bytes_per_sec'] as num?)?.toDouble() ?? 0.0,
    );
  }

  double get rxMbPerSec => rxBytesPerSec / (1024 * 1024);
  double get txMbPerSec => txBytesPerSec / (1024 * 1024);
}

class NetworkMetrics {
  final double rxBytesPerSec;
  final double txBytesPerSec;
  final List<NetInterfaceMetric> interfaces;
  final List<double> history;

  const NetworkMetrics({required this.rxBytesPerSec, required this.txBytesPerSec, required this.interfaces, required this.history});

  factory NetworkMetrics.fromJson(Map<String, dynamic> json) {
    final ifaces =
        (json['interfaces'] as List<dynamic>?)?.map((e) => NetInterfaceMetric.fromJson(e as Map<String, dynamic>)).toList() ?? [];
    final hist = (json['history'] as List<dynamic>?)?.map((e) => (e as num).toDouble()).toList() ?? [];
    return NetworkMetrics(
      rxBytesPerSec: (json['rx_bytes_per_sec'] as num?)?.toDouble() ?? 0.0,
      txBytesPerSec: (json['tx_bytes_per_sec'] as num?)?.toDouble() ?? 0.0,
      interfaces: ifaces,
      history: hist,
    );
  }

  double get rxMbPerSec => rxBytesPerSec / (1024 * 1024);
  double get txMbPerSec => txBytesPerSec / (1024 * 1024);
  double get totalMbPerSec => rxMbPerSec + txMbPerSec;
}

class HostInfo {
  final String hostname;
  final String os;
  final String kernel;
  final String arch;

  const HostInfo({this.hostname = '', this.os = '', this.kernel = '', this.arch = ''});

  factory HostInfo.fromJson(Map<String, dynamic> json) {
    return HostInfo(
      hostname: json['hostname'] as String? ?? '',
      os: json['os'] as String? ?? '',
      kernel: json['kernel'] as String? ?? '',
      arch: json['arch'] as String? ?? '',
    );
  }
}

class SystemMetrics {
  final int timestamp;
  final int uptimeSeconds;
  final HostInfo host;
  final CPUMetrics cpu;
  final MemoryMetrics memory;
  final DiskMetrics disk;
  final NetworkMetrics network;

  const SystemMetrics({
    required this.timestamp,
    this.uptimeSeconds = 0,
    this.host = const HostInfo(),
    required this.cpu,
    required this.memory,
    required this.disk,
    required this.network,
  });

  factory SystemMetrics.fromJson(Map<String, dynamic> json) {
    return SystemMetrics(
      timestamp: (json['timestamp'] as num?)?.toInt() ?? 0,
      uptimeSeconds: (json['uptime_seconds'] as num?)?.toInt() ?? 0,
      host: HostInfo.fromJson((json['host'] as Map<String, dynamic>?) ?? const {}),
      cpu: CPUMetrics.fromJson((json['cpu'] as Map<String, dynamic>?) ?? const {}),
      memory: MemoryMetrics.fromJson((json['memory'] as Map<String, dynamic>?) ?? const {}),
      disk: DiskMetrics.fromJson((json['disk'] as Map<String, dynamic>?) ?? const {}),
      network: NetworkMetrics.fromJson((json['network'] as Map<String, dynamic>?) ?? const {}),
    );
  }

  String get uptimeLabel {
    if (uptimeSeconds <= 0) return '—';
    final days = uptimeSeconds ~/ 86400;
    final hours = (uptimeSeconds % 86400) ~/ 3600;
    if (days > 0) return '${days}d';
    if (hours > 0) return '${hours}h';
    final mins = (uptimeSeconds % 3600) ~/ 60;
    return '${mins}m';
  }

  String get detailedUptimeLabel {
    if (uptimeSeconds <= 0) return '—';
    final days = uptimeSeconds ~/ 86400;
    final hours = (uptimeSeconds % 86400) ~/ 3600;
    final mins = (uptimeSeconds % 3600) ~/ 60;
    final parts = <String>[];
    if (days > 0) parts.add('${days}d');
    if (hours > 0 || days > 0) parts.add('${hours}h');
    parts.add('${mins}m');
    return parts.join(' ');
  }
}

class LiveProcessInfo {
  final int pid;
  final String name;
  final String user;
  final double cpu;
  final double mem;
  final int rssBytes;
  final String state;

  const LiveProcessInfo({
    required this.pid,
    required this.name,
    required this.user,
    required this.cpu,
    required this.mem,
    this.rssBytes = 0,
    required this.state,
  });

  factory LiveProcessInfo.fromJson(Map<String, dynamic> json) {
    return LiveProcessInfo(
      pid: (json['pid'] as num?)?.toInt() ?? 0,
      name: json['name'] as String? ?? '',
      user: json['user'] as String? ?? '',
      cpu: (json['cpu'] as num?)?.toDouble() ?? 0.0,
      mem: (json['mem'] as num?)?.toDouble() ?? 0.0,
      rssBytes: (json['rss_bytes'] as num?)?.toInt() ?? 0,
      state: json['state'] as String? ?? 'S',
    );
  }

  String get memoryLabel {
    if (rssBytes <= 0) {
      return '${mem.toStringAsFixed(1)}%';
    }
    final mb = rssBytes / (1024 * 1024);
    if (mb >= 1024) {
      return '${(mb / 1024.0).toStringAsFixed(1)} GB';
    }
    return '${mb.toStringAsFixed(1)} MB';
  }
}
