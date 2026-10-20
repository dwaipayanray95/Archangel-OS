import 'package:flutter/material.dart';

import '../theme.dart';
import 'ax_button.dart';

/// Asks the user to confirm something with consequences. Resolves to true
/// only when they press the confirm button; dismissing or Cancel is false.
///
/// [message] states the consequence in plain language. With [typeToConfirm]
/// the confirm button stays disabled until that exact text is typed - for
/// things that cannot be undone.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = 'Cancel',
  bool danger = false,
  String? typeToConfirm,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder:
        (context) => ConfirmDialog(
          title: title,
          message: message,
          confirmLabel: confirmLabel,
          cancelLabel: cancelLabel,
          danger: danger,
          typeToConfirm: typeToConfirm,
        ),
  );
  return result ?? false;
}

class ConfirmDialog extends StatefulWidget {
  const ConfirmDialog({
    super.key,
    required this.title,
    required this.message,
    required this.confirmLabel,
    this.cancelLabel = 'Cancel',
    this.danger = false,
    this.typeToConfirm,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  final bool danger;
  final String? typeToConfirm;

  @override
  State<ConfirmDialog> createState() => _ConfirmDialogState();
}

class _ConfirmDialogState extends State<ConfirmDialog> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _matches => widget.typeToConfirm == null || _controller.text.trim() == widget.typeToConfirm;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final needsTyping = widget.typeToConfirm != null;
    return AlertDialog(
      scrollable: true,
      title: Row(
        children: [
          if (widget.danger) ...[Icon(Icons.warning_amber_rounded, color: c.danger), SizedBox(width: ax.space.sm)],
          Expanded(child: Text(widget.title, style: ax.typo.title.copyWith(color: c.text))),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.message, style: ax.typo.body.copyWith(color: c.textMuted)),
            if (needsTyping) ...[
              SizedBox(height: ax.space.lg),
              TextField(
                controller: _controller,
                autofocus: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(labelText: 'Type "${widget.typeToConfirm}" to confirm'),
                onSubmitted: (_) {
                  if (_matches) Navigator.of(context).pop(true);
                },
              ),
            ],
          ],
        ),
      ),
      actionsOverflowButtonSpacing: ax.space.sm,
      actions: [
        AxButton.ghost(label: widget.cancelLabel, onPressed: () => Navigator.of(context).pop(false)),
        widget.danger
            ? AxButton.danger(label: widget.confirmLabel, onPressed: _matches ? () => Navigator.of(context).pop(true) : null)
            : AxButton(label: widget.confirmLabel, onPressed: _matches ? () => Navigator.of(context).pop(true) : null),
      ],
    );
  }
}
