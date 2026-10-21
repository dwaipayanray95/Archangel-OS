import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/file_entry.dart';
import '../../../services/files_service.dart';
import '../../ui.dart';
import 'file_helpers.dart';

const int kMaxPreviewImageSizeBytes = 20 * 1024 * 1024; // 20 MB

/// Content body of a file preview: text, image, or unsupported/binary message.
class FilePreviewBody extends StatefulWidget {
  const FilePreviewBody({super.key, required this.entry, required this.files});

  final FileEntryModel entry;
  final FilesService files;

  @override
  State<FilePreviewBody> createState() => _FilePreviewBodyState();
}

class _FilePreviewBodyState extends State<FilePreviewBody> {
  Uint8List? _imageBytes;
  bool _imageLoading = false;
  String? _imageError;
  String? _loadedImagePath;

  @override
  void initState() {
    super.initState();
    _checkLoad();
  }

  @override
  void didUpdateWidget(covariant FilePreviewBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry.path != widget.entry.path) {
      _loadedImagePath = null;
      _imageBytes = null;
      _imageError = null;
      _checkLoad();
    }
  }

  void _checkLoad() {
    final e = widget.entry;
    final isImg = isImageFile(e);
    if (isImg && e.sizeBytes <= kMaxPreviewImageSizeBytes && _loadedImagePath != e.path) {
      _loadedImagePath = e.path;
      _imageLoading = true;
      widget.files
          .downloadFileBytes(e.path)
          .then((bytes) {
            if (!mounted || _loadedImagePath != e.path) return;
            setState(() {
              _imageBytes = bytes;
              _imageLoading = false;
              if (bytes == null) _imageError = 'Could not load image';
            });
          })
          .catchError((err) {
            if (!mounted || _loadedImagePath != e.path) return;
            setState(() {
              _imageError = err.toString();
              _imageLoading = false;
            });
          });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final e = widget.entry;
    final files = widget.files;

    final isImg = isImageFile(e);
    if (isImg) {
      if (e.sizeBytes > kMaxPreviewImageSizeBytes) {
        return _unsupportedBlock(context, 'There\'s no preview for this kind of file. Download it to open it on this device.');
      }
      if (_imageLoading) {
        return Container(
          height: 180,
          decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(ax.radii.md)),
          child: Center(child: CircularProgressIndicator(color: c.accent)),
        );
      }
      if (_imageBytes != null) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(ax.radii.md),
          child: Image.memory(_imageBytes!, fit: BoxFit.contain, semanticLabel: 'Preview of ${e.name}'),
        );
      }
      if (_imageError != null) {
        return _unsupportedBlock(context, 'There\'s no preview for this kind of file. Download it to open it on this device.');
      }
    }

    final content = files.fileContent;
    final loading = files.previewLoading || (content == null && files.activePreviewPath == e.path);

    if (loading) {
      return Container(
        height: 140,
        decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(ax.radii.md)),
        child: Center(child: CircularProgressIndicator(color: c.accent)),
      );
    }

    if (content != null && content.path == e.path) {
      if (content.isBinary) {
        return _unsupportedBlock(
          context,
          'There\'s no preview for this kind of file. Download it to open it on this device.',
          icon: fileIconFor(e),
        );
      }

      final lines = content.lines.join('\n');
      final footerText = content.truncated ? 'Showing the first 400 lines. Download to see the whole file.' : 'Showing the whole file.';

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            constraints: const BoxConstraints(maxHeight: 240),
            padding: EdgeInsets.all(ax.space.md),
            decoration: BoxDecoration(
              color: c.surfaceAlt,
              borderRadius: BorderRadius.circular(ax.radii.md),
              border: Border.all(color: c.border),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                lines.isEmpty ? '(empty file)' : lines,
                style: ax.typo.mono.copyWith(fontSize: 12, height: 1.6, color: c.text),
              ),
            ),
          ),
          SizedBox(height: ax.space.xs),
          Text(footerText, style: ax.typo.caption.copyWith(color: c.textMuted)),
        ],
      );
    }

    return _unsupportedBlock(
      context,
      'There\'s no preview for this kind of file. Download it to open it on this device.',
      icon: fileIconFor(e),
    );
  }

  Widget _unsupportedBlock(BuildContext context, String text, {IconData icon = Icons.insert_drive_file_outlined}) {
    final ax = context.ax;
    final c = ax.colors;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: ax.space.lg, vertical: ax.space.xl),
      decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(ax.radii.md), border: Border.all(color: c.border)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 32, color: c.textMuted),
          SizedBox(height: ax.space.sm),
          Text(text, textAlign: TextAlign.center, style: ax.typo.body.copyWith(fontSize: 13, color: c.textMuted)),
        ],
      ),
    );
  }
}

/// Action buttons for file preview: Copy private link (hidden when unsupported).
class PreviewActionButtons extends StatefulWidget {
  const PreviewActionButtons({super.key, required this.entry, required this.files});

  final FileEntryModel entry;
  final FilesService files;

  @override
  State<PreviewActionButtons> createState() => _PreviewActionButtonsState();
}

class _PreviewActionButtonsState extends State<PreviewActionButtons> {
  bool _linking = false;

  Future<void> _handlePrivateLink() async {
    if (_linking) return;
    setState(() => _linking = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final res = await widget.files.privateLink(widget.entry.path);
      if (!mounted) return;
      if (res.ok && res.url != null) {
        await Clipboard.setData(ClipboardData(text: res.url!));
        if (!mounted) return;
        messenger.showSnackBar(const SnackBar(content: Text('Link copied. It opens only on your own devices.')));
      } else {
        messenger.showSnackBar(SnackBar(content: Text(res.error ?? 'Could not create private link')));
      }
    } finally {
      if (mounted) setState(() => _linking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final showLink = widget.files.supportsPrivateLink;
    if (!showLink) return const SizedBox.shrink();

    return AxButton.secondary(label: 'Copy private link', icon: Icons.link_rounded, loading: _linking, onPressed: _handlePrivateLink);
  }
}

/// Compact, elegant icon button for the preview panel header.
class _PreviewHeaderIconButton extends StatelessWidget {
  const _PreviewHeaderIconButton({required this.icon, required this.tooltip, required this.onPressed, this.loading = false});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        mouseCursor: loading ? SystemMouseCursors.basic : SystemMouseCursors.click,
        borderRadius: BorderRadius.circular(ax.radii.sm),
        onTap: loading ? null : onPressed,
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: c.surfaceAlt,
            borderRadius: BorderRadius.circular(ax.radii.sm),
            border: Border.all(color: c.border),
          ),
          alignment: Alignment.center,
          child:
              loading
                  ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: c.accent))
                  : Icon(icon, size: 16, color: c.textMuted),
        ),
      ),
    );
  }
}

/// Wide preview card (300px wide, beside list).
class WidePreviewCard extends StatefulWidget {
  const WidePreviewCard({super.key, required this.entry, required this.files, required this.onClose});

  final FileEntryModel entry;
  final FilesService files;
  final VoidCallback onClose;

  @override
  State<WidePreviewCard> createState() => _WidePreviewCardState();
}

class _WidePreviewCardState extends State<WidePreviewCard> {
  bool _downloading = false;

  Future<void> _handleDownload() async {
    if (_downloading) return;
    setState(() => _downloading = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final res = await widget.files.downloadToDisk(widget.entry.path);
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(res.ok ? 'Saved to ${res.savedPath}' : (res.error ?? 'Download failed'))));
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final entry = widget.entry;
    final formattedDate = formatFileDate(entry.mtime);
    final meta = formattedDate.isEmpty ? entry.size : '${entry.size} · $formattedDate';

    return SizedBox(
      width: 300,
      child: AxCard(
        padding: EdgeInsets.all(ax.space.lg),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(entry.name, style: ax.typo.mono.copyWith(fontWeight: FontWeight.w600, color: c.text), softWrap: true),
                        SizedBox(height: ax.space.xs),
                        Text(meta, style: ax.typo.caption.copyWith(color: c.textMuted)),
                      ],
                    ),
                  ),
                  SizedBox(width: ax.space.sm),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _PreviewHeaderIconButton(
                        icon: Icons.download_rounded,
                        tooltip: 'Download',
                        loading: _downloading,
                        onPressed: _handleDownload,
                      ),
                      SizedBox(width: ax.space.xs),
                      _PreviewHeaderIconButton(icon: Icons.close_rounded, tooltip: 'Close preview', onPressed: widget.onClose),
                    ],
                  ),
                ],
              ),
              SizedBox(height: ax.space.md),
              FilePreviewBody(entry: entry, files: widget.files),
              SizedBox(height: ax.space.md),
              PreviewActionButtons(entry: entry, files: widget.files),
            ],
          ),
        ),
      ),
    );
  }
}

/// Narrow full-screen preview view with ghost back button.
class NarrowPreviewView extends StatefulWidget {
  const NarrowPreviewView({super.key, required this.entry, required this.files, required this.onClose});

  final FileEntryModel entry;
  final FilesService files;
  final VoidCallback onClose;

  @override
  State<NarrowPreviewView> createState() => _NarrowPreviewViewState();
}

class _NarrowPreviewViewState extends State<NarrowPreviewView> {
  bool _downloading = false;

  Future<void> _handleDownload() async {
    if (_downloading) return;
    setState(() => _downloading = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final res = await widget.files.downloadToDisk(widget.entry.path);
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(res.ok ? 'Saved to ${res.savedPath}' : (res.error ?? 'Download failed'))));
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final entry = widget.entry;
    final parentName = parentBaseNameOf(entry.path, rootPath: widget.files.rootPath);
    final formattedDate = formatFileDate(entry.mtime);
    final parentDir = parentDirOf(entry.path);

    return SingleChildScrollView(
      padding: EdgeInsets.all(ax.space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              AxButton.ghost(label: '‹ $parentName', onPressed: widget.onClose),
              _PreviewHeaderIconButton(
                icon: Icons.download_rounded,
                tooltip: 'Download',
                loading: _downloading,
                onPressed: _handleDownload,
              ),
            ],
          ),
          SizedBox(height: ax.space.md),
          Text(entry.name, style: ax.typo.mono.copyWith(fontSize: 18, fontWeight: FontWeight.w600, color: c.text), softWrap: true),
          SizedBox(height: ax.space.lg),
          AxCard(
            padding: EdgeInsets.all(ax.space.md),
            child: Column(
              children: [
                _MetaRow(label: 'Size', value: entry.size),
                Divider(color: c.border, height: ax.space.md),
                _MetaRow(label: 'Modified', value: formattedDate.isEmpty ? '—' : formattedDate),
                Divider(color: c.border, height: ax.space.md),
                _MetaRow(label: 'Where', value: parentDir),
              ],
            ),
          ),
          SizedBox(height: ax.space.lg),
          FilePreviewBody(entry: entry, files: widget.files),
          SizedBox(height: ax.space.lg),
          PreviewActionButtons(entry: entry, files: widget.files),
        ],
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: ax.typo.body.copyWith(color: c.textMuted)),
        const SizedBox(width: 8),
        Flexible(
          child: Text(value, style: ax.typo.mono.copyWith(color: c.text), textAlign: TextAlign.end, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}
