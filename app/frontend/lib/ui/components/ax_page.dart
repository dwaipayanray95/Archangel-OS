import 'package:flutter/material.dart';

import '../theme.dart';

/// Standard page frame: title (+ subtitle) with optional actions, then the
/// body. Padding and content width adapt to the available width.
class AxPage extends StatelessWidget {
  const AxPage({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.actions = const [],
    this.scrollable = true,
    this.maxContentWidth = 1100,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget child;

  /// Wrap the body in a vertical scroll view. Pass false when the body is
  /// itself a scrollable (e.g. a ListView) and should fill the page.
  final bool scrollable;
  final double maxContentWidth;

  static double paddingFor(double width) => width < 600 ? 16 : (width < 1100 ? 24 : 32);

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final pad = paddingFor(constraints.maxWidth);
        final header = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(header: true, child: Text(title, style: ax.typo.headline.copyWith(color: c.text))),
                  if (subtitle != null)
                    Padding(
                      padding: EdgeInsets.only(top: ax.space.xs),
                      child: Text(subtitle!, style: ax.typo.body.copyWith(color: c.textMuted)),
                    ),
                ],
              ),
            ),
            if (actions.isNotEmpty) ...[
              SizedBox(width: ax.space.md),
              Wrap(spacing: ax.space.sm, runSpacing: ax.space.sm, crossAxisAlignment: WrapCrossAlignment.center, children: actions),
            ],
          ],
        );
        final body = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [header, SizedBox(height: ax.space.lg), if (scrollable) child else Expanded(child: child)],
        );
        final padded = Padding(padding: EdgeInsets.all(pad), child: body);
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxContentWidth),
            child: scrollable ? SingleChildScrollView(child: padded) : padded,
          ),
        );
      },
    );
  }
}
