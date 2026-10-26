import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../services/devices_service.dart';
import '../../ui.dart';

/// "Add a device": asks for a name, has the server create a pairing code for
/// it and shows that code once as a QR code and as text. The device list is
/// refreshed when the dialog closes.
Future<void> showAddDeviceDialog(BuildContext context) async {
  final devices = context.read<DevicesService>();
  await showDialog<void>(context: context, barrierDismissible: false, builder: (_) => const AddDeviceDialog());
  await devices.refresh();
}

class AddDeviceDialog extends StatefulWidget {
  const AddDeviceDialog({super.key});

  @override
  State<AddDeviceDialog> createState() => _AddDeviceDialogState();
}

class _AddDeviceDialogState extends State<AddDeviceDialog> {
  final _name = TextEditingController();
  bool _creating = false;
  String? _error;
  DeviceCreateResult? _result;
  bool _copied = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final problem = DevicesService.validateDeviceName(_name.text);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _creating = true;
      _error = null;
    });
    final res = await context.read<DevicesService>().create(_name.text.trim());
    if (!mounted) return;
    setState(() {
      _creating = false;
      if (res.success) {
        _result = res;
      } else {
        _error = res.message;
      }
    });
  }

  Future<void> _copy(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (mounted) setState(() => _copied = true);
  }

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final result = _result;
    return AlertDialog(
      scrollable: true,
      title: Text(result == null ? 'Add a device' : 'Pair "${result.name}"', style: ax.typo.title.copyWith(color: c.text)),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: result == null ? _nameStep(ax) : _codeStep(ax, result.bundle!),
      ),
      actions: result == null
          ? [
              AxButton.ghost(label: 'Cancel', onPressed: _creating ? null : () => Navigator.of(context).pop()),
              AxButton(label: 'Create pairing code', loading: _creating, onPressed: _create),
            ]
          : [AxButton(label: 'Done', onPressed: () => Navigator.of(context).pop())],
    );
  }

  Widget _nameStep(ArchangelTheme ax) {
    final c = ax.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Another phone or computer can use this server too. Name it so you can tell your devices apart, '
          'then the server makes a one-time pairing code for it.',
          style: ax.typo.body.copyWith(color: c.textMuted),
        ),
        SizedBox(height: ax.space.lg),
        TextField(
          controller: _name,
          autofocus: true,
          enabled: !_creating,
          maxLength: 32,
          autocorrect: false,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _create(),
          decoration: const InputDecoration(labelText: 'Device name', hintText: 'Maria\'s phone'),
        ),
        if (_error != null)
          Padding(
            padding: EdgeInsets.only(top: ax.space.sm),
            child: Semantics(
              liveRegion: true,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline, size: 18, color: c.danger),
                  SizedBox(width: ax.space.sm),
                  Expanded(
                    child: Text(_error!, style: ax.typo.body.copyWith(color: c.danger)),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _codeStep(ArchangelTheme ax, String code) {
    final c = ax.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
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
                child: Text(
                  'Anyone with this code can access your server — don\'t share it. It\'s only shown now.',
                  style: ax.typo.body.copyWith(color: c.text, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: ax.space.lg),
        Center(
          child: Semantics(
            label: 'QR code with the pairing code',
            image: true,
            child: Container(
              // QR scanners need dark modules on a light quiet zone in both
              // themes, so this is deliberately not themed.
              padding: EdgeInsets.all(ax.space.lg),
              color: Colors.white,
              // Fixed size: AlertDialog measures intrinsic widths, which QrImageView's
              // LayoutBuilder cannot answer.
              child: SizedBox(
                width: 220,
                height: 220,
                child: QrImageView(
                  data: code,
                  size: 220,
                  padding: EdgeInsets.zero,
                  backgroundColor: Colors.white,
                  errorCorrectionLevel: QrErrorCorrectLevel.L,
                  eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Colors.black),
                  dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Colors.black),
                ),
              ),
            ),
          ),
        ),
        SizedBox(height: ax.space.lg),
        Text('Or copy the code', style: ax.typo.label.copyWith(color: c.text)),
        SizedBox(height: ax.space.xs),
        Container(
          padding: EdgeInsets.all(ax.space.md),
          constraints: const BoxConstraints(maxHeight: 120),
          decoration: BoxDecoration(
            color: c.surfaceAlt,
            borderRadius: BorderRadius.circular(ax.radii.md),
            border: Border.all(color: c.border),
          ),
          child: SingleChildScrollView(
            child: SelectableText(code, style: ax.typo.mono.copyWith(color: c.text)),
          ),
        ),
        SizedBox(height: ax.space.sm),
        Align(
          alignment: Alignment.centerLeft,
          child: AxButton.secondary(
            label: _copied ? 'Copied' : 'Copy code',
            icon: _copied ? Icons.check : Icons.copy,
            onPressed: () => _copy(code),
          ),
        ),
        SizedBox(height: ax.space.lg),
        Text('On the new device', style: ax.typo.label.copyWith(color: c.text)),
        SizedBox(height: ax.space.xs),
        Text(
          'Install Archangel, choose "I have a pairing code", then scan this QR code (Android) or paste the code.',
          style: ax.typo.body.copyWith(color: c.textMuted),
        ),
      ],
    );
  }
}
