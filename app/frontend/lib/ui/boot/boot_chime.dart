import 'dart:io' show Platform;

import 'package:audioplayers/audioplayers.dart';

/// Plays the start-up chime. Replaceable in tests.
abstract class BootChimePlayer {
  /// Starts [asset] (a path under `assets/`) at [volume] (0..1).
  Future<void> play(String asset, double volume);

  /// Stops the sound and frees the player.
  Future<void> dispose();
}

/// How loud the chime is: gentle, never a surprise.
const double kBootChimeVolume = 0.6;

/// The long (7 s) animation's chime. Its main bloom is 1.0 s in.
const String kBootChimeLong = 'sounds/boot_chime.wav';

/// The short (2 s) animation's chime. Its bloom is 0.4 s in.
const String kBootChimeShort = 'sounds/boot_chime_short.wav';

/// The long animation's wordmark starts to open 4.45 s in (0.56 of the
/// motion at 7 s / 0.88), so the chime starts 1.0 s earlier than that.
const Duration kBootChimeLongDelay = Duration(milliseconds: 3450);

/// The short animation's wordmark is in focus at 0.8 s; the bloom is 0.4 s in.
const Duration kBootChimeShortDelay = Duration(milliseconds: 400);

/// Makes the player used by the splash.
class BootChime {
  /// Replaceable in tests. Outside `flutter test` it plays through
  /// `audioplayers`.
  static BootChimePlayer Function() playerFactory = _create;

  static BootChimePlayer _create() => Platform.environment.containsKey('FLUTTER_TEST') ? _SilentPlayer() : _AudioplayersPlayer();
}

class _SilentPlayer implements BootChimePlayer {
  @override
  Future<void> play(String asset, double volume) async {}

  @override
  Future<void> dispose() async {}
}

class _AudioplayersPlayer implements BootChimePlayer {
  AudioPlayer? _player;

  @override
  Future<void> play(String asset, double volume) async {
    final p = _player = AudioPlayer();
    await p.setReleaseMode(ReleaseMode.stop);
    await p.setVolume(volume);
    await p.play(AssetSource(asset));
  }

  @override
  Future<void> dispose() async {
    final p = _player;
    _player = null;
    if (p == null) return;
    try {
      await p.stop();
    } catch (_) {}
    await p.dispose();
  }
}
