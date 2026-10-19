import 'package:flutter/material.dart';

import '../../../models/file_entry.dart';

/// One clickable part of the breadcrumb bar.
class Crumb {
  const Crumb(this.label, this.path);
  final String label;

  /// What to ask the server for; '' means "the server's files root" (Home).
  final String path;
}

/// Breadcrumbs for [path]. Inside the files root they start at "Home" so the
/// person never sees (or clicks) places Archangel cannot show.
List<Crumb> buildCrumbs(String path, {String? rootPath}) {
  final root = rootPath == null || rootPath.isEmpty || rootPath == '/' ? null : rootPath.replaceFirst(RegExp(r'/+$'), '');
  final clean = path.replaceFirst(RegExp(r'/+$'), '');
  if (root != null && (clean == root || clean.startsWith('$root/') || clean.isEmpty)) {
    final rest = clean.isEmpty ? <String>[] : clean.substring(root.length).split('/').where((p) => p.isNotEmpty).toList();
    var acc = root;
    return [
      const Crumb('Home', ''),
      for (final part in rest) Crumb(part, acc = '$acc/$part'),
    ];
  }
  final parts = clean.split('/').where((p) => p.isNotEmpty).toList();
  var acc = '';
  return [
    const Crumb('/', '/'),
    for (final part in parts) Crumb(part, acc = '$acc/$part'),
  ];
}

/// True when the server refused a folder for being outside the allowed root.
bool isOutsideRootError(String? message) {
  final m = (message ?? '').toLowerCase();
  return m.contains('outside') || m.contains('files_root');
}

/// The plain-language hint shown for an "outside the allowed folder" error.
String outsideRootHint(String? rootPath) =>
    'Archangel can only show files inside ${rootPath == null || rootPath.isEmpty ? '/home/archangel' : rootPath}.';

/// Folders first, then by name (case-insensitive).
List<FileEntryModel> sortEntries(Iterable<FileEntryModel> entries) {
  final list = entries.toList();
  list.sort((a, b) {
    if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return list;
}

IconData fileIconFor(FileEntryModel e) {
  if (e.isDir) return Icons.folder_rounded;
  if (e.isSymlink) return Icons.link_rounded;
  if (e.isLog) return Icons.receipt_long_outlined;
  return Icons.insert_drive_file_outlined;
}

/// "Folder, changed Sep 02 06:14" / "1.2 KB, changed Sep 02 06:14".
String entrySubtitle(FileEntryModel e) {
  final what = e.isDir ? 'Folder' : (e.size.isEmpty || e.size == '—' ? 'File' : e.size);
  return e.mtime.isEmpty ? what : '$what · changed ${e.mtime}';
}

/// The folder containing [filePath] ('/' at the top).
String parentDirOf(String filePath) {
  final i = filePath.lastIndexOf('/');
  if (i <= 0) return '/';
  return filePath.substring(0, i);
}
