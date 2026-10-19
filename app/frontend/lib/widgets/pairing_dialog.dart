import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../services/archangeld_connection.dart';
import '../services/pairing_bundle.dart';
import '../services/server_registry.dart';
import '../services/wireguard_controller.dart';
import '../theme/tokens.dart';
import 'ax_widgets.dart';

/// The one pairing dialog every entry point (Settings' "Pair device",
/// Terminal's "No backend paired" prompt) should use. Replaces the old
/// pair of separate dialogs (one for the wg-quick config, one for
/// host/token) now that `archangeld pair` outputs a single bundle
/// carrying both - see PairingBundle and app/backend/README.md.
///
/// Every platform can paste the bundle string `archangeld pair` printed.
/// Android additionally gets a camera scan button for its QR output
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

  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        Future<void> submit(String raw) async {
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
            setState(() => error = e.message);
          } catch (e) {
            setState(() => error = 'Pairing failed: $e');
          }
        }

        Future<void> scan() async {
          final result = await Navigator.of(context).push<String>(
            MaterialPageRoute(builder: (_) => const _QrScanPage()),
          );
          if (result != null) {
            controller.text = result;
            await submit(result);
          }
        }

        return AlertDialog(
          backgroundColor: AxColors.s2,
          title: Text('Pair device', style: AxTextStyles.sans.copyWith(fontSize: 15, fontWeight: FontWeight.w700)),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Paste the pairing code from `archangeld pair <name>` on the server. '
                  'It configures the WireGuard tunnel and the backend connection together.',
                  style: AxTextStyles.sans.copyWith(fontSize: 12, color: AxColors.fg2, height: 1.5),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: controller,
                  maxLines: 6,
                  style: AxTextStyles.mono.copyWith(fontSize: 12),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: AxColors.s1,
                    hintText: 'Paste the pairing code here',
                    hintStyle: AxTextStyles.mono.copyWith(fontSize: 11, color: AxColors.fg3),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  ),
                ),
                if (Platform.isAndroid) ...[
                  const SizedBox(height: 10),
                  AxGhostButton(label: 'Scan QR code instead', onTap: scan),
                ],
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(error!, style: AxTextStyles.mono.copyWith(fontSize: 11, color: AxColors.bad)),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
            TextButton(onPressed: () => submit(controller.text), child: const Text('Pair')),
          ],
        );
      },
    ),
  );
  return paired;
}

void _promptEnableSeamlessTunnel(BuildContext context, WireGuardController wg) {
  showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) {
        return AlertDialog(
          backgroundColor: AxColors.s2,
          title: Row(
            children: [
              Icon(Icons.shield_outlined, size: 18, color: AxColors.accent),
              const SizedBox(width: 8),
              Text('Seamless Tunnel', style: AxTextStyles.sans.copyWith(fontSize: 15, fontWeight: FontWeight.w700)),
            ],
          ),
          content: Text(
            'Archangel needs a one-time permission to control the VPN tunnel seamlessly without prompting you every time.',
            style: AxTextStyles.sans.copyWith(fontSize: 12.5, color: AxColors.fg2, height: 1.45),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Maybe later'),
            ),
            FilledButton.tonal(
              onPressed: () async {
                Navigator.of(ctx).pop();
                await wg.installMacosHelper();
              },
              child: const Text('Enable Seamless Tunnel'),
            ),
          ],
        );
      },
    ),
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
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Scan pairing QR code'),
      ),
      body: MobileScanner(onDetect: _onDetect),
    );
  }
}
