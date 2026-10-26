import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../services/local_kv_store.dart';
import '../../components/ax_button.dart';
import '../../theme.dart';
import 'terminal_palette.dart';

const String kTerminalSnippetsKey = 'terminal_snippets';

class TerminalSnippet {
  final String name;
  final String command;

  const TerminalSnippet({required this.name, required this.command});

  factory TerminalSnippet.fromJson(Map<String, dynamic> json) =>
      TerminalSnippet(name: json['name'] as String? ?? '', command: json['command'] as String? ?? '');

  Map<String, dynamic> toJson() => {'name': name, 'command': command};

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TerminalSnippet && runtimeType == other.runtimeType && name == other.name && command == other.command;

  @override
  int get hashCode => Object.hash(name, command);
}

const List<TerminalSnippet> kDefaultSnippets = [
  TerminalSnippet(name: "What's running", command: 'docker ps'),
  TerminalSnippet(name: 'How full is the disk', command: 'df -h'),
  TerminalSnippet(name: 'Memory in use', command: 'free -h'),
  TerminalSnippet(name: "Follow Archangel's log", command: 'journalctl -u archangeld -f'),
  TerminalSnippet(name: 'Update the server', command: 'sudo apt update && sudo apt upgrade'),
  TerminalSnippet(name: 'Busy programs', command: 'htop'),
];

Future<List<TerminalSnippet>> loadTerminalSnippets() async {
  try {
    final raw = await LocalKvStore.instance.read(kTerminalSnippetsKey);
    if (raw == null || raw.trim().isEmpty) return List.of(kDefaultSnippets);
    final decoded = jsonDecode(raw);
    if (decoded is! List) return List.of(kDefaultSnippets);
    final list = <TerminalSnippet>[];
    for (final item in decoded) {
      if (item is Map) {
        list.add(TerminalSnippet.fromJson(Map<String, dynamic>.from(item)));
      }
    }
    return list.isEmpty ? List.of(kDefaultSnippets) : list;
  } catch (_) {
    return List.of(kDefaultSnippets);
  }
}

Future<void> saveTerminalSnippets(List<TerminalSnippet> snippets) async {
  final jsonStr = jsonEncode(snippets.map((s) => s.toJson()).toList());
  await LocalKvStore.instance.write(kTerminalSnippetsKey, jsonStr);
}

Future<TerminalSnippet?> showSaveSnippetDialog(BuildContext context) {
  return showDialog<TerminalSnippet>(context: context, builder: (_) => const _SaveSnippetDialog());
}

class _SaveSnippetDialog extends StatefulWidget {
  const _SaveSnippetDialog();

  @override
  State<_SaveSnippetDialog> createState() => _SaveSnippetDialogState();
}

class _SaveSnippetDialogState extends State<_SaveSnippetDialog> {
  final _nameController = TextEditingController();
  final _commandController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _commandController.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    final command = _commandController.text.trim();
    if (name.isNotEmpty && command.isNotEmpty) {
      Navigator.of(context).pop(TerminalSnippet(name: name, command: command));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    return AlertDialog(
      title: Text('Save a snippet', style: ax.typo.title.copyWith(color: c.text)),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameController,
              autofocus: true,
              style: ax.typo.body.copyWith(color: c.text),
              decoration: const InputDecoration(labelText: 'Name', hintText: 'e.g. My snippet'),
            ),
            SizedBox(height: ax.space.md),
            TextField(
              controller: _commandController,
              style: ax.typo.mono.copyWith(color: c.text),
              decoration: const InputDecoration(labelText: 'Command', hintText: 'e.g. ls -la'),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        AxButton.ghost(label: 'Cancel', onPressed: () => Navigator.of(context).pop()),
        AxButton(label: 'Save', onPressed: _submit),
      ],
    );
  }
}

class SnippetsView extends StatelessWidget {
  const SnippetsView({
    super.key,
    required this.snippets,
    required this.onSelect,
    required this.onSave,
    required this.onDelete,
    this.onReorder,
    this.inSheet = false,
  });

  final List<TerminalSnippet> snippets;
  final ValueChanged<TerminalSnippet> onSelect;
  final VoidCallback onSave;
  final ValueChanged<TerminalSnippet> onDelete;
  final ReorderCallback? onReorder;
  final bool inSheet;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final tp = context.terminalPalette;

    final header = Padding(
      padding: EdgeInsets.fromLTRB(ax.space.sm, ax.space.sm, ax.space.sm, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Snippets',
            style: ax.typo.caption.copyWith(fontSize: 13, fontWeight: FontWeight.w600, color: inSheet ? c.text : tp.text),
          ),
          const SizedBox(height: 2),
          Text(
            'Tap to insert on command line.',
            style: ax.typo.caption.copyWith(fontSize: 11, color: inSheet ? c.textMuted : tp.textMuted),
          ),
        ],
      ),
    );

    final list = Expanded(
      child: ReorderableListView.builder(
        padding: EdgeInsets.symmetric(horizontal: ax.space.xs, vertical: 2),
        itemCount: snippets.length,
        onReorderItem: onReorder,
        buildDefaultDragHandles: false,
        proxyDecorator: (child, index, animation) {
          return Material(
            color: inSheet ? ax.colors.surface : tp.barBg,
            elevation: 6,
            shadowColor: Colors.black.withValues(alpha: tp.isDark ? 0.5 : 0.15),
            borderRadius: BorderRadius.circular(ax.radii.sm),
            child: child,
          );
        },
        itemBuilder: (context, index) {
          final s = snippets[index];
          return _SnippetTile(
            key: ValueKey('snippet_${s.name}_${s.command}'),
            index: index,
            snippet: s,
            onSelect: () => onSelect(s),
            onDelete: () => onDelete(s),
            inSheet: inSheet,
            reorderable: onReorder != null,
          );
        },
      ),
    );

    final bottomButton = Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: AxButton.secondary(label: '+ Save a snippet', onPressed: onSave),
    );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [header, list, bottomButton]);
  }
}

class _SnippetTile extends StatelessWidget {
  const _SnippetTile({
    super.key,
    required this.index,
    required this.snippet,
    required this.onSelect,
    required this.onDelete,
    required this.inSheet,
    required this.reorderable,
  });

  final int index;
  final TerminalSnippet snippet;
  final VoidCallback onSelect;
  final VoidCallback onDelete;
  final bool inSheet;
  final bool reorderable;

  void _showContextMenu(BuildContext context, Offset globalPos) {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(globalPos & const Size(1, 1), Offset.zero & overlay.size),
      items: const [PopupMenuItem(value: 'delete', child: Text('Delete snippet'))],
    ).then((v) {
      if (v == 'delete') onDelete();
    });
  }

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final tp = context.terminalPalette;
    final fg = inSheet ? c.text : tp.text;
    final cmdColor = inSheet ? c.accent : tp.accent;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(ax.radii.sm),
        child: InkWell(
          borderRadius: BorderRadius.circular(ax.radii.sm),
          onTap: onSelect,
          onLongPress: () {
            final box = context.findRenderObject() as RenderBox?;
            final pos = box != null ? box.localToGlobal(box.size.center(Offset.zero)) : Offset.zero;
            _showContextMenu(context, pos);
          },
          onSecondaryTapUp: (details) => _showContextMenu(context, details.globalPosition),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        snippet.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ax.typo.caption.copyWith(fontFamily: kUiFontFamily, fontWeight: FontWeight.w600, fontSize: 12, color: fg),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        snippet.command,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ax.typo.mono.copyWith(fontSize: 11, color: cmdColor),
                      ),
                    ],
                  ),
                ),
                if (reorderable)
                  ReorderableDragStartListener(
                    index: index,
                    child: Tooltip(
                      message: 'Drag to reorder',
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(Icons.drag_indicator, size: 16, color: tp.textMuted.withValues(alpha: 0.45)),
                      ),
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

Future<void> showSnippetsBottomSheet({
  required BuildContext context,
  required List<TerminalSnippet> snippets,
  required ValueChanged<TerminalSnippet> onSelect,
  required VoidCallback onSave,
  required ValueChanged<TerminalSnippet> onDelete,
  ReorderCallback? onReorder,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: context.ax.colors.surface,
    isScrollControlled: true,
    builder: (sheetContext) {
      final ax = sheetContext.ax;
      return SafeArea(
        child: SizedBox(
          height: 480,
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: ax.space.md),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [AxButton.ghost(label: 'Close', onPressed: () => Navigator.of(sheetContext).pop())],
                ),
              ),
              Expanded(
                child: SnippetsView(
                  snippets: snippets,
                  inSheet: true,
                  onSelect: (s) {
                    Navigator.of(sheetContext).pop();
                    onSelect(s);
                  },
                  onSave: onSave,
                  onDelete: onDelete,
                  onReorder: onReorder,
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
