import 'package:flutter_test/flutter_test.dart';

import 'test_utils.dart';

void main() {
  testWidgets('App shell renders the Home screen by default', (WidgetTester tester) async {
    await pumpAppShell(tester);

    expect(find.text('Home'), findsWidgets);
    expect(find.text('Archangel'), findsOneWidget);
  });
}
