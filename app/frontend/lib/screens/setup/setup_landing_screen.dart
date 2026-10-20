import 'package:flutter/material.dart';

import '../../ui/screens/setup/get_server_screen.dart';
import '../../ui/screens/setup/setup_widgets.dart';
import '../../ui/ui.dart';
import '../../widgets/pairing_dialog.dart';
import 'setup_wizard_screen.dart';

/// First screen shown when neither the WireGuard tunnel nor the backend
/// connection is paired: "Do you have a server?" with three ways forward -
/// set up a server from scratch (the wizard), pair with a code from an
/// already-running server (also how a second device joins), or learn how to
/// get a server.
class SetupLandingScreen extends StatelessWidget {
  const SetupLandingScreen({super.key, this.canCancel = false});

  /// True when opened from the server switcher ("Add a server") on top of
  /// the running app, so it can be closed again.
  final bool canCancel;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    return AxBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar:
            canCancel
                ? AppBar(
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  scrolledUnderElevation: 0,
                  title: Text('Add a server', style: ax.typo.title.copyWith(color: c.text)),
                )
                : null,
        body: SafeArea(
          child: SetupFrame(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: canCancel ? 0 : ax.space.xl),
                if (!canCancel) ...[
                  const Align(alignment: Alignment.centerLeft, child: AxWordmark(size: 20)),
                  SizedBox(height: ax.space.xxl),
                ],
                Text('Welcome to Archangel OS', style: ax.typo.caption.copyWith(color: c.textMuted, fontSize: 13)),
                SizedBox(height: ax.space.sm),
                Semantics(header: true, child: Text('Do you have a server?', style: ax.typo.display.copyWith(color: c.text))),
                SizedBox(height: ax.space.sm),
                Text(
                  'Archangel turns a small rented server into your own private cloud, guarded 24/7. Pick the option that fits you.',
                  style: ax.typo.body.copyWith(color: c.textMuted),
                ),
                SizedBox(height: ax.space.xl),
                _Option(
                  icon: Icons.auto_fix_high_outlined,
                  title: 'Yes, set it up for me',
                  body: 'Give Archangel your server\'s address and SSH key. It installs everything and connects this device.',
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SetupWizardScreen())),
                ),
                SizedBox(height: ax.space.md),
                _Option(
                  icon: Icons.qr_code_2,
                  title: 'I have a pairing code',
                  body: 'Your server is already running Archangel and you have a code from it. Also use this to add another device.',
                  onTap: () async {
                    final paired = await showPairingDialog(context);
                    if (paired && canCancel && context.mounted) Navigator.of(context).pop();
                  },
                ),
                SizedBox(height: ax.space.md),
                _Option(
                  icon: Icons.cloud_outlined,
                  title: 'Not yet — show me how to get one',
                  body: 'What a server is, what it costs, and guides for getting one in a few minutes.',
                  onTap:
                      () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder:
                              (ctx) => GetServerScreen(
                                onHaveServer:
                                    () => Navigator.of(
                                      ctx,
                                    ).pushReplacement(MaterialPageRoute<void>(builder: (_) => const SetupWizardScreen())),
                              ),
                        ),
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

class _Option extends StatelessWidget {
  const _Option({required this.icon, required this.title, required this.body, required this.onTap});

  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    return AxCard(
      onTap: onTap,
      semanticsLabel: title,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: c.accentWash, borderRadius: BorderRadius.circular(ax.radii.md)),
            child: Icon(icon, color: c.accent, size: 22),
          ),
          SizedBox(width: ax.space.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: ax.typo.title.copyWith(color: c.text)),
                SizedBox(height: ax.space.xs),
                Text(body, style: ax.typo.body.copyWith(color: c.textMuted)),
              ],
            ),
          ),
          SizedBox(width: ax.space.sm),
          Icon(Icons.chevron_right, color: c.textMuted),
        ],
      ),
    );
  }
}
