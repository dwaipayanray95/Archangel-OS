import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:archangel/screens/setup/setup_landing_screen.dart';
import 'package:archangel/ui/theme.dart';

// Tests SetupLandingScreen directly rather than through the full
// ArchangelApp -> _RootRouter path: that path depends on
// WireGuardController.bootstrap() resolving wireguard_flutter's
// initialize() plugin call, which has no mocked channel response in a
// bare test environment and never settles. The routing decision itself
// (_RootRouter in main.dart) is a small, easily-reasoned-about if/else
// on two public getters - this screen is the part actually worth
// covering with a widget test.
void main() {
  testWidgets('shows both setup options', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: const SetupLandingScreen(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Yes, set it up for me'), findsOneWidget);
    expect(find.text('I have a pairing code'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
