import 'package:flutter/material.dart';

import '../../../services/browser_service.dart';
import '../../ui.dart';

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _two(int n) => n.toString().padLeft(2, '0');

String browserTimeLabel(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

/// "Today", "Yesterday", or "18 Oct 2026".
String browserDayLabel(DateTime day, DateTime now) {
  final d = DateTime(day.year, day.month, day.day);
  final today = DateTime(now.year, now.month, now.day);
  final diff = today.difference(d).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  return '${d.day} ${_months[d.month - 1]} ${d.year}';
}

/// One row: icon, title, a mono second line, and a delete button.
class _ListRow extends StatelessWidget {
  const _ListRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.deleteTooltip,
    required this.onOpen,
    required this.onDelete,
  });

  final String title;
  final String subtitle;
  final String deleteTooltip;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    return InkWell(
      onTap: onOpen,
      child: Container(
        height: 54,
        padding: EdgeInsets.only(left: ax.space.lg),
        child: Row(
          children: [
            Icon(Icons.public, size: 20, color: c.textMuted),
            SizedBox(width: ax.space.md),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ax.typo.body.copyWith(color: c.text),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ax.typo.mono.copyWith(color: c.textMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
            AxIconButton(icon: Icons.delete_outline, tooltip: deleteTooltip, onPressed: onDelete),
          ],
        ),
      ),
    );
  }
}

class _ListFrame extends StatelessWidget {
  const _ListFrame({
    required this.title,
    required this.filterLabel,
    required this.onBack,
    required this.controller,
    required this.onFilter,
    required this.body,
    this.action,
  });

  final String title;
  final String filterLabel;
  final VoidCallback onBack;
  final TextEditingController controller;
  final ValueChanged<String> onFilter;
  final Widget body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            AxIconButton(icon: Icons.arrow_back, tooltip: 'Back to the page', onPressed: onBack),
            SizedBox(width: ax.space.sm),
            Expanded(
              child: Semantics(
                header: true,
                child: Text(title, style: ax.typo.title.copyWith(color: c.text)),
              ),
            ),
            ?action,
          ],
        ),
        SizedBox(height: ax.space.sm),
        TextField(
          controller: controller,
          onChanged: onFilter,
          decoration: InputDecoration(labelText: filterLabel, prefixIcon: const Icon(Icons.search)),
        ),
        SizedBox(height: ax.space.sm),
        Expanded(
          child: AxCard(padding: EdgeInsets.zero, child: body),
        ),
      ],
    );
  }
}

Widget _emptyBody(String title, String message) => BrowserEmptyList(title: title, message: message);

class BrowserEmptyList extends StatelessWidget {
  const BrowserEmptyList({super.key, required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(ax.space.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: ax.typo.title.copyWith(color: c.text),
            ),
            SizedBox(height: ax.space.xs),
            Text(
              message,
              textAlign: TextAlign.center,
              style: ax.typo.body.copyWith(color: c.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full-screen history inside the browser: grouped by day, filterable,
/// per-row delete, and Clear history behind a confirm.
class BrowserHistoryPage extends StatefulWidget {
  const BrowserHistoryPage({super.key, required this.service, required this.onBack, required this.onOpen, this.now});

  final BrowserService service;
  final VoidCallback onBack;
  final ValueChanged<Uri> onOpen;

  /// The current time; a test seam.
  final DateTime Function()? now;

  @override
  State<BrowserHistoryPage> createState() => _BrowserHistoryPageState();
}

class _BrowserHistoryPageState extends State<BrowserHistoryPage> {
  final _filter = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  Future<void> _clear() async {
    final ok = await showConfirmDialog(
      context,
      title: 'Clear history?',
      message: "This removes every page Archangel OS remembers you visiting on this device. It can't be undone.",
      confirmLabel: 'Clear history',
      danger: true,
    );
    if (ok) widget.service.clearHistory();
  }

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    return LayoutBuilder(
      builder: (context, box) => ListenableBuilder(
        listenable: widget.service,
        builder: (context, _) {
          final narrow = box.maxWidth < 520;
          final q = _q.trim().toLowerCase();
          final all = widget.service.history;
          final shown = [
            for (final v in all)
              if (q.isEmpty || v.title.toLowerCase().contains(q) || v.url.toLowerCase().contains(q)) v,
          ];
          final now = (widget.now ?? DateTime.now)();
          final rows = <Widget>[];
          String? lastDay;
          for (final v in shown) {
            final at = v.visitedAt.toLocal();
            final day = browserDayLabel(at, now);
            if (day != lastDay) {
              lastDay = day;
              rows.add(
                Padding(
                  padding: EdgeInsets.fromLTRB(ax.space.lg, ax.space.md, ax.space.lg, ax.space.xs),
                  child: Semantics(
                    header: true,
                    child: Text(day, style: ax.typo.label.copyWith(color: c.textMuted)),
                  ),
                ),
              );
            }
            rows.add(
              _ListRow(
                key: ValueKey('history-${v.id}'),
                title: v.title,
                subtitle: '${v.host} · ${browserTimeLabel(at)}',
                deleteTooltip: 'Delete from history',
                onOpen: () => widget.onOpen(Uri.parse(v.url)),
                onDelete: () => widget.service.deleteVisit(v.id),
              ),
            );
          }
          final Widget body = all.isEmpty
              ? _emptyBody('No history yet', 'Pages you visit will show up here.')
              : shown.isEmpty
              ? _emptyBody('Nothing matches "${_q.trim()}"', 'Try a shorter word.')
              : ListView(children: rows);
          return _ListFrame(
            title: 'History',
            filterLabel: 'Filter history',
            onBack: widget.onBack,
            controller: _filter,
            onFilter: (v) => setState(() => _q = v),
            body: body,
            action: narrow
                ? AxIconButton(icon: Icons.delete_sweep_outlined, tooltip: 'Clear history', onPressed: all.isEmpty ? null : _clear)
                : AxButton.secondary(label: 'Clear history', icon: Icons.delete_sweep_outlined, onPressed: all.isEmpty ? null : _clear),
          );
        },
      ),
    );
  }
}

/// Full-screen bookmarks: a plain list with a filter and delete.
class BrowserBookmarksPage extends StatefulWidget {
  const BrowserBookmarksPage({super.key, required this.service, required this.onBack, required this.onOpen});

  final BrowserService service;
  final VoidCallback onBack;
  final ValueChanged<Uri> onOpen;

  @override
  State<BrowserBookmarksPage> createState() => _BrowserBookmarksPageState();
}

class _BrowserBookmarksPageState extends State<BrowserBookmarksPage> {
  final _filter = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.service,
      builder: (context, _) {
        final q = _q.trim().toLowerCase();
        final all = widget.service.bookmarks;
        final shown = [
          for (final b in all)
            if (q.isEmpty || b.title.toLowerCase().contains(q) || b.url.toLowerCase().contains(q)) b,
        ];
        final Widget body = all.isEmpty
            ? _emptyBody('No bookmarks yet', 'Tap the star next to the address to keep a page here.')
            : shown.isEmpty
            ? _emptyBody('Nothing matches "${_q.trim()}"', 'Try a shorter word.')
            : ListView(
                children: [
                  for (final b in shown)
                    _ListRow(
                      key: ValueKey('bookmark-${b.id}'),
                      title: b.title,
                      subtitle: b.host,
                      deleteTooltip: 'Delete bookmark',
                      onOpen: () => widget.onOpen(Uri.parse(b.url)),
                      onDelete: () => widget.service.deleteBookmarkById(b.id),
                    ),
                ],
              );
        return _ListFrame(
          title: 'Bookmarks',
          filterLabel: 'Filter bookmarks',
          onBack: widget.onBack,
          controller: _filter,
          onFilter: (v) => setState(() => _q = v),
          body: body,
        );
      },
    );
  }
}
