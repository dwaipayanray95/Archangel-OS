import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import '../../widgets/archangel_mark.dart';
import '../../widgets/ax_widgets.dart';
import '../../widgets/pairing_dialog.dart';
import 'setup_wizard_screen.dart';

/// First screen shown when neither the WireGuard tunnel nor the backend
/// connection is paired: choose between bootstrapping a brand-new VPS
/// (the setup wizard) or pairing this device to a server that's already
/// running (the existing paste/QR dialog, unchanged) - so pairing a
/// *second* device isn't forced through the wizard.
class SetupLandingScreen extends StatelessWidget {
  const SetupLandingScreen({super.key, this.canCancel = false});

  /// True when opened from the server switcher ("Add a server") on top of
  /// the running app, so it can be closed again.
  final bool canCancel;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AxColors.bg,
      appBar: canCancel
          ? AppBar(
              backgroundColor: AxColors.bg,
              elevation: 0,
              title: const Text('Add a server'),
            )
          : null,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Align(alignment: Alignment.centerLeft, child: ArchangelMark(size: 34, tile: true)),
                const SizedBox(height: 16),
                Text(
                  'Archangel',
                  style: AxTextStyles.sans.copyWith(fontSize: 28, fontWeight: FontWeight.w700, color: AxColors.fg),
                ),
                const SizedBox(height: 6),
                Text(
                  'Get your server connected.',
                  style: AxTextStyles.sans.copyWith(fontSize: 14, color: AxColors.fg2),
                ),
                const SizedBox(height: 32),
                AxCard(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SetupWizardScreen()),
                  ),
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Icon(Icons.dns_outlined, color: AxColors.accent, size: 28),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Set up a new server', style: AxTextStyles.sans.copyWith(fontSize: 15, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 4),
                            Text(
                              'Point Archangel at a fresh VPS and an SSH key - it installs and pairs everything for you.',
                              style: AxTextStyles.sans.copyWith(fontSize: 12.5, color: AxColors.fg2, height: 1.4),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.chevron_right, color: AxColors.fg3),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                AxCard(
                  onTap: () async {
                    final paired = await showPairingDialog(context);
                    if (paired && canCancel && context.mounted) Navigator.of(context).pop();
                  },
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Icon(Icons.qr_code_2, color: AxColors.fg2, size: 28),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('I already have a pairing code', style: AxTextStyles.sans.copyWith(fontSize: 15, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 4),
                            Text(
                              'From `archangeld pair` on a server that\'s already set up.',
                              style: AxTextStyles.sans.copyWith(fontSize: 12.5, color: AxColors.fg2, height: 1.4),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.chevron_right, color: AxColors.fg3),
                    ],
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
