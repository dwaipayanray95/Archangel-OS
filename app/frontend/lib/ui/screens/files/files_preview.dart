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
        return _unsupportedBlock(context, 'There\'s no preview for this kind of file. Download it to open it on this device.');
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
              color: const Color(0xFF0F111A),
              borderRadius: BorderRadius.circular(ax.radii.md),
              border: Border.all(color: const Color(0x1AFFFFFF)),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                lines.isEmpty ? '(empty file)' : lines,
                style: ax.typo.mono.copyWith(fontSize: 12, height: 1.6, color: const Color(0xFFE2E8F0)),
              ),
            ),
          ),
          SizedBox(height: ax.space.xs),
          Text(footerText, style: ax.typo.caption.copyWith(color: c.textMuted)),
        ],
      );
    }

    return _unsupportedBlock(context, 'There\'s no preview for this kind of file. Download it to open it on this device.');
  }

  Widget _unsupportedBlock(BuildContext context, String text) {
    final ax = context.ax;
    final c = ax.colors;
    return Container(
      padding: EdgeInsets.all(ax.space.lg),
      decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(ax.radii.md)),
      child: Center(child: Text(text, textAlign: TextAlign.center, style: ax.typo.body.copyWith(color: c.textMuted))),
    );
  }
}

/// Buttons row: Download (primary) and Copy private link (secondary, hidden when unsupported).
class PreviewActionButtons extends StatefulWidget {
  const PreviewActionButtons({super.key, required this.entry, required this.files});

  final FileEntryModel entry;
  final FilesService files;

  @override
  State<PreviewActionButtons> createState() => _PreviewActionButtonsState();
}

class _PreviewActionButtonsState extends State<PreviewActionButtons> {
  bool _downloading = false;
  bool _linking = false;

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
    final ax = context.ax;
    final showLink = widget.files.supportsPrivateLink;

    return Wrap(
      spacing: ax.space.sm,
      runSpacing: ax.space.sm,
      children: [
        AxButton(label: 'Download', icon: Icons.download_rounded, loading: _downloading, onPressed: _handleDownload),
        if (showLink)
          AxButton.secondary(label: 'Copy private link', icon: Icons.link_rounded, loading: _linking, onPressed: _handlePrivateLink),
      ],
    );
  }
}

/// Wide preview card (300px wide, beside list).
class WidePreviewCard extends StatelessWidget {
  const WidePreviewCard({super.key, required this.entry, required this.files, required this.onClose});

  final FileEntryModel entry;
  final FilesService files;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final formattedDate = formatFileDate(entry.mtime);
    final meta = formattedDate.isEmpty ? entry.size : '${entry.size} · $formattedDate';

    return SizedBox(
      width: 300,
      child: AxCard(
        padding: EdgeInsets.all(ax.space.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Text(entry.name, style: ax.typo.mono.copyWith(fontWeight: FontWeight.w600, color: c.text), softWrap: true)),
                AxIconButton(icon: Icons.close_rounded, tooltip: 'Close preview', onPressed: onClose),
              ],
            ),
            SizedBox(height: ax.space.xs),
            Text(meta, style: ax.typo.caption.copyWith(color: c.textMuted)),
            SizedBox(height: ax.space.md),
            FilePreviewBody(entry: entry, files: files),
            SizedBox(height: ax.space.md),
            PreviewActionButtons(entry: entry, files: files),
          ],
        ),
      ),
    );
  }
}

/// Narrow full-screen preview view with ghost back button.
class NarrowPreviewView extends StatelessWidget {
  const NarrowPreviewView({super.key, required this.entry, required this.files, required this.onClose});

  final FileEntryModel entry;
  final FilesService files;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final parentName = parentBaseNameOf(entry.path, rootPath: files.rootPath);
    final formattedDate = formatFileDate(entry.mtime);
    final parentDir = parentDirOf(entry.path);

    return SingleChildScrollView(
      padding: EdgeInsets.all(ax.space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(alignment: Alignment.centerLeft, child: AxButton.ghost(label: '‹ $parentName', onPressed: onClose)),
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
          FilePreviewBody(entry: entry, files: files),
          SizedBox(height: ax.space.lg),
          PreviewActionButtons(entry: entry, files: files),
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
