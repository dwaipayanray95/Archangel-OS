import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ui.dart';

/// Prominent, dismissible message when the server refuses an action. When the
/// refusal is about Admin mode, [onOpenSettings] adds an "Open Settings" button.
class RefusalBanner extends StatelessWidget {
  const RefusalBanner({super.key, required this.message, required this.onDismiss, this.onOpenSettings});

  final String message;
  final VoidCallback onDismiss;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        padding: EdgeInsets.all(ax.space.md),
        decoration: BoxDecoration(
          color: c.warningWash,
          borderRadius: BorderRadius.circular(ax.radii.md),
          border: Border.all(color: c.warning, width: 1.5),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.shield_outlined, color: c.warning),
            SizedBox(width: ax.space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("That wasn't allowed", style: ax.typo.title.copyWith(color: c.text)),
                  SizedBox(height: ax.space.xs),
                  Text(message, style: ax.typo.body.copyWith(color: c.text)),
                  if (onOpenSettings != null) ...[
                    SizedBox(height: ax.space.md),
                    AxButton(label: 'Open Settings', icon: Icons.settings_outlined, onPressed: onOpenSettings),
                  ],
                ],
              ),
            ),
            AxIconButton(icon: Icons.close_rounded, tooltip: 'Dismiss message', onPressed: onDismiss),
          ],
        ),
      ),
    );
  }
}

/// Shows what a script printed when it ran: a Finished / Did not finish badge,
/// the output in a mono block, Copy and Close.
Future<void> showRunOutputSheet(
  BuildContext context, {
  required String scriptName,
  required bool ok,
  required String message,
  required String output,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 720),
    builder: (_) => RunOutputSheet(scriptName: scriptName, ok: ok, message: message, output: output),
  );
}

class RunOutputSheet extends StatefulWidget {
  const RunOutputSheet({super.key, required this.scriptName, required this.ok, required this.message, required this.output});

  final String scriptName;
  final bool ok;
  final String message;
  final String output;

  @override
  State<RunOutputSheet> createState() => _RunOutputSheetState();
}

class _RunOutputSheetState extends State<RunOutputSheet> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.output));
    if (mounted) setState(() => _copied = true);
  }

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final maxH = MediaQuery.sizeOf(context).height * 0.45;
    final hasOutput = widget.output.trim().isNotEmpty;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(ax.space.lg, 0, ax.space.lg, ax.space.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(text: 'Output of '),
                    TextSpan(
                      text: widget.scriptName,
                      style: ax.typo.mono.copyWith(fontWeight: FontWeight.w700, color: c.text),
                    ),
                  ],
                ),
                style: ax.typo.title.copyWith(color: c.text),
              ),
            ),
            SizedBox(height: ax.space.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: widget.ok ? const StatusBadge.ok('Finished') : const StatusBadge.error('Did not finish'),
            ),
            if (widget.message.isNotEmpty) ...[
              SizedBox(height: ax.space.sm),
              Text(widget.message, style: ax.typo.body.copyWith(color: c.textMuted)),
            ],
            SizedBox(height: ax.space.md),
            Container(
              constraints: BoxConstraints(maxHeight: maxH),
              padding: EdgeInsets.all(ax.space.md),
              decoration: BoxDecoration(
                color: c.surfaceHigh,
                borderRadius: BorderRadius.circular(ax.radii.md),
                border: Border.all(color: c.border),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  hasOutput ? widget.output : 'The script finished without printing anything.',
                  style: ax.typo.mono.copyWith(fontSize: 12, color: hasOutput ? c.text : c.textMuted),
                ),
              ),
            ),
            SizedBox(height: ax.space.md),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: ax.space.sm,
              runSpacing: ax.space.sm,
              children: [
                if (hasOutput)
                  AxButton.secondary(
                    label: _copied ? 'Copied' : 'Copy',
                    icon: _copied ? Icons.check_rounded : Icons.copy_rounded,
                    onPressed: _copy,
                  ),
                AxButton.ghost(label: 'Close', onPressed: () => Navigator.of(context).pop()),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
