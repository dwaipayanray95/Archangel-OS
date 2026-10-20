class DockerContainerItem {
  final String id;
  final String name;
  final String image;
  final String stack;
  final String state;
  final String status;
  final String uptime;
  final double cpu;
  final int memMb;
  final String memLabel;
  final String ports;
  final String cid;
  final bool running;

  const DockerContainerItem({
    required this.id,
    required this.name,
    required this.image,
    required this.stack,
    required this.state,
    required this.status,
    required this.uptime,
    required this.cpu,
    required this.memMb,
    required this.memLabel,
    required this.ports,
    required this.cid,
    required this.running,
  });

  factory DockerContainerItem.fromJson(Map<String, dynamic> json) {
    return DockerContainerItem(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      image: json['image'] as String? ?? '',
      stack: json['stack'] as String? ?? 'standalone',
      state: json['state'] as String? ?? 'stopped',
      status: json['status'] as String? ?? '',
      uptime: json['uptime'] as String? ?? '—',
      cpu: (json['cpu'] as num?)?.toDouble() ?? 0.0,
      memMb: (json['mem_mb'] as num?)?.toInt() ?? 0,
      memLabel: json['mem_label'] as String? ?? '—',
      ports: json['ports'] as String? ?? '—',
      cid: json['cid'] as String? ?? '',
      running: json['running'] as bool? ?? (json['state'] == 'running'),
    );
  }
}

class DockerOverviewModel {
  final bool dockerAvailable;
  final String engineVersion;
  final int runningCount;
  final int stoppedCount;
  final String totalImagesSize;
  final List<DockerContainerItem> containers;
  final List<String> stacks;
  final Map<String, String> stackMeta;

  const DockerOverviewModel({
    required this.dockerAvailable,
    required this.engineVersion,
    required this.runningCount,
    required this.stoppedCount,
    required this.totalImagesSize,
    required this.containers,
    required this.stacks,
    required this.stackMeta,
  });

  factory DockerOverviewModel.fromJson(Map<String, dynamic> json) {
    final rawList =
        (json['containers'] as List<dynamic>?)?.map((e) => DockerContainerItem.fromJson(e as Map<String, dynamic>)).toList() ?? [];

    final rawStacks = (json['stacks'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
    final rawMeta = (json['stack_meta'] as Map<String, dynamic>?)?.map((k, v) => MapEntry(k, v.toString())) ?? {};

    return DockerOverviewModel(
      dockerAvailable: json['docker_available'] as bool? ?? false,
      engineVersion: json['engine_version'] as String? ?? 'offline',
      runningCount: (json['running_count'] as num?)?.toInt() ?? 0,
      stoppedCount: (json['stopped_count'] as num?)?.toInt() ?? 0,
      totalImagesSize: json['total_images_size'] as String? ?? '—',
      containers: rawList,
      stacks: rawStacks,
      stackMeta: rawMeta,
    );
  }
}

class DockerLogEntry {
  final String ts;
  final String level;
  final String source;
  final String text;

  const DockerLogEntry({required this.ts, required this.level, required this.source, required this.text});

  factory DockerLogEntry.fromJson(Map<String, dynamic> json) {
    return DockerLogEntry(
      ts: json['ts'] as String? ?? '',
      level: json['level'] as String? ?? 'INFO',
      source: json['source'] as String? ?? '',
      text: json['text'] as String? ?? '',
    );
  }
}
