import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../data/app_state.dart';
import '../services/containers_service.dart';
import '../theme/tokens.dart';

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

/// Global command-palette overlay (⌘K / Ctrl K) — the second non-negotiable "OS-like" element besides
/// the top bar: jump to any section or entity from anywhere in the app.
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

    final sections = <_PaletteItem>[
      for (final s in AxSection.values)
        _PaletteItem(label: axSectionLabels[s]!, sub: 'Jump to section', icon: Icons.arrow_forward_rounded, go: () => app.go(s)),
    ];
    final liveContainers = contSvc.overview?.containers ?? [];
    final containerItems = <_PaletteItem>[
      for (final c in liveContainers.take(4))
        _PaletteItem(label: c.name, sub: c.image, icon: Icons.view_in_ar_outlined, go: () => app.go(AxSection.containers)),
    ];

    final query = _controller.text.trim().toLowerCase();
    List<_PaletteItem> filter(List<_PaletteItem> items) =>
        query.isEmpty ? items : items.where((i) => i.label.toLowerCase().contains(query)).toList();

    final groups = <String, List<_PaletteItem>>{
      'Sections': filter(sections),
      'Containers': filter(containerItems),
    }..removeWhere((_, v) => v.isEmpty);
    _flat = [for (final g in groups.values) ...g];
    if (_selected >= _flat.length) _selected = _flat.isEmpty ? 0 : _flat.length - 1;
    var flatIndex = 0;

    return GestureDetector(
      onTap: app.closePalette,
      child: Container(
        color: const Color(0x9E040504),
        alignment: const Alignment(0, -0.55),
        padding: const EdgeInsets.only(top: 0),
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.975, end: 1),
          duration: AxMotion.pop,
          curve: AxMotion.easeOutSoft,
          builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
          child: GestureDetector(
            onTap: () {}, // swallow taps so they don't close the palette
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: 560,
                constraints: const BoxConstraints(maxWidth: 560),
                decoration: BoxDecoration(
                  color: AxColors.s2,
                  borderRadius: BorderRadius.circular(17),
                  border: Border.all(color: AxColors.line2),
                  boxShadow: const [BoxShadow(color: Colors.black87, blurRadius: 80, offset: Offset(0, 32))],
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
                      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AxColors.line))),
                      child: Row(
                        children: [
                          const Icon(Icons.search, size: 15, color: AxColors.accent),
                          const SizedBox(width: 11),
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
                              style: AxTextStyles.sans.copyWith(fontSize: 15),
                              decoration: InputDecoration(
                                border: InputBorder.none,
                                isDense: true,
                                hintText: 'Search sections and containers…',
                                hintStyle: AxTextStyles.sans.copyWith(fontSize: 15, color: AxColors.fg3),
                              ),
                            ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(color: AxColors.bg, borderRadius: BorderRadius.circular(6), border: Border.all(color: AxColors.line)),
                            child: Text('ESC', style: AxTextStyles.mono.copyWith(fontSize: 9.5, color: AxColors.fg3)),
                          ),
                        ],
                      ),
                    ),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 360),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(7),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (groups.isEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 32),
                                child: Center(
                                  child: Text('no match for "$query"', style: AxTextStyles.mono.copyWith(fontSize: 12, color: AxColors.fg3)),
                                ),
                              )
                            else
                              for (final entry in groups.entries) ...[
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(9, 7, 9, 5),
                                  child: Text(entry.key.toUpperCase(), style: AxTextStyles.mono.copyWith(fontSize: 9.5, fontWeight: FontWeight.w500, letterSpacing: 1.2, color: AxColors.fg3)),
                                ),
                                for (final item in entry.value)
                                  _PaletteRow(item: item, selected: flatIndex++ == _selected),
                              ],
                          ],
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: const BoxDecoration(color: AxColors.s1, border: Border(top: BorderSide(color: AxColors.line))),
                      child: Row(
                        children: [
                          _hint('↑↓', 'navigate'),
                          const SizedBox(width: 14),
                          _hint('↵', 'open'),
                          const SizedBox(width: 14),
                          _hint('esc', 'close'),
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

  Widget _hint(String key, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(color: AxColors.s3, borderRadius: BorderRadius.circular(5)),
          child: Text(key, style: AxTextStyles.mono.copyWith(fontSize: 9, color: AxColors.fg2)),
        ),
        const SizedBox(width: 5),
        Text(label, style: AxTextStyles.sans.copyWith(fontSize: 10.5, color: AxColors.fg3)),
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
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.item.go,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
          margin: const EdgeInsets.symmetric(vertical: 1),
          decoration: BoxDecoration(color: (_hover || widget.selected) ? AxColors.s3 : Colors.transparent, borderRadius: BorderRadius.circular(10)),
          child: Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(color: AxColors.wash, borderRadius: BorderRadius.circular(8)),
                child: Icon(widget.item.icon, size: 14, color: AxColors.accent),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(widget.item.label, style: AxTextStyles.sans.copyWith(fontSize: 13, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                    Text(widget.item.sub, style: AxTextStyles.mono.copyWith(fontSize: 10.5, color: AxColors.fg3), overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
