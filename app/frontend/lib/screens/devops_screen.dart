import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/app_state.dart';
import '../models/devops_model.dart';
import '../services/archangeld_connection.dart';
import '../services/devops_service.dart';
import '../theme/tokens.dart';
import '../widgets/ax_widgets.dart';

enum _DevTab { services, scheduled, proxy, deployments }

class DevopsScreen extends StatefulWidget {
  const DevopsScreen({super.key});

  @override
  State<DevopsScreen> createState() => _DevopsScreenState();
}

class _DevopsScreenState extends State<DevopsScreen> {
  _DevTab _tab = _DevTab.services;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final backend = context.read<ArchangeldConnection>();
      context.read<DevopsService>().init(backend);
    });
  }

  void _handleAction(BuildContext context, DevRowModel row, String action) async {
    final svc = context.read<DevopsService>();
    final app = context.read<AppState>();

    if (action == 'Logs') {
      // Deep-link to Terminal with journalctl command
      app.openTerminalWithCommand('journalctl -u ${row.name} -n 50 --no-pager');
      return;
    }

    if (action == 'Test') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Testing reachability for ${row.name}...')),
      );
      final res = await svc.testProxy(row.name);
      if (context.mounted && res != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${row.name}: $res')),
        );
      }
      return;
    }

    if (_tab == _DevTab.services) {
      final ok = await svc.triggerServiceAction(row.name, action);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ok ? 'Service ${row.name} $action triggered.' : (svc.lastActionMessage ?? 'Failed to $action ${row.name}.'))),
        );
      }
    } else if (_tab == _DevTab.scheduled) {
      final ok = await svc.triggerScheduled(row.name);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ok ? 'Timer ${row.name} triggered.' : (svc.lastActionMessage ?? 'Failed to trigger ${row.name}.'))),
        );
      }
    } else if (_tab == _DevTab.deployments) {
      if (action == 'Edit') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Loading ${row.name}...')),
        );
        final content = await svc.getDeploymentContent(row.name);
        if (context.mounted) {
          _openScriptEditor(context, row.name, initialContent: content ?? '');
        }
        return;
      }

      if (action == 'Delete') {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AxColors.s1,
            title: Text('Delete Script?', style: AxTextStyles.h2),
            content: Text('Are you sure you want to delete ${row.name}?', style: AxTextStyles.sans),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text('Cancel', style: AxTextStyles.sans.copyWith(color: AxColors.fg3)),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text('Delete', style: AxTextStyles.sans.copyWith(color: AxColors.danger, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
        if (confirm == true) {
          final ok = await svc.deleteDeployment(row.name);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(ok ? 'Script ${row.name} deleted.' : 'Failed to delete ${row.name}.')),
            );
          }
        }
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Executing ${row.name}...')),
      );
      final res = await svc.runDeployment(row.name);
      if (context.mounted && res != null) {
        final msg = res['message'] ?? '';
        final out = res['output'] ?? '';
        if (out.isNotEmpty) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: AxColors.s1,
              title: Text('Deployment: ${row.name}', style: AxTextStyles.h2),
              content: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(msg, style: AxTextStyles.sans.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF070807),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AxColors.line),
                      ),
                      child: SelectableText(out, style: AxTextStyles.mono.copyWith(fontSize: 11)),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Close'),
                ),
              ],
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${row.name}: $msg')),
          );
        }
      }
    }
  }

  void _openScriptEditor(BuildContext context, String? scriptName, {String? initialContent}) {
    showDialog(
      context: context,
      builder: (ctx) => _ScriptEditorDialog(
        service: context.read<DevopsService>(),
        scriptName: scriptName,
        initialContent: initialContent,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 620;
    final backend = context.watch<ArchangeldConnection>();
    final svc = context.watch<DevopsService>();

    final rows = switch (_tab) {
      _DevTab.services => svc.services,
      _DevTab.scheduled => svc.scheduled,
      _DevTab.proxy => svc.proxy,
      _DevTab.deployments => svc.deployments,
    };

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
               child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('DevOps', style: AxTextStyles.h1),
                      if (svc.loading) ...[
                        const SizedBox(width: 8),
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AxColors.accent),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text('systemd · cron · caddy · deploy hooks', style: AxTextStyles.mutedMono),
                ],
               ),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(AxRadius.pill),
                onTap: () => svc.fetchAll(),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
                  decoration: BoxDecoration(
                    color: AxColors.wash,
                    borderRadius: BorderRadius.circular(AxRadius.pill),
                    border: Border.all(color: AxColors.accent.withValues(alpha: 0.22)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.refresh_rounded, size: 12, color: AxColors.accent),
                      const SizedBox(width: 6),
                      Text('Refresh', style: AxTextStyles.sans.copyWith(fontSize: 11.5, fontWeight: FontWeight.w700, color: AxColors.accent)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              AxSegmented<_DevTab>(
                values: _DevTab.values,
                selected: _tab,
                label: (t) => switch (t) {
                  _DevTab.services => 'Services',
                  _DevTab.scheduled => 'Scheduled',
                  _DevTab.proxy => 'Reverse proxy',
                  _DevTab.deployments => 'Deployments',
                },
                onSelect: (t) => setState(() => _tab = t),
              ),
              if (_tab == _DevTab.deployments)
                InkWell(
                  borderRadius: BorderRadius.circular(AxRadius.pill),
                  onTap: () => _openScriptEditor(context, null),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
                    decoration: BoxDecoration(
                      color: AxColors.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AxRadius.pill),
                      border: Border.all(color: AxColors.accent.withValues(alpha: 0.35)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.add_rounded, size: 14, color: AxColors.accent),
                        const SizedBox(width: 5),
                        Text('New Script', style: AxTextStyles.sans.copyWith(fontSize: 11.5, fontWeight: FontWeight.w700, color: AxColors.accent)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (backend.isPaired && svc.error != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: AxColors.bad.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AxRadius.md),
                border: Border.all(color: AxColors.bad.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded, size: 14, color: AxColors.bad),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(svc.error!, style: AxTextStyles.mono.copyWith(fontSize: 11.5, color: AxColors.bad)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (!backend.isPaired)
            Container(
              padding: const EdgeInsets.all(32),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AxColors.s1,
                borderRadius: BorderRadius.circular(AxRadius.xl),
                border: Border.all(color: AxColors.line),
              ),
              child: Column(
                children: [
                  const Icon(Icons.link_off_rounded, size: 32, color: AxColors.fg3),
                  const SizedBox(height: 12),
                  Text('Host Not Paired', style: AxTextStyles.mono.copyWith(fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text('Pair with archangeld to inspect systemd services, cron, and Caddy.', style: AxTextStyles.mutedMono, textAlign: TextAlign.center),
                ],
              ),
            )
          else if (rows.isEmpty && !svc.loading)
            Container(
              padding: const EdgeInsets.all(32),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AxColors.s1,
                borderRadius: BorderRadius.circular(AxRadius.xl),
                border: Border.all(color: AxColors.line),
              ),
              child: Column(
                children: [
                  const Icon(Icons.inbox_rounded, size: 28, color: AxColors.fg3),
                  const SizedBox(height: 10),
                  Text('No items found in ${_tab.name}', style: AxTextStyles.mono.copyWith(fontSize: 13, color: AxColors.fg2)),
                  const SizedBox(height: 4),
                  Text('Host does not have configured entries for this section.', style: AxTextStyles.mutedMono),
                ],
              ),
            )
          else
            Container(
              decoration: BoxDecoration(
                color: AxColors.s1,
                borderRadius: BorderRadius.circular(AxRadius.xl),
                border: Border.all(color: AxColors.line),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final r in rows)
                    _DevRowTile(
                      row: r,
                      wide: wide,
                      onAction: (act) => _handleAction(context, r, act),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _DevRowTile extends StatelessWidget {
  final DevRowModel row;
  final bool wide;
  final ValueChanged<String> onAction;

  const _DevRowTile({
    required this.row,
    required this.wide,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final dot = row.ok ? AxColors.accent : AxColors.fg3;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0x0BE8F0E6)))),
      child: Row(
        children: [
          Container(width: 7, height: 7, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(row.name, style: AxTextStyles.mono.copyWith(fontSize: 12, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(row.meta, style: AxTextStyles.mono.copyWith(fontSize: 10.5, color: AxColors.fg3), overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const SizedBox(width: 8),
          AxPill(text: row.status, color: dot),
          if (wide) ...[
            const SizedBox(width: 8),
            Row(
              children: [
                for (final a in row.actions)
                  Padding(
                    padding: const EdgeInsets.only(left: 5),
                    child: AxGhostButton(
                      label: a,
                      onTap: () => onAction(a),
                    ),
                  ),
              ],
            ),
          ] else ...[
            const SizedBox(width: 4),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded, size: 16, color: AxColors.fg3),
              color: AxColors.s2,
              onSelected: onAction,
              itemBuilder: (ctx) => [
                for (final a in row.actions)
                  PopupMenuItem(
                    value: a,
                    child: Text(a, style: AxTextStyles.sans.copyWith(fontSize: 12, color: a == 'Delete' ? AxColors.danger : AxColors.fg)),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ScriptEditorDialog extends StatefulWidget {
  final DevopsService service;
  final String? scriptName;
  final String? initialContent;

  const _ScriptEditorDialog({
    required this.service,
    this.scriptName,
    this.initialContent,
  });

  @override
  State<_ScriptEditorDialog> createState() => _ScriptEditorDialogState();
}

class _ScriptEditorDialogState extends State<_ScriptEditorDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _contentCtrl;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.scriptName ?? 'deploy-app.sh');
    _contentCtrl = TextEditingController(
      text: widget.initialContent ??
          '#!/bin/sh\nset -e\n\necho "Starting deployment..."\n# docker compose pull && docker compose up -d\n',
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  Future<void> _save({bool runAfter = false}) async {
    var name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Script name is required');
      return;
    }
    if (!name.endsWith('.sh')) {
      name += '.sh';
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final res = await widget.service.saveDeployment(name, _contentCtrl.text);
    if (!mounted) return;
    setState(() => _saving = false);

    final ok = res['success'] == true;
    if (ok) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Deployment script $name saved.')),
      );
      if (runAfter) {
        final runRes = await widget.service.runDeployment(name);
        if (mounted && runRes != null) {
          final msg = runRes['message'] ?? '';
          final out = runRes['output'] ?? '';
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: AxColors.s1,
              title: Text('Deployment: $name', style: AxTextStyles.h2),
              content: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(msg, style: AxTextStyles.sans.copyWith(fontWeight: FontWeight.w600)),
                    if (out.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF070807),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AxColors.line),
                        ),
                        child: SelectableText(out, style: AxTextStyles.mono.copyWith(fontSize: 11)),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close')),
              ],
            ),
          );
        }
      }
    } else {
      final errorMsg = res['message'] as String? ?? 'Failed to save deployment script. Check permissions on host.';
      setState(() => _error = errorMsg);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.scriptName != null;
    return Dialog(
      backgroundColor: AxColors.s1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AxRadius.xl), side: const BorderSide(color: AxColors.line)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(isEditing ? 'Edit Deployment Script' : 'New Deployment Script', style: AxTextStyles.h2),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18, color: AxColors.fg3),
                    onPressed: _saving ? null : () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text('Script Filename', style: AxTextStyles.label),
              const SizedBox(height: 5),
              TextField(
                controller: _nameCtrl,
                enabled: !isEditing,
                style: AxTextStyles.mono.copyWith(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'deploy-prod.sh',
                  hintStyle: AxTextStyles.mono.copyWith(fontSize: 13, color: AxColors.fg3),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  filled: true,
                  fillColor: AxColors.s2,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AxColors.line)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AxColors.line)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AxColors.accent)),
                ),
              ),
              const SizedBox(height: 12),
              Text('Shell Script Content', style: AxTextStyles.label),
              const SizedBox(height: 5),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF0A0C0A),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AxColors.line),
                ),
                child: TextField(
                  controller: _contentCtrl,
                  maxLines: 12,
                  minLines: 8,
                  style: AxTextStyles.mono.copyWith(fontSize: 12, height: 1.4),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.all(12),
                    hintText: '#!/bin/sh\n\n# Your deployment commands here...',
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: AxTextStyles.sans.copyWith(fontSize: 12, color: AxColors.danger)),
              ],
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _saving ? null : () => Navigator.of(context).pop(),
                    child: Text('Cancel', style: AxTextStyles.sans.copyWith(color: AxColors.fg3)),
                  ),
                  const SizedBox(width: 10),
                  AxGhostButton(
                    label: 'Save & Run',
                    onTap: _saving ? null : () => _save(runAfter: true),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: _saving ? null : () => _save(runAfter: false),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AxColors.accent,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AxRadius.pill)),
                    ),
                    child: _saving
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                        : Text('Save Script', style: AxTextStyles.sans.copyWith(fontWeight: FontWeight.w700, color: Colors.black)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
