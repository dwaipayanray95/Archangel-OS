import 'package:flutter/material.dart';

import '../theme.dart';
import 'ax_button.dart';
import 'ax_icon_button.dart';

/// Opens a short explanation in a bottom sheet.
Future<void> showHelpSheet(BuildContext context, {required String title, required String message}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) {
      final ax = context.ax;
      final c = ax.colors;
      return SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(ax.space.xl, 0, ax.space.xl, ax.space.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(header: true, child: Text(title, style: ax.typo.title.copyWith(color: c.text))),
              SizedBox(height: ax.space.sm),
              Text(message, style: ax.typo.body.copyWith(color: c.textMuted)),
              SizedBox(height: ax.space.lg),
              Align(
                alignment: Alignment.centerRight,
                child: AxButton.secondary(label: 'Got it', onPressed: () => Navigator.of(context).pop()),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// The (i) button next to a term the user may not know. Tapping it explains
/// the term in plain words.
class HelpTip extends StatelessWidget {
  const HelpTip({super.key, required this.title, required this.message, this.tooltip});

  final String title;
  final String message;

  /// Defaults to "What is <title>?".
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return AxIconButton(
      icon: Icons.info_outline,
      tooltip: tooltip ?? 'What is $title?',
      onPressed: () => showHelpSheet(context, title: title, message: message),
    );
  }
}

/// A text-style variant of [HelpTip] for use inside error and empty states.
class HelpLink extends StatelessWidget {
  const HelpLink({super.key, required this.label, required this.title, required this.message});

  final String label;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return AxButton.ghost(label: label, icon: Icons.help_outline, onPressed: () => showHelpSheet(context, title: title, message: message));
  }
}
