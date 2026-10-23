import 'package:flutter_test/flutter_test.dart';
import 'package:archangel/services/hotkey_service.dart';

void main() {
  test('HotkeyService respects test environment and handles callbacks safely', () async {
    expect(HotkeyService.isDesktop, isFalse, reason: 'FLUTTER_TEST environment prevents native desktop hotkey binding');

    bool summonTriggered = false;
    bool terminalTriggered = false;
    bool serverTriggered = false;

    await HotkeyService.init(
      onSummonAction: () => summonTriggered = true,
      onQuickTerminalAction: () => terminalTriggered = true,
      onSwitchServerAction: () => serverTriggered = true,
    );

    expect(HotkeyService.onSummon, isNotNull);
    expect(HotkeyService.onQuickTerminal, isNotNull);
    expect(HotkeyService.onSwitchServer, isNotNull);

    HotkeyService.onSummon?.call();
    expect(summonTriggered, isTrue);

    HotkeyService.onQuickTerminal?.call();
    expect(terminalTriggered, isTrue);

    HotkeyService.onSwitchServer?.call();
    expect(serverTriggered, isTrue);

    await HotkeyService.dispose();
  });
}
