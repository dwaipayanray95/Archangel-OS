class FileEntryModel {
  final String name;
  final String path;
  final String kind; // "dir", "file", "symlink", "log"
  final int sizeBytes;
  final String size;
  final String perms;
  final String mtime;
  final String? owner;
  final String? group;
  final String? target;
  final bool isBroken;

  const FileEntryModel({
    required this.name,
    required this.path,
    required this.kind,
    required this.sizeBytes,
    required this.size,
    required this.perms,
    required this.mtime,
    this.owner,
    this.group,
    this.target,
    this.isBroken = false,
  });

  bool get isDir => kind == 'dir';
  bool get isLog => kind == 'log';
  bool get isSymlink => kind == 'symlink';

  factory FileEntryModel.fromJson(Map<String, dynamic> json) {
    return FileEntryModel(
      name: json['name'] as String? ?? '',
      path: json['path'] as String? ?? '',
      kind: json['kind'] as String? ?? 'file',
      sizeBytes: (json['size_bytes'] as num?)?.toInt() ?? 0,
      size: json['size'] as String? ?? '—',
      perms: json['perms'] as String? ?? '-rw-r--r--',
      mtime: json['mtime'] as String? ?? '',
      owner: json['owner'] as String?,
      group: json['group'] as String?,
      target: json['target'] as String?,
      isBroken: json['is_broken'] as bool? ?? false,
    );
  }
}

class DirectoryListingModel {
  final String path;
  final String parent;
  final List<FileEntryModel> entries;
  final int totalEntries;
  final bool readable;
  final String? error;

  const DirectoryListingModel({
    required this.path,
    required this.parent,
    required this.entries,
    required this.totalEntries,
    required this.readable,
    this.error,
  });

  factory DirectoryListingModel.fromJson(Map<String, dynamic> json) {
    final list = (json['entries'] as List<dynamic>?)?.map((e) => FileEntryModel.fromJson(e as Map<String, dynamic>)).toList() ?? [];
    return DirectoryListingModel(
      path: json['path'] as String? ?? '/',
      parent: json['parent'] as String? ?? '/',
      entries: list,
      totalEntries: (json['total_entries'] as num?)?.toInt() ?? list.length,
      readable: json['readable'] as bool? ?? true,
      error: json['error'] as String?,
    );
  }
}

class FileContentResult {
  final String path;
  final String name;
  final int sizeBytes;
  final List<String> lines;
  final int lineCount;
  final bool truncated;
  final bool isBinary;
  final String mimeType;

  const FileContentResult({
    required this.path,
    required this.name,
    required this.sizeBytes,
    required this.lines,
    required this.lineCount,
    required this.truncated,
    required this.isBinary,
    required this.mimeType,
  });

  factory FileContentResult.fromJson(Map<String, dynamic> json) {
    final rawLines = (json['lines'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
    return FileContentResult(
      path: json['path'] as String? ?? '',
      name: json['name'] as String? ?? '',
      sizeBytes: (json['size_bytes'] as num?)?.toInt() ?? 0,
      lines: rawLines,
      lineCount: (json['line_count'] as num?)?.toInt() ?? rawLines.length,
      truncated: json['truncated'] as bool? ?? false,
      isBinary: json['binary'] as bool? ?? false,
      mimeType: json['mime_type'] as String? ?? 'text/plain',
    );
  }
}
