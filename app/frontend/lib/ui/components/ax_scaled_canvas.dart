import 'package:flutter/material.dart';

/// Scales the canvas to [scaleFactor] while filling 100% of the screen
/// with the wallpaper, top bar, and dock using [FittedBox].
///
/// On phones (width < [phoneBreakpoint]), it preserves 1.0 scale to keep touch targets comfortable.
class AxScaledCanvas extends StatelessWidget {
  const AxScaledCanvas({super.key, required this.child, required this.scaleFactor, this.phoneBreakpoint = 500});

  final Widget child;
  final double scaleFactor;
  final double phoneBreakpoint;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final effectiveScale = constraints.maxWidth < phoneBreakpoint ? 1.0 : scaleFactor;

        if (effectiveScale == 1.0) return child;

        final media = MediaQuery.of(context);
        final scaledMedia = media.copyWith(
          size: Size(media.size.width / effectiveScale, media.size.height / effectiveScale),
          padding: media.padding / effectiveScale,
          viewPadding: media.viewPadding / effectiveScale,
          viewInsets: media.viewInsets / effectiveScale,
        );

        return FittedBox(
          fit: BoxFit.fill,
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
