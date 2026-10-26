import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../../services/files_service.dart';
import '../../ui.dart';

/// Opens the system picker (several files allowed). Files are streamed from
/// the picked file when uploading, never read into memory here.
Future<List<UploadFileItem>> pickFilesToUpload() async {
  final picked = await openFiles();
  final items = <UploadFileItem>[];
  for (final f in picked) {
    items.add(UploadFileItem(name: f.name, sizeBytes: await f.length(), openRead: f.openRead));
  }
  return items;
}

/// Asks "Replace [name]?" with Replace / Skip / Keep both. Null if dismissed.
Future<UploadConflictChoice?> showUploadConflictDialog(BuildContext context, String name) {
  return showDialog<UploadConflictChoice>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      final ax = context.ax;
      return AlertDialog(
        scrollable: true,
        title: Text('Replace $name?', style: ax.typo.title.copyWith(color: ax.colors.text)),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Text(
            'A file with that name is already in this folder. Replace it, skip this one, or keep both.',
            style: ax.typo.body.copyWith(color: ax.colors.textMuted),
          ),
        ),
        actionsOverflowButtonSpacing: ax.space.sm,
        actions: [
          AxButton.ghost(label: 'Skip', onPressed: () => Navigator.of(context).pop(UploadConflictChoice.skip)),
          AxButton.ghost(label: 'Keep both', onPressed: () => Navigator.of(context).pop(UploadConflictChoice.keepBoth)),
          AxButton(label: 'Replace', onPressed: () => Navigator.of(context).pop(UploadConflictChoice.replace)),
        ],
      );
    },
  );
}

/// Progress card shown while files are uploading into a folder.
class UploadProgressCard extends StatelessWidget {
  const UploadProgressCard({
    super.key,
    required this.folderName,
    required this.progress,
    required this.onCancel,
    this.errorMessage,
    this.onRetry,
    this.onDismiss,
  });

  final String folderName;
  final UploadProgress progress;
  final VoidCallback onCancel;
  final String? errorMessage;
  final VoidCallback? onRetry;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final count = progress.totalFiles;
    final title = 'Uploading $count ${count == 1 ? 'file' : 'files'} to $folderName';
    final currentStatus = '${progress.currentFileName} · ${progress.fileIndex + 1} of ${progress.totalFiles}';
    final progressFraction = progress.totalBytes > 0 ? (progress.bytesSent / progress.totalBytes).clamp(0.0, 1.0) : null;

    return AxCard(
      padding: EdgeInsets.all(ax.space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: ax.typo.label.copyWith(color: c.text, fontWeight: FontWeight.w600))),
              if (errorMessage == null) AxButton.ghost(label: 'Cancel', small: true, onPressed: onCancel),
            ],
          ),
          SizedBox(height: ax.space.sm),
          if (errorMessage != null) ...[
            Text(errorMessage!, style: ax.typo.caption.copyWith(color: c.danger)),
            if (onRetry != null) ...[
              SizedBox(height: ax.space.sm),
              Wrap(
                spacing: ax.space.sm,
                children: [
                  AxButton(label: 'Try again', small: true, onPressed: onRetry),
                  if (onDismiss != null) AxButton.ghost(label: 'Dismiss', small: true, onPressed: onDismiss),
                ],
              ),
            ],
          ] else ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(ax.radii.pill),
              child: LinearProgressIndicator(value: progressFraction, minHeight: 6, color: c.accent, backgroundColor: c.border),
            ),
            SizedBox(height: ax.space.xs),
            Text(currentStatus, style: ax.typo.caption.copyWith(color: c.textMuted)),
          ],
        ],
      ),
    );
  }
}
