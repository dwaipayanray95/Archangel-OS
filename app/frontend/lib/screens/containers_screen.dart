import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/container_model.dart';
import '../services/archangeld_connection.dart';
import '../services/containers_service.dart';
import '../theme/tokens.dart';
import '../widgets/ax_widgets.dart';
import 'container_detail_screen.dart';

enum _View { cards, table }

class ContainersScreen extends StatefulWidget {
  const ContainersScreen({super.key});

  @override
  State<ContainersScreen> createState() => _ContainersScreenState();
}

class _ContainersScreenState extends State<ContainersScreen> {
  _View _view = _View.cards;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final backend = context.read<ArchangeldConnection>();
      context.read<ContainersService>().init(backend);
    });
  }

  void _openDetail(DockerContainerItem c) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ContainerDetailScreen(container: c)));
  }

  void _showCreateContainerDialog(BuildContext context, ContainersService svc) {
    showDialog(
      context: context,
      builder: (ctx) => _CreateContainerDialog(service: svc),
    );
  }

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<ContainersService>();
    final overview = svc.overview;

    final containers = overview?.containers ?? [];
    final running = overview?.runningCount ?? containers.where((c) => c.running).length;
    final stopped = overview?.stoppedCount ?? (containers.length - running);
    final version = overview?.engineVersion ?? 'docker';
    final imagesSize = overview?.totalImagesSize ?? '—';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.end,
            runSpacing: 10,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Containers', style: AxTextStyles.h1),
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
                  Text(
                    'docker $version · $running running · $stopped stopped · $imagesSize images',
                    style: AxTextStyles.mutedMono,
                  ),
                ],
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  AxSegmented<_View>(
                    values: _View.values,
                    selected: _view,
                    label: (v) => v == _View.cards ? 'Cards' : 'Table',
                    onSelect: (v) => setState(() => _view = v),
                  ),
                  InkWell(
                    borderRadius: BorderRadius.circular(AxRadius.pill),
                    onTap: () => _showCreateContainerDialog(context, svc),
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
                          Text('Run Container', style: AxTextStyles.sans.copyWith(fontSize: 11.5, fontWeight: FontWeight.w700, color: AxColors.accent)),
                        ],
                      ),
                    ),
                  ),
                  InkWell(
                    borderRadius: BorderRadius.circular(AxRadius.pill),
                    onTap: () => svc.fetchContainers(),
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
            ],
          ),
          const SizedBox(height: 15),
          if (containers.isEmpty)
            AxCard(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.view_in_ar_outlined, size: 36, color: AxColors.fg3.withValues(alpha: 0.7)),
                    const SizedBox(height: 12),
                    Text(
                      overview?.dockerAvailable == false
                          ? 'Docker daemon is offline or unreachable on host'
                          : 'No containers running or configured on this server',
                      style: AxTextStyles.sans.copyWith(fontSize: 14, fontWeight: FontWeight.w600, color: AxColors.fg),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      overview?.dockerAvailable == false
                          ? 'Ensure Docker Engine is installed and the systemd unit `docker.service` is active.'
                          : 'Launch containers via docker run, compose, or deployment scripts to view live statistics here.',
                      style: AxTextStyles.sans.copyWith(fontSize: 12, color: AxColors.fg3),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          else if (_view == _View.cards)
            _CardsView(
              containers: containers,
              stacks: overview?.stacks ?? [],
              stackMeta: overview?.stackMeta ?? {},
              onOpen: _openDetail,
            )
          else
            _TableView(
              containers: containers,
              onOpen: _openDetail,
              onAction: (c, action) async {
                final success = await svc.triggerAction(c.id, action);
                if (context.mounted && !success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to $action container ${c.name}')),
                  );
                }
              },
            ),
        ],
      ),
    );
  }
}

class _CardsView extends StatelessWidget {
  final List<DockerContainerItem> containers;
  final List<String> stacks;
  final Map<String, String> stackMeta;
  final ValueChanged<DockerContainerItem> onOpen;

  const _CardsView({
    required this.containers,
    required this.stacks,
    required this.stackMeta,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveStacks = stacks.isNotEmpty
        ? stacks
        : containers.map((c) => c.stack).toSet().toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final stack in effectiveStacks)
          if (containers.any((c) => c.stack == stack))
            Padding(
              padding: const EdgeInsets.only(bottom: 15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        stack == 'standalone' ? 'STANDALONE CONTAINERS' : stack.toUpperCase(),
                        style: AxTextStyles.mono.copyWith(fontSize: 10.5, fontWeight: FontWeight.w500, letterSpacing: 0.8, color: AxColors.fg2),
                      ),
                      const SizedBox(width: 9),
                      Text(
                        stackMeta[stack] ?? (stack == 'standalone' ? 'unaffiliated with compose' : 'compose stack'),
                        style: AxTextStyles.mono.copyWith(fontSize: 10, color: AxColors.fg3),
                      ),
                      const SizedBox(width: 9),
                      const Expanded(child: Divider(color: AxColors.line, height: 1)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LayoutBuilder(
                    builder: (context, c) {
                      final cols = c.maxWidth >= 900 ? 3 : (c.maxWidth >= 560 ? 2 : 1);
                      final items = containers.where((item) => item.stack == stack).toList();
                      return GridView.count(
                        crossAxisCount: cols,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 2.2,
                        children: [for (final ct in items) _ContainerCard(c: ct, onTap: () => onOpen(ct))],
                      );
                    },
                  ),
                ],
              ),
            ),
      ],
    );
  }
}

class _ContainerCard extends StatelessWidget {
  final DockerContainerItem c;
  final VoidCallback onTap;
  const _ContainerCard({required this.c, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final dot = c.running ? AxColors.accent : AxColors.fg3;
    return AxCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              StatusDot(color: dot, size: 7, pulse: c.running),
              const SizedBox(width: 8),
              Expanded(child: Text(c.name, style: AxTextStyles.mono.copyWith(fontSize: 12.5, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis)),
              AxPill(text: c.running ? c.uptime : (c.uptime.isNotEmpty ? c.uptime : 'stopped'), color: dot),
            ],
          ),
          const SizedBox(height: 3),
          Text(c.image, style: AxTextStyles.mono.copyWith(fontSize: 10.5, color: AxColors.fg3), overflow: TextOverflow.ellipsis),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _MiniMeter(label: 'CPU', value: '${c.cpu}%', frac: (c.cpu / 10).clamp(0, 1), color: AxColors.accent)),
              const SizedBox(width: 14),
              Expanded(child: _MiniMeter(label: 'MEM', value: c.memLabel, frac: (c.memMb / 1600).clamp(0, 1), color: AxColors.info)),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniMeter extends StatelessWidget {
  final String label;
  final String value;
  final double frac;
  final Color color;
  const _MiniMeter({required this.label, required this.value, required this.frac, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: AxTextStyles.mono.copyWith(fontSize: 9.5, color: AxColors.fg3)),
            Text(value, style: AxTextStyles.mono.copyWith(fontSize: 9.5, color: AxColors.fg)),
          ],
        ),
        const SizedBox(height: 4),
        AxMeter(value: frac, color: color),
      ],
    );
  }
}

class _TableView extends StatelessWidget {
  final List<DockerContainerItem> containers;
  final ValueChanged<DockerContainerItem> onOpen;
  final void Function(DockerContainerItem, String) onAction;

  const _TableView({
    required this.containers,
    required this.onOpen,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: AxColors.s1, borderRadius: BorderRadius.circular(AxRadius.xl), border: Border.all(color: AxColors.line)),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: 720,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                color: AxColors.s2,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                child: Row(
                  children: [
                    Expanded(flex: 13, child: Text('NAME', style: AxTextStyles.label)),
                    Expanded(flex: 17, child: Text('IMAGE', style: AxTextStyles.label)),
                    Expanded(flex: 9, child: Text('UPTIME', style: AxTextStyles.label)),
                    Expanded(flex: 7, child: Text('CPU', style: AxTextStyles.label, textAlign: TextAlign.right)),
                    Expanded(flex: 8, child: Text('MEM', style: AxTextStyles.label, textAlign: TextAlign.right)),
                    const Expanded(flex: 11, child: SizedBox()),
                  ],
                ),
              ),
              for (final c in containers)
                GestureDetector(
                  onTap: () => onOpen(c),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0x0BE8F0E6)))),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 13,
                          child: Row(
                            children: [
                              StatusDot(color: c.running ? AxColors.accent : AxColors.fg3, size: 6, pulse: c.running),
                              const SizedBox(width: 8),
                              Expanded(child: Text(c.name, style: AxTextStyles.mono.copyWith(fontSize: 11.5), overflow: TextOverflow.ellipsis)),
                            ],
                          ),
                        ),
                        Expanded(flex: 17, child: Text(c.image, style: AxTextStyles.mono.copyWith(fontSize: 11, color: AxColors.fg3), overflow: TextOverflow.ellipsis)),
                        Expanded(flex: 9, child: Text(c.uptime, style: AxTextStyles.mono.copyWith(fontSize: 10.5, color: c.running ? AxColors.accent : AxColors.fg3))),
                        Expanded(flex: 7, child: Text('${c.cpu}%', textAlign: TextAlign.right, style: AxTextStyles.mono.copyWith(fontSize: 11))),
                        Expanded(flex: 8, child: Text(c.memLabel, textAlign: TextAlign.right, style: AxTextStyles.mono.copyWith(fontSize: 11, color: AxColors.fg2))),
                        Expanded(
                          flex: 11,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              _IconBtn(
                                icon: c.running ? Icons.stop_rounded : Icons.play_arrow_rounded,
                                onTap: () => onAction(c, c.running ? 'stop' : 'start'),
                              ),
                              const SizedBox(width: 4),
                              _IconBtn(
                                icon: Icons.restart_alt_rounded,
                                onTap: () => onAction(c, 'restart'),
                              ),
                              const SizedBox(width: 4),
                              _IconBtn(
                                icon: Icons.delete_outline_rounded,
                                color: AxColors.danger,
                                onTap: () async {
                                  final confirm = await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      backgroundColor: AxColors.s1,
                                      title: Text('Remove Container?', style: AxTextStyles.h2),
                                      content: Text('Force remove container ${c.name}? This will delete the instance.', style: AxTextStyles.sans),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.of(ctx).pop(false),
                                          child: Text('Cancel', style: AxTextStyles.sans.copyWith(color: AxColors.fg3)),
                                        ),
                                        TextButton(
                                          onPressed: () => Navigator.of(ctx).pop(true),
                                          child: Text('Remove', style: AxTextStyles.sans.copyWith(color: AxColors.danger, fontWeight: FontWeight.bold)),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirm == true) {
                                    onAction(c, 'remove');
                                  }
                                },
                              ),
                              const SizedBox(width: 4),
                              _IconBtn(
                                icon: Icons.chevron_right_rounded,
                                onTap: () => onOpen(c),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final Color? color;
  final VoidCallback? onTap;
  const _IconBtn({required this.icon, this.color, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AxColors.line)),
        child: Icon(icon, size: 13, color: color ?? AxColors.fg2),
      ),
    );
  }
}

class _CreateContainerDialog extends StatefulWidget {
  final ContainersService service;
  const _CreateContainerDialog({required this.service});

  @override
  State<_CreateContainerDialog> createState() => _CreateContainerDialogState();
}

class _CreateContainerDialogState extends State<_CreateContainerDialog> {
  final _imageCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _portsCtrl = TextEditingController();
  final _envCtrl = TextEditingController();
  String _restartPolicy = 'unless-stopped';
  bool _loading = false;
  String? _error;

  final _quickImages = const ['nginx:alpine', 'redis:alpine', 'caddy:alpine', 'postgres:16-alpine'];

  @override
  void dispose() {
    _imageCtrl.dispose();
    _nameCtrl.dispose();
    _portsCtrl.dispose();
    _envCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final image = _imageCtrl.text.trim();
    if (image.isEmpty) {
      setState(() => _error = 'Image name is required');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final ports = _portsCtrl.text
        .split(RegExp(r'[\s,]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    final env = _envCtrl.text
        .split(RegExp(r'[\r\n]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    final res = await widget.service.createContainer(
      image: image,
      name: _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim(),
      ports: ports.isEmpty ? null : ports,
      env: env.isEmpty ? null : env,
      restart: _restartPolicy,
    );

    if (!mounted) return;
    setState(() => _loading = false);

    if (res['success'] == true) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res['message'] as String? ?? 'Container created successfully')),
      );
    } else {
      setState(() => _error = res['message'] as String? ?? 'Failed to create container');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AxColors.s1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AxRadius.xl), side: const BorderSide(color: AxColors.line)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Run New Container', style: AxTextStyles.h2),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18, color: AxColors.fg3),
                    onPressed: _loading ? null : () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text('Image (e.g. nginx:alpine)', style: AxTextStyles.label),
              const SizedBox(height: 5),
              TextField(
                controller: _imageCtrl,
                style: AxTextStyles.mono.copyWith(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'nginx:alpine',
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
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _quickImages.map((img) {
                  return InkWell(
                    borderRadius: BorderRadius.circular(AxRadius.pill),
                    onTap: () => setState(() => _imageCtrl.text = img),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AxColors.s2,
                        borderRadius: BorderRadius.circular(AxRadius.pill),
                        border: Border.all(color: AxColors.line),
                      ),
                      child: Text(img, style: AxTextStyles.mono.copyWith(fontSize: 10, color: AxColors.fg2)),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              Text('Container Name (optional)', style: AxTextStyles.label),
              const SizedBox(height: 5),
              TextField(
                controller: _nameCtrl,
                style: AxTextStyles.mono.copyWith(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'my-web-app',
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
              Text('Ports (Host:Container, space or comma separated)', style: AxTextStyles.label),
              const SizedBox(height: 5),
              TextField(
                controller: _portsCtrl,
                style: AxTextStyles.mono.copyWith(fontSize: 13),
                decoration: InputDecoration(
                  hintText: '8080:80, 443:443',
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
              Text('Environment Variables (KEY=VALUE per line)', style: AxTextStyles.label),
              const SizedBox(height: 5),
              TextField(
                controller: _envCtrl,
                maxLines: 2,
                style: AxTextStyles.mono.copyWith(fontSize: 12),
                decoration: InputDecoration(
                  hintText: 'NODE_ENV=production\nPORT=3000',
                  hintStyle: AxTextStyles.mono.copyWith(fontSize: 12, color: AxColors.fg3),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  filled: true,
                  fillColor: AxColors.s2,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AxColors.line)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AxColors.line)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AxColors.accent)),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text('Restart: ', style: AxTextStyles.label),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: _restartPolicy,
                    dropdownColor: AxColors.s2,
                    underline: const SizedBox(),
                    style: AxTextStyles.mono.copyWith(fontSize: 12, color: AxColors.fg),
                    items: const [
                      DropdownMenuItem(value: 'unless-stopped', child: Text('unless-stopped')),
                      DropdownMenuItem(value: 'always', child: Text('always')),
                      DropdownMenuItem(value: 'no', child: Text('no')),
                      DropdownMenuItem(value: 'on-failure', child: Text('on-failure')),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _restartPolicy = v);
                    },
                  ),
                ],
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
                    onPressed: _loading ? null : () => Navigator.of(context).pop(),
                    child: Text('Cancel', style: AxTextStyles.sans.copyWith(color: AxColors.fg3)),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: _loading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AxColors.accent,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AxRadius.pill)),
                    ),
                    child: _loading
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                        : Text('Deploy Container', style: AxTextStyles.sans.copyWith(fontWeight: FontWeight.w700, color: Colors.black)),
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
