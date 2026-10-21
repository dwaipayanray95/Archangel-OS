import 'package:flutter/material.dart';

/// Scales the entire app drawing canvas down by [scale] (default 0.85),
/// providing higher information density, crisper typography, and an elegant,
/// proportional feel across the entire UI on wide screens.
///
/// On phones (width < 500), it preserves 1.0 scale to keep touch targets comfortable.
class AxScaledCanvas extends StatelessWidget {
  const AxScaledCanvas({super.key, required this.child, this.scale = 0.85, this.phoneBreakpoint = 500});

  final Widget child;
  final double scale;
  final double phoneBreakpoint;

  @override
  Widget build(BuildContext context) {
    if (scale == 1.0) return child;

    return LayoutBuilder(
      builder: (context, constraints) {
        final media = MediaQuery.of(context);
        final effectiveScale = constraints.maxWidth < phoneBreakpoint ? 1.0 : scale;

        if (effectiveScale == 1.0) return child;

        final scaledMedia = media.copyWith(
          size: Size(media.size.width / effectiveScale, media.size.height / effectiveScale),
          padding: media.padding / effectiveScale,
          viewPadding: media.viewPadding / effectiveScale,
          viewInsets: media.viewInsets / effectiveScale,
        );

        return Transform.scale(
          scale: effectiveScale,
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: constraints.maxWidth / effectiveScale,
            height: constraints.maxHeight / effectiveScale,
            child: MediaQuery(data: scaledMedia, child: child),
          ),
        );
      },
    );
  }
}
