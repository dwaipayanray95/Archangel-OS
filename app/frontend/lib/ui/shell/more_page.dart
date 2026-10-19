import 'package:flutter/material.dart';

import '../../data/app_state.dart';
import '../components/ax_card.dart';
import '../components/ax_list_tile.dart';
import '../components/ax_page.dart';
import '../theme.dart';
import 'destinations.dart';
import 'server_switcher.dart';

const _moreBlurbs = <AxSection, String>{
  AxSection.activity: 'How busy your server is: processor, memory, disk and network.',
  AxSection.services: 'Background programs, scheduled jobs, web addresses and scripts.',
  AxSection.settings: 'Servers, devices, security, appearance and updates.',
};

/// Phone-only "More" destination: the sections that don't fit in the bottom
/// bar, plus the server switcher.
class MorePage extends StatelessWidget {
  const MorePage({super.key, required this.onOpen});

  final void Function(AxSection section) onOpen;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    return AxPage(
      title: 'More',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text('Server', style: ax.typo.label.copyWith(color: ax.colors.textMuted)),
          ),
          SizedBox(height: ax.space.sm),
          AxCard(padding: EdgeInsets.all(ax.space.sm), child: const ServerList()),
          SizedBox(height: ax.space.xl),
          Semantics(
            header: true,
            child: Text('Manage', style: ax.typo.label.copyWith(color: ax.colors.textMuted)),
          ),
          SizedBox(height: ax.space.sm),
          AxCard(
            padding: EdgeInsets.all(ax.space.sm),
            child: Column(
              children: [
                for (final s in axMoreSections)
                  AxListTile(
                    key: ValueKey('more-${s.name}'),
                    title: axSectionLabels[s]!,
                    subtitle: _moreBlurbs[s],
                    leading: Icon(axSectionIcons[s]),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => onOpen(s),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
