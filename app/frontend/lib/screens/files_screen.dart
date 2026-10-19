import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../data/app_state.dart';
import '../models/file_entry.dart';
import '../services/archangeld_connection.dart';
import '../services/files_service.dart';
import '../theme/tokens.dart';

class FilesScreen extends StatefulWidget {
  const FilesScreen({super.key});

  @override
  State<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends State<FilesScreen> {
  String _filter = '';

  Future<void> _download(BuildContext context, FilesService files, String path) async {
    final messenger = ScaffoldMessenger.of(context);
    final res = await files.downloadToDisk(path);
    messenger.showSnackBar(
      SnackBar(
        content: Text(res.ok ? 'Saved to ${res.savedPath}' : (res.error ?? 'Download failed')),
        backgroundColor: res.ok ? AxColors.s2 : AxColors.bad,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final backend = context.read<ArchangeldConnection>();
      context.read<FilesService>().init(backend);
    });
  }

  List<String> _buildCrumbs(String path) {
    if (path == '/' || path.isEmpty) return ['/'];
    final parts = path.split('/').where((p) => p.isNotEmpty).toList();
    return ['/', ...parts];
  }

  void _openCrumb(List<String> crumbs, int idx, FilesService files) {
    if (idx == 0) {
      files.loadDirectory('/');
      return;
    }
    final parts = crumbs.sublist(1, idx + 1);
    files.loadDirectory('/${parts.join('/')}');
  }

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final files = context.watch<FilesService>();
    final currentPath = files.currentPath;
    final crumbs = _buildCrumbs(currentPath);
    final wide = MediaQuery.of(context).size.width >= 760;

    final listing = files.listing;
    final allEntries = listing?.entries ?? const [];
    
    // Filter dotfiles unless showHidden is true
    final visibleEntries = files.showHidden
        ? allEntries
        : allEntries.where((e) => !e.name.startsWith('.')).toList();

    final entries = _filter.isEmpty
        ? visibleEntries
        : visibleEntries.where((e) => e.name.toLowerCase().contains(_filter.toLowerCase())).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Top breadcrumb & action bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
          decoration: const BoxDecoration(
            color: AxColors.s1,
            border: Border(bottom: BorderSide(color: AxColors.line)),
          ),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (var i = 0; i < crumbs.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(right: 3),
                          child: GestureDetector(
                            onTap: () => _openCrumb(crumbs, i, files),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: i == crumbs.length - 1 ? AxColors.s2 : Colors.transparent,
                                borderRadius: BorderRadius.circular(7),
                              ),
                              child: Text(
                                crumbs[i],
                                style: AxTextStyles.mono.copyWith(
                                  fontSize: 11.5,
                                  color: i == crumbs.length - 1 ? AxColors.fg : AxColors.fg2,
                                  fontWeight: i == crumbs.length - 1 ? FontWeight.w600 : FontWeight.normal,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Refresh button
              IconButton(
                icon: const Icon(Icons.refresh_rounded, size: 16, color: AxColors.fg2),
                tooltip: 'Refresh directory',
                onPressed: () => files.loadDirectory(currentPath, forceRefresh: true),
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () => app.openTerminalInDir(currentPath),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                  decoration: BoxDecoration(
                    color: AxColors.s2,
                    borderRadius: BorderRadius.circular(AxRadius.pill),
                    border: Border.all(color: AxColors.line),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.terminal_rounded, size: 13, color: AxColors.accent),
                      const SizedBox(width: 6),
                      Text(
                        'Open in terminal',
                        style: AxTextStyles.sans.copyWith(fontSize: 11.5, fontWeight: FontWeight.w600, color: AxColors.fg2),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        // Filter bar, hidden files toggle & item count
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 6),
          decoration: const BoxDecoration(
            color: AxColors.bg,
            border: Border(bottom: BorderSide(color: AxColors.line)),
          ),
          child: Row(
            children: [
              Flexible(
               child: Container(
                constraints: const BoxConstraints(maxWidth: 240),
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
                decoration: BoxDecoration(
                  color: AxColors.s1,
                  borderRadius: BorderRadius.circular(AxRadius.pill),
                  border: Border.all(color: AxColors.line),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.search, size: 12, color: AxColors.fg3),
                    const SizedBox(width: 6),
                    Expanded(
                      child: TextField(
                        onChanged: (v) => setState(() => _filter = v),
                        style: AxTextStyles.mono.copyWith(fontSize: 11),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          hintText: 'filter files in folder',
                        ),
                      ),
                    ),
                  ],
                ),
               ),
              ),
              const SizedBox(width: 10),
              // Hidden files toggle
              InkWell(
                onTap: files.toggleShowHidden,
                borderRadius: BorderRadius.circular(AxRadius.pill),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: files.showHidden ? AxColors.s3 : AxColors.s1,
                    borderRadius: BorderRadius.circular(AxRadius.pill),
                    border: Border.all(color: files.showHidden ? AxColors.accent.withValues(alpha: 0.4) : AxColors.line),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        files.showHidden ? Icons.visibility : Icons.visibility_off_outlined,
                        size: 11,
                        color: files.showHidden ? AxColors.accent : AxColors.fg3,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'hidden',
                        style: AxTextStyles.mono.copyWith(
                          fontSize: 10.5,
                          color: files.showHidden ? AxColors.accent : AxColors.fg3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              if (files.loading)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 1.5, color: AxColors.accent),
                )
              else
                Text(
                  '${entries.length} items',
                  style: AxTextStyles.mono.copyWith(fontSize: 10.5, color: AxColors.fg3),
                ),
            ],
          ),
        ),
        // Main view: Quick Jump + File list
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (wide)
                Container(
                  width: 196,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                  decoration: const BoxDecoration(
                    color: AxColors.s1,
                    border: Border(right: BorderSide(color: AxColors.line)),
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _TreeRow(
                          label: files.rootPath ?? 'Root',
                          selected: currentPath.isEmpty,
                          onTap: () => files.loadDirectory(''),
                        ),
                        for (final d in files.quickJumpDirs)
                          _TreeRow(
                            label: d.name,
                            selected: d.path == currentPath,
                            onTap: () => files.loadDirectory(d.path),
                          ),
                      ],
                    ),
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AxColors.line))),
                            child: const Row(
                              children: [
                                Expanded(flex: 3, child: _ColLabel('NAME')),
                                SizedBox(width: 14),
                                Expanded(child: _ColLabel('SIZE', alignEnd: true)),
                                SizedBox(width: 14),
                                Expanded(child: _ColLabel('PERMS')),
                                SizedBox(width: 14),
                                Expanded(child: _ColLabel('MODIFIED')),
                              ],
                            ),
                          ),
                          if (files.error != null)
                            Padding(
                              padding: const EdgeInsets.all(20),
                              child: Row(
                                children: [
                                  const Icon(Icons.error_outline, size: 16, color: AxColors.bad),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(files.error!, style: AxTextStyles.mono.copyWith(color: AxColors.bad, fontSize: 12)),
                                  ),
                                ],
                              ),
                            )
                          else
                            Expanded(
                              child: ListView.builder(
                                itemCount: entries.length,
                                itemBuilder: (context, i) {
                                  final f = entries[i];
                                  return _FileRow(
                                    entry: f,
                                    onTap: () {
                                      if (f.isDir) {
                                        files.loadDirectory(f.path);
                                        files.closePreview();
                                      } else {
                                        files.openFilePreview(f.path);
                                      }
                                    },
                                    onDownload: () => _download(context, files, f.path),
                                  );
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (files.activePreviewPath != null)
                      _PreviewPane(
                        path: files.activePreviewPath!,
                        content: files.fileContent,
                        loading: files.previewLoading,
                        onClose: files.closePreview,
                        onDownload: () => _download(context, files, files.activePreviewPath!),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ColLabel extends StatelessWidget {
  final String text;
  final bool alignEnd;
  const _ColLabel(this.text, {this.alignEnd = false});

  @override
  Widget build(BuildContext context) => Text(text, textAlign: alignEnd ? TextAlign.right : TextAlign.left, style: AxTextStyles.label);
}

class _TreeRow extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _TreeRow({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 1),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(color: selected ? AxColors.s2 : Colors.transparent, borderRadius: BorderRadius.circular(8)),
        child: Row(
          children: [
            Icon(Icons.folder_outlined, size: 12, color: selected ? AxColors.accent : AxColors.fg3),
            const SizedBox(width: 8),
            Expanded(child: Text(label, style: AxTextStyles.mono.copyWith(fontSize: 11.5, color: selected ? AxColors.fg : AxColors.fg2), overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
    );
  }
}

class _FileRow extends StatefulWidget {
  final FileEntryModel entry;
  final VoidCallback onTap;
  final VoidCallback? onDownload;

  const _FileRow({
    required this.entry,
    required this.onTap,
    this.onDownload,
  });

  @override
  State<_FileRow> createState() => _FileRowState();
}

class _FileRowState extends State<_FileRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final f = widget.entry;
    final icon = f.isDir
        ? Icons.folder_outlined
        : (f.isLog
            ? Icons.article_outlined
            : (f.isSymlink
                ? (f.isBroken ? Icons.link_off_rounded : Icons.link_rounded)
                : Icons.insert_drive_file_outlined));
    final iconColor = f.isDir
        ? AxColors.info
        : (f.isLog
            ? AxColors.warn
            : (f.isSymlink
                ? (f.isBroken ? AxColors.bad : AxColors.accent)
                : AxColors.fg3));

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 7),
          decoration: BoxDecoration(
            color: _hover ? AxColors.s2 : Colors.transparent,
            border: const Border(bottom: BorderSide(color: Color(0x0BE8F0E6))),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Row(
                  children: [
                    Icon(icon, size: 14, color: iconColor),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              f.name,
                              style: AxTextStyles.mono.copyWith(
                                fontSize: 12,
                                color: f.isBroken ? AxColors.bad : AxColors.fg,
                                decoration: f.isBroken ? TextDecoration.lineThrough : null,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (f.target != null && f.target!.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Text(
                              '→ ${f.target}${f.isBroken ? ' [broken]' : ''}',
                              style: AxTextStyles.mono.copyWith(
                                fontSize: 10,
                                color: f.isBroken ? AxColors.bad : AxColors.fg3,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(child: Text(f.size, textAlign: TextAlign.right, style: AxTextStyles.mono.copyWith(fontSize: 11, color: AxColors.fg2))),
              const SizedBox(width: 14),
              Expanded(child: Text(f.perms, style: AxTextStyles.mono.copyWith(fontSize: 11, color: AxColors.fg3))),
              const SizedBox(width: 14),
              Expanded(child: Text(f.mtime, style: AxTextStyles.mono.copyWith(fontSize: 11, color: AxColors.fg3))),
            ],
          ),
        ),
      ),
    );
  }
}

class _PreviewPane extends StatelessWidget {
  final String path;
  final FileContentResult? content;
  final bool loading;
  final VoidCallback onClose;
  final VoidCallback? onDownload;

  const _PreviewPane({
    required this.path,
    required this.content,
    required this.loading,
    required this.onClose,
    this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final fileName = path.split('/').last;
    final lines = content?.lines ?? const [];

    return Container(
      decoration: const BoxDecoration(
        color: AxColors.s1,
        border: Border(top: BorderSide(color: AxColors.line2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.description_outlined, size: 14, color: AxColors.accent),
                const SizedBox(width: 8),
                Text(fileName, style: AxTextStyles.mono.copyWith(fontSize: 11.5, fontWeight: FontWeight.w600)),
                const SizedBox(width: 9),
                if (!loading && content != null)
                  Text(
                    '${content!.lineCount} lines${content!.truncated ? ' (first 400 shown)' : ''}',
                    style: AxTextStyles.mono.copyWith(fontSize: 10, color: AxColors.fg3),
                  ),
                const Spacer(),
                if (onDownload != null)
                  IconButton(
                    icon: const Icon(Icons.download_rounded, size: 14, color: AxColors.fg2),
                    tooltip: 'Download file',
                    onPressed: onDownload,
                  ),
                if (content != null && !content!.isBinary)
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 14, color: AxColors.fg3),
                    tooltip: 'Copy preview to clipboard',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: lines.join('\n')));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('File preview copied to clipboard'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
                GestureDetector(
                  onTap: onClose,
                  child: const Padding(
                    padding: EdgeInsets.all(4.0),
                    child: Icon(Icons.close_rounded, size: 16, color: AxColors.fg3),
                  ),
                ),
              ],
            ),
          ),
          if (loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AxColors.accent),
                ),
              ),
            )
          else if (content != null && content!.isBinary)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: Column(
                  children: [
                    Text(
                      'Binary file (${content!.mimeType}) cannot be previewed directly.',
                      style: AxTextStyles.mono.copyWith(fontSize: 11, color: AxColors.fg3),
                    ),
                    if (onDownload != null) ...[
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.download_rounded, size: 14),
                        label: const Text('Download File'),
                        style: ElevatedButton.styleFrom(backgroundColor: AxColors.s2),
                        onPressed: onDownload,
                      ),
                    ],
                  ],
                ),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(15, 0, 15, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < lines.length; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 1.5),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 32,
                              child: Text(
                                '${i + 1}',
                                textAlign: TextAlign.right,
                                style: AxTextStyles.mono.copyWith(
                                  fontSize: 11,
                                  color: AxColors.fg3.withValues(alpha: 0.55),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: SelectableText(
                                lines[i],
                                style: AxTextStyles.mono.copyWith(fontSize: 11, height: 1.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
