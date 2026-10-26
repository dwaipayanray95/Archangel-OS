import 'dart:async';

import 'package:flutter/material.dart';

import '../theme.dart';
import 'ax_button.dart';
import 'help_tip.dart';

class _StateFrame extends StatelessWidget {
  const _StateFrame({required this.icon, required this.iconColor, required this.title, this.message, this.children = const []});

  final Widget icon;
  final Color iconColor;
  final String title;
  final String? message;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: EdgeInsets.all(ax.space.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconTheme(
                data: IconThemeData(color: iconColor, size: 40),
                child: icon,
              ),
              SizedBox(height: ax.space.md),
              Text(
                title,
                textAlign: TextAlign.center,
                style: ax.typo.title.copyWith(color: c.text),
              ),
              if (message != null) ...[
                SizedBox(height: ax.space.sm),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: ax.typo.body.copyWith(color: c.textMuted),
                ),
              ],
              for (final w in children) ...[SizedBox(height: ax.space.lg), w],
            ],
          ),
        ),
      ),
    );
  }
}

/// "Nothing here yet" with a way forward.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.title, this.message, this.icon = Icons.inbox_outlined, this.actionLabel, this.onAction});

  final String title;
  final String? message;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return _StateFrame(
      icon: Icon(icon),
      iconColor: context.ax.colors.textMuted,
      title: title,
      message: message,
      children: [if (actionLabel != null && onAction != null) AxButton(label: actionLabel!, onPressed: onAction)],
    );
  }
}

/// Something went wrong: what happened in plain words, a Retry button and an
/// optional "What does this mean?" explanation.
class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.message, this.title = 'Something went wrong', this.onRetry, this.helpTitle, this.helpText});

  final String title;
  final String message;
  final VoidCallback? onRetry;
  final String? helpTitle;
  final String? helpText;

  @override
  Widget build(BuildContext context) {
    final c = context.ax.colors;
    return _StateFrame(
      icon: const Icon(Icons.error_outline),
      iconColor: c.danger,
      title: title,
      message: message,
      children: [
        if (onRetry != null) AxButton(label: 'Retry', icon: Icons.refresh, onPressed: onRetry),
        if (helpText != null) HelpLink(label: 'What does this mean?', title: helpTitle ?? 'What does this mean?', message: helpText!),
      ],
    );
  }
}

/// A spinner with a message. If it is still showing after [stillWaitingAfter]
/// (10 s by default) it switches to an actionable "still waiting" message,
/// because an endless spinner tells the user nothing.
class LoadingState extends StatefulWidget {
  const LoadingState({
    super.key,
    this.message = 'Loading...',
    this.stillWaitingAfter = const Duration(seconds: 10),
    this.stillWaitingMessage = 'This is taking longer than usual. Your server may be offline, or the secure connection may be down.',
    this.onRetry,
  });

  final String message;
  final Duration stillWaitingAfter;
  final String stillWaitingMessage;

  /// Shown as a Retry button in the "still waiting" state when provided.
  final VoidCallback? onRetry;

  @override
  State<LoadingState> createState() => _LoadingStateState();
}

class _LoadingStateState extends State<LoadingState> {
  Timer? _timer;
  bool _slow = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.stillWaitingAfter, () {
      if (mounted) setState(() => _slow = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ax.colors;
    return Semantics(
      liveRegion: true,
      child: _slow
          ? _StateFrame(
              icon: const Icon(Icons.hourglass_empty),
              iconColor: c.warning,
              title: 'Still waiting...',
              message: widget.stillWaitingMessage,
              children: [if (widget.onRetry != null) AxButton(label: 'Try again', icon: Icons.refresh, onPressed: widget.onRetry)],
            )
          : _StateFrame(
              icon: SizedBox(width: 32, height: 32, child: CircularProgressIndicator(strokeWidth: 3, color: c.accent)),
              iconColor: c.accent,
              title: widget.message,
            ),
    );
  }
}
