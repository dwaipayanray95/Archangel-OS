import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../services/archangeld_connection.dart';
import '../services/pairing_bundle.dart';
import '../services/server_registry.dart';
import '../services/wireguard_controller.dart';
import '../ui/ui.dart';

/// The one pairing dialog every entry point (Settings' "Pair device",
/// Terminal's "No backend paired" prompt, the welcome screen) uses.
/// `archangeld pair` outputs a single bundle carrying both the secure
/// connection and the server login - see PairingBundle and
/// app/backend/README.md.
///
/// Every platform can paste the code `archangeld pair` printed. Android
/// additionally gets a camera scan button for its QR output
/// (`archangeld pair <name> --qr`) - other platforms don't get a camera
/// option since scanning a QR code off a phone screen with a laptop
/// webcam isn't a real workflow.
///
/// Resolves to true when a server was paired (added to the
/// [ServerRegistry] and made active), false if the dialog was cancelled.
Future<bool> showPairingDialog(BuildContext context) async {
  final wg = context.read<WireGuardController>();
  final backend = context.read<ArchangeldConnection>();
  final registry = context.read<ServerRegistry>();
  var paired = false;
  final controller = TextEditingController();
  String? error;
  var busy = false;

  await showDialog<void>(
    context: context,
    builder:
        (context) => StatefulBuilder(
          builder: (context, setState) {
            final ax = context.ax;
            final c = ax.colors;

            Future<void> submit(String raw) async {
              if (busy) return;
              if (raw.trim().isEmpty) {
                setState(() => error = 'Paste the pairing code first.');
                return;
              }
              setState(() {
                busy = true;
                error = null;
              });
              try {
                final bundle = PairingBundle.parse(raw);
                await pairNewServer(registry: registry, wg: wg, backend: backend, bundle: bundle);
                paired = true;
                if (context.mounted) {
                  Navigator.of(context).pop();
                  if (Platform.isMacOS && !wg.isMacosHelperInstalled) {
                    _promptEnableSeamlessTunnel(context, wg);
                  }
                }
              } on FormatException catch (e) {
                if (context.mounted) setState(() => error = 'That does not look like a pairing code. ${e.message}');
              } catch (e) {
                if (context.mounted) setState(() => error = 'Pairing failed: $e');
              } finally {
                if (!paired && context.mounted) setState(() => busy = false);
              }
            }

            Future<void> scan() async {
              final result = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const _QrScanPage()));
              if (result != null) {
                controller.text = result;
                await submit(result);
              }
            }

            const command = 'sudo /opt/archangel/archangeld pair <name>';
            return AlertDialog(
              backgroundColor: c.surface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ax.radii.lg), side: BorderSide(color: c.border)),
              title: Text('Pair with a code', style: ax.typo.title.copyWith(color: c.text)),
              content: SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'A pairing code connects this device to a server that already runs Archangel. '
                        'You can create one on another device that is already paired: open Settings, then Devices, '
                        'then "Add a device". Or sign in to the server and run this (use any name for this device):',
                        style: ax.typo.body.copyWith(color: c.textMuted),
                      ),
                      SizedBox(height: ax.space.sm),
                      Container(
                        padding: EdgeInsets.only(left: ax.space.md),
                        decoration: BoxDecoration(
                          color: c.surfaceAlt,
                          borderRadius: BorderRadius.circular(ax.radii.sm),
                          border: Border.all(color: c.border),
                        ),
                        child: Row(
                          children: [
                            Expanded(child: SelectableText(command, style: ax.typo.mono.copyWith(color: c.text))),
                            AxIconButton(
                              icon: Icons.copy,
                              tooltip: 'Copy command',
                              onPressed: () => Clipboard.setData(const ClipboardData(text: command)),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: ax.space.md),
                      TextField(
                        controller: controller,
                        maxLines: 6,
                        enabled: !busy,
                        autocorrect: false,
                        enableSuggestions: false,
                        style: ax.typo.mono.copyWith(color: c.text),
                        decoration: const InputDecoration(
                          labelText: 'Pairing code',
                          hintText: 'Paste the pairing code here',
                          alignLabelWithHint: true,
                        ),
                      ),
                      if (Platform.isAndroid) ...[
                        SizedBox(height: ax.space.sm),
                        AxButton.ghost(label: 'Scan QR code instead', icon: Icons.qr_code_scanner, onPressed: busy ? null : scan),
                      ],
                      if (error != null)
                        Padding(
                          padding: EdgeInsets.only(top: ax.space.md),
                          child: Semantics(
                            liveRegion: true,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.error_outline, size: 18, color: c.danger),
                                SizedBox(width: ax.space.sm),
                                Expanded(child: Text(error!, style: ax.typo.body.copyWith(color: c.danger))),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              actionsOverflowButtonSpacing: ax.space.sm,
              actions: [
                AxButton.secondary(label: 'Cancel', onPressed: busy ? null : () => Navigator.of(context).pop()),
                AxButton(label: 'Pair', loading: busy, onPressed: () => submit(controller.text)),
              ],
            );
          },
        ),
  );
  controller.dispose();
  return paired;
}

void _promptEnableSeamlessTunnel(BuildContext context, WireGuardController wg) {
  showDialog<void>(
    context: context,
    builder: (ctx) {
      final ax = ctx.ax;
      final c = ax.colors;
      return AlertDialog(
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ax.radii.lg), side: BorderSide(color: c.border)),
        title: Row(
          children: [
            Icon(Icons.shield_outlined, size: 20, color: c.accent),
            SizedBox(width: ax.space.sm),
            Expanded(child: Text('Connect without asking each time', style: ax.typo.title.copyWith(color: c.text))),
          ],
        ),
        content: Text(
          'Archangel needs a one-time permission to control the secure connection (a VPN tunnel) without prompting you every time.',
          style: ax.typo.body.copyWith(color: c.textMuted),
        ),
        actions: [
          AxButton.secondary(label: 'Maybe later', onPressed: () => Navigator.of(ctx).pop()),
          AxButton(
            label: 'Allow',
            onPressed: () async {
              Navigator.of(ctx).pop();
              await wg.installMacosHelper();
            },
          ),
        ],
      );
    },
  );
}

class _QrScanPage extends StatefulWidget {
  const _QrScanPage();

  @override
  State<_QrScanPage> createState() => _QrScanPageState();
}

class _QrScanPageState extends State<_QrScanPage> {
  bool _handled = false;

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    if (capture.barcodes.isEmpty) return;
    final value = capture.barcodes.first.rawValue;
    if (value == null || value.isEmpty) return;
    _handled = true;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(backgroundColor: c.bg, title: Text('Scan pairing QR code', style: ax.typo.title.copyWith(color: c.text))),
      body: Stack(
        children: [
          MobileScanner(onDetect: _onDetect),
          Positioned(
            left: ax.space.lg,
            right: ax.space.lg,
            bottom: ax.space.xl,
            child: Container(
              padding: EdgeInsets.all(ax.space.md),
              decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(ax.radii.md)),
              child: Text(
                'Point the camera at the QR code shown by "archangeld pair <name> --qr" on your server.',
                style: ax.typo.body.copyWith(color: c.text),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
