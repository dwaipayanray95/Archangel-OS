import 'package:flutter/material.dart';

import '../../../services/files_service.dart';
import '../../ui.dart';

/// Progress card shown while files are uploading into a folder.
class UploadProgressCard extends StatelessWidget {
  const UploadProgressCard({
    super.key,
    required this.folderName,
    required this.progress,
    required this.onCancel,
    this.errorMessage,
    this.onRetry,
  });

  final String folderName;
  final UploadProgress progress;
  final VoidCallback onCancel;
  final String? errorMessage;
  final VoidCallback? onRetry;

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
              Align(alignment: Alignment.centerLeft, child: AxButton(label: 'Try again', small: true, onPressed: onRetry)),
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
