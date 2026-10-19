import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../services/build_config.dart';
import '../../ui.dart';
import 'setup_widgets.dart';

/// Where a provider's step-by-step guide lives on GitHub.
Uri providerGuideUri(String slug) => Uri.parse('https://github.com/$kGithubRepoSlug/blob/main/docs/guides/$slug.md');

class _Provider {
  const _Provider(this.name, this.slug, this.cost, this.note, {this.recommended = false});
  final String name;
  final String slug;
  final String cost;
  final String note;
  final bool recommended;
}

const _providers = [
  _Provider(
    'Oracle Cloud Always Free',
    'oracle-cloud',
    'Free',
    'A generous free server that stays free. Sign-up needs a card for verification, and popular regions can '
        'be full, so you may need to try again later.',
    recommended: true,
  ),
  _Provider(
    'Hetzner',
    'hetzner',
    'About 4 to 5 euros a month',
    'Simple, fast and cheap. Billed by the hour, so you can delete it any time.',
  ),
  _Provider(
    'DigitalOcean',
    'digitalocean',
    'About 6 US dollars a month',
    'Beginner-friendly control panel with very clear step-by-step screens.',
  ),
];

/// "Not yet - show me how to get one": explains what a server (VPS) is, what
/// it costs, and links to a guide per provider.
class GetServerScreen extends StatelessWidget {
  const GetServerScreen({super.key, this.onHaveServer});

  /// Called by "I have a server now". Defaults to popping back to the
  /// welcome screen.
  final VoidCallback? onHaveServer;

  Future<void> _open(BuildContext context, _Provider p) async {
    var ok = false;
    try {
      ok = await launchUrl(providerGuideUri(p.slug), mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open the guide. Visit ${providerGuideUri(p.slug)} in a browser.')),
      );
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
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text('Get a server', style: ax.typo.title.copyWith(color: c.text)),
      ),
      body: SetupFrame(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SetupHeading(
              title: 'What is a server?',
              subtitle: 'Archangel runs on a small computer that is always on and always connected to the internet. '
                  'Companies rent these out by the month. It is called a VPS (virtual private server). '
                  'You rent one, and Archangel sets everything up on it for you.',
            ),
            SizedBox(height: ax.space.sm),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'A small one is plenty and usually costs between free and about 6 US dollars a month.',
                    style: ax.typo.body.copyWith(color: c.textMuted),
                  ),
                ),
                const HelpTip(
                  title: 'VPS',
                  message: 'A VPS (virtual private server) is a slice of a big computer in a data centre that you rent. '
                      'It behaves like your own computer that you reach over the internet. '
                      'You can cancel any time and nothing is installed on your own devices.',
                ),
              ],
            ),
            SizedBox(height: ax.space.xl),
            Semantics(header: true, child: Text('Where to get one', style: ax.typo.title.copyWith(color: c.text))),
            SizedBox(height: ax.space.md),
            for (final p in _providers) ...[
              AxCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: ax.space.sm,
                      runSpacing: ax.space.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(p.name, style: ax.typo.title.copyWith(color: c.text)),
                        if (p.recommended) const StatusBadge.info('Recommended', icon: Icons.thumb_up_alt_outlined),
                      ],
                    ),
                    SizedBox(height: ax.space.xs),
                    Text(p.cost, style: ax.typo.label.copyWith(color: c.accent)),
                    SizedBox(height: ax.space.xs),
                    Text(p.note, style: ax.typo.body.copyWith(color: c.textMuted)),
                    SizedBox(height: ax.space.md),
                    AxButton.secondary(
                      label: 'Open guide',
                      icon: Icons.open_in_new,
                      semanticsLabel: 'Open the ${p.name} guide',
                      onPressed: () => _open(context, p),
                    ),
                  ],
                ),
              ),
              SizedBox(height: ax.space.md),
            ],
            SizedBox(height: ax.space.md),
            Semantics(header: true, child: Text('What you will need', style: ax.typo.title.copyWith(color: c.text))),
            SizedBox(height: ax.space.sm),
            const SetupBullet(text: 'A server running Ubuntu 22.04 or 24.04.'),
            Row(
              children: [
                const Expanded(
                  child: SetupBullet(text: 'An SSH key, so Archangel can sign in to it. Your provider usually helps you make one.'),
                ),
                AxIconButton(icon: Icons.help_outline, tooltip: 'How do I get an SSH key?', onPressed: () => showSshKeyHelp(context)),
              ],
            ),
            const SetupBullet(text: 'The server\'s public IP address, shown on your provider\'s server page.'),
            SizedBox(height: ax.space.xl),
            AxButton(
              label: 'I have a server now',
              icon: Icons.arrow_forward,
              expand: true,
              onPressed: onHaveServer ?? () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}
