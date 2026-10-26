import 'package:flutter/material.dart';

import '../../../services/devops_service.dart';
import '../../ui.dart';
import 'script_widgets.dart';
import 'services_logic.dart';

const kNewScriptTemplate = '#!/bin/sh\nset -e\n\necho "Starting..."\n# Add the commands you want to run here.\n';

/// Full-screen editor for a script. [scriptName] null means a new script (the
/// name can be typed); otherwise the name is fixed. Pops `true` after a
/// successful save. Leaving with unsaved changes asks first.
class ScriptEditorPage extends StatefulWidget {
  const ScriptEditorPage({super.key, required this.service, this.scriptName, this.initialContent});

  final DevopsService service;
  final String? scriptName;
  final String? initialContent;

  /// Returns true when something was saved.
  static Future<bool> open(BuildContext context, DevopsService service, {String? scriptName, String? initialContent}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ScriptEditorPage(service: service, scriptName: scriptName, initialContent: initialContent),
      ),
    );
    return saved ?? false;
  }

  @override
  State<ScriptEditorPage> createState() => _ScriptEditorPageState();
}

class _ScriptEditorPageState extends State<ScriptEditorPage> {
  late final TextEditingController _name;
  late final TextEditingController _content;
  late final String _initialName;
  late final String _initialContent;
  bool _saving = false;
  bool _showNameError = false;
  String? _saveError;
  bool _saveErrorIsAdmin = false;

  bool get _isNew => widget.scriptName == null;

  @override
  void initState() {
    super.initState();
    _initialName = widget.scriptName ?? '';
    _initialContent = widget.initialContent ?? (_isNew ? kNewScriptTemplate : '');
    _name = TextEditingController(text: _initialName)..addListener(_changed);
    _content = TextEditingController(text: _initialContent)..addListener(_changed);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    _name.dispose();
    _content.dispose();
    super.dispose();
  }

  bool get _dirty => _name.text != _initialName || _content.text != _initialContent;
  String? get _nameError => _isNew ? validateScriptName(_name.text) : null;

  Future<void> _save() async {
    if (_nameError != null) {
      setState(() => _showNameError = true);
      return;
    }
    setState(() {
      _saving = true;
      _saveError = null;
    });
    final name = widget.scriptName ?? _name.text.trim();
    final res = await widget.service.saveDeployment(name, _content.text);
    if (!mounted) return;
    if (res['success'] == true) {
      Navigator.of(context).pop(true);
    } else {
      final message = (res['message'] as String?) ?? "The script couldn't be saved.";
      setState(() {
        _saving = false;
        _saveError = message;
        _saveErrorIsAdmin = isAdminModeRefusal(message, widget.service.lastActionStatus);
      });
    }
  }

  Future<void> _onBack() async {
    final leave = await showConfirmDialog(
      context,
      title: 'Discard your changes?',
      message: "You have changes that aren't saved. If you leave now they will be lost.",
      confirmLabel: 'Discard changes',
      cancelLabel: 'Keep editing',
      danger: true,
    );
    if (leave && mounted) Navigator.of(context).pop(false);
  }

  Widget _errorBox(ArchangelTheme ax, AxPalette c) {
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
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
            Expanded(
              child: Text(_saveError!, style: ax.typo.body.copyWith(color: c.text)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final canSave = !_saving && (_isNew || _dirty);
    return PopScope(
      canPop: !_dirty || _saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
        backgroundColor: c.bg,
        appBar: AppBar(
          backgroundColor: c.bg,
          foregroundColor: c.text,
          elevation: 0,
          scrolledUnderElevation: 0,
          automaticallyImplyLeading: false,
          leading: AxIconButton(icon: Icons.arrow_back_rounded, tooltip: 'Back', onPressed: () => Navigator.of(context).maybePop()),
          title: Text(
            _isNew ? 'New script' : widget.scriptName!,
            style: (_isNew ? ax.typo.title : ax.typo.mono.copyWith(fontWeight: FontWeight.w700, fontSize: 16)).copyWith(color: c.text),
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            Padding(
              padding: EdgeInsets.only(right: ax.space.md),
              child: Center(
                child: AxButton(label: 'Save', icon: Icons.save_outlined, loading: _saving, onPressed: canSave ? _save : null),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(ax.space.lg, ax.space.sm, ax.space.lg, ax.space.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_isNew) ...[
                  TextField(
                    key: const ValueKey('script-name'),
                    controller: _name,
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.next,
                    style: ax.typo.mono.copyWith(color: c.text),
                    decoration: InputDecoration(
                      labelText: 'Script name',
                      hintText: 'deploy.sh',
                      helperText: 'Letters, numbers, dots, dashes and underscores. Must end with .sh',
                      helperMaxLines: 2,
                      errorMaxLines: 2,
                      errorText: _showNameError ? _nameError : null,
                    ),
                    onChanged: (_) {
                      if (_showNameError && _nameError == null) setState(() => _showNameError = false);
                    },
                  ),
                  SizedBox(height: ax.space.md),
                ],
                Text('This script runs on your server as the archangel user.', style: ax.typo.caption.copyWith(color: c.textMuted)),
                if (_saveError != null) ...[
                  SizedBox(height: ax.space.sm),
                  _saveErrorIsAdmin
                      ? RefusalBanner(message: _saveError!, onDismiss: () => setState(() => _saveError = null))
                      : _errorBox(ax, c),
                ],
                SizedBox(height: ax.space.sm),
                Expanded(
                  child: TextField(
                    key: const ValueKey('script-content'),
                    controller: _content,
                    expands: true,
                    maxLines: null,
                    minLines: null,
                    textAlignVertical: TextAlignVertical.top,
                    keyboardType: TextInputType.multiline,
                    autocorrect: false,
                    enableSuggestions: false,
                    style: ax.typo.mono.copyWith(color: c.text),
                    decoration: const InputDecoration(labelText: 'Script', alignLabelWithHint: true),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
