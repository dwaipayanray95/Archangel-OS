import 'package:flutter/material.dart';

import '../../ui.dart';
import 'browser_tabs.dart';
import 'browser_url.dart';

const String kBrowserCapTooltip = "That's as many tabs as Archangel OS keeps open.";

/// Row height for the chrome: 44, or the platform's touch target if larger.
double browserRowHeight(BuildContext context) => axMinTarget(context) < 44 ? 44 : axMinTarget(context);

/// A site's icon, or a globe when there is none.
class BrowserFavicon extends StatelessWidget {
  const BrowserFavicon({super.key, this.url, this.size = 16});

  final Uri? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.ax.colors;
    final globe = Icon(Icons.public, size: size, color: c.textMuted);
    final u = url;
    if (u == null || (u.scheme != 'https' && u.scheme != 'http')) return globe;
    return SizedBox(
      width: size,
      height: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: Image.network(u.toString(), width: size, height: size, fit: BoxFit.cover, errorBuilder: (_, _, _) => globe),
      ),
    );
  }
}

/// Shows the address with the host emphasised and the rest muted, until it
/// is edited.
class _OmniboxController extends TextEditingController {
  bool emphasise = true;

  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    if (!emphasise || text.isEmpty || value.composing.isValid) {
      return super.buildTextSpan(context: context, style: style, withComposing: withComposing);
    }
    final c = context.ax.colors;
    final parts = splitUrlForDisplay(text);
    return TextSpan(
      style: style,
      children: [
        TextSpan(
          text: parts.prefix,
          style: TextStyle(color: c.textMuted),
        ),
        TextSpan(
          text: parts.host,
          style: TextStyle(color: c.text),
        ),
        TextSpan(
          text: parts.rest,
          style: TextStyle(color: c.textMuted),
        ),
      ],
    );
  }
}

/// The address field: a mono pill holding the page's address.
class BrowserOmnibox extends StatefulWidget {
  const BrowserOmnibox({super.key, required this.tab, this.trailing});

  final BrowserTab tab;

  /// Inside the pill, on its right (the bookmark star on wide).
  final Widget? trailing;

  @override
  State<BrowserOmnibox> createState() => _BrowserOmniboxState();
}

class _BrowserOmniboxState extends State<BrowserOmnibox> {
  final _controller = _OmniboxController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.tab.addListener(_sync);
    _focus.addListener(_onFocus);
    _controller.text = widget.tab.address;
  }

  @override
  void didUpdateWidget(covariant BrowserOmnibox old) {
    super.didUpdateWidget(old);
    if (old.tab != widget.tab) {
      old.tab.removeListener(_sync);
      widget.tab.addListener(_sync);
      _sync();
    }
  }

  @override
  void dispose() {
    widget.tab.removeListener(_sync);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _sync() {
    if (_focus.hasFocus) return;
    final address = widget.tab.address;
    if (_controller.text != address) _controller.text = address;
  }

  void _onFocus() {
    if (_focus.hasFocus) {
      _controller.emphasise = false;
      _controller.selection = TextSelection(baseOffset: 0, extentOffset: _controller.text.length);
      // The tap that focused the field also places the caret; select again after it.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _focus.hasFocus) _controller.selection = TextSelection(baseOffset: 0, extentOffset: _controller.text.length);
      });
    } else {
      _controller.emphasise = true;
      _controller.text = widget.tab.address;
    }
    setState(() {});
  }

  void _submit(String value) {
    _focus.unfocus();
    widget.tab.submit(value);
  }

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final insecure = isInsecureUri(widget.tab.controller.currentUrl) && widget.tab.view == BrowserTabView.page;
    return Container(
      constraints: BoxConstraints(minHeight: browserRowHeight(context)),
      decoration: BoxDecoration(
        color: c.glassStrong,
        borderRadius: BorderRadius.circular(ax.radii.pill),
        border: Border.all(color: _focus.hasFocus ? c.accent : c.outline, width: _focus.hasFocus ? 2 : 1),
      ),
      padding: EdgeInsets.only(left: ax.space.md, right: widget.trailing == null ? ax.space.md : 0),
      child: Row(
        children: [
          if (insecure) ...[
            Flexible(
              flex: 0,
              child: AxPill(label: 'Not secure', icon: Icons.warning_amber_rounded, fg: c.warning, bg: c.warningWash, dense: true),
            ),
            SizedBox(width: ax.space.sm),
          ],
          Expanded(
            child: TextField(
              key: const ValueKey('browser-omnibox'),
              controller: _controller,
              focusNode: _focus,
              style: ax.typo.mono.copyWith(color: c.text),
              textInputAction: TextInputAction.go,
              keyboardType: TextInputType.url,
              autocorrect: false,
              enableSuggestions: false,
              maxLines: 1,
              onSubmitted: _submit,
              cursorColor: c.accent,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                contentPadding: EdgeInsets.symmetric(vertical: ax.space.sm),
                hintText: 'Search, or type an address',
                hintStyle: ax.typo.mono.copyWith(color: c.textSubtle),
              ),
            ),
          ),
          if (widget.trailing != null) widget.trailing!,
        ],
      ),
    );
  }
}

/// Back and forward.
List<Widget> browserNavButtons(BrowserTab tab) => [
  AxIconButton(icon: Icons.arrow_back, tooltip: 'Back', onPressed: tab.controller.canGoBack ? tab.goBack : null),
  AxIconButton(icon: Icons.arrow_forward, tooltip: 'Forward', onPressed: tab.controller.canGoForward ? tab.controller.goForward : null),
];

/// Reload, or Stop while the page is loading.
Widget browserReloadButton(BrowserTab tab) {
  final loading = tab.controller.isLoading;
  return AxIconButton(
    icon: loading ? Icons.close : Icons.refresh,
    tooltip: loading ? 'Stop' : 'Reload',
    onPressed: loading ? tab.controller.stop : (tab.controller.currentUrl == null ? null : tab.reload),
  );
}

/// The bookmark star.
Widget browserBookmarkButton({required bool bookmarked, required VoidCallback? onPressed}) => AxIconButton(
  icon: bookmarked ? Icons.star_rounded : Icons.star_border_rounded,
  tooltip: bookmarked ? 'Remove bookmark' : 'Add bookmark',
  onPressed: onPressed,
  selected: bookmarked,
);

enum BrowserMenuChoice { history, bookmarks }

/// The overflow menu: History, Bookmarks.
class BrowserOverflowMenu extends StatelessWidget {
  const BrowserOverflowMenu({super.key, required this.onChoose});

  final ValueChanged<BrowserMenuChoice> onChoose;

  @override
  Widget build(BuildContext context) {
    final c = context.ax.colors;
    final target = axMinTarget(context);
    return PopupMenuButton<BrowserMenuChoice>(
      tooltip: 'More options',
      icon: const Icon(Icons.more_horiz),
      iconColor: c.textMuted,
      constraints: const BoxConstraints(minWidth: 180),
      style: IconButton.styleFrom(minimumSize: Size(target, target), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
      color: c.surface,
      onSelected: onChoose,
      itemBuilder: (_) => const [
        PopupMenuItem(value: BrowserMenuChoice.history, child: Text('History')),
        PopupMenuItem(value: BrowserMenuChoice.bookmarks, child: Text('Bookmarks')),
      ],
    );
  }
}

/// The 2px accent line under the chrome while a page loads. It is simply
/// absent when nothing is loading.
class BrowserProgressLine extends StatelessWidget {
  const BrowserProgressLine({super.key, required this.tab});

  final BrowserTab tab;

  @override
  Widget build(BuildContext context) {
    final c = context.ax.colors;
    final controller = tab.controller;
    return SizedBox(
      height: 2,
      child: controller.isLoading
          ? Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                key: const ValueKey('browser-progress'),
                widthFactor: controller.progress.clamp(0.03, 1.0),
                child: ColoredBox(color: c.accent, child: const SizedBox(height: 2)),
              ),
            )
          : null,
    );
  }
}

/// Wide chrome: back, forward, reload, the address, and the menu.
class BrowserChromeWide extends StatelessWidget {
  const BrowserChromeWide({super.key, required this.tab, required this.bookmarked, required this.onBookmark, required this.onMenu});

  final BrowserTab tab;
  final bool bookmarked;
  final VoidCallback? onBookmark;
  final ValueChanged<BrowserMenuChoice> onMenu;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    return Row(
      children: [
        ...browserNavButtons(tab),
        browserReloadButton(tab),
        SizedBox(width: ax.space.sm),
        Expanded(
          child: BrowserOmnibox(
            key: ValueKey('omnibox-${tab.id}'),
            tab: tab,
            trailing: browserBookmarkButton(bookmarked: bookmarked, onPressed: onBookmark),
          ),
        ),
        BrowserOverflowMenu(onChoose: onMenu),
      ],
    );
  }
}

/// Narrow chrome: the address and reload on one row; back, forward, the
/// star, the tab count and the menu on the next.
class BrowserChromeNarrow extends StatelessWidget {
  const BrowserChromeNarrow({
    super.key,
    required this.tab,
    required this.tabCount,
    required this.bookmarked,
    required this.onBookmark,
    required this.onMenu,
    required this.onShowTabs,
  });

  final BrowserTab tab;
  final int tabCount;
  final bool bookmarked;
  final VoidCallback? onBookmark;
  final ValueChanged<BrowserMenuChoice> onMenu;
  final VoidCallback onShowTabs;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: BrowserOmnibox(key: ValueKey('omnibox-${tab.id}'), tab: tab),
            ),
            browserReloadButton(tab),
          ],
        ),
        SizedBox(height: ax.space.xs),
        Row(
          children: [
            ...browserNavButtons(tab),
            browserBookmarkButton(bookmarked: bookmarked, onPressed: onBookmark),
            const Spacer(),
            BrowserTabCount(count: tabCount, onTap: onShowTabs),
            BrowserOverflowMenu(onChoose: onMenu),
          ],
        ),
      ],
    );
  }
}

/// The tab-count pill ("3") that opens the tab list on narrow screens.
class BrowserTabCount extends StatelessWidget {
  const BrowserTabCount({super.key, required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    return Tooltip(
      message: 'Show tabs',
      child: Semantics(
        button: true,
        label: 'Show tabs, $count open',
        excludeSemantics: true,
        child: InkWell(
          key: const ValueKey('browser-tab-count'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(ax.radii.pill),
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: axMinTarget(context), minHeight: axMinTarget(context)),
            child: Center(
              child: Container(
                constraints: const BoxConstraints(minWidth: 32),
                height: 28,
                alignment: Alignment.center,
                padding: EdgeInsets.symmetric(horizontal: ax.space.sm),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(ax.radii.pill),
                  border: Border.all(color: c.textMuted, width: 1.5),
                ),
                child: Text('$count', style: ax.typo.label.copyWith(color: c.text)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
