import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:archangel/data/app_state.dart';
import 'package:archangel/ui/shell/archangel_shell.dart';

import '../test_utils.dart';

/// Flutter's accessibility guidelines over every top-level destination at
/// phone size, in both themes. Screens render their offline/empty states
/// here (no server), which is also what a new user sees first.
void main() {
  const phone = Size(390, 844);

  for (final brightness in Brightness.values) {
    group('a11y (${brightness.name})', () {
      for (final overlay in ['Search', 'Notifications']) {
        testWidgets('$overlay overlay', (tester) async {
          final handle = tester.ensureSemantics();
          try {
            await pumpAppShell(tester, size: phone, brightness: brightness);
            final app = tester.element(find.byType(ArchangelShell)).read<AppState>();
            overlay == 'Search' ? app.openPalette() : app.toggleNotif();
            for (var i = 0; i < 5; i++) {
              await tester.pump(const Duration(milliseconds: 100));
            }
            await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
            await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
            await expectLater(tester, meetsGuideline(textContrastGuideline));
          } finally {
            handle.dispose();
          }
        });
      }
      for (final section in [...AxSection.values, null]) {
        final name = section == null ? 'More' : axSectionLabels[section]!;
        testWidgets(name, (tester) async {
          final handle = tester.ensureSemantics();
          try {
            await pumpAppShell(tester, size: phone, brightness: brightness);
            final app = tester.element(find.byType(ArchangelShell)).read<AppState>();
            if (section == null) {
              await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('More')));
            } else {
              app.go(section);
            }
            for (var i = 0; i < 5; i++) {
              await tester.pump(const Duration(milliseconds: 100));
            }

            await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
            await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
            await expectLater(tester, meetsGuideline(textContrastGuideline));
          } finally {
            handle.dispose();
          }
        });
      }
    });
  }
}
