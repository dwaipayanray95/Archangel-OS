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
    return Scaffold(
      backgroundColor: c.bg,
      appBar: canCancel
          ? AppBar(
              backgroundColor: c.bg,
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
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: EdgeInsets.all(ax.space.md),
                  decoration: BoxDecoration(color: c.accentWash, borderRadius: BorderRadius.circular(ax.radii.md)),
                  child: Icon(Icons.shield_outlined, size: 32, color: c.accent, semanticLabel: 'Archangel'),
                ),
              ),
              SizedBox(height: ax.space.lg),
              Text('Welcome to Archangel', style: ax.typo.headline.copyWith(color: c.text)),
              SizedBox(height: ax.space.sm),
              Text(
                'Archangel lets you run and manage your own private server from your phone or computer.',
                style: ax.typo.body.copyWith(color: c.textMuted),
              ),
              SizedBox(height: ax.space.xl),
              Semantics(
                header: true,
                child: Text('Do you have a server?', style: ax.typo.title.copyWith(color: c.text)),
              ),
              SizedBox(height: ax.space.md),
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
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (ctx) => GetServerScreen(
                      onHaveServer: () => Navigator.of(ctx).pushReplacement(
                        MaterialPageRoute<void>(builder: (_) => const SetupWizardScreen()),
                      ),
                    ),
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
          Icon(icon, color: c.accent, size: 28),
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
