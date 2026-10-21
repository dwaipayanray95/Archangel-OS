import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../theme.dart';

/// A row with optional leading/trailing widgets, a title and a subtitle.
/// Tappable rows are at least one touch target tall.
///
/// With [controls] it becomes a settings-style row: the text on the left and
/// the controls (buttons, switches, chips) on the right. When the controls
/// leave the text less than 200 wide they wrap below it.
class AxListTile extends StatelessWidget {
  const AxListTile({
    super.key,
    required this.title,
    this.subtitle,
    this.subtitleWidget,
    this.leading,
    this.trailing,
    this.controls = const [],
    this.onTap,
    this.selected = false,
    this.semanticsLabel,
    this.titleMono = false,
    this.subtitleMono = false,
  });

  final String title;
  final String? subtitle;

  /// Replaces [subtitle] when it needs mixed styles (for example a mono address).
  final Widget? subtitleWidget;
  final Widget? leading;
  final Widget? trailing;

  /// Widgets on the right of a settings-style row. Not used with [onTap].
  final List<Widget> controls;
  final VoidCallback? onTap;
  final bool selected;
  final String? semanticsLabel;

  /// Names, addresses and paths are shown in the mono face.
  final bool titleMono;
  final bool subtitleMono;

  /// The least width the text keeps before the controls wrap below it.
  static const double minTextWidth = 200;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    if (controls.isNotEmpty) return _controlsRow(context);
    final tile = ListTile(
      onTap: onTap,
      selected: selected,
      selectedColor: c.text,
      selectedTileColor: c.accentWash,
      iconColor: c.textMuted,
      textColor: c.text,
      minTileHeight: axMinTarget(context),
      contentPadding: EdgeInsets.symmetric(horizontal: ax.space.lg, vertical: ax.space.xs),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ax.radii.md)),
      leading: leading,
      trailing: trailing,
      title: Text(title, style: (titleMono ? ax.typo.mono : ax.typo.label).copyWith(color: c.text)),
      subtitle: subtitleWidget ?? (subtitle == null ? null : Text(subtitle!, style: _subtitleStyle(ax).copyWith(color: c.textMuted))),
    );
    if (semanticsLabel == null) return tile;
    return Semantics(label: semanticsLabel, button: onTap != null, container: true, excludeSemantics: true, onTap: onTap, child: tile);
  }

  TextStyle _subtitleStyle(ArchangelTheme ax) => subtitleMono ? ax.typo.mono : ax.typo.caption;

  Widget _controlsRow(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: (titleMono ? ax.typo.mono : ax.typo.body).copyWith(color: c.text)),
        if (subtitleWidget != null || subtitle != null)
          Padding(
            padding: EdgeInsets.only(top: ax.space.xs / 2),
            child: subtitleWidget ?? Text(subtitle!, style: _subtitleStyle(ax).copyWith(color: c.textMuted)),
          ),
      ],
    );
    final body = _SplitRow(
      gap: ax.space.md,
      minText: minTextWidth,
      text: text,
      controls: Wrap(spacing: ax.space.sm, runSpacing: ax.space.sm, crossAxisAlignment: WrapCrossAlignment.center, children: controls),
    );
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: ax.space.lg, vertical: ax.space.md),
      child: Row(
        children: [
          if (leading != null) ...[leading!, SizedBox(width: ax.space.md)],
          Expanded(child: body),
        ],
      ),
    );
  }
}

/// The small rounded square behind a row's icon.
class AxTileIcon extends StatelessWidget {
  const AxTileIcon(this.icon, {super.key, this.color});

  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(color: c.surfaceHigh, borderRadius: BorderRadius.circular(ax.radii.sm)),
      child: Icon(icon, size: 20, color: color ?? c.textMuted),
    );
  }
}

/// Lays out [text] on the left and [controls] on the right on one line. When
/// the text would get less than [minText] it puts the controls below it.
class _SplitRow extends MultiChildRenderObjectWidget {
  _SplitRow({required Widget text, required Widget controls, required this.gap, required this.minText})
    : super(children: [text, controls]);

  final double gap;
  final double minText;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderSplitRow(gap: gap, minText: minText);

  @override
  void updateRenderObject(BuildContext context, _RenderSplitRow renderObject) {
    renderObject
      ..gap = gap
      ..minText = minText;
  }
}

class _SplitParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderSplitRow extends RenderBox
    with ContainerRenderObjectMixin<RenderBox, _SplitParentData>, RenderBoxContainerDefaultsMixin<RenderBox, _SplitParentData> {
  _RenderSplitRow({required double gap, required double minText}) : _gap = gap, _minText = minText;

  double _gap;
  set gap(double v) {
    if (v == _gap) return;
    _gap = v;
    markNeedsLayout();
  }

  double _minText;
  set minText(double v) {
    if (v == _minText) return;
    _minText = v;
    markNeedsLayout();
  }

  RenderBox get _text => firstChild!;
  RenderBox get _controls => lastChild!;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _SplitParentData) child.parentData = _SplitParentData();
  }

  ({Size size, Offset text, Offset controls}) _arrange(BoxConstraints constraints, Size Function(RenderBox, BoxConstraints) layoutChild) {
    final maxW = constraints.maxWidth;
    final controlsSize = layoutChild(_controls, BoxConstraints(maxWidth: maxW));
    final room = maxW.isFinite ? maxW - controlsSize.width - _gap : double.infinity;
    if (room >= _minText) {
      final textSize = layoutChild(_text, BoxConstraints(maxWidth: room));
      final h = math.max(textSize.height, controlsSize.height);
      final w = maxW.isFinite ? maxW : textSize.width + _gap + controlsSize.width;
      return (
        size: constraints.constrain(Size(w, h)),
        text: Offset(0, (h - textSize.height) / 2),
        controls: Offset(w - controlsSize.width, (h - controlsSize.height) / 2),
      );
    }
    final textSize = layoutChild(_text, BoxConstraints(maxWidth: maxW));
    return (
      size: constraints.constrain(Size(maxW, textSize.height + _gap + controlsSize.height)),
      text: Offset.zero,
      controls: Offset(0, textSize.height + _gap),
    );
  }

  @override
  void performLayout() {
    final a = _arrange(constraints, ChildLayoutHelper.layoutChild);
    (_text.parentData! as _SplitParentData).offset = a.text;
    (_controls.parentData! as _SplitParentData).offset = a.controls;
    size = a.size;
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) => _arrange(constraints, ChildLayoutHelper.dryLayoutChild).size;

  @override
  double computeMinIntrinsicWidth(double height) => math.max(_text.getMinIntrinsicWidth(height), _controls.getMinIntrinsicWidth(height));

  @override
  double computeMaxIntrinsicWidth(double height) => _text.getMaxIntrinsicWidth(height) + _gap + _controls.getMaxIntrinsicWidth(height);

  @override
  double computeMinIntrinsicHeight(double width) => computeDryLayout(BoxConstraints(maxWidth: width)).height;

  @override
  double computeMaxIntrinsicHeight(double width) => computeMinIntrinsicHeight(width);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) => defaultHitTestChildren(result, position: position);

  @override
  void paint(PaintingContext context, Offset offset) => defaultPaint(context, offset);
}
