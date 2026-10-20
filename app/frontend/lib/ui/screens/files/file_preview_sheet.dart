import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/app_state.dart';
import '../../../models/file_entry.dart';
import '../../../services/files_service.dart';
import '../../ui.dart';
import 'file_helpers.dart';

/// Bottom sheet previewing a file (first lines), with Download and
/// "Open terminal here" for the folder it lives in.
Future<void> showFilePreviewSheet(BuildContext context, FileEntryModel entry) async {
  final files = context.read<FilesService>();
  final app = context.read<AppState>();
  final messenger = ScaffoldMessenger.of(context);
  files.openFilePreview(entry.path);
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 720),
    builder:
        (sheetContext) => ChangeNotifierProvider<FilesService>.value(
          value: files,
          child: _PreviewBody(
            entry: entry,
            onDownload: () async {
              final res = await files.downloadToDisk(entry.path);
              messenger.showSnackBar(SnackBar(content: Text(res.ok ? 'Saved to ${res.savedPath}' : (res.error ?? 'Download failed'))));
            },
            onTerminal: () {
              Navigator.of(sheetContext).pop();
              app.openTerminalInDir(parentDirOf(entry.path));
            },
          ),
        ),
  );
  files.closePreview();
}

class _PreviewBody extends StatefulWidget {
  const _PreviewBody({required this.entry, required this.onDownload, required this.onTerminal});

  final FileEntryModel entry;
  final Future<void> Function() onDownload;
  final VoidCallback onTerminal;

  @override
  State<_PreviewBody> createState() => _PreviewBodyState();
}

class _PreviewBodyState extends State<_PreviewBody> {
  bool _downloading = false;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final files = context.watch<FilesService>();
    final content = files.activePreviewPath == widget.entry.path ? files.fileContent : null;
    final loading = files.previewLoading || content == null;
    final maxPreview = MediaQuery.sizeOf(context).height * 0.4;

    Widget preview;
    if (loading) {
      preview = Padding(padding: EdgeInsets.all(ax.space.xl), child: Center(child: CircularProgressIndicator(color: c.accent)));
    } else if (content.isBinary) {
      preview = Padding(
        padding: EdgeInsets.all(ax.space.lg),
        child: Text(
          'This looks like a binary file, so there is no text preview. Use Download to save it.',
          style: ax.typo.body.copyWith(color: c.textMuted),
        ),
      );
    } else {
      preview = Scrollbar(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(ax.space.md),
          child: SelectableText(
            content.lines.isEmpty ? '(empty file)' : content.lines.join('\n'),
            style: ax.typo.mono.copyWith(color: c.text),
          ),
        ),
      );
    }

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(ax.space.xl, 0, ax.space.xl, ax.space.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(widget.entry.name, style: ax.typo.title.copyWith(color: c.text), overflow: TextOverflow.ellipsis),
            ),
            SizedBox(height: ax.space.xs),
            Text(entrySubtitle(widget.entry), style: ax.typo.caption.copyWith(color: c.textMuted)),
            SizedBox(height: ax.space.md),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxPreview),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: c.surfaceAlt,
                  borderRadius: BorderRadius.circular(ax.radii.md),
                  border: Border.all(color: c.border),
                ),
                child: preview,
              ),
            ),
            if (content != null && content.truncated)
              Padding(
                padding: EdgeInsets.only(top: ax.space.xs),
                child: Text('Showing the first lines only.', style: ax.typo.caption.copyWith(color: c.textMuted)),
              ),
            SizedBox(height: ax.space.lg),
            Wrap(
              spacing: ax.space.sm,
              runSpacing: ax.space.sm,
              children: [
                AxButton(
                  label: 'Download',
                  icon: Icons.download_rounded,
                  loading: _downloading,
                  onPressed: () async {
                    setState(() => _downloading = true);
                    await widget.onDownload();
                    if (mounted) setState(() => _downloading = false);
                  },
                ),
                AxButton.secondary(label: 'Open terminal here', icon: Icons.terminal_rounded, onPressed: widget.onTerminal),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
