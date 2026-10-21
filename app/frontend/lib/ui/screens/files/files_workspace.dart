import 'package:flutter/material.dart';

import '../../../models/file_entry.dart';
import '../../../services/files_service.dart';
import '../../ui.dart';
import 'file_helpers.dart';
import 'files_preview.dart';
import 'files_upload.dart';

const double kFilesWideMinWidth = 720.0;

class FilesWorkspace extends StatefulWidget {
  const FilesWorkspace({
    super.key,
    required this.files,
    required this.onOpenTerminal,
    required this.onBackToRoot,
    this.sort = FilesSortChoice.name,
    this.onSortChanged,
  });

  final FilesService files;
  final void Function(String dir) onOpenTerminal;
  final VoidCallback onBackToRoot;
  final FilesSortChoice sort;
  final ValueChanged<FilesSortChoice>? onSortChanged;

  @override
  State<FilesWorkspace> createState() => _FilesWorkspaceState();
}

class _FilesWorkspaceState extends State<FilesWorkspace> {
  final TextEditingController _filterController = TextEditingController();
  String _filter = '';
  late FilesSortChoice _sort;
  FileEntryModel? _selectedFile;

  // Upload progress simulation/tracking
  UploadProgress? _uploadProgress;
  String? _uploadError;

  @override
  void initState() {
    super.initState();
    _sort = widget.sort;
  }

  @override
  void didUpdateWidget(covariant FilesWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sort != widget.sort) {
      _sort = widget.sort;
    }
  }

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  void _setSort(FilesSortChoice choice) {
    setState(() => _sort = choice);
    widget.onSortChanged?.call(choice);
  }

  void _onOpen(FileEntryModel e) {
    if (e.isDir) {
      setState(() {
        _filter = '';
        _filterController.clear();
        _selectedFile = null;
      });
      widget.files.loadDirectory(e.path);
    } else {
      setState(() => _selectedFile = e);
      widget.files.openFilePreview(e.path);
    }
  }

  Future<void> _handleUpload(String currentFolder) async {
    // Ray adds the upload endpoint to backend. For now, FilesService reports unsupported.
    // In tests with a fake service, supportsUpload returns true.
    if (!widget.files.supportsUpload) return;

    // Simulate / invoke upload for selected files
    final dummyFiles = [const UploadFileItem(name: 'upload1.txt', sizeBytes: 1024)];
    setState(() {
      _uploadError = null;
      _uploadProgress = UploadProgress(
        fileIndex: 0,
        totalFiles: dummyFiles.length,
        currentFileName: dummyFiles.first.name,
        bytesSent: 0,
        totalBytes: 1024,
      );
    });

    final res = await widget.files.upload(
      currentFolder,
      dummyFiles,
      onProgress: (p) {
        if (mounted) setState(() => _uploadProgress = p);
      },
    );

    if (!mounted) return;
    if (res.ok) {
      setState(() => _uploadProgress = null);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Uploaded ${res.uploadedCount} ${res.uploadedCount == 1 ? 'file' : 'files'}')));
      widget.files.loadDirectory(currentFolder, forceRefresh: true);
    } else {
      setState(() {
        _uploadError = res.error ?? 'Upload failed';
      });
    }
  }

  Future<void> _handleDownloadFile(FileEntryModel entry) async {
    final messenger = ScaffoldMessenger.of(context);
    final res = await widget.files.downloadToDisk(entry.path);
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(content: Text(res.ok ? 'Saved to ${res.savedPath}' : (res.error ?? 'Download failed'))));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= kFilesWideMinWidth;
        return wide ? _buildWide(context) : _buildNarrow(context);
      },
    );
  }

  // --------------------------------------------------------------------------
  // Wide Layout (>= 720)
  // --------------------------------------------------------------------------
  Widget _buildWide(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final files = widget.files;
    final listing = files.listing;
    final currentPath = (listing != null && listing.path.isNotEmpty) ? listing.path : files.currentPath;
    final rootPath = files.rootPath ?? '/';
    final effectivePath = currentPath.isEmpty ? rootPath : currentPath;

    final all = listing?.entries ?? const <FileEntryModel>[];
    final hiddenCount = all.where((e) => e.name.startsWith('.')).length;
    final shown = sortEntries(all.where((e) => files.showHidden || !e.name.startsWith('.')), sort: _sort);
    final filtered = _filter.isEmpty ? shown : shown.where((e) => e.name.toLowerCase().contains(_filter.toLowerCase())).toList();

    return Padding(
      padding: EdgeInsets.all(ax.space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top row: Breadcrumbs on the left, action icon(s) on the right
          Row(
            children: [
              Expanded(
                child: _BreadcrumbBar(
                  path: effectivePath,
                  rootPath: rootPath,
                  collapseNarrow: false,
                  onTapCrumb: (path) {
                    setState(() => _selectedFile = null);
                    files.loadDirectory(path);
                  },
                ),
              ),
              SizedBox(width: ax.space.sm),
              AxIconButton(
                icon: Icons.terminal_rounded,
                tooltip: 'Open terminal here',
                onPressed: () => widget.onOpenTerminal(effectivePath),
              ),
              if (files.supportsUpload) ...[
                SizedBox(width: ax.space.xs),
                AxIconButton(icon: Icons.upload_rounded, tooltip: 'Upload', color: c.accent, onPressed: () => _handleUpload(effectivePath)),
              ],
            ],
          ),
          SizedBox(height: ax.space.md),

          // Toolbar
          _buildToolbar(context, wide: true, filteredCount: filtered.length, hiddenCount: hiddenCount),
          SizedBox(height: ax.space.md),

          // Upload card if uploading
          if (_uploadProgress != null) ...[
            UploadProgressCard(
              folderName: parentBaseNameOf(effectivePath, rootPath: rootPath),
              progress: _uploadProgress!,
              errorMessage: _uploadError,
              onCancel: () => setState(() => _uploadProgress = null),
              onRetry: () => _handleUpload(effectivePath),
            ),
            SizedBox(height: ax.space.md),
          ],

          // Main list + optional preview card
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: AxCard(
                    padding: EdgeInsets.zero,
                    child: _buildListOrState(
                      context,
                      wide: true,
                      allEntries: all,
                      filteredEntries: filtered,
                      rootPath: rootPath,
                      effectivePath: effectivePath,
                    ),
                  ),
                ),
                if (_selectedFile != null) ...[
                  SizedBox(width: ax.space.lg),
                  WidePreviewCard(
                    entry: _selectedFile!,
                    files: files,
                    onClose: () {
                      setState(() => _selectedFile = null);
                      files.closePreview();
                    },
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // Narrow Layout (< 720)
  // --------------------------------------------------------------------------
  Widget _buildNarrow(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final files = widget.files;
    final listing = files.listing;
    final currentPath = (listing != null && listing.path.isNotEmpty) ? listing.path : files.currentPath;
    final rootPath = files.rootPath ?? '/';
    final effectivePath = currentPath.isEmpty ? rootPath : currentPath;

    // Full-screen preview on narrow if a file is selected
    if (_selectedFile != null) {
      return NarrowPreviewView(
        entry: _selectedFile!,
        files: files,
        onClose: () {
          setState(() => _selectedFile = null);
          files.closePreview();
        },
      );
    }

    final all = listing?.entries ?? const <FileEntryModel>[];
    final shown = sortEntries(all.where((e) => files.showHidden || !e.name.startsWith('.')), sort: _sort);
    final filtered = _filter.isEmpty ? shown : shown.where((e) => e.name.toLowerCase().contains(_filter.toLowerCase())).toList();

    return SingleChildScrollView(
      padding: EdgeInsets.all(ax.space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top row: Breadcrumbs on the left (collapsed to … on narrow), action icon(s) on the right
          Row(
            children: [
              Expanded(
                child: _BreadcrumbBar(
                  path: effectivePath,
                  rootPath: rootPath,
                  collapseNarrow: true,
                  onTapCrumb: (path) {
                    setState(() => _selectedFile = null);
                    files.loadDirectory(path);
                  },
                ),
              ),
              SizedBox(width: ax.space.xs),
              AxIconButton(
                icon: Icons.terminal_rounded,
                tooltip: 'Open terminal here',
                onPressed: () => widget.onOpenTerminal(effectivePath),
              ),
              if (files.supportsUpload) ...[
                SizedBox(width: ax.space.xs),
                AxIconButton(icon: Icons.upload_rounded, tooltip: 'Upload', color: c.accent, onPressed: () => _handleUpload(effectivePath)),
              ],
            ],
          ),
          SizedBox(height: ax.space.md),

          // Toolbar
          _buildToolbar(context, wide: false, filteredCount: filtered.length, hiddenCount: 0),
          SizedBox(height: ax.space.md),

          // Upload card if uploading
          if (_uploadProgress != null) ...[
            UploadProgressCard(
              folderName: parentBaseNameOf(effectivePath, rootPath: rootPath),
              progress: _uploadProgress!,
              errorMessage: _uploadError,
              onCancel: () => setState(() => _uploadProgress = null),
              onRetry: () => _handleUpload(effectivePath),
            ),
            SizedBox(height: ax.space.md),
          ],

          // List or state
          AxCard(
            padding: EdgeInsets.zero,
            child: _buildListOrState(
              context,
              wide: false,
              allEntries: all,
              filteredEntries: filtered,
              rootPath: rootPath,
              effectivePath: effectivePath,
            ),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // Toolbar
  // --------------------------------------------------------------------------
  Widget _buildToolbar(BuildContext context, {required bool wide, required int filteredCount, required int hiddenCount}) {
    final ax = context.ax;
    final c = ax.colors;
    final files = widget.files;

    final controls = Wrap(
      spacing: ax.space.md,
      runSpacing: ax.space.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // Filter field
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: wide ? 280 : 200, minWidth: 150),
          child: TextField(
            controller: _filterController,
            decoration: InputDecoration(
              isDense: true,
              labelText: 'Filter this folder',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              suffixIcon:
                  _filter.isNotEmpty
                      ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 16),
                        onPressed: () {
                          setState(() {
                            _filter = '';
                            _filterController.clear();
                          });
                        },
                      )
                      : null,
            ),
            onChanged: (v) => setState(() => _filter = v),
          ),
        ),

        // Sort menu button
        PopupMenuButton<FilesSortChoice>(
          tooltip: 'Sort order',
          initialValue: _sort,
          onSelected: _setSort,
          itemBuilder:
              (context) => [for (final choice in FilesSortChoice.values) PopupMenuItem(value: choice, child: Text(choice.menuLabel))],
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: ax.space.md, vertical: ax.space.sm),
              decoration: BoxDecoration(
                color: c.surfaceAlt,
                borderRadius: BorderRadius.circular(ax.radii.pill),
                border: Border.all(color: c.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Sort: ${_sort.buttonLabel}', style: ax.typo.label.copyWith(color: c.text)),
                  SizedBox(width: ax.space.xs),
                  Icon(Icons.arrow_drop_down_rounded, size: 18, color: c.textMuted),
                ],
              ),
            ),
          ),
        ),

        // Show hidden files switch
        Semantics(
          toggled: files.showHidden,
          label: wide ? 'Show hidden files' : 'Hidden',
          excludeSemantics: true,
          onTap: files.toggleShowHidden,
          child: InkWell(
            mouseCursor: SystemMouseCursors.click,
            borderRadius: BorderRadius.circular(ax.radii.sm),
            onTap: files.toggleShowHidden,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IgnorePointer(
                  child: Switch(value: files.showHidden, onChanged: (_) {}, activeThumbColor: c.accent, activeTrackColor: c.accentWash),
                ),
                SizedBox(width: ax.space.xs),
                Text(wide ? 'Show hidden files' : 'Hidden', style: ax.typo.body.copyWith(color: c.text)),
              ],
            ),
          ),
        ),
      ],
    );

    if (wide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: controls),
          SizedBox(width: ax.space.md),
          Text(
            '$filteredCount ${filteredCount == 1 ? 'item' : 'items'} · $hiddenCount hidden',
            style: ax.typo.caption.copyWith(color: c.textMuted),
          ),
        ],
      );
    }

    return controls;
  }

  // --------------------------------------------------------------------------
  // List or State View
  // --------------------------------------------------------------------------
  Widget _buildListOrState(
    BuildContext context, {
    required bool wide,
    required List<FileEntryModel> allEntries,
    required List<FileEntryModel> filteredEntries,
    required String rootPath,
    required String effectivePath,
  }) {
    final files = widget.files;

    // 1. Loading state
    if (files.loading && files.listing == null) {
      return const _FilesLoadingState();
    }

    // 2. Error states
    if (files.error != null) {
      if (isOutsideRootError(files.error)) {
        // 403 not allowed
        return _NotAllowedState(
          rootPath: rootPath,
          onBackToRoot: widget.onBackToRoot,
          onOpenTerminal: () => widget.onOpenTerminal(rootPath),
        );
      }
      return ErrorState(
        title: 'Couldn\'t open this folder',
        message:
            files.error!.contains('Exception') || files.error!.contains('Socket')
                ? 'Your server didn\'t answer. Check that it\'s online, then try again.'
                : files.error!,
        onRetry: files.retry,
      );
    }

    // 3. Empty states
    if (filteredEntries.isEmpty) {
      if (_filter.isNotEmpty) {
        return EmptyState(
          icon: Icons.search_off_rounded,
          title: 'Nothing matches "$_filter"',
          message: 'Try a shorter word. The filter only looks in this folder.',
          actionLabel: 'Clear filter',
          onAction: () {
            setState(() {
              _filter = '';
              _filterController.clear();
            });
          },
        );
      }
      if (!files.showHidden && allEntries.any((e) => e.name.startsWith('.'))) {
        return EmptyState(
          icon: Icons.visibility_off_outlined,
          title: 'Only hidden files here',
          actionLabel: 'Show hidden files',
          onAction: files.toggleShowHidden,
        );
      }
      return const EmptyState(icon: Icons.folder_open_outlined, title: 'This folder is empty', message: 'Nothing has been saved here yet.');
    }

    // 4. File list
    final c = context.ax.colors;
    if (wide) {
      return Column(
        children: [
          _WideTableHeader(currentSort: _sort, onSortChanged: _setSort),
          Divider(height: 1, color: c.border),
          Expanded(
            child: ListView.separated(
              itemCount: filteredEntries.length,
              separatorBuilder: (_, __) => Divider(height: 1, color: c.border),
              itemBuilder: (context, i) {
                final e = filteredEntries[i];
                final selected = _selectedFile?.path == e.path;
                return _WideTableRow(
                  entry: e,
                  selected: selected,
                  onTap: () => _onOpen(e),
                  onDownload: e.isDir ? null : () => _handleDownloadFile(e),
                );
              },
            ),
          ),
        ],
      );
    } else {
      return ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: filteredEntries.length,
        separatorBuilder: (_, __) => Divider(height: 1, color: c.border),
        itemBuilder: (context, i) {
          final e = filteredEntries[i];
          final selected = _selectedFile?.path == e.path;
          return _NarrowTableRow(
            entry: e,
            selected: selected,
            onTap: () => _onOpen(e),
            onDownload: e.isDir ? null : () => _handleDownloadFile(e),
          );
        },
      );
    }
  }
}

// ----------------------------------------------------------------------------
// Breadcrumbs bar
// ----------------------------------------------------------------------------
class _BreadcrumbBar extends StatelessWidget {
  const _BreadcrumbBar({required this.path, required this.rootPath, required this.collapseNarrow, required this.onTapCrumb});

  final String path;
  final String rootPath;
  final bool collapseNarrow;
  final void Function(String path) onTapCrumb;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final crumbs = buildCrumbs(path, rootPath: rootPath, collapseNarrow: collapseNarrow);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < crumbs.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Icon(Icons.chevron_right_rounded, size: 16, color: c.textMuted),
              ),
            _CrumbChip(crumb: crumbs[i], onTap: () => onTapCrumb(crumbs[i].path)),
          ],
        ],
      ),
    );
  }
}

class _CrumbChip extends StatelessWidget {
  const _CrumbChip({required this.crumb, required this.onTap});

  final Crumb crumb;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final isLast = crumb.isCurrent;

    return Semantics(
      button: true,
      selected: isLast,
      label: isLast ? 'Current folder: ${crumb.label}' : 'Go to ${crumb.label}',
      child: InkWell(
        mouseCursor: isLast ? SystemMouseCursors.basic : SystemMouseCursors.click,
        borderRadius: BorderRadius.circular(ax.radii.sm),
        onTap: isLast ? null : onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: ax.space.xs, vertical: ax.space.xs),
          child: Text(
            crumb.label,
            style: ax.typo.mono.copyWith(fontWeight: isLast ? FontWeight.w700 : FontWeight.w500, color: isLast ? c.text : c.accent),
          ),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// Wide Table Header & Row
// ----------------------------------------------------------------------------
class _WideTableHeader extends StatelessWidget {
  const _WideTableHeader({required this.currentSort, required this.onSortChanged});

  final FilesSortChoice currentSort;
  final void Function(FilesSortChoice) onSortChanged;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;

    return Container(
      height: 40,
      padding: EdgeInsets.symmetric(horizontal: ax.space.lg),
      color: c.surfaceAlt,
      child: Row(
        children: [
          const SizedBox(width: 44), // tile spacer
          Expanded(
            child: _HeaderColumn(
              title: 'Name',
              active: currentSort == FilesSortChoice.name,
              onTap: () => onSortChanged(FilesSortChoice.name),
            ),
          ),
          SizedBox(
            width: 110,
            child: _HeaderColumn(
              title: 'Size',
              alignment: Alignment.centerRight,
              active: currentSort == FilesSortChoice.largest,
              onTap: () => onSortChanged(FilesSortChoice.largest),
            ),
          ),
          SizedBox(
            width: 150,
            child: _HeaderColumn(
              title: 'Modified',
              alignment: Alignment.centerRight,
              active: currentSort == FilesSortChoice.newest,
              onTap: () => onSortChanged(FilesSortChoice.newest),
            ),
          ),
          const SizedBox(width: 40), // Download column spacer
        ],
      ),
    );
  }
}

class _HeaderColumn extends StatelessWidget {
  const _HeaderColumn({required this.title, this.alignment = Alignment.centerLeft, this.active = false, this.onTap});

  final String title;
  final Alignment alignment;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;

    return Align(
      alignment: alignment,
      child: InkWell(
        mouseCursor: SystemMouseCursors.click,
        onTap: onTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: ax.typo.label.copyWith(fontWeight: active ? FontWeight.w700 : FontWeight.w500, color: active ? c.text : c.textMuted),
            ),
            if (active) ...[const SizedBox(width: 4), Icon(Icons.arrow_downward_rounded, size: 14, color: c.accent)],
          ],
        ),
      ),
    );
  }
}

class _WideTableRow extends StatelessWidget {
  const _WideTableRow({required this.entry, required this.selected, required this.onTap, this.onDownload});

  final FileEntryModel entry;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onDownload;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final icon = fileIconFor(entry);
    final isHidden = entry.name.startsWith('.');
    final formattedDate = formatFileDate(entry.mtime);

    return InkWell(
      mouseCursor: SystemMouseCursors.click,
      onTap: onTap,
      child: Container(
        height: 46,
        padding: EdgeInsets.symmetric(horizontal: ax.space.lg),
        color: selected ? c.accentWash : null,
        child: Row(
          children: [
            // Tile icon
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: entry.isDir ? c.accentWash : c.surfaceHigh,
                borderRadius: BorderRadius.circular(ax.radii.sm),
              ),
              child: Icon(icon, size: 18, color: entry.isDir ? c.accent : c.textMuted),
            ),
            SizedBox(width: ax.space.md),

            // Name
            Expanded(
              child: Text(
                entry.name,
                overflow: TextOverflow.ellipsis,
                style: ax.typo.body.copyWith(fontWeight: FontWeight.w500, color: isHidden ? c.textMuted : c.text),
              ),
            ),

            // Size (folders show "—")
            SizedBox(
              width: 110,
              child: Text(entry.isDir ? '—' : entry.size, textAlign: TextAlign.end, style: ax.typo.mono.copyWith(color: c.textMuted)),
            ),

            // Modified
            SizedBox(
              width: 150,
              child: Text(
                formattedDate.isEmpty ? '—' : formattedDate,
                textAlign: TextAlign.end,
                style: ax.typo.mono.copyWith(color: c.textMuted),
              ),
            ),

            // Download action
            SizedBox(
              width: 40,
              child:
                  entry.isDir || onDownload == null
                      ? const SizedBox.shrink()
                      : Align(
                        alignment: Alignment.centerRight,
                        child: Tooltip(
                          message: 'Download ${entry.name}',
                          child: InkWell(
                            mouseCursor: SystemMouseCursors.click,
                            borderRadius: BorderRadius.circular(ax.radii.sm),
                            onTap: onDownload,
                            child: Container(
                              width: 28,
                              height: 28,
                              alignment: Alignment.center,
                              child: Icon(Icons.download_rounded, size: 18, color: c.textMuted),
                            ),
                          ),
                        ),
                      ),
            ),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// Narrow Table Row (54-60 tall)
// ----------------------------------------------------------------------------
class _NarrowTableRow extends StatelessWidget {
  const _NarrowTableRow({required this.entry, required this.selected, required this.onTap, this.onDownload});

  final FileEntryModel entry;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onDownload;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final icon = fileIconFor(entry);
    final isHidden = entry.name.startsWith('.');
    final subtitle = entrySubtitle(entry);

    return InkWell(
      mouseCursor: SystemMouseCursors.click,
      onTap: onTap,
      child: Container(
        height: 56,
        padding: EdgeInsets.symmetric(horizontal: ax.space.md),
        color: selected ? c.accentWash : null,
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: entry.isDir ? c.accentWash : c.surfaceHigh,
                borderRadius: BorderRadius.circular(ax.radii.sm),
              ),
              child: Icon(icon, size: 20, color: entry.isDir ? c.accent : c.textMuted),
            ),
            SizedBox(width: ax.space.md),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ax.typo.body.copyWith(fontWeight: FontWeight.w600, color: isHidden ? c.textMuted : c.text),
                  ),
                  SizedBox(height: ax.space.xs),
                  Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: ax.typo.caption.copyWith(color: c.textMuted)),
                ],
              ),
            ),
            if (entry.isDir)
              Icon(Icons.chevron_right_rounded, size: 20, color: c.textSubtle)
            else if (onDownload != null)
              Tooltip(
                message: 'Download ${entry.name}',
                child: InkWell(
                  mouseCursor: SystemMouseCursors.click,
                  borderRadius: BorderRadius.circular(ax.radii.sm),
                  onTap: onDownload,
                  child: Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    child: Icon(Icons.download_rounded, size: 18, color: c.textMuted),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// 403 Off limits state view
// ----------------------------------------------------------------------------
class _NotAllowedState extends StatelessWidget {
  const _NotAllowedState({required this.rootPath, required this.onBackToRoot, required this.onOpenTerminal});

  final String rootPath;
  final VoidCallback onBackToRoot;
  final VoidCallback onOpenTerminal;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;

    return Center(
      child: Padding(
        padding: EdgeInsets.all(ax.space.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(color: c.warningWash, shape: BoxShape.circle),
              child: Icon(Icons.lock_outline_rounded, size: 28, color: c.warning),
            ),
            SizedBox(height: ax.space.md),
            Text('This folder is off limits', style: ax.typo.title.copyWith(color: c.text), textAlign: TextAlign.center),
            SizedBox(height: ax.space.sm),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Text(
                'Files only shows what\'s inside $rootPath, to keep system files safe. Use the terminal to look elsewhere.',
                style: ax.typo.body.copyWith(color: c.textMuted),
                textAlign: TextAlign.center,
              ),
            ),
            SizedBox(height: ax.space.lg),
            Wrap(
              spacing: ax.space.sm,
              runSpacing: ax.space.sm,
              alignment: WrapAlignment.center,
              children: [
                AxButton(label: 'Back to $rootPath', onPressed: onBackToRoot),
                AxButton.secondary(label: 'Open terminal', onPressed: onOpenTerminal),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// Loading state with skeleton rows + chip
// ----------------------------------------------------------------------------
class _FilesLoadingState extends StatelessWidget {
  const _FilesLoadingState();

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;

    return Padding(
      padding: EdgeInsets.all(ax.space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.symmetric(horizontal: ax.space.md, vertical: ax.space.xs),
            decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(ax.radii.pill)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: c.accent)),
                SizedBox(width: ax.space.sm),
                Text('Opening folder…', style: ax.typo.caption.copyWith(color: c.text)),
              ],
            ),
          ),
          SizedBox(height: ax.space.lg),
          for (var i = 0; i < 4; i++) ...[
            Padding(
              padding: EdgeInsets.symmetric(vertical: ax.space.sm),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(ax.radii.sm)),
                  ),
                  SizedBox(width: ax.space.md),
                  Container(
                    width: 120 + (i * 30.0),
                    height: 16,
                    decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(ax.radii.sm)),
                  ),
                  const Spacer(),
                  Container(
                    width: 50,
                    height: 14,
                    decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(ax.radii.sm)),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
