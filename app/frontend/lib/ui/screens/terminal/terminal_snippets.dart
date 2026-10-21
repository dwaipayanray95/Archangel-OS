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
      actions: [AxButton.ghost(label: 'Cancel', onPressed: () => Navigator.of(context).pop()), AxButton(label: 'Save', onPressed: _submit)],
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
    this.inSheet = false,
  });

  final List<TerminalSnippet> snippets;
  final ValueChanged<TerminalSnippet> onSelect;
  final VoidCallback onSave;
  final ValueChanged<TerminalSnippet> onDelete;
  final bool inSheet;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;

    final header = Padding(
      padding: EdgeInsets.fromLTRB(ax.space.md, ax.space.md, ax.space.md, ax.space.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Snippets', style: ax.typo.title.copyWith(color: inSheet ? c.text : kConText)),
          SizedBox(height: ax.space.xs),
          Text(
            'Tap one to put it on the command line. It runs only when you press Enter.',
            style: ax.typo.caption.copyWith(color: inSheet ? c.textMuted : kConMuted),
          ),
        ],
      ),
    );

    final list = Expanded(
      child: ListView.separated(
        padding: EdgeInsets.symmetric(horizontal: ax.space.sm, vertical: ax.space.xs),
        itemCount: snippets.length,
        separatorBuilder: (_, __) => SizedBox(height: ax.space.xs),
        itemBuilder: (context, index) {
          final s = snippets[index];
          return _SnippetTile(snippet: s, onSelect: () => onSelect(s), onDelete: () => onDelete(s), inSheet: inSheet);
        },
      ),
    );

    final bottomButton = Padding(
      padding: EdgeInsets.all(ax.space.md),
      child: AxButton.secondary(label: '+ Save a snippet', onPressed: onSave),
    );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [header, list, bottomButton]);
  }
}

class _SnippetTile extends StatelessWidget {
  const _SnippetTile({required this.snippet, required this.onSelect, required this.onDelete, required this.inSheet});

  final TerminalSnippet snippet;
  final VoidCallback onSelect;
  final VoidCallback onDelete;
  final bool inSheet;

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
    final fg = inSheet ? c.text : kConText;
    final cmdColor = inSheet ? c.accent : kConAccent;

    return Material(
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
          padding: EdgeInsets.symmetric(horizontal: ax.space.sm, vertical: ax.space.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(snippet.name, style: ax.typo.caption.copyWith(fontFamily: kUiFontFamily, fontWeight: FontWeight.w600, color: fg)),
              SizedBox(height: ax.space.xs - 2),
              Text(snippet.command, style: ax.typo.mono.copyWith(fontSize: 12, color: cmdColor)),
            ],
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
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
