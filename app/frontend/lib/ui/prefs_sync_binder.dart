import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../services/archangeld_connection.dart';
import '../services/prefs_sync_service.dart';
import '../services/server_registry.dart';

/// The key the active server's prefs are stored under, or null while there
/// is no server (or the app is still being re-pointed at another one).
String? prefsServerKeyFor(ServerRegistry registry, ArchangeldConnection backend) {
  final p = registry.active;
  if (!registry.isLoaded || !backend.isLoaded || p == null || !backend.isPaired || p.host != backend.host) return null;
  return p.serverKey ?? 'id-${p.id}';
}

/// Keeps [PrefsSyncService] pointed at the active server and tells it when
/// the server comes back. Renders [child] untouched; nothing waits on it.
class PrefsSyncBinder extends StatefulWidget {
  const PrefsSyncBinder({super.key, required this.child});

  final Widget child;

  @override
  State<PrefsSyncBinder> createState() => _PrefsSyncBinderState();
}

class _PrefsSyncBinderState extends State<PrefsSyncBinder> {
  late final ServerRegistry _registry;
  late final ArchangeldConnection _backend;
  late final PrefsSyncService _sync;
  String? _boundKey;
  bool _bound = false;
  int _generation = -1;

  @override
  void initState() {
    super.initState();
    _registry = context.read<ServerRegistry>();
    _backend = context.read<ArchangeldConnection>();
    _sync = context.read<PrefsSyncService>();
    _registry.addListener(_reconcile);
    _backend.addListener(_reconcile);
    WidgetsBinding.instance.addPostFrameCallback((_) => _reconcile());
  }

  void _reconcile() {
    if (!mounted) return;
    _sync.setReachable(_backend.reachable != false);
    final key = prefsServerKeyFor(_registry, _backend);
    final repaired = _backend.pairingGeneration != _generation;
    if (_bound && key == _boundKey && !repaired) return;
    _bound = true;
    _boundKey = key;
    _generation = _backend.pairingGeneration;
    unawaited(_sync.bind(key).then((_) => _sync.syncNow()));
  }

  @override
  void dispose() {
    _registry.removeListener(_reconcile);
    _backend.removeListener(_reconcile);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
