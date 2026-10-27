import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../ui.dart';
import 'browser_chrome.dart';
import 'browser_tabs.dart';

const double kBrowserTabHeight = 32;
const double kBrowserTabMinWidth = 120;
const double kBrowserTabMaxWidth = 220;

/// Wide layout: the strip of tabs above the chrome, with "+" at the end.
/// The selected tab is scrolled into view when there are more than fit.
class BrowserTabStrip extends StatefulWidget {
  const BrowserTabStrip({super.key, required this.tabs});

  final BrowserTabs tabs;

  @override
  State<BrowserTabStrip> createState() => _BrowserTabStripState();
}

class _BrowserTabStripState extends State<BrowserTabStrip> {
  final _keys = <String, GlobalKey>{};
  String? _shown;

  void _revealSelected() {
    final id = widget.tabs.selected.id;
    if (id == _shown) return;
    _shown = id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _keys[id]?.currentContext;
      if (mounted && ctx != null) Scrollable.ensureVisible(ctx, duration: Duration.zero);
    });
  }

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final tabs = widget.tabs;
    final list = tabs.tabs;
    _keys.removeWhere((id, _) => !list.any((t) => t.id == id));
    _revealSelected();
    final addButton = AxIconButton(
      icon: Icons.add,
      tooltip: tabs.atCap ? kBrowserCapTooltip : 'New tab',
      onPressed: tabs.atCap ? null : tabs.newTab,
    );
    return SizedBox(
      height: math.max(kBrowserTabHeight, axMinTarget(context)),
      child: LayoutBuilder(
        builder: (context, box) {
          final room = box.maxWidth - axMinTarget(context) - ax.space.xs;
          final each = (room / list.length - ax.space.xs).clamp(kBrowserTabMinWidth, kBrowserTabMaxWidth);
          return Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final t in list)
                        Padding(
                          key: _keys.putIfAbsent(t.id, GlobalKey.new),
                          padding: EdgeInsets.only(right: ax.space.xs),
                          child: SizedBox(
                            width: each,
                            child: _TabChip(
                              key: ValueKey('tab-${t.id}'),
                              tab: t,
                              selected: t == tabs.selected,
                              onSelect: () => tabs.select(t),
                              onClose: () => tabs.close(t),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              addButton,
            ],
          );
        },
      ),
    );
  }
}

class _TabChip extends StatefulWidget {
  const _TabChip({super.key, required this.tab, required this.selected, required this.onSelect, required this.onClose});

  final BrowserTab tab;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onClose;

  @override
  State<_TabChip> createState() => _TabChipState();
}

class _TabChipState extends State<_TabChip> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final selected = widget.selected;
    final title = widget.tab.displayTitle;
    final content = Row(
      children: [
        SizedBox(width: ax.space.md),
        BrowserFavicon(url: widget.tab.controller.faviconUrl),
        SizedBox(width: ax.space.sm),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: ax.typo.caption.copyWith(
              color: selected ? c.text : c.textMuted,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
        if (selected || _hover)
          Tooltip(
            message: 'Close tab',
            child: InkResponse(
              key: ValueKey('tab-close-${widget.tab.id}'),
              onTap: widget.onClose,
              radius: 14,
              child: Padding(
                padding: EdgeInsets.all(ax.space.xs + 2),
                child: Icon(Icons.close, size: 16, color: c.textMuted),
              ),
            ),
          )
        else
          SizedBox(width: ax.space.md),
      ],
    );
    final shape = BorderRadius.circular(ax.radii.pill);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Semantics(
        button: true,
        selected: selected,
        label: title,
        child: InkWell(
          onTap: widget.onSelect,
          borderRadius: shape,
          child: SizedBox(
            height: kBrowserTabHeight,
            child: selected ? AxGlass(strong: true, radius: ax.radii.pill, child: content) : content,
          ),
        ),
      ),
    );
  }
}

/// Narrow layout: every tab as a 54-tall row, plus "New tab" at the bottom.
class BrowserTabList extends StatelessWidget {
  const BrowserTabList({super.key, required this.tabs, required this.onPick, required this.onDone});

  final BrowserTabs tabs;

  /// A row was tapped: the tab is selected, go back to the page.
  final VoidCallback onPick;

  /// "Back" or a new tab was opened.
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final list = tabs.tabs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            AxIconButton(icon: Icons.arrow_back, tooltip: 'Back to the page', onPressed: onDone),
            SizedBox(width: ax.space.sm),
            Expanded(
              child: Semantics(
                header: true,
                child: Text('Tabs', style: ax.typo.title.copyWith(color: c.text)),
              ),
            ),
          ],
        ),
        SizedBox(height: ax.space.sm),
        Expanded(
          child: AxCard(
            padding: EdgeInsets.zero,
            child: ListView.builder(
              itemCount: list.length,
              itemBuilder: (context, i) {
                final t = list[i];
                final selected = t == tabs.selected;
                final host = t.controller.currentUrl?.host ?? '';
                return Semantics(
                  button: true,
                  selected: selected,
                  label: t.displayTitle,
                  child: InkWell(
                    key: ValueKey('tab-row-${t.id}'),
                    onTap: () {
                      tabs.select(t);
                      onPick();
                    },
                    child: Container(
                      height: 54,
                      color: selected ? c.accentWash : null,
                      padding: EdgeInsets.only(left: ax.space.lg),
                      child: Row(
                        children: [
                          BrowserFavicon(url: t.controller.faviconUrl, size: 20),
                          SizedBox(width: ax.space.md),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  t.displayTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: ax.typo.body.copyWith(color: c.text, fontWeight: selected ? FontWeight.w600 : FontWeight.w400),
                                ),
                                if (host.isNotEmpty)
                                  Text(
                                    host,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: ax.typo.mono.copyWith(color: c.textMuted, fontSize: 12),
                                  ),
                              ],
                            ),
                          ),
                          AxIconButton(icon: Icons.close, tooltip: 'Close tab', onPressed: () => tabs.close(t)),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        SizedBox(height: ax.space.md),
        Tooltip(
          message: tabs.atCap ? kBrowserCapTooltip : '',
          child: AxButton(
            label: 'New tab',
            icon: Icons.add,
            expand: true,
            onPressed: tabs.atCap
                ? null
                : () {
                    tabs.newTab();
                    onDone();
                  },
          ),
        ),
      ],
    );
  }
}
