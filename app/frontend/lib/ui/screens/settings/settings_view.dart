import 'package:flutter/material.dart';

import '../../ui.dart';
import 'about_section.dart';
import 'devices_admin_sections.dart';
import 'other_sections.dart';
import 'servers_section.dart';

/// The Settings sections, in the order they are listed.
enum SettingsSectionId {
  about('About', Icons.auto_awesome_rounded),
  servers('Servers', Icons.dns_outlined),
  devices('Devices', Icons.devices_outlined),
  admin('Admin mode', Icons.key_outlined),
  security('Security', Icons.shield_outlined),
  appearance('Appearance', Icons.light_mode_outlined),
  system('System', Icons.tune_rounded);

  const SettingsSectionId(this.label, this.icon);
  final String label;
  final IconData icon;

  /// Devices and Admin mode only exist once a server is paired.
  bool get needsPairing => this == devices || this == admin;

  Widget get content => switch (this) {
    about => const ArchangelOsSection(),
    servers => const ServersSection(),
    devices => const DevicesSection(),
    admin => const AdminModeSection(),
    security => const SecuritySection(),
    appearance => const AppearanceSection(),
    system => const SystemSection(),
  };
}

/// Below this width Settings shows the list and one section at a time.
const double kSettingsWideMinWidth = 720;

/// Settings laid out for the width it is given: a section list beside the
/// chosen section when wide, or the list and then one section when narrow.
class SettingsView extends StatefulWidget {
  const SettingsView({super.key, required this.paired, required this.version});

  final bool paired;
  final String version;

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  SettingsSectionId _selected = SettingsSectionId.about;

  /// Narrow only: whether the chosen section is open (instead of the list).
  bool _opened = false;

  List<SettingsSectionId> get _visible => [
    for (final s in SettingsSectionId.values)
      if (!s.needsPairing || widget.paired) s,
  ];

  List<SettingsSectionId> get _serverSettings => [
    for (final s in [SettingsSectionId.servers, SettingsSectionId.devices, SettingsSectionId.admin, SettingsSectionId.security])
      if (!s.needsPairing || widget.paired) s,
  ];

  List<SettingsSectionId> get _systemSettings => const [SettingsSectionId.appearance, SettingsSectionId.system];

  SettingsSectionId get _current => _visible.contains(_selected) ? _selected : SettingsSectionId.about;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth >= kSettingsWideMinWidth ? _wide(context) : _narrow(context),
    );
  }

  Widget _wide(BuildContext context) {
    final ax = context.ax;
    final width = MediaQuery.sizeOf(context).width;
    final pad = AxPage.paddingFor(width);

    return SingleChildScrollView(
      padding: EdgeInsets.all(pad),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 220,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AxCard(
                      padding: EdgeInsets.all(ax.space.xs),
                      child: _NavRow(
                        key: const ValueKey('settings-nav-about'),
                        section: SettingsSectionId.about,
                        selected: _current == SettingsSectionId.about,
                        onTap: () => setState(() => _selected = SettingsSectionId.about),
                      ),
                    ),
                    SizedBox(height: ax.space.sm),
                    AxCard(
                      padding: EdgeInsets.all(ax.space.sm),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final s in _serverSettings)
                            _NavRow(
                              key: ValueKey('settings-nav-${s.name}'),
                              section: s,
                              selected: s == _current,
                              onTap: () => setState(() => _selected = s),
                            ),
                        ],
                      ),
                    ),
                    SizedBox(height: ax.space.sm),
                    AxCard(
                      padding: EdgeInsets.all(ax.space.sm),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final s in _systemSettings)
                            _NavRow(
                              key: ValueKey('settings-nav-${s.name}'),
                              section: s,
                              selected: s == _current,
                              onTap: () => setState(() => _selected = s),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: ax.space.lg),
              Expanded(child: _current.content),
            ],
          ),
        ),
      ),
    );
  }

  Widget _narrow(BuildContext context) {
    final ax = context.ax;
    if (!_opened) {
      final width = MediaQuery.sizeOf(context).width;
      final pad = AxPage.paddingFor(width);
      return SingleChildScrollView(
        padding: EdgeInsets.all(pad),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AxCard(
                  padding: EdgeInsets.all(ax.space.xs),
                  child: _NavRow(
                    key: const ValueKey('settings-nav-about'),
                    section: SettingsSectionId.about,
                    selected: false,
                    chevron: true,
                    onTap:
                        () => setState(() {
                          _selected = SettingsSectionId.about;
                          _opened = true;
                        }),
                  ),
                ),
                SizedBox(height: ax.space.sm),
                AxCard(
                  padding: EdgeInsets.all(ax.space.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final s in _serverSettings)
                        _NavRow(
                          key: ValueKey('settings-nav-${s.name}'),
                          section: s,
                          selected: false,
                          chevron: true,
                          onTap:
                              () => setState(() {
                                _selected = s;
                                _opened = true;
                              }),
                        ),
                    ],
                  ),
                ),
                SizedBox(height: ax.space.sm),
                AxCard(
                  padding: EdgeInsets.all(ax.space.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final s in _systemSettings)
                        _NavRow(
                          key: ValueKey('settings-nav-${s.name}'),
                          section: s,
                          selected: false,
                          chevron: true,
                          onTap:
                              () => setState(() {
                                _selected = s;
                                _opened = true;
                              }),
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
    final section = _current;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _opened = false);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.only(left: ax.space.sm, top: ax.space.sm),
            child: Align(
              alignment: Alignment.centerLeft,
              child: AxButton.ghost(label: 'All settings', icon: Icons.chevron_left, onPressed: () => setState(() => _opened = false)),
            ),
          ),
          Expanded(child: AxPage(title: section.label, child: section.content)),
        ],
      ),
    );
  }
}

/// One row of the section list: icon and label, with a chevron when narrow.
class _NavRow extends StatelessWidget {
  const _NavRow({super.key, required this.section, required this.selected, required this.onTap, this.chevron = false});

  final SettingsSectionId section;
  final bool selected;
  final bool chevron;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final fg = selected ? c.accent : c.text;
    final height = chevron ? (axMinTarget(context) + 8) : 42.0;
    final radius = BorderRadius.circular(12);
    return Semantics(
      button: true,
      selected: selected,
      label: section.label,
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: selected ? c.accentWash : Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Container(
            height: height,
            padding: EdgeInsets.symmetric(horizontal: ax.space.md),
            child: Row(
              children: [
                Icon(section.icon, size: 20, color: selected ? c.accent : c.textMuted),
                SizedBox(width: ax.space.md),
                Expanded(
                  child: Text(section.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: ax.typo.label.copyWith(color: fg)),
                ),
                if (chevron) Icon(Icons.chevron_right, size: 20, color: c.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
