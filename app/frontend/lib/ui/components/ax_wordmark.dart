import 'package:flutter/material.dart';

import '../theme.dart';

/// The Archangel OS wordmark: "Archangel" in Inter semibold, "OS" in the
/// accent colour at a lighter weight. It is the whole logo - there is no
/// separate symbol.
class AxWordmark extends StatelessWidget {
  const AxWordmark({super.key, this.size = 17, this.letterSpacing, this.color, this.osColor});

  final double size;

  /// Overrides the default tight tracking (the boot animation animates it).
  final double? letterSpacing;

  /// Overrides the colours (the boot animation paints a sweep through them).
  final Color? color;
  final Color? osColor;

  @override
  Widget build(BuildContext context) {
    final c = context.ax.colors;
    final spacing = letterSpacing ?? -0.02 * size;
    return Semantics(
      label: 'Archangel OS',
      excludeSemantics: true,
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: 'Archangel',
              style: TextStyle(fontWeight: FontWeight.w600, color: color ?? c.text, letterSpacing: spacing),
            ),
            TextSpan(
              text: ' ',
              style: TextStyle(letterSpacing: spacing),
            ),
            TextSpan(
              text: 'OS',
              style: TextStyle(fontWeight: FontWeight.w400, color: osColor ?? c.accent, letterSpacing: spacing.clamp(0, 99)),
            ),
          ],
        ),
        maxLines: 1,
        softWrap: false,
        style: TextStyle(fontFamily: kUiFontFamily, fontSize: size, height: 1.1),
      ),
    );
  }
}
