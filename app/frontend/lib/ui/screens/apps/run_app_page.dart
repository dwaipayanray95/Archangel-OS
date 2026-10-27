import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../services/archangeld_connection.dart';
import '../../../services/containers_service.dart';
import '../../ui.dart';
import 'app_actions.dart' show openAppInBrowser;
import 'app_catalog.dart';
import 'app_specs.dart';

enum _Step { pick, configure, running }

/// "Run an app" in three calm steps:
///
/// 1. Pick something to run from a short catalog (or "Something else").
/// 2. Two choices: its name, and who can open it (Private / Public). Ports,
///    folders, settings and restart behaviour are prefilled and tucked under
///    "More options".
/// 3. Watch it start, then open it.
///
/// Pops with `true` once the server accepted the app.
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
  _FolderRow([FolderMapping? m]) {
    if (m != null) {
      host.text = m.hostPath;
      container.text = m.containerPath;
    }
  }
  final host = TextEditingController();
  final container = TextEditingController();
  void dispose() {
    host.dispose();
    container.dispose();
  }
}

class _SettingRow {
  _SettingRow([SettingEntry? e]) {
    if (e != null) {
      key.text = e.key;
      value.text = e.value;
    }
  }
  final key = TextEditingController();
  final value = TextEditingController();
  void dispose() {
    key.dispose();
    value.dispose();
  }
}

class _RunAppPageState extends State<RunAppPage> {
  final _formKey = GlobalKey<FormState>();
  _Step _step = _Step.pick;
  AppPreset? _preset;

  final _image = TextEditingController();
  final _name = TextEditingController();
  final _inside = TextEditingController();
  final _outside = TextEditingController();
  PortVisibility _access = PortVisibility.private;
  final _ports = <_PortRow>[];
  final _folders = <_FolderRow>[];
  final _settings = <_SettingRow>[];
  String _restart = restartChoices.first.$1;
  bool _more = false;

  bool _busy = false;
  bool _done = false;
  String? _error;

  static const _examples = ['nginx', 'louislam/uptime-kuma', 'vaultwarden/server'];

  @override
  void dispose() {
    for (final c in [_image, _name, _inside, _outside]) {
      c.dispose();
    }
    _clearRows();
    super.dispose();
  }

  void _clearRows() {
    for (final r in _ports) {
      r.dispose();
    }
    for (final r in _folders) {
      r.dispose();
    }
    for (final r in _settings) {
      r.dispose();
    }
    _ports.clear();
    _folders.clear();
    _settings.clear();
  }

  void _pick(AppPreset p) {
    setState(() {
      _preset = p;
      _clearRows();
      _image.text = p.image;
      _name.text = p.isCustom ? '' : p.id;
      _inside.text = p.containerPort ?? '';
      _outside.text = p.hostPort ?? '';
      _access = PortVisibility.private;
      _folders.addAll(p.folders.map(_FolderRow.new));
      _settings.addAll(p.settings.map(_SettingRow.new));
      _restart = restartChoices.first.$1;
      _more = false;
      _error = null;
      _step = _Step.configure;
    });
  }

  String get _displayName {
    final n = _name.text.trim();
    if (n.isNotEmpty) return n;
    final p = _preset;
    if (p != null && !p.isCustom) return p.name;
    final img = _image.text.trim().split('/').last.split(':').first;
    return img.isEmpty ? 'Your app' : img;
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      // A problem may be hiding inside "More options": open it so it shows.
      if (!_more) {
        setState(() => _more = true);
        WidgetsBinding.instance.addPostFrameCallback((_) => _formKey.currentState?.validate());
      }
      return;
    }
    final ports = buildPortSpecs([
      PortMapping(containerPort: _inside.text, hostPort: _outside.text, visibility: _access),
      for (final r in _ports) PortMapping(containerPort: r.container.text, hostPort: r.host.text, visibility: r.visibility),
    ]);
    final volumes = buildVolumeSpecs([for (final r in _folders) FolderMapping(hostPath: r.host.text, containerPath: r.container.text)]);
    final env = buildEnvSpecs([for (final r in _settings) SettingEntry(key: r.key.text, value: r.value.text)]);
    setState(() {
      _step = _Step.running;
      _busy = true;
      _done = false;
      _error = null;
    });
    final res = await widget.service.createContainer(
      image: _image.text.trim(),
      name: _name.text,
      ports: ports,
      volumes: volumes,
      env: env,
      restart: _restart,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (res['success'] == true) {
        _done = true;
      } else {
        _error = '${res['message'] ?? 'The server could not run this app.'}';
      }
    });
  }

  Uri? _openUri() {
    String? host;
    try {
      host = context.read<ArchangeldConnection>().host;
    } catch (_) {}
    final port = (_outside.text.trim().isNotEmpty ? _outside.text : _inside.text).trim().split('/').first;
    if (port.isEmpty) return null;
    return appOpenUri(host, port);
  }

  void _back() {
    if (_step == _Step.configure) {
      setState(() => _step = _Step.pick);
    } else if (_step == _Step.running && !_busy && !_done) {
      setState(() => _step = _Step.configure);
    } else {
      Navigator.of(context).maybePop(_done);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final title = switch (_step) {
      _Step.pick => 'Run an app',
      _Step.configure => _preset?.isCustom == true ? 'Run an app' : 'Run ${_preset?.name ?? 'an app'}',
      _Step.running => _done ? 'Done' : 'Starting $_displayName',
    };
    return PopScope(
      canPop: _step == _Step.pick || _done,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_busy) _back();
      },
      child: AxBackdrop(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            foregroundColor: c.text,
            leading: _step == _Step.pick || _done
                ? CloseButton(onPressed: () => Navigator.of(context).maybePop(_done))
                : BackButton(onPressed: _busy ? null : _back),
            title: Text(title, style: ax.typo.title.copyWith(color: c.text)),
          ),
          body: LayoutBuilder(
            builder: (context, box) {
              final pad = AxPage.paddingFor(box.maxWidth);
              final Widget content = switch (_step) {
                _Step.pick => _pickView(context),
                _Step.configure => _configureView(context),
                _Step.running => _runningView(context),
              };
              return Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(pad, ax.space.sm, pad, pad + MediaQuery.of(context).viewInsets.bottom),
                    child: KeyedSubtree(key: ValueKey(_step), child: content),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  // ───────────────────────────── step 1: pick

  Widget _pickView(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('What would you like to run?', style: ax.typo.display.copyWith(color: c.text)),
        SizedBox(height: ax.space.sm),
        Text(
          'Each app runs in its own sealed box on your server. Pick one to start; you can change everything on the next screen.',
          style: ax.typo.body.copyWith(color: c.textMuted),
        ),
        SizedBox(height: ax.space.xl),
        LayoutBuilder(
          builder: (context, box) {
            final cols = box.maxWidth >= 560 ? 2 : 1;
            final gap = ax.space.md;
            final w = (box.maxWidth - gap * (cols - 1)) / cols;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final (i, p) in kAppCatalog.indexed)
                  SizedBox(
                    width: w,
                    child: AxCard(
                      key: ValueKey('preset-${p.id}'),
                      onTap: () => _pick(p),
                      semanticsLabel: p.isCustom ? 'Run something else' : 'Run ${p.name}. ${p.blurb}',
                      padding: EdgeInsets.all(ax.space.md + 2),
                      child: Row(
                        children: [
                          AppTile(label: p.isCustom ? null : p.name, index: i, icon: p.isCustom ? Icons.add_rounded : null),
                          SizedBox(width: ax.space.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(p.name, style: ax.typo.label.copyWith(color: c.text)),
                                const SizedBox(height: 2),
                                Text(p.blurb, style: ax.typo.caption.copyWith(color: c.textMuted, fontSize: 12.5)),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right, color: c.textMuted),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  // ───────────────────────────── step 2: configure

  Widget _configureView(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final p = _preset!;
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (p.isCustom) ...[
            Semantics(
              header: true,
              child: Text('Which app?', style: ax.typo.title.copyWith(color: c.text)),
            ),
            SizedBox(height: ax.space.sm),
            TextFormField(
              controller: _image,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(labelText: 'Image', hintText: 'nginx', helperText: 'The name of the app on Docker Hub.'),
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
          ] else
            AxCard(
              padding: EdgeInsets.all(ax.space.md + 2),
              child: Row(
                children: [
                  AppTile(label: p.name, index: kAppCatalog.indexOf(p)),
                  SizedBox(width: ax.space.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.blurb, style: ax.typo.body.copyWith(color: c.text)),
                        const SizedBox(height: 2),
                        Text(p.image, style: ax.typo.mono.copyWith(color: c.textMuted, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          SizedBox(height: ax.space.xl),
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
          SizedBox(height: ax.space.xl),
          Semantics(
            header: true,
            child: Text('Who can open it?', style: ax.typo.title.copyWith(color: c.text)),
          ),
          SizedBox(height: ax.space.sm),
          _ChoiceCard(
            key: const ValueKey('access-private'),
            icon: Icons.lock_outline_rounded,
            title: 'Private (recommended)',
            body: 'Only your own devices, through the private connection. Nobody else can even see it.',
            selected: _access == PortVisibility.private,
            onTap: () => setState(() => _access = PortVisibility.private),
          ),
          SizedBox(height: ax.space.sm),
          _ChoiceCard(
            key: const ValueKey('access-public'),
            icon: Icons.public_rounded,
            title: 'Public',
            body: 'Anyone on the internet who has the address.',
            selected: _access == PortVisibility.public,
            tone: c.info,
            onTap: () => setState(() => _access = PortVisibility.public),
          ),
          if (_access == PortVisibility.public) ...[
            SizedBox(height: ax.space.sm),
            const _Notice(
              key: ValueKey('public-warning-main'),
              text:
                  'Anyone on the internet will be able to reach this app. Only choose this for things meant to be public, '
                  'and make sure the app is password protected.',
            ),
          ],
          SizedBox(height: ax.space.lg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  controller: _inside,
                  decoration: const InputDecoration(labelText: 'Port inside the app', hintText: '80'),
                  validator: (v) {
                    final inside = (v ?? '').trim();
                    if (inside.isEmpty) {
                      return _outside.text.trim().isEmpty ? null : 'Port inside the app is required';
                    }
                    return validateContainerPort(inside);
                  },
                ),
              ),
              SizedBox(width: ax.space.md),
              Expanded(
                child: TextFormField(
                  controller: _outside,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Port on your server', hintText: '8080'),
                  validator: (v) => validateHostPort(v ?? ''),
                ),
              ),
            ],
          ),
          SizedBox(height: ax.space.xs),
          Text(
            p.isCustom
                ? 'The app’s instructions say which port it uses. Leave both empty if it has no web page.'
                : 'Already filled in for ${p.name}. Most people never change these.',
            style: ax.typo.caption.copyWith(color: c.textMuted),
          ),
          if (_folders.isNotEmpty) ...[
            SizedBox(height: ax.space.lg),
            Row(
              children: [
                Icon(Icons.folder_outlined, size: 18, color: c.textMuted),
                SizedBox(width: ax.space.sm),
                Expanded(
                  child: Text(
                    'Keeps its data in ${_folders.map((f) => f.host.text).where((s) => s.isNotEmpty).join(' and ')}',
                    style: ax.typo.caption.copyWith(color: c.textMuted, fontSize: 12.5),
                  ),
                ),
              ],
            ),
          ],
          SizedBox(height: ax.space.lg),
          _MoreToggle(open: _more, onTap: () => setState(() => _more = !_more)),
          if (_more) ..._moreOptions(context),
          SizedBox(height: ax.space.xl),
          AxButton(label: 'Run app', icon: Icons.play_arrow_rounded, expand: true, loading: _busy, onPressed: _busy ? null : _submit),
        ],
      ),
    );
  }

  List<Widget> _moreOptions(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    return [
      SizedBox(height: ax.space.md),
      _section(
        context,
        'More ports',
        const HelpTip(
          title: 'Ports',
          message:
              'A port is a numbered door into an app. Web apps usually listen on port 80 or 8080 '
              'inside. Choose which port on your server leads to it. "Private" doors can only be '
              'used by your paired devices over the secure connection. "Public" doors are open to '
              'everyone on the internet, so only use them for things meant to be public.',
        ),
        [
          if (_ports.isEmpty) Text('Most apps need only the one above.', style: ax.typo.body.copyWith(color: c.textMuted)),
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
          if (_settings.isEmpty) Text('No settings. Most apps work without any.', style: ax.typo.body.copyWith(color: c.textMuted)),
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
          // ignore: deprecated_member_use
          value: _restart,
          isExpanded: true,
          dropdownColor: c.surfaceHigh,
          decoration: const InputDecoration(labelText: 'Restart behaviour'),
          items: [
            for (final (value, label) in restartChoices)
              DropdownMenuItem(
                value: value,
                child: Text(label, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) => setState(() => _restart = v ?? _restart),
        ),
      ]),
    ];
  }

  // ───────────────────────────── step 3: running

  Widget _runningView(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final failed = _error != null;
    final uri = _done ? _openUri() : null;
    final steps = <(String, bool, bool)>[
      ('Sending it to your server', true, false),
      ('Downloading and starting $_displayName', _done, _busy),
      (_access == PortVisibility.public ? 'Opening it to the internet' : 'Connecting it to your private connection', _done, false),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: ax.space.lg),
        AxCard(
          padding: EdgeInsets.all(ax.space.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: failed ? c.dangerWash : (_done ? c.successWash : c.infoWash),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: _busy
                    ? Padding(
                        padding: const EdgeInsets.all(14),
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: c.info),
                      )
                    : Icon(failed ? Icons.error_outline : Icons.check_rounded, color: failed ? c.danger : c.success, size: 28),
              ),
              SizedBox(height: ax.space.lg),
              Text(
                failed ? 'That didn’t work' : (_done ? '$_displayName is running.' : 'Starting $_displayName…'),
                style: ax.typo.display.copyWith(color: c.text),
              ),
              SizedBox(height: ax.space.sm),
              Text(
                failed
                    ? _error!
                    : _done
                    ? (_access == PortVisibility.public
                          ? 'Anyone with the address can open it.'
                          : 'Open it from any of your devices while the private connection is on.')
                    : 'This usually takes under a minute. Big apps take longer the first time.',
                style: ax.typo.body.copyWith(color: failed ? c.danger : c.textMuted),
              ),
              if (!failed) ...[
                SizedBox(height: ax.space.lg),
                for (final (label, done, working) in steps)
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: ax.space.xs + 2),
                    child: Row(
                      children: [
                        if (done)
                          Icon(Icons.check_circle_rounded, size: 20, color: c.success)
                        else if (working)
                          SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: c.info))
                        else
                          Icon(Icons.radio_button_unchecked, size: 20, color: c.textSubtle),
                        SizedBox(width: ax.space.md),
                        Expanded(
                          child: Text(label, style: ax.typo.body.copyWith(color: done || working ? c.text : c.textMuted)),
                        ),
                        Text(
                          done ? 'Done' : (working ? 'Working…' : 'Waiting'),
                          style: ax.typo.caption.copyWith(color: done ? c.success : c.textMuted),
                        ),
                      ],
                    ),
                  ),
              ],
              SizedBox(height: ax.space.xl),
              Wrap(
                spacing: ax.space.sm,
                runSpacing: ax.space.sm,
                children: [
                  if (failed) ...[
                    AxButton(label: 'Change settings', icon: Icons.tune_rounded, onPressed: () => setState(() => _step = _Step.configure)),
                    AxButton.secondary(label: 'Close', onPressed: () => Navigator.of(context).maybePop(false)),
                  ],
                  if (_done) ...[
                    if (uri != null)
                      AxButton.secondary(
                        label: 'Open it',
                        icon: Icons.open_in_new_rounded,
                        onPressed: () => openAppInBrowser(context, uri),
                      ),
                    AxButton(label: 'Done', onPressed: () => Navigator.of(context).maybePop(true)),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ───────────────────────────── shared pieces

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
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(title, style: ax.typo.title.copyWith(color: c.text)),
                ),
              ),
              ?help,
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
        decoration: BoxDecoration(
          color: c.glass,
          borderRadius: BorderRadius.circular(ax.radii.md),
          border: Border.all(color: c.glassBorder),
        ),
        child: Padding(
          padding: EdgeInsets.all(ax.space.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
              ),
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
      removeTip: 'Remove port ${i + 2}',
      onRemove: () => setState(() => _ports.removeAt(i).dispose()),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                controller: r.container,
                decoration: const InputDecoration(labelText: 'Inside the app', hintText: '443'),
                validator: (v) => validateContainerPort(v ?? ''),
              ),
            ),
            SizedBox(width: ax.space.md),
            Expanded(
              child: TextFormField(
                controller: r.host,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'On your server', hintText: '8443'),
                validator: (v) => validateHostPort(v ?? ''),
              ),
            ),
          ],
        ),
        SizedBox(height: ax.space.md),
        DropdownButtonFormField<PortVisibility>(
          // ignore: deprecated_member_use
          value: r.visibility,
          isExpanded: true,
          dropdownColor: c.surfaceHigh,
          decoration: const InputDecoration(labelText: 'Who can reach it'),
          items: [
            for (final v in PortVisibility.values)
              DropdownMenuItem(
                value: v,
                child: Text(v.label, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) => setState(() => r.visibility = v ?? r.visibility),
        ),
        if (r.visibility == PortVisibility.public) ...[
          SizedBox(height: ax.space.sm),
          _Notice(
            key: ValueKey('public-warning-$i'),
            text: 'Anyone on the internet will be able to reach this port. Only choose this for things meant to be public.',
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

/// A rounded square with an app's initial (or an icon), tinted by [index]
/// so neighbouring apps are easy to tell apart.
class AppTile extends StatelessWidget {
  const AppTile({super.key, this.label, this.index = 0, this.icon, this.size = 42});

  final String? label;
  final int index;
  final IconData? icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.ax.colors;
    final tones = [
      (c.accentWash, c.accent),
      (c.infoWash, c.info),
      (c.successWash, c.success),
      (c.warningWash, c.warning),
      (c.surfaceHigh, c.text),
    ];
    final (bg, fg) = icon != null ? (c.surfaceHigh, c.text) : tones[index % tones.length];
    final letter = (label ?? '').trim().isEmpty ? '?' : label!.trim()[0].toUpperCase();
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(size * 0.3)),
        child: icon != null
            ? Icon(icon, color: fg, size: size * 0.5)
            : Text(
                letter,
                style: TextStyle(fontFamily: kUiFontFamily, fontWeight: FontWeight.w700, fontSize: size * 0.4, color: fg),
              ),
      ),
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    required this.selected,
    required this.onTap,
    this.tone,
  });

  final IconData icon;
  final String title;
  final String body;
  final bool selected;
  final VoidCallback onTap;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final fg = tone ?? c.accent;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      child: AxCard(
        selected: selected,
        onTap: onTap,
        semanticsLabel: '$title. $body',
        padding: EdgeInsets.all(ax.space.md + 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: c.surfaceHigh, borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: fg, size: 20),
            ),
            SizedBox(width: ax.space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: ax.typo.label.copyWith(color: c.text)),
                  const SizedBox(height: 2),
                  Text(body, style: ax.typo.body.copyWith(color: c.textMuted, fontSize: 13)),
                ],
              ),
            ),
            SizedBox(width: ax.space.sm),
            Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: selected ? c.accent : c.outline, size: 22),
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    return Container(
      padding: EdgeInsets.all(ax.space.md),
      decoration: BoxDecoration(
        color: c.warningWash,
        borderRadius: BorderRadius.circular(ax.radii.md),
        border: Border.all(color: c.warning),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: c.warning),
          SizedBox(width: ax.space.sm),
          Expanded(
            child: Text(text, style: ax.typo.body.copyWith(color: c.text)),
          ),
        ],
      ),
    );
  }
}

class _MoreToggle extends StatelessWidget {
  const _MoreToggle({required this.open, required this.onTap});
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    return Semantics(
      button: true,
      expanded: open,
      label: 'More options',
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ax.radii.md),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: axMinTarget(context)),
          child: Row(
            children: [
              Icon(open ? Icons.expand_less : Icons.expand_more, color: c.accent),
              SizedBox(width: ax.space.sm),
              Text('More options', style: ax.typo.label.copyWith(color: c.accent)),
              SizedBox(width: ax.space.sm),
              Flexible(
                child: Text(
                  'more ports, folders, settings, restarts',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ax.typo.caption.copyWith(color: c.textMuted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
