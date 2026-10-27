import 'package:flutter/material.dart';

import '../../../services/browser_service.dart';
import '../../ui.dart';
import 'browser_chrome.dart';
import 'browser_lists.dart';
import 'browser_states.dart';
import 'browser_tab_strip.dart';
import 'browser_tabs.dart';
import 'web_view_host.dart';

/// At or above this width the browser shows the tab strip and one chrome row.
const double kBrowserWideMinWidth = 720;

enum _BrowserPane { page, tabs, history, bookmarks }

/// The browser: tabs, chrome and the page area. It only knows
/// [AxWebController]; the real web view is installed in `main.dart`.
class BrowserWorkspace extends StatefulWidget {
  const BrowserWorkspace({super.key, required this.service, this.controllerFactory});

  final BrowserService service;

  /// Makes each tab's controller; defaults to [AxWebControllers.create].
  final AxWebControllerFactory? controllerFactory;

  @override
  State<BrowserWorkspace> createState() => _BrowserWorkspaceState();
}

class _BrowserWorkspaceState extends State<BrowserWorkspace> {
  late final BrowserTabs _tabs;
  _BrowserPane _pane = _BrowserPane.page;

  @override
  void initState() {
    super.initState();
    _tabs = BrowserTabs(service: widget.service, factory: widget.controllerFactory);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _show(_BrowserPane pane) => setState(() => _pane = pane);

  void _onMenu(BrowserMenuChoice choice) => _show(choice == BrowserMenuChoice.history ? _BrowserPane.history : _BrowserPane.bookmarks);

  /// Opens [url] in the current tab and returns to the page.
  void _openHere(Uri url) {
    _show(_BrowserPane.page);
    _tabs.selected.open(url);
  }

  void _toggleBookmark(BrowserTab tab) {
    final url = tab.controller.currentUrl;
    if (url == null) return;
    widget.service.toggleBookmark(url.toString(), title: tab.controller.title);
  }

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    return LayoutBuilder(
      builder: (context, box) {
        final wide = box.maxWidth >= kBrowserWideMinWidth;
        return Padding(
          padding: EdgeInsets.all(AxPage.paddingFor(box.maxWidth)),
          child: ListenableBuilder(
            listenable: Listenable.merge([_tabs, widget.service, ..._tabs.tabs]),
            builder: (context, _) {
              final tab = _tabs.selected;
              final url = tab.controller.currentUrl;
              final bookmarked = url != null && widget.service.isBookmarked(url.toString());
              final onBookmark = tab.canBookmark ? () => _toggleBookmark(tab) : null;

              // Only the new-tab view uses this, and working it out walks the
              // whole history - so don't do it on every progress tick.
              final mostVisited = tab.view == BrowserTabView.newTab ? widget.service.mostVisited() : const <BrowserVisit>[];
              final Widget page = _PageArea(tabs: _tabs, wide: wide, mostVisited: mostVisited);
              final Widget browse = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (wide) ...[BrowserTabStrip(tabs: _tabs), SizedBox(height: ax.space.xs)],
                  if (wide)
                    BrowserChromeWide(tab: tab, bookmarked: bookmarked, onBookmark: onBookmark, onMenu: _onMenu)
                  else
                    BrowserChromeNarrow(
                      tab: tab,
                      tabCount: _tabs.tabs.length,
                      bookmarked: bookmarked,
                      onBookmark: onBookmark,
                      onMenu: _onMenu,
                      onShowTabs: () => _show(_BrowserPane.tabs),
                    ),
                  BrowserProgressLine(tab: tab),
                  SizedBox(height: ax.space.xs),
                  Expanded(child: page),
                ],
              );

              final Widget? other = switch (_pane) {
                _BrowserPane.page => null,
                _BrowserPane.tabs => BrowserTabList(
                  tabs: _tabs,
                  onPick: () => _show(_BrowserPane.page),
                  onDone: () => _show(_BrowserPane.page),
                ),
                _BrowserPane.history => BrowserHistoryPage(
                  service: widget.service,
                  onBack: () => _show(_BrowserPane.page),
                  onOpen: _openHere,
                ),
                _BrowserPane.bookmarks => BrowserBookmarksPage(
                  service: widget.service,
                  onBack: () => _show(_BrowserPane.page),
                  onOpen: _openHere,
                ),
              };
              // Wide windows keep the pages loaded behind History and Bookmarks;
              // narrow ones let go of them (phones are short on memory).
              if (!wide) return other ?? browse;
              return Stack(
                fit: StackFit.expand,
                children: [
                  Offstage(offstage: other != null, child: browse),
                  if (other != null) Positioned.fill(child: other),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

/// The page card: the selected tab's web view (wide windows keep every
/// loaded tab mounted, narrow ones only the selected), with state views on top.
class _PageArea extends StatelessWidget {
  const _PageArea({required this.tabs, required this.wide, required this.mostVisited});

  final BrowserTabs tabs;
  final bool wide;
  final List<BrowserVisit> mostVisited;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final selected = tabs.selected;
    final view = selected.view;
    final covered = view != BrowserTabView.page;

    Widget host(BrowserTab t) => KeyedSubtree(
      key: ValueKey('page-${t.id}'),
      child: Offstage(
        offstage: t == selected && covered,
        child: AxWebViewHost(controller: t.controller),
      ),
    );

    final List<Widget> hosts;
    if (wide) {
      final list = tabs.tabs;
      hosts = [
        IndexedStack(
          index: tabs.selectedIndex,
          children: [for (final t in list) t.controller.currentUrl == null ? SizedBox.shrink(key: ValueKey('empty-${t.id}')) : host(t)],
        ),
      ];
    } else {
      hosts = [if (selected.controller.currentUrl != null) host(selected)];
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(ax.radii.md),
        border: Border.all(color: c.glassBorder),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(ax.radii.md - 1),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ...hosts,
            if (view == BrowserTabView.newTab)
              Positioned.fill(
                child: ColoredBox(
                  color: c.surface,
                  child: BrowserNewTabView(mostVisited: mostVisited, onOpen: (u) => selected.open(u)),
                ),
              )
            else if (covered)
              Positioned.fill(
                child: ColoredBox(
                  color: c.surface,
                  child: BrowserTabStateView(tab: selected),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
