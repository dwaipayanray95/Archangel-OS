import 'package:flutter/material.dart';

import '../../../services/containers_service.dart';
import '../../ui.dart';
import 'app_specs.dart';

/// Full-height "Run an app" page: image, name, ports, folders, settings and
/// restart behaviour. Pops with `true` once the server accepted the app.
class RunAppPage extends StatefulWidget {
  const RunAppPage({super.key, required this.service});

  final ContainersService service;

  static Future<bool?> open(BuildContext context, ContainersService service) {
    return Navigator.of(context).push<bool>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => RunAppPage(service: service)));
  }

  @override
  State<RunAppPage> createState() => _RunAppPageState();
}

class _PortRow {
  final container = TextEditingController();
  final host = TextEditingController();
  PortVisibility visibility = PortVisibility.private;
  void dispose() {
    container.dispose();
    host.dispose();
  }
}

class _FolderRow {
  final host = TextEditingController();
  final container = TextEditingController();
  void dispose() {
    host.dispose();
    container.dispose();
  }
}

class _SettingRow {
  final key = TextEditingController();
  final value = TextEditingController();
  void dispose() {
    key.dispose();
    value.dispose();
  }
}

class _RunAppPageState extends State<RunAppPage> {
  final _formKey = GlobalKey<FormState>();
  final _image = TextEditingController();
  final _name = TextEditingController();
  final _ports = <_PortRow>[];
  final _folders = <_FolderRow>[];
  final _settings = <_SettingRow>[];
  String _restart = restartChoices.first.$1;
  bool _busy = false;
  String? _error;

  static const _examples = ['nginx', 'louislam/uptime-kuma', 'vaultwarden/server'];

  @override
  void dispose() {
    _image.dispose();
    _name.dispose();
    for (final r in _ports) {
      r.dispose();
    }
    for (final r in _folders) {
      r.dispose();
    }
    for (final r in _settings) {
      r.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final ports = buildPortSpecs([
      for (final r in _ports) PortMapping(containerPort: r.container.text, hostPort: r.host.text, visibility: r.visibility),
    ]);
    final volumes = buildVolumeSpecs([for (final r in _folders) FolderMapping(hostPath: r.host.text, containerPath: r.container.text)]);
    final env = buildEnvSpecs([for (final r in _settings) SettingEntry(key: r.key.text, value: r.value.text)]);
    final res = await widget.service.createContainer(
      image: _image.text.trim(),
      name: _name.text,
      ports: ports,
      volumes: volumes,
      env: env,
      restart: _restart,
    );
    if (!mounted) return;
    if (res['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${res['message'] ?? 'Your app is starting.'}')));
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _busy = false;
        _error = '${res['message'] ?? 'The server could not run this app.'}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        surfaceTintColor: Colors.transparent,
        foregroundColor: c.text,
        leading: const CloseButton(),
        title: Text('Run an app', style: ax.typo.title.copyWith(color: c.text)),
      ),
      body: LayoutBuilder(
        builder: (context, box) {
          final pad = AxPage.paddingFor(box.maxWidth);
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Form(
                key: _formKey,
                // Not a lazy ListView: the form is short and every field must
                // exist so validation covers rows scrolled out of view.
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(pad, ax.space.sm, pad, pad + MediaQuery.of(context).viewInsets.bottom),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Apps run in their own sealed box on your server. Pick an app image, choose how you reach it, and run it.',
                        style: ax.typo.body.copyWith(color: c.textMuted),
                      ),
                      SizedBox(height: ax.space.xl),
                      _section(context, 'App image', null, [
                        TextFormField(
                          controller: _image,
                          autocorrect: false,
                          enableSuggestions: false,
                          decoration: const InputDecoration(
                            labelText: 'Image',
                            hintText: 'nginx',
                            helperText: 'The name of the app on Docker Hub.',
                          ),
                          validator: (v) => validateImage(v ?? ''),
                        ),
                        SizedBox(height: ax.space.sm),
                        Wrap(
                          spacing: ax.space.sm,
                          runSpacing: ax.space.sm,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text('Examples:', style: ax.typo.caption.copyWith(color: c.textMuted)),
                            for (final e in _examples)
                              ActionChip(
                                label: Text(e, style: ax.typo.caption.copyWith(color: c.text)),
                                backgroundColor: c.surfaceAlt,
                                side: BorderSide(color: c.outline),
                                onPressed: () => setState(() => _image.text = e),
                              ),
                          ],
                        ),
                        SizedBox(height: ax.space.lg),
                        TextFormField(
                          controller: _name,
                          autocorrect: false,
                          enableSuggestions: false,
                          decoration: const InputDecoration(
                            labelText: 'Name (optional)',
                            helperText: 'A short name to recognise it by. Leave blank to pick one for you.',
                          ),
                          validator: (v) => validateAppName(v ?? ''),
                        ),
                      ]),
                      _section(
                        context,
                        'Ports',
                        const HelpTip(
                          title: 'Ports',
                          message:
                              'A port is a numbered door into an app. Web apps usually listen on port 80 or 8080 '
                              'inside. Choose which port on your server leads to it. "Private" doors can only be '
                              'used by your paired devices over the secure connection. "Public" doors are open to '
                              'everyone on the internet, so only use them for things meant to be public.',
                        ),
                        [
                          if (_ports.isEmpty)
                            Text(
                              'No ports yet. Add one if you want to open the app from a browser.',
                              style: ax.typo.body.copyWith(color: c.textMuted),
                            ),
                          for (var i = 0; i < _ports.length; i++) _portRow(context, i),
                          SizedBox(height: ax.space.sm),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: AxButton.secondary(
                              label: 'Add a port',
                              icon: Icons.add_rounded,
                              onPressed: () => setState(() => _ports.add(_PortRow())),
                            ),
                          ),
                        ],
                      ),
                      _section(
                        context,
                        'Folders',
                        const HelpTip(
                          title: 'Folders',
                          message:
                              'Apps forget everything when they are removed unless they save to a folder on your '
                              'server. Link a folder on your server (the first path) to a place inside the app (the '
                              'second path) so its data is kept. The app’s page will say where it stores data.',
                        ),
                        [
                          if (_folders.isEmpty)
                            Text(
                              'No folders linked. Without one, the app’s data is lost if you remove it.',
                              style: ax.typo.body.copyWith(color: c.textMuted),
                            ),
                          for (var i = 0; i < _folders.length; i++) _folderRow(context, i),
                          SizedBox(height: ax.space.sm),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: AxButton.secondary(
                              label: 'Add a folder',
                              icon: Icons.add_rounded,
                              onPressed: () => setState(() => _folders.add(_FolderRow())),
                            ),
                          ),
                        ],
                      ),
                      _section(
                        context,
                        'Settings',
                        const HelpTip(
                          title: 'Settings',
                          message:
                              'Some apps are configured with named values, for example a password or a time zone. '
                              'Their instructions list the names to use, such as TZ with the value Europe/London.',
                        ),
                        [
                          if (_settings.isEmpty)
                            Text('No settings. Most apps work without any.', style: ax.typo.body.copyWith(color: c.textMuted)),
                          for (var i = 0; i < _settings.length; i++) _settingRow(context, i),
                          SizedBox(height: ax.space.sm),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: AxButton.secondary(
                              label: 'Add a setting',
                              icon: Icons.add_rounded,
                              onPressed: () => setState(() => _settings.add(_SettingRow())),
                            ),
                          ),
                        ],
                      ),
                      _section(context, 'If the server restarts', null, [
                        DropdownButtonFormField<String>(
                          value: _restart,
                          isExpanded: true,
                          dropdownColor: c.surfaceHigh,
                          decoration: const InputDecoration(labelText: 'Restart behaviour'),
                          items: [
                            for (final (value, label) in restartChoices)
                              DropdownMenuItem(value: value, child: Text(label, overflow: TextOverflow.ellipsis)),
                          ],
                          onChanged: (v) => setState(() => _restart = v ?? _restart),
                        ),
                      ]),
                      if (_error != null) ...[
                        Container(
                          padding: EdgeInsets.all(ax.space.md),
                          decoration: BoxDecoration(
                            color: c.dangerWash,
                            borderRadius: BorderRadius.circular(ax.radii.md),
                            border: Border.all(color: c.danger),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.error_outline, color: c.danger),
                              SizedBox(width: ax.space.sm),
                              Expanded(child: Text(_error!, style: ax.typo.body.copyWith(color: c.text))),
                            ],
                          ),
                        ),
                        SizedBox(height: ax.space.lg),
                      ],
                      AxButton(
                        label: 'Run app',
                        icon: Icons.play_arrow_rounded,
                        expand: true,
                        loading: _busy,
                        onPressed: _busy ? null : _submit,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _section(BuildContext context, String title, Widget? help, List<Widget> children) {
    final ax = context.ax;
    final c = ax.colors;
    return Padding(
      padding: EdgeInsets.only(bottom: ax.space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Semantics(header: true, child: Text(title, style: ax.typo.title.copyWith(color: c.text)))),
              if (help != null) help,
            ],
          ),
          SizedBox(height: ax.space.sm),
          ...children,
        ],
      ),
    );
  }

  Widget _rowFrame(BuildContext context, {required List<Widget> children, required String removeTip, required VoidCallback onRemove}) {
    final ax = context.ax;
    final c = ax.colors;
    return Padding(
      padding: EdgeInsets.only(bottom: ax.space.md),
      child: DecoratedBox(
        decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(ax.radii.md), border: Border.all(color: c.border)),
        child: Padding(
          padding: EdgeInsets.all(ax.space.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children)),
              AxIconButton(icon: Icons.close_rounded, tooltip: removeTip, onPressed: onRemove),
            ],
          ),
        ),
      ),
    );
  }

  Widget _portRow(BuildContext context, int i) {
    final ax = context.ax;
    final c = ax.colors;
    final r = _ports[i];
    return _rowFrame(
      context,
      removeTip: 'Remove port ${i + 1}',
      onRemove: () => setState(() => _ports.removeAt(i).dispose()),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                controller: r.container,
                keyboardType: TextInputType.text,
                decoration: const InputDecoration(labelText: 'Port inside the app', hintText: '80'),
                validator: (v) => validateContainerPort(v ?? ''),
              ),
            ),
            SizedBox(width: ax.space.md),
            Expanded(
              child: TextFormField(
                controller: r.host,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Port on your server', hintText: '8080'),
                validator: (v) => validateHostPort(v ?? ''),
              ),
            ),
          ],
        ),
        SizedBox(height: ax.space.md),
        DropdownButtonFormField<PortVisibility>(
          value: r.visibility,
          isExpanded: true,
          dropdownColor: c.surfaceHigh,
          decoration: const InputDecoration(labelText: 'Who can reach it'),
          items: [for (final v in PortVisibility.values) DropdownMenuItem(value: v, child: Text(v.label, overflow: TextOverflow.ellipsis))],
          onChanged: (v) => setState(() => r.visibility = v ?? r.visibility),
        ),
        if (r.visibility == PortVisibility.public) ...[
          SizedBox(height: ax.space.sm),
          Container(
            key: ValueKey('public-warning-$i'),
            padding: EdgeInsets.all(ax.space.md),
            decoration: BoxDecoration(
              color: c.warningWash,
              borderRadius: BorderRadius.circular(ax.radii.sm),
              border: Border.all(color: c.warning),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded, color: c.warning),
                SizedBox(width: ax.space.sm),
                Expanded(
                  child: Text(
                    'Anyone on the internet will be able to reach this app. Only choose this for things meant to be '
                    'public, and make sure the app is password protected.',
                    style: ax.typo.body.copyWith(color: c.text),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _folderRow(BuildContext context, int i) {
    final ax = context.ax;
    final r = _folders[i];
    return _rowFrame(
      context,
      removeTip: 'Remove folder ${i + 1}',
      onRemove: () => setState(() => _folders.removeAt(i).dispose()),
      children: [
        TextFormField(
          controller: r.host,
          autocorrect: false,
          decoration: const InputDecoration(labelText: 'Folder on your server', hintText: '/srv/myapp'),
          validator: (v) => validateFolderPath(v ?? '', what: 'Folder on your server'),
        ),
        SizedBox(height: ax.space.md),
        TextFormField(
          controller: r.container,
          autocorrect: false,
          decoration: const InputDecoration(labelText: 'Place inside the app', hintText: '/data'),
          validator: (v) => validateFolderPath(v ?? '', what: 'Place inside the app'),
        ),
      ],
    );
  }

  Widget _settingRow(BuildContext context, int i) {
    final ax = context.ax;
    final r = _settings[i];
    return _rowFrame(
      context,
      removeTip: 'Remove setting ${i + 1}',
      onRemove: () => setState(() => _settings.removeAt(i).dispose()),
      children: [
        TextFormField(
          controller: r.key,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(labelText: 'Name', hintText: 'TZ'),
          validator: (v) => validateSettingKey(v ?? ''),
        ),
        SizedBox(height: ax.space.md),
        TextFormField(
          controller: r.value,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(labelText: 'Value', hintText: 'Europe/London'),
        ),
      ],
    );
  }
}
