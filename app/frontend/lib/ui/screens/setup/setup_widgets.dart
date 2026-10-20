import 'package:flutter/material.dart';

import '../../ui.dart';

/// Max width of setup content on desktop.
const double kSetupMaxWidth = 640;

/// Centers [child] in a column no wider than [kSetupMaxWidth] with the
/// standard responsive padding. Scrolls when [scrollable].
class SetupFrame extends StatelessWidget {
  const SetupFrame({super.key, required this.child, this.scrollable = true});

  final Widget child;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final pad = AxPage.paddingFor(constraints.maxWidth);
        final padded = Padding(padding: EdgeInsets.all(pad), child: child);
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kSetupMaxWidth),
            child: scrollable ? SingleChildScrollView(child: padded) : padded,
          ),
        );
      },
    );
  }
}

/// A screen heading: title, optional explanation.
class SetupHeading extends StatelessWidget {
  const SetupHeading({super.key, required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(header: true, child: Text(title, style: ax.typo.headline.copyWith(color: c.text))),
        if (subtitle != null)
          Padding(padding: EdgeInsets.only(top: ax.space.sm), child: Text(subtitle!, style: ax.typo.body.copyWith(color: c.textMuted))),
      ],
    );
  }
}

/// An icon followed by wrapped text, used for lists of facts or steps.
class SetupBullet extends StatelessWidget {
  const SetupBullet({super.key, required this.text, this.icon = Icons.check_circle_outline, this.iconColor});

  final String text;
  final IconData icon;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: ax.space.xs + 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(top: 2), child: Icon(icon, size: 18, color: iconColor ?? c.accent)),
          SizedBox(width: ax.space.md),
          Expanded(child: Text(text, style: ax.typo.body.copyWith(color: c.text))),
        ],
      ),
    );
  }
}

/// Explains where an SSH key lives and how to make one.
Future<void> showSshKeyHelp(BuildContext context) {
  return showHelpSheet(
    context,
    title: 'How do I get an SSH key?',
    message:
        'An SSH key is a pair of files that work like a very long password. The "private" file stays with you; '
        'the "public" half is installed on your server so it recognises you.\n\n'
        'If your hosting provider gave you a key when you created the server, it is the file you downloaded '
        '(often ending in .pem or .key). That file is the private key.\n\n'
        'Your own key is usually here:\n'
        '  Mac or Linux: ~/.ssh/id_ed25519\n'
        '  Windows: C:\\Users\\<you>\\.ssh\\id_ed25519\n'
        'Open it in a text editor and copy everything, including the BEGIN and END lines. '
        '(The file ending in .pub is the public half. Do not paste that one.)\n\n'
        'No key yet? Open a terminal and run:\n'
        '  ssh-keygen -t ed25519\n'
        'Then add the contents of the .pub file to your server in your provider\'s "SSH keys" page. '
        'This must be done when the server is created, or through your provider\'s console afterwards.',
  );
}

/// Step-by-step help for opening UDP 51820 at the provider's own network
/// firewall. Provider order is deliberately alphabetical-ish and neutral.
class ProviderFirewallHelp extends StatelessWidget {
  const ProviderFirewallHelp({super.key, this.port = 51820});

  final int port;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final steps = <(String, List<String>)>[
      (
        'AWS (EC2)',
        [
          'EC2 Console, Instances, select your instance, Security tab.',
          'Click the security group listed there.',
          'Edit inbound rules, add a rule: Type "Custom UDP", Port range $port, Source 0.0.0.0/0.',
          'Save rules.',
        ],
      ),
      (
        'DigitalOcean',
        [
          'Control panel, Networking, Firewalls.',
          'Create (or edit) a firewall and attach it to your droplet.',
          'Add an inbound rule: Type UDP, Port $port, Sources: All IPv4 and All IPv6.',
          'Save.',
        ],
      ),
      (
        'Hetzner',
        [
          'Cloud Console, your project, Firewalls.',
          'Create a firewall (or open the one attached to your server).',
          'Add an inbound rule: Protocol UDP, Port $port, Source Any.',
          'Apply the firewall to your server.',
        ],
      ),
      (
        'Oracle Cloud (OCI)',
        [
          'Console, Networking, Virtual Cloud Networks, open your VCN.',
          'Open the subnet your instance is in, then its Security List.',
          'Add an Ingress Rule: Source CIDR 0.0.0.0/0, IP Protocol UDP, Destination Port Range $port.',
          'Save. It takes effect immediately.',
        ],
      ),
      (
        'Any other provider',
        [
          'Find the "network firewall", "security group" or "cloud firewall" section in your provider\'s console. '
              'It is separate from anything set up on the server itself.',
          'Allow incoming UDP traffic on port $port from any source.',
          'Save or apply the change.',
        ],
      ),
    ];

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: Material(
        type: MaterialType.transparency,
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: EdgeInsets.only(bottom: ax.space.md),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          iconColor: c.accent,
          collapsedIconColor: c.textMuted,
          title: Text('How do I open UDP port $port at my provider?', style: ax.typo.label.copyWith(color: c.text)),
          children: [
            for (final (provider, list) in steps) ...[
              Padding(
                padding: EdgeInsets.only(top: ax.space.sm, bottom: ax.space.xs),
                child: Text(provider, style: ax.typo.label.copyWith(color: c.text)),
              ),
              for (var i = 0; i < list.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 22, child: Text('${i + 1}.', style: ax.typo.caption.copyWith(color: c.textMuted))),
                      Expanded(child: Text(list[i], style: ax.typo.caption.copyWith(color: c.textMuted))),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
