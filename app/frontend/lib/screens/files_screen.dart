import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/app_state.dart';
import '../models/file_entry.dart';
import '../services/archangeld_connection.dart';
import '../services/files_service.dart';
import '../ui/screens/files/file_helpers.dart';
import '../ui/screens/files/file_preview_sheet.dart';
import '../ui/ui.dart';

/// Files: browse the server's folders. Rows on a phone, a table on desktop.
class FilesScreen extends StatefulWidget {
  const FilesScreen({super.key});

  @override
  State<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends State<FilesScreen> {
  String _filter = '';
  final _crumbScroll = ScrollController();
  String? _lastCrumbPath;

  static const _jumps = <(String, String)>[('/etc', '/etc'), ('/var/log', '/var/log'), ('/srv', '/srv')];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<FilesService>().init(context.read<ArchangeldConnection>());
    });
  }

  @override
  void dispose() {
    _crumbScroll.dispose();
    super.dispose();
  }

  void _scrollCrumbsToEnd(String path) {
    if (_lastCrumbPath == path) return;
    _lastCrumbPath = path;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _crumbScroll.hasClients) _crumbScroll.jumpTo(_crumbScroll.position.maxScrollExtent);
    });
  }

  void _open(FilesService files, FileEntryModel e) {
    if (e.isDir) {
      setState(() => _filter = '');
      files.loadDirectory(e.path);
    } else {
      showFilePreviewSheet(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final files = context.watch<FilesService>();
    final ax = context.ax;
    final c = ax.colors;
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final listing = files.listing;
    final here = (listing != null && listing.path.isNotEmpty) ? listing.path : files.currentPath;
    final crumbs = buildCrumbs(here, rootPath: files.rootPath);
    _scrollCrumbsToEnd(here);

    final all = listing?.entries ?? const <FileEntryModel>[];
    final shown = sortEntries(all.where((e) => files.showHidden || !e.name.startsWith('.')));
    final entries = _filter.isEmpty ? shown : shown.where((e) => e.name.toLowerCase().contains(_filter.toLowerCase())).toList();

    // AxPage's header has no room for buttons next to the title on a phone,
    // so there they live in the toolbar instead.
    final actions = <Widget>[
      AxIconButton(
        icon: Icons.refresh_rounded,
        tooltip: 'Refresh this folder',
        onPressed: () => files.loadDirectory(files.currentPath, forceRefresh: true),
      ),
      AxButton.secondary(
        label: 'Open terminal here',
        icon: Icons.terminal_rounded,
        onPressed: () => context.read<AppState>().openTerminalInDir(here),
      ),
    ];
    final toolbar = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Breadcrumbs: scroll sideways instead of wrapping or clipping.
        SizedBox(
          height: axMinTarget(context),
          child: ListView(
            controller: _crumbScroll,
            scrollDirection: Axis.horizontal,
            children: [
              for (var i = 0; i < crumbs.length; i++) ...[
                if (i > 0) Icon(Icons.chevron_right_rounded, size: 18, color: c.textSubtle),
                _CrumbButton(crumb: crumbs[i], last: i == crumbs.length - 1, onTap: () => files.loadDirectory(crumbs[i].path)),
              ],
            ],
          ),
        ),
        SizedBox(height: ax.space.sm),
        SizedBox(
          height: axMinTarget(context),
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _JumpChip(label: 'Home', icon: Icons.home_outlined, onTap: () => files.loadDirectory('')),
              for (final (label, path) in _jumps) _JumpChip(label: label, onTap: () => files.loadDirectory(path)),
            ],
          ),
        ),
        SizedBox(height: ax.space.sm),
        if (!wide) ...[
          Wrap(spacing: ax.space.sm, runSpacing: ax.space.sm, crossAxisAlignment: WrapCrossAlignment.center, children: actions),
          SizedBox(height: ax.space.sm),
        ],
        Wrap(
          spacing: ax.space.lg,
          runSpacing: ax.space.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320, minWidth: 200),
              child: TextField(
                decoration: const InputDecoration(isDense: true, labelText: 'Filter this folder', prefixIcon: Icon(Icons.search_rounded)),
                onChanged: (v) => setState(() => _filter = v),
              ),
            ),
            Semantics(
              toggled: files.showHidden,
              label: 'Show hidden files',
              excludeSemantics: true,
              onTap: files.toggleShowHidden,
              child: InkWell(
                borderRadius: BorderRadius.circular(ax.radii.sm),
                onTap: files.toggleShowHidden,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: axMinTarget(context)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IgnorePointer(child: Switch(value: files.showHidden, onChanged: (_) {})),
                      SizedBox(width: ax.space.sm),
                      Text('Show hidden files', style: ax.typo.body.copyWith(color: c.text)),
                      SizedBox(width: ax.space.sm),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: ax.space.md),
        if (files.loading && listing != null) LinearProgressIndicator(minHeight: 2, color: c.accent, backgroundColor: c.border),
        if (wide && listing != null && files.error == null && entries.isNotEmpty) const _TableHeader(),
      ],
    );

    Widget? stateView;
    if (files.error != null) {
      final outside = isOutsideRootError(files.error);
      stateView = ErrorState(
        title: outside ? 'That folder is off limits' : 'Couldn’t open this folder',
        message: outside ? outsideRootHint(files.rootPath) : files.error!,
        onRetry: files.retry,
        helpTitle: 'Why can’t I see this?',
        helpText:
            'For safety, Archangel only shows files inside one folder on your server. '
            'Use Home or the folder path above to get back to files it can show. '
            'For anything else, open a terminal.',
      );
    } else if (listing == null) {
      stateView = LoadingState(message: 'Loading files...', onRetry: files.retry);
    } else if (entries.isEmpty) {
      final onlyHidden = !files.showHidden && all.isNotEmpty && _filter.isEmpty;
      stateView = EmptyState(
        icon: Icons.folder_open_rounded,
        title: _filter.isNotEmpty ? 'Nothing matches "$_filter"' : (onlyHidden ? 'Only hidden files here' : 'This folder is empty'),
        message: onlyHidden ? 'Turn on "Show hidden files" to see them.' : null,
      );
    }

    return AxPage(
      title: 'Files',
      subtitle:
          listing == null || files.error != null
              ? null
              : '${entries.length} ${entries.length == 1 ? 'item' : 'items'} in ${listing.path.isEmpty ? '/' : listing.path}',
      scrollable: false,
      actions: wide ? actions : const [],
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: toolbar),
          if (stateView != null)
            SliverToBoxAdapter(child: stateView)
          else
            SliverList.builder(
              itemCount: entries.length,
              itemBuilder:
                  (context, i) =>
                      wide
                          ? _TableRow(entry: entries[i], onOpen: () => _open(files, entries[i]))
                          : _PhoneRow(entry: entries[i], onOpen: () => _open(files, entries[i])),
            ),
        ],
      ),
    );
  }
}

class _CrumbButton extends StatelessWidget {
  const _CrumbButton({required this.crumb, required this.last, required this.onTap});
  final Crumb crumb;
  final bool last;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    return Semantics(
      button: true,
      label: 'Go to ${crumb.label}',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(ax.radii.sm),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: axMinTarget(context), minWidth: axMinTarget(context)),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: ax.space.sm),
            child: Center(child: Text(crumb.label, style: ax.typo.label.copyWith(color: last ? c.text : c.accent))),
          ),
        ),
      ),
    );
  }
}

class _JumpChip extends StatelessWidget {
  const _JumpChip({required this.label, required this.onTap, this.icon});
  final String label;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    return Padding(
      padding: EdgeInsets.only(right: ax.space.sm),
      child: ActionChip(
        avatar: icon == null ? null : Icon(icon, size: 18, color: c.textMuted),
        label: Text(label, style: ax.typo.label.copyWith(color: c.text)),
        backgroundColor: c.surfaceAlt,
        side: BorderSide(color: c.outline),
        onPressed: onTap,
      ),
    );
  }
}

class _PhoneRow extends StatelessWidget {
  const _PhoneRow({required this.entry, required this.onOpen});
  final FileEntryModel entry;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.ax.colors;
    return AxListTile(
      leading: Icon(fileIconFor(entry), color: entry.isDir ? c.accent : c.textMuted),
      title: entry.name,
      subtitle: entrySubtitle(entry),
      trailing:
          entry.isDir
              ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AxIconButton(
                    icon: Icons.terminal_rounded,
                    tooltip: 'Open terminal in ${entry.name}',
                    onPressed: () => context.read<AppState>().openTerminalInDir(entry.path),
                  ),
                  Icon(Icons.chevron_right_rounded, color: c.textSubtle),
                ],
              )
              : null,
      onTap: onOpen,
    );
  }
}

const _sizeW = 100.0;
const _modW = 150.0;
const _actW = 56.0;

class _TableHeader extends StatelessWidget {
  const _TableHeader();

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    Widget h(String t) => Text(t, style: ax.typo.caption.copyWith(color: c.textMuted, fontWeight: FontWeight.w700));
    return Container(
      key: const ValueKey('files-table'),
      padding: EdgeInsets.symmetric(horizontal: ax.space.lg, vertical: ax.space.sm),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border))),
      child: Row(
        children: [
          Expanded(child: h('Name')),
          SizedBox(width: _sizeW, child: h('Size')),
          SizedBox(width: _modW, child: h('Changed')),
          const SizedBox(width: _actW),
        ],
      ),
    );
  }
}

class _TableRow extends StatelessWidget {
  const _TableRow({required this.entry, required this.onOpen});
  final FileEntryModel entry;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    return InkWell(
      onTap: onOpen,
      child: Container(
        constraints: BoxConstraints(minHeight: axMinTarget(context)),
        padding: EdgeInsets.symmetric(horizontal: ax.space.lg),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border))),
        child: Row(
          children: [
            Icon(fileIconFor(entry), size: 20, color: entry.isDir ? c.accent : c.textMuted),
            SizedBox(width: ax.space.md),
            Expanded(child: Text(entry.name, style: ax.typo.label.copyWith(color: c.text), overflow: TextOverflow.ellipsis)),
            SizedBox(width: _sizeW, child: Text(entry.isDir ? '—' : entry.size, style: ax.typo.body.copyWith(color: c.textMuted))),
            SizedBox(
              width: _modW,
              child: Text(entry.mtime, style: ax.typo.body.copyWith(color: c.textMuted), overflow: TextOverflow.ellipsis),
            ),
            SizedBox(
              width: _actW,
              child:
                  entry.isDir
                      ? AxIconButton(
                        icon: Icons.terminal_rounded,
                        tooltip: 'Open terminal in ${entry.name}',
                        onPressed: () => context.read<AppState>().openTerminalInDir(entry.path),
                      )
                      : AxIconButton(
                        icon: Icons.download_rounded,
                        tooltip: 'Download ${entry.name}',
                        onPressed: () => _download(context, entry),
                      ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _download(BuildContext context, FileEntryModel e) async {
    final messenger = ScaffoldMessenger.of(context);
    final res = await context.read<FilesService>().downloadToDisk(e.path);
    messenger.showSnackBar(SnackBar(content: Text(res.ok ? 'Saved to ${res.savedPath}' : (res.error ?? 'Download failed'))));
  }
}
