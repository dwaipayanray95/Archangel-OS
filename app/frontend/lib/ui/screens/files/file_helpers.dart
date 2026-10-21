import 'package:flutter/material.dart';

import '../../../models/file_entry.dart';

const kFilesSortKey = 'files_sort';

/// Sorting choices for the Files screen.
enum FilesSortChoice {
  name('Name', 'Name (A–Z)'),
  newest('Newest', 'Newest'),
  largest('Largest', 'Largest');

  const FilesSortChoice(this.buttonLabel, this.menuLabel);
  final String buttonLabel;
  final String menuLabel;

  static FilesSortChoice fromString(String? val) {
    return switch (val) {
      'newest' => FilesSortChoice.newest,
      'largest' => FilesSortChoice.largest,
      _ => FilesSortChoice.name,
    };
  }

  String toStorageString() => this.name;
}

/// One clickable part of the breadcrumb bar.
class Crumb {
  const Crumb({required this.label, required this.path, this.isCurrent = false, this.isEllipsis = false});

  final String label;

  /// What to ask the server for; '' means the server's files root.
  final String path;
  final bool isCurrent;
  final bool isEllipsis;
}

/// Breadcrumbs for [path].
/// First crumb = [rootPath] (e.g. /home/ray), then each folder, chevrons between.
/// When [collapseNarrow] is true and there are more than 2 crumbs, collapses
/// leading crumbs into "…" so it stays one line on phones and narrow windows.
List<Crumb> buildCrumbs(String path, {String? rootPath, bool collapseNarrow = false}) {
  final cleanRoot = (rootPath == null || rootPath.isEmpty || rootPath == '/') ? null : rootPath.replaceFirst(RegExp(r'/+$'), '');
  final cleanPath = path.replaceFirst(RegExp(r'/+$'), '');
  final rootLabel = cleanRoot ?? '/';

  final List<Crumb> crumbs;

  if (cleanRoot != null && (cleanPath == cleanRoot || cleanPath.startsWith('$cleanRoot/') || cleanPath.isEmpty)) {
    final rest =
        cleanPath.isEmpty || cleanPath == cleanRoot
            ? <String>[]
            : cleanPath.substring(cleanRoot.length).split('/').where((p) => p.isNotEmpty).toList();

    var acc = cleanRoot;
    crumbs = [
      Crumb(label: rootLabel, path: '', isCurrent: rest.isEmpty),
      for (var i = 0; i < rest.length; i++) Crumb(label: rest[i], path: acc = '$acc/${rest[i]}', isCurrent: i == rest.length - 1),
    ];
  } else {
    final parts = cleanPath.split('/').where((p) => p.isNotEmpty).toList();
    var acc = '';
    crumbs = [
      Crumb(label: rootLabel, path: cleanRoot != null ? '' : '/', isCurrent: parts.isEmpty),
      for (var i = 0; i < parts.length; i++) Crumb(label: parts[i], path: acc = '$acc/${parts[i]}', isCurrent: i == parts.length - 1),
    ];
  }

  if (collapseNarrow && crumbs.length > 2) {
    // Show '…' pointing to parent, followed by the active crumb.
    final parent = crumbs[crumbs.length - 2];
    final current = crumbs.last;
    return [Crumb(label: '…', path: parent.path, isEllipsis: true), current];
  }

  return crumbs;
}

/// True when the server refused a folder for being outside the allowed root.
bool isOutsideRootError(String? message) {
  final m = (message ?? '').toLowerCase();
  return m.contains('outside') || m.contains('files_root') || m.contains('403') || m.contains('permission denied');
}

/// The plain-language hint shown for an "outside the allowed folder" error.
String outsideRootHint(String? rootPath) =>
    'Archangel can only show files inside ${rootPath == null || rootPath.isEmpty ? '/home/archangel' : rootPath}.';

const _kMonthMap = {
  'jan': 1,
  'feb': 2,
  'mar': 3,
  'apr': 4,
  'may': 5,
  'jun': 6,
  'jul': 7,
  'aug': 8,
  'sep': 9,
  'oct': 10,
  'nov': 11,
  'dec': 12,
};

const _kMonthsShort = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// Parses various mtime formats to DateTime.
DateTime? parseFileDate(String mtime) {
  if (mtime.isEmpty) return null;
  final iso = DateTime.tryParse(mtime);
  if (iso != null) return iso;

  final parts = mtime.trim().split(RegExp(r'\s+'));
  if (parts.length >= 3) {
    final mStr = parts[0].toLowerCase();
    final month = _kMonthMap[mStr];
    final day = int.tryParse(parts[1]);
    if (month != null && day != null) {
      if (parts[2].contains(':')) {
        final timeParts = parts[2].split(':');
        final hour = int.tryParse(timeParts[0]) ?? 0;
        final minute = int.tryParse(timeParts[1]) ?? 0;
        final now = DateTime.now();
        var year = now.year;
        if (month > now.month + 1) year -= 1;
        return DateTime(year, month, day, hour, minute);
      } else {
        final year = int.tryParse(parts[2]);
        if (year != null) return DateTime(year, month, day);
      }
    }
  }
  return null;
}

/// Dates: today → "Today, 09:41"; this year → "18 Oct, 22:10"; older → "2 Sep 2025".
String formatFileDate(String mtime, {DateTime? now}) {
  if (mtime.isEmpty) return '';
  final dt = parseFileDate(mtime);
  if (dt == null) return mtime;

  final current = now ?? DateTime.now();
  final hh = dt.hour.toString().padLeft(2, '0');
  final mm = dt.minute.toString().padLeft(2, '0');

  if (dt.year == current.year && dt.month == current.month && dt.day == current.day) {
    return 'Today, $hh:$mm';
  } else if (dt.year == current.year) {
    final monthStr = _kMonthsShort[dt.month - 1];
    return '${dt.day} $monthStr, $hh:$mm';
  } else {
    final monthStr = _kMonthsShort[dt.month - 1];
    return '${dt.day} $monthStr ${dt.year}';
  }
}

/// Folders first, then sorted by [sort] choice.
List<FileEntryModel> sortEntries(Iterable<FileEntryModel> entries, {FilesSortChoice sort = FilesSortChoice.name}) {
  final list = entries.toList();
  list.sort((a, b) {
    // Folders always first
    if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
    switch (sort) {
      case FilesSortChoice.name:
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      case FilesSortChoice.newest:
        final da = parseFileDate(a.mtime);
        final db = parseFileDate(b.mtime);
        if (da != null && db != null) {
          final cmp = db.compareTo(da);
          if (cmp != 0) return cmp;
        }
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      case FilesSortChoice.largest:
        final cmp = b.sizeBytes.compareTo(a.sizeBytes);
        if (cmp != 0) return cmp;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    }
  });
  return list;
}

bool isImageFile(FileEntryModel e, {String? mimeType}) {
  if (mimeType != null && mimeType.startsWith('image/')) return true;
  final name = e.name.toLowerCase();
  return name.endsWith('.png') ||
      name.endsWith('.jpg') ||
      name.endsWith('.jpeg') ||
      name.endsWith('.gif') ||
      name.endsWith('.webp') ||
      name.endsWith('.svg') ||
      name.endsWith('.ico') ||
      name.endsWith('.bmp');
}

IconData fileIconFor(FileEntryModel e) {
  if (e.isDir) return Icons.folder_rounded;
  if (e.isSymlink) return Icons.link_rounded;
  if (e.isLog) return Icons.receipt_long_outlined;
  if (isImageFile(e)) return Icons.image_outlined;
  final name = e.name.toLowerCase();
  if (name.endsWith('.txt') ||
      name.endsWith('.md') ||
      name.endsWith('.json') ||
      name.endsWith('.yaml') ||
      name.endsWith('.yml') ||
      name.endsWith('.sh') ||
      name.endsWith('.dart') ||
      name.endsWith('.go') ||
      name.endsWith('.html') ||
      name.endsWith('.css') ||
      name.endsWith('.js') ||
      name.endsWith('.ts')) {
    return Icons.description_outlined;
  }
  return Icons.insert_drive_file_outlined;
}

/// "Folder · 18 Oct, 22:10" / "1.2 KB · Today, 09:41".
String entrySubtitle(FileEntryModel e) {
  final what = e.isDir ? 'Folder' : (e.size.isEmpty || e.size == '—' ? 'File' : e.size);
  final formatted = formatFileDate(e.mtime);
  return formatted.isEmpty ? what : '$what · $formatted';
}

/// The folder containing [filePath] ('/' at the top).
String parentDirOf(String filePath) {
  final clean = filePath.replaceFirst(RegExp(r'/+$'), '');
  final i = clean.lastIndexOf('/');
  if (i <= 0) return '/';
  return clean.substring(0, i);
}

/// The base name of the parent folder (e.g. 'photos' from '/home/ray/photos/file.txt').
String parentBaseNameOf(String filePath, {String? rootPath}) {
  final p = parentDirOf(filePath);
  if (rootPath != null && (p == rootPath || p.isEmpty)) {
    final clean = rootPath.replaceFirst(RegExp(r'/+$'), '');
    final lastSlash = clean.lastIndexOf('/');
    return lastSlash >= 0 ? clean.substring(lastSlash + 1) : rootPath;
  }
  final clean = p.replaceFirst(RegExp(r'/+$'), '');
  final lastSlash = clean.lastIndexOf('/');
  return lastSlash >= 0 ? clean.substring(lastSlash + 1) : p;
}
