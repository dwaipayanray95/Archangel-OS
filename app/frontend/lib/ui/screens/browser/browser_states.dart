import 'package:flutter/material.dart';

import '../../../services/browser_service.dart';
import '../../ui.dart';
import 'browser_tabs.dart';
import 'web_view_host.dart';

/// A calm, centred message with actions, scrolling if the window is tiny.
class BrowserStateFrame extends StatelessWidget {
  const BrowserStateFrame({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    this.message,
    this.children = const [],
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String? message;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: EdgeInsets.all(ax.space.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 40, color: iconColor),
                    SizedBox(height: ax.space.md),
                    Semantics(
                      header: true,
                      child: Text(
                        title,
                        textAlign: TextAlign.center,
                        style: ax.typo.title.copyWith(color: c.text),
                      ),
                    ),
                    if (message != null) ...[
                      SizedBox(height: ax.space.sm),
                      Text(
                        message!,
                        textAlign: TextAlign.center,
                        style: ax.typo.body.copyWith(color: c.textMuted),
                      ),
                    ],
                    for (final w in children) ...[SizedBox(height: ax.space.lg), w],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A new tab with nothing loaded.
class BrowserNewTabView extends StatelessWidget {
  const BrowserNewTabView({super.key, required this.mostVisited, required this.onOpen});

  final List<BrowserVisit> mostVisited;
  final ValueChanged<Uri> onOpen;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    return BrowserStateFrame(
      icon: Icons.public,
      iconColor: c.textMuted,
      title: 'Where to?',
      message: 'Type an address, or search. Pages open on this device.',
      children: [
        if (mostVisited.isNotEmpty)
          Wrap(
            alignment: WrapAlignment.center,
            spacing: ax.space.sm,
            runSpacing: ax.space.sm,
            children: [
              for (final v in mostVisited) _SiteChip(key: ValueKey('site-${v.host}'), host: v.host, onTap: () => onOpen(_siteRoot(v.url))),
            ],
          ),
      ],
    );
  }
}

Uri _siteRoot(String url) {
  final u = Uri.parse(url);
  return Uri(scheme: u.scheme, host: u.host, port: u.hasPort ? u.port : null, path: '/');
}

class _SiteChip extends StatelessWidget {
  const _SiteChip({super.key, required this.host, required this.onTap});

  final String host;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final shape = BorderRadius.circular(ax.radii.pill);
    return Semantics(
      button: true,
      label: 'Open $host',
      excludeSemantics: true,
      child: Material(
        color: c.glass,
        shape: RoundedRectangleBorder(
          borderRadius: shape,
          side: BorderSide(color: c.glassBorder),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: shape,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: axMinTarget(context), maxWidth: 220),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: ax.space.lg),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.public, size: 16, color: c.textMuted),
                  SizedBox(width: ax.space.sm),
                  Flexible(
                    child: Text(
                      host,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ax.typo.mono.copyWith(color: c.text),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String browserErrorMessage(AxWebError? error) => switch (error?.kind) {
  AxWebErrorKind.notFound => "That address doesn't exist.",
  AxWebErrorKind.timeout => 'The connection timed out.',
  AxWebErrorKind.certificate => "That site's security certificate isn't valid.",
  _ => 'Something went wrong loading that page.',
};

/// The page tab's overlay for blocked, error and offline states.
class BrowserTabStateView extends StatelessWidget {
  const BrowserTabStateView({super.key, required this.tab});

  final BrowserTab tab;

  @override
  Widget build(BuildContext context) {
    final c = context.ax.colors;
    switch (tab.view) {
      case BrowserTabView.blocked:
        return BrowserStateFrame(
          icon: Icons.lock_outline,
          iconColor: c.warning,
          title: "Archangel OS won't open that kind of link",
          message: 'It only opens web pages — addresses starting with http or https.',
          children: [AxButton(label: 'Back', icon: Icons.arrow_back, onPressed: tab.dismissBlocked)],
        );
      case BrowserTabView.offline:
        return BrowserStateFrame(
          icon: Icons.wifi_off_rounded,
          iconColor: c.danger,
          title: "You're not connected to the internet",
          message: 'Check your connection, then try again.',
          children: [AxButton(label: 'Try again', icon: Icons.refresh, onPressed: tab.retry)],
        );
      case BrowserTabView.error:
        return BrowserStateFrame(
          icon: Icons.cloud_off_rounded,
          iconColor: c.danger,
          title: "Couldn't open this page",
          message: browserErrorMessage(tab.error),
          children: [
            AxButton(label: 'Try again', icon: Icons.refresh, onPressed: tab.retry),
            if (tab.controller.canGoBack) AxButton.secondary(label: 'Go back', icon: Icons.arrow_back, onPressed: tab.goBack),
          ],
        );
      case BrowserTabView.newTab:
      case BrowserTabView.page:
        return const SizedBox.shrink();
    }
  }
}
