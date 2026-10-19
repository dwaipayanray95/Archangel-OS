import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/app_state.dart';
import '../services/monitoring_service.dart';
import '../theme/tokens.dart';
import 'ax_widgets.dart';

const _navIcons = <AxSection, IconData>{
  AxSection.overview: Icons.grid_view_rounded,
  AxSection.monitoring: Icons.show_chart_rounded,
  AxSection.files: Icons.folder_outlined,
  AxSection.containers: Icons.view_in_ar_outlined,
  AxSection.devops: Icons.settings_ethernet_rounded,
  AxSection.terminal: Icons.chevron_right_rounded,
  AxSection.settings: Icons.tune_rounded,
};

/// Title and subtitle for the sidebar's host card, from live metrics only.
(String, String) hostSummary(MonitoringService mon) {
  final m = mon.metrics;
  if (m == null) {
    return mon.status == MonitoringStatus.connecting ? ('Connecting…', '') : ('Not connected', '');
  }
  final parts = <String>[
    if (m.host.os.isNotEmpty) m.host.os,
    if (m.cpu.cores.isNotEmpty) '${m.cpu.cores.length} vCPU',
  ];
  return (m.host.hostname.isNotEmpty ? m.host.hostname : 'Connected', parts.join(' · '));
}

/// Left rail app-switcher shown at desktop widths — the second half of the
/// "OS-like" shell alongside the persistent top bar.
class Sidebar extends StatelessWidget {
  const Sidebar({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final mon = context.watch<MonitoringService>();
    final (title, subtitle) = hostSummary(mon);
    return Container(
      width: 206,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 11),
      decoration: const BoxDecoration(
        color: AxColors.s1,
        border: Border(right: BorderSide(color: AxColors.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final s in AxSection.values)
            _NavItem(section: s, selected: app.section == s, onTap: () => app.go(s)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              color: AxColors.s2,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AxColors.line),
            ),
            child: Row(
              children: [
                StatusDot(
                  color: mon.isConnected ? app.accent : (mon.status == MonitoringStatus.connecting ? AxColors.warn : AxColors.fg3),
                  size: 7,
                  pulse: mon.isConnected,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title, style: AxTextStyles.mono.copyWith(fontSize: 11.5, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
                      Text(subtitle, style: AxTextStyles.sans.copyWith(fontSize: 10.5, color: AxColors.fg3), overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatefulWidget {
  final AxSection section;
  final bool selected;
  final VoidCallback onTap;
  const _NavItem({required this.section, required this.selected, required this.onTap});

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final accent = context.watch<AppState>().accent;
    final label = axSectionLabels[widget.section]!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: -9,
                top: 0,
                bottom: 0,
                child: AnimatedContainer(
                  duration: AxMotion.base,
                  curve: AxMotion.easeOutSnap,
                  width: 2.5,
                  margin: widget.selected ? const EdgeInsets.symmetric(vertical: 6) : const EdgeInsets.symmetric(vertical: 18),
                  decoration: BoxDecoration(
                    color: widget.selected ? accent : Colors.transparent,
                    borderRadius: const BorderRadius.horizontal(right: Radius.circular(3)),
                  ),
                ),
              ),
              AnimatedContainer(
                duration: AxMotion.base,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: widget.selected ? AxColors.s2 : (_hover ? AxColors.s3 : Colors.transparent),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Row(
                  children: [
                    Icon(_navIcons[widget.section], size: 16, color: widget.selected ? AxColors.fg : AxColors.fg2),
                    const SizedBox(width: 10),
                    Text(
                      label,
                      style: AxTextStyles.sans.copyWith(
                        fontSize: 13.5,
                        fontWeight: widget.selected ? FontWeight.w700 : FontWeight.w500,
                        color: widget.selected ? AxColors.fg : AxColors.fg2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom tab bar shown at phone widths in place of the sidebar.
class BottomTabs extends StatelessWidget {
  const BottomTabs({super.key});

  static const _tabs = [AxSection.overview, AxSection.monitoring, AxSection.files, AxSection.containers, AxSection.terminal];

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 9),
      decoration: const BoxDecoration(
        color: AxColors.s1,
        border: Border(top: BorderSide(color: AxColors.line)),
      ),
      child: Row(
        children: [
          for (final s in _tabs)
            Expanded(
              child: GestureDetector(
                onTap: () => app.go(s),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: [
                      Icon(_navIcons[s], size: 19, color: app.section == s ? app.accent : AxColors.fg3),
                      const SizedBox(height: 3),
                      Text(axSectionLabels[s]!, style: AxTextStyles.sans.copyWith(fontSize: 9.5, fontWeight: FontWeight.w600, color: app.section == s ? app.accent : AxColors.fg3)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
