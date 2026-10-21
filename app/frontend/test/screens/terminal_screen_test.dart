import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:archangel/data/app_state.dart';
import 'package:archangel/screens/terminal_screen.dart';
import 'package:archangel/services/admin_mode_service.dart';
import 'package:archangel/services/archangeld_connection.dart';
import 'package:archangel/services/server_registry.dart';
import 'package:archangel/ui/theme.dart';

import '../test_utils.dart';

void main() {
  testWidgets('TerminalScreen shows un-paired EmptyState when not paired', (tester) async {
    final backend = ArchangeldConnection();
    await tester.runAsync(() async {
      await useTempKvStore();
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: backend),
          ChangeNotifierProvider(create: (_) => AppState()),
          ChangeNotifierProvider(create: (_) => ServerRegistry()),
          ChangeNotifierProvider(create: (_) => AdminModeService()),
        ],
        child: MaterialApp(theme: buildTheme(Brightness.dark), home: const Scaffold(body: TerminalScreen())),
      ),
    );
    await tester.pump();

    expect(find.text('Connect to your server first'), findsOneWidget);
    expect(find.text('Pair with your server'), findsOneWidget);
  });
}
