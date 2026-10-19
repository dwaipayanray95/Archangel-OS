import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../data/app_state.dart';
import '../services/containers_service.dart';
import '../ui/theme.dart';

/// "⌘K" on Apple platforms, "Ctrl K" elsewhere.
String paletteShortcutLabel() =>
    (defaultTargetPlatform == TargetPlatform.macOS || defaultTargetPlatform == TargetPlatform.iOS) ? '⌘K' : 'Ctrl K';

class _PaletteItem {
  final String label;
  final String sub;
  final IconData icon;
  final VoidCallback go;
  const _PaletteItem({required this.label, required this.sub, required this.icon, required this.go});
}

/// Global command-palette overlay (⌘K / Ctrl K): jump to any section or app
/// from anywhere.
class CommandPalette extends StatefulWidget {
  const CommandPalette({super.key});

  @override
  State<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<CommandPalette> {
  final _controller = TextEditingController();
  int _selected = 0;
  List<_PaletteItem> _flat = const [];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      context.read<AppState>().closePalette();
      return KeyEventResult.handled;
    }
    if (_flat.isEmpty) return KeyEventResult.ignored;
    if (key == LogicalKeyboardKey.arrowDown) {
      setState(() => _selected = (_selected + 1) % _flat.length);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      setState(() => _selected = (_selected - 1 + _flat.length) % _flat.length);
      return KeyEventResult.handled;
    }
    // Enter is handled by the field's onSubmitted (also covers soft keyboards).
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final contSvc = context.watch<ContainersService>();
    final ax = context.ax;
    final c = ax.colors;

    final sections = <_PaletteItem>[
      for (final s in AxSection.values)
        _PaletteItem(label: axSectionLabels[s]!, sub: 'Jump to section', icon: Icons.arrow_forward_rounded, go: () => app.go(s)),
    ];
    final liveContainers = contSvc.overview?.containers ?? [];
    final containerItems = <_PaletteItem>[
      for (final ct in liveContainers.take(4))
        _PaletteItem(label: ct.name, sub: ct.image, icon: Icons.view_in_ar_outlined, go: () => app.go(AxSection.apps)),
    ];

    final query = _controller.text.trim().toLowerCase();
    List<_PaletteItem> filter(List<_PaletteItem> items) =>
        query.isEmpty ? items : items.where((i) => i.label.toLowerCase().contains(query)).toList();

    final groups = <String, List<_PaletteItem>>{
      'Sections': filter(sections),
      'Apps': filter(containerItems),
    }..removeWhere((_, v) => v.isEmpty);
    _flat = [for (final g in groups.values) ...g];
    if (_selected >= _flat.length) _selected = _flat.isEmpty ? 0 : _flat.length - 1;
    var flatIndex = 0;

    return GestureDetector(
      excludeFromSemantics: true, // dismissed by Esc or the system back action
      onTap: app.closePalette,
      child: Container(
        color: c.scrim,
        alignment: const Alignment(0, -0.55),
        padding: EdgeInsets.all(ax.space.lg),
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.975, end: 1),
          duration: const Duration(milliseconds: 230),
          curve: Curves.easeOutCubic,
          builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
          child: GestureDetector(
            excludeFromSemantics: true,
            onTap: () {}, // swallow taps so they don't close the palette
            child: Material(
              color: Colors.transparent,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 560),
                decoration: BoxDecoration(
                  color: c.surfaceHigh,
                  borderRadius: BorderRadius.circular(ax.radii.lg),
                  border: Border.all(color: c.border),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: ax.space.lg, vertical: ax.space.sm),
                      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border))),
                      child: Row(
                        children: [
                          Icon(Icons.search, size: 20, color: c.accent),
                          SizedBox(width: ax.space.md),
                          Expanded(
                            child: Focus(
                              onKeyEvent: _onKey,
                              child: TextField(
                                controller: _controller,
                                autofocus: true,
                                onChanged: (_) => setState(() => _selected = 0),
                                onSubmitted: (_) {
                                  if (_flat.isNotEmpty) _flat[_selected.clamp(0, _flat.length - 1)].go();
                                },
                                style: ax.typo.body.copyWith(color: c.text),
                                decoration: InputDecoration(
                                  border: InputBorder.none,
                                  hintText: 'Search sections and apps…',
                                  hintStyle: ax.typo.body.copyWith(color: c.textMuted),
                                ),
                              ),
                            ),
                          ),
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: ax.space.sm, vertical: ax.space.xs),
                            decoration: BoxDecoration(
                              color: c.bg,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: c.border),
                            ),
                            child: Text('ESC', style: ax.typo.mono.copyWith(fontSize: 12, color: c.textMuted)),
                          ),
                        ],
                      ),
                    ),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 360),
                      child: SingleChildScrollView(
                        padding: EdgeInsets.all(ax.space.sm),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (groups.isEmpty)
                              Padding(
                                padding: EdgeInsets.symmetric(vertical: ax.space.xxl),
                                child: Center(
                                  child: Text('No match for "$query"', style: ax.typo.body.copyWith(color: c.textMuted)),
                                ),
                              )
                            else
                              for (final entry in groups.entries) ...[
                                Padding(
                                  padding: EdgeInsets.fromLTRB(ax.space.sm, ax.space.sm, ax.space.sm, ax.space.xs),
                                  child: Text(
                                    entry.key.toUpperCase(),
                                    style: ax.typo.caption.copyWith(fontWeight: FontWeight.w600, letterSpacing: 1, color: c.textMuted),
                                  ),
                                ),
                                for (final item in entry.value)
                                  _PaletteRow(item: item, selected: flatIndex++ == _selected),
                              ],
                          ],
                        ),
                      ),
                    ),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: ax.space.lg, vertical: ax.space.sm),
                      decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.border))),
                      child: Wrap(
                        spacing: ax.space.lg,
                        runSpacing: ax.space.xs,
                        children: [
                          _hint(ax, '↑↓', 'navigate'),
                          _hint(ax, '↵', 'open'),
                          _hint(ax, 'esc', 'close'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _hint(ArchangelTheme ax, String key, String label) {
    final c = ax.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: EdgeInsets.symmetric(horizontal: ax.space.xs + 1, vertical: 2),
          decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(5)),
          child: Text(key, style: ax.typo.mono.copyWith(fontSize: 12, color: c.textMuted)),
        ),
        SizedBox(width: ax.space.xs + 1),
        Text(label, style: ax.typo.caption.copyWith(color: c.textMuted)),
      ],
    );
  }
}

class _PaletteRow extends StatefulWidget {
  final _PaletteItem item;
  final bool selected;
  const _PaletteRow({required this.item, required this.selected});

  @override
  State<_PaletteRow> createState() => _PaletteRowState();
}

class _PaletteRowState extends State<_PaletteRow> {
  bool _hover = false;

  @override
  void didUpdateWidget(_PaletteRow old) {
    super.didUpdateWidget(old);
    if (widget.selected && !old.selected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Scrollable.ensureVisible(context, duration: const Duration(milliseconds: 80));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final item = widget.item;
    return Semantics(
      button: true,
      selected: widget.selected,
      label: '${item.label}, ${item.sub}',
      excludeSemantics: true,
      onTap: item.go,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: item.go,
          child: Container(
            constraints: BoxConstraints(minHeight: axMinTarget(context)),
            padding: EdgeInsets.symmetric(horizontal: ax.space.sm, vertical: ax.space.sm),
            margin: const EdgeInsets.symmetric(vertical: 1),
            decoration: BoxDecoration(
              color: (_hover || widget.selected) ? c.surfaceAlt : Colors.transparent,
              borderRadius: BorderRadius.circular(ax.radii.md),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(color: c.accentWash, borderRadius: BorderRadius.circular(ax.radii.sm)),
                  child: Icon(item.icon, size: 18, color: c.accent),
                ),
                SizedBox(width: ax.space.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(item.label, style: ax.typo.label.copyWith(color: c.text), overflow: TextOverflow.ellipsis),
                      Text(item.sub, style: ax.typo.caption.copyWith(color: c.textMuted), overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
