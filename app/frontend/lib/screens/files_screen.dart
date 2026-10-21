import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/app_state.dart';
import '../services/archangeld_connection.dart';
import '../services/files_service.dart';
import '../services/local_kv_store.dart';
import '../ui/screens/files/file_helpers.dart';
import '../ui/screens/files/files_workspace.dart';
import '../ui/ui.dart';

/// Files: browse the server's folders.
class FilesScreen extends StatefulWidget {
  const FilesScreen({super.key, this.initialSort, this.restoreSortOnStart = true});

  final FilesSortChoice? initialSort;
  final bool restoreSortOnStart;

  @override
  State<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends State<FilesScreen> {
  String? _lastBackendHost;
  late FilesSortChoice _sort;

  @override
  void initState() {
    super.initState();
    _sort = widget.initialSort ?? FilesSortChoice.name;
    if (widget.restoreSortOnStart) {
      _loadSort();
    }
  }

  Future<void> _loadSort() async {
    try {
      final val = await LocalKvStore.instance.read(kFilesSortKey);
      if (val != null && mounted) {
        setState(() => _sort = FilesSortChoice.fromString(val));
      }
    } catch (_) {}
  }

  void _setSort(FilesSortChoice choice) {
    setState(() => _sort = choice);
    LocalKvStore.instance.write(kFilesSortKey, choice.toStorageString()).catchError((_) {});
  }

  void _syncBackend(ArchangeldConnection backend, FilesService files) {
    final host = backend.isPaired ? backend.host : null;
    if (host == _lastBackendHost) return;
    _lastBackendHost = host;
    if (backend.isPaired) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        files.init(backend);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final backend = context.watch<ArchangeldConnection>();
    final files = context.watch<FilesService>();
    final app = context.watch<AppState>();

    _syncBackend(backend, files);

    if (!backend.isPaired && files.listing == null && files.error == null) {
      return AxPage(
        title: 'Files',
        child: EmptyState(
          icon: Icons.cloud_off_rounded,
          title: 'Not connected to a server',
          message: 'Pair Archangel with a server to browse its files.',
          actionLabel: 'Connect a server',
          onAction: () => context.read<AppState>().go(AxSection.settings),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: FilesWorkspace(
          files: files,
          sort: _sort,
          onSortChanged: _setSort,
          onOpenTerminal: (dir) => app.openTerminalInDir(dir),
          onBackToRoot: () => files.loadDirectory(''),
        ),
      ),
    );
  }
}
