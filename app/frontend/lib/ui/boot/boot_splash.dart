import 'dart:io' show Platform;
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/app_state.dart';
import '../../services/local_kv_store.dart';
import '../components/ax_wordmark.dart';
import '../theme.dart';
import 'boot_chime.dart';

/// Set once the long first-launch animation has played on this device.
const kBootSeenKey = 'boot_first_seen';

/// Length of the long animation's motion (orbs -> line -> wordmark).
const kBootFirstDuration = Duration(milliseconds: 7000);
const kBootShortDuration = Duration(milliseconds: 2000);
const kBootReducedDuration = Duration(milliseconds: 900);

/// After the motion, the finished wordmark stays on screen this long...
const kBootHold = Duration(seconds: 3);

/// ...then everything fades into the app.
const kBootFade = Duration(milliseconds: 450);

/// Total time the splash is on screen for [kind]. With reduce motion it is a
/// brief fade with no hold.
Duration bootTotalDuration(BootKind kind, {bool reduced = false}) =>
    reduced ? kBootReducedDuration : (kind == BootKind.first ? kBootFirstDuration : kBootShortDuration) + kBootHold + kBootFade;

/// Plays the start-up animation over the app while it loads underneath.
///
/// Tablets and computers play the long abstract animation (7 s: light
/// gathers, folds into a line, the line opens into the wordmark) every time
/// the app opens. Phones play it the first time only, then the short 2 s
/// wordmark. Either way the finished wordmark then holds for 3 s before
/// fading into the app. With "reduce motion" on, it is a brief fade.
///
/// The app below keeps bootstrapping (tunnel, saved servers) during the
/// animation, so the animation never adds to the real start-up time
/// beyond its own length.
class BootGate extends StatefulWidget {
  const BootGate({super.key, required this.child});

  final Widget child;

  /// Tests pump the app directly; the animation would only add pending
  /// frames. On by default outside `flutter test`.
  static bool enabled = !Platform.environment.containsKey('FLUTTER_TEST');

  /// Whether the long animation has already played on this device, and
  /// recording that it has. Replaceable in tests.
  static Future<bool> Function() hasSeenFirst = _readSeen;
  static Future<void> Function() markSeenFirst = _writeSeen;

  static Future<bool> _readSeen() async => await LocalKvStore.instance.read(kBootSeenKey) != null;
  static Future<void> _writeSeen() => LocalKvStore.instance.write(kBootSeenKey, '1');

  @override
  State<BootGate> createState() => _BootGateState();
}

class _BootGateState extends State<BootGate> {
  BootKind? _kind;
  bool _showing = BootGate.enabled;
  int _run = 0;
  int? _lastReplay;

  bool _decided = false;

  /// Phones get the short animation after the first launch.
  static const kPhoneShortestSide = 600.0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_decided || !BootGate.enabled) return;
    _decided = true;
    final phone = MediaQuery.sizeOf(context).shortestSide < kPhoneShortestSide;
    if (phone) {
      _decide();
    } else {
      _kind = BootKind.first;
    }
  }

  Future<void> _decide() async {
    bool seen;
    try {
      seen = await BootGate.hasSeenFirst();
    } catch (_) {
      seen = true; // storage unavailable: don't risk replaying the long one every time
    }
    if (!mounted) return;
    setState(() => _kind = seen ? BootKind.short : BootKind.first);
    if (!seen) {
      BootGate.markSeenFirst().catchError((_) {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final replay = context.select<AppState, int>((a) => a.bootReplay);
    if (_lastReplay != null && replay != _lastReplay) {
      _kind = context.read<AppState>().bootReplayKind;
      _showing = true;
      _run++;
    }
    _lastReplay = replay;

    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (_showing)
          Positioned.fill(
            child: _kind == null
                ? ColoredBox(color: context.ax.colors.bg)
                : BootSplash(
                    key: ValueKey(_run),
                    kind: _kind!,
                    sound: context.read<AppState>().startupSound,
                    onDone: () {
                      if (mounted) setState(() => _showing = false);
                    },
                  ),
          ),
      ],
    );
  }
}

/// The start-up animation itself. Calls [onDone] when finished.
class BootSplash extends StatefulWidget {
  const BootSplash({super.key, required this.kind, required this.onDone, this.sound = false});

  final BootKind kind;

  /// Whether to play the start-up chime (Settings > Appearance).
  final bool sound;
  final VoidCallback onDone;

  @override
  State<BootSplash> createState() => _BootSplashState();
}

class _BootSplashState extends State<BootSplash> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this);
  bool _started = false;
  bool _reduced = false;
  Timer? _chimeTimer;
  BootChimePlayer? _chime;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _c.duration = bootTotalDuration(widget.kind, reduced: _reduced);
    _c.forward().whenCompleteOrCancel(() {
      if (mounted) widget.onDone();
    });
    if (widget.sound) _scheduleChime();
  }

  /// Starts the chime so its bloom meets the wordmark. Never blocks or breaks
  /// the animation: any audio problem is ignored.
  void _scheduleChime() {
    final long = widget.kind == BootKind.first && !_reduced;
    final asset = long ? kBootChimeLong : kBootChimeShort;
    final delay = _reduced ? Duration.zero : (long ? kBootChimeLongDelay : kBootChimeShortDelay);
    _chimeTimer = Timer(delay, () {
      try {
        final player = _chime = BootChime.playerFactory();
        player.play(asset, kBootChimeVolume).catchError((_) {});
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _chimeTimer?.cancel();
    try {
      _chime?.dispose().catchError((_) {});
    } catch (_) {}
    _chime = null;
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    return Semantics(
      label: 'Archangel OS is starting',
      container: true,
      excludeSemantics: true,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final Widget scene;
          final double out;
          if (_reduced) {
            scene = _reducedScene(_c.value);
            out = 1 - _seg(_c.value, 0.75, 1.0);
          } else {
            // Motion, then the finished wordmark holds for [kBootHold], then
            // everything fades into the app.
            final total = _c.duration!.inMilliseconds;
            final motion = (widget.kind == BootKind.first ? kBootFirstDuration : kBootShortDuration).inMilliseconds;
            final elapsed = _c.value * total;
            final p = (elapsed / motion).clamp(0.0, 1.0);
            out = 1 - _seg(elapsed, (total - kBootFade.inMilliseconds).toDouble(), total.toDouble());
            // The long scene's keyframes finish at 0.88 (tagline in).
            scene = widget.kind == BootKind.first ? _firstScene(context, p * 0.88) : _shortScene(context, p);
          }
          // Sits above the Navigator (no Material ancestor): give the text
          // a proper default style.
          return Material(
            type: MaterialType.transparency,
            child: Opacity(
              opacity: out,
              child: ColoredBox(
                color: c.bg,
                child: Center(child: scene),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _reducedScene(double t) => Opacity(opacity: _seg(t, 0, 0.3), child: const AxWordmark(size: 40));

  /// ~7 s: three soft orbs drift in and merge, fold into a line of light,
  /// and the line opens to reveal the wordmark and the tagline. [t] runs
  /// 0 -> 0.88 over the motion.
  Widget _firstScene(BuildContext context, double t) {
    final c = context.ax.colors;
    const size = 44.0;
    final reveal = Curves.easeOutCubic.transform(_seg(t, 0.56, 0.76));
    final settle = Curves.easeOutCubic.transform(_seg(t, 0.56, 0.80));
    final spacing = _lerp(0.32 * size, -0.02 * size, settle);
    final blur = _lerp(10, 0, settle);
    final tag = Curves.easeOut.transform(_seg(t, 0.74, 0.88));

    Widget word = AxWordmark(size: size, letterSpacing: spacing);
    if (blur > 0.05) {
      word = ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: word,
      );
    }

    return SizedBox(
      width: double.infinity,
      height: 260,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _OrbsPainter(t: t, a: c.orbA, b: c.orbB, cc: c.orbC),
            ),
          ),
          ClipRect(clipper: _CenterReveal(reveal), child: word),
          Positioned(
            top: 260 / 2 + 36,
            child: Opacity(
              opacity: tag,
              child: Transform.translate(
                offset: Offset(0, 8 * (1 - tag)),
                child: Text('Your private cloud, guarded 24/7.', style: context.ax.typo.body.copyWith(color: c.textMuted)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// ~2 s: the wordmark sharpens into focus while a band of light sweeps
  /// across it.
  Widget _shortScene(BuildContext context, double t) {
    final c = context.ax.colors;
    final appear = Curves.easeOutCubic.transform(_seg(t, 0, 0.4));
    final blur = _lerp(12, 0, appear);
    final sweep = _lerp(-0.3, 1.3, Curves.easeInOut.transform(_seg(t, 0.15, 0.85)));
    final glow = t < 0.4 ? _seg(t, 0, 0.4) * 0.35 : (1 - _seg(t, 0.4, 1)) * 0.35;

    Widget word = ShaderMask(
      blendMode: BlendMode.srcATop,
      shaderCallback: (rect) => LinearGradient(
        colors: [Colors.transparent, c.accent.withValues(alpha: 0.85), Colors.transparent],
        stops: [(sweep - 0.12).clamp(0.0, 1.0), sweep.clamp(0.0, 1.0), (sweep + 0.12).clamp(0.0, 1.0)],
      ).createShader(rect),
      child: const AxWordmark(size: 44),
    );
    if (blur > 0.05) {
      word = ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: word,
      );
    }

    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 380,
          height: 130,
          decoration: BoxDecoration(
            gradient: RadialGradient(
              colors: [
                c.orbA.withValues(alpha: glow),
                c.orbA.withValues(alpha: 0),
              ],
            ),
          ),
        ),
        Opacity(
          opacity: appear,
          child: Transform.scale(scale: _lerp(0.96, 1, appear), child: word),
        ),
      ],
    );
  }
}

/// 0 before [a], 1 after [b], linear between.
double _seg(double t, double a, double b) => ((t - a) / (b - a)).clamp(0.0, 1.0);
double _lerp(double a, double b, double t) => a + (b - a) * t;

/// Piecewise keyframes [(time, value), ...] with ease-in-out between them.
double _kf(double t, List<(double, double)> k) {
  if (t <= k.first.$1) return k.first.$2;
  for (var i = 1; i < k.length; i++) {
    if (t <= k[i].$1) {
      final p = Curves.easeInOut.transform(_seg(t, k[i - 1].$1, k[i].$1));
      return _lerp(k[i - 1].$2, k[i].$2, p);
    }
  }
  return k.last.$2;
}

/// Shows a band of [fraction] of the child's width, growing from the centre.
class _CenterReveal extends CustomClipper<Rect> {
  _CenterReveal(this.fraction);
  final double fraction;

  @override
  Rect getClip(Size size) => Rect.fromCenter(center: size.center(Offset.zero), width: size.width * fraction, height: size.height * 2);

  @override
  bool shouldReclip(_CenterReveal old) => old.fraction != fraction;
}

class _OrbsPainter extends CustomPainter {
  _OrbsPainter({required this.t, required this.a, required this.b, required this.cc});

  final double t;
  final Color a;
  final Color b;
  final Color cc;

  void _orb(
    Canvas canvas,
    Offset centre,
    Color color,
    double radius, {
    required List<(double, double)> x,
    required List<(double, double)> y,
    required List<(double, double)> sx,
    required List<(double, double)> sy,
    required List<(double, double)> op,
  }) {
    final o = _kf(t, op);
    if (o <= 0.01) return;
    canvas.save();
    canvas.translate(centre.dx + _kf(t, x), centre.dy + _kf(t, y));
    canvas.scale(math.max(_kf(t, sx), 0.01), math.max(_kf(t, sy), 0.01));
    canvas.drawCircle(
      Offset.zero,
      radius,
      Paint()
        ..color = color.withValues(alpha: o)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 46),
    );
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final ctr = size.center(Offset.zero);
    _orb(
      canvas,
      ctr,
      a,
      110,
      x: [(0, -190), (0.45, -30), (0.58, 0)],
      y: [(0, -80), (0.45, -6), (0.58, 0)],
      sx: [(0, 0.5), (0.45, 1.05), (0.58, 1.6), (0.72, 2.4)],
      sy: [(0, 0.5), (0.45, 1.05), (0.58, 0.12), (0.72, 0.05)],
      op: [(0, 0), (0.18, 0.85), (0.45, 0.9), (0.58, 0.8), (0.72, 0)],
    );
    _orb(
      canvas,
      ctr,
      b,
      110,
      x: [(0, 200), (0.45, 36), (0.58, 0)],
      y: [(0, 90), (0.45, 10), (0.58, 0)],
      sx: [(0, 0.5), (0.45, 1.0), (0.58, 1.6), (0.72, 2.4)],
      sy: [(0, 0.5), (0.45, 1.0), (0.58, 0.12), (0.72, 0.05)],
      op: [(0, 0), (0.22, 0.8), (0.45, 0.9), (0.58, 0.75), (0.72, 0)],
    );
    _orb(
      canvas,
      ctr,
      cc,
      80,
      x: [(0, 20), (0.48, 0)],
      y: [(0, 170), (0.48, 20), (0.6, 0)],
      sx: [(0, 0.4), (0.48, 0.9), (0.6, 1.4)],
      sy: [(0, 0.4), (0.48, 0.9), (0.6, 0.1)],
      op: [(0, 0), (0.28, 0.6), (0.48, 0.7), (0.6, 0)],
    );

    // The beam: a thin line of light that opens into the wordmark.
    final w = _kf(t, [(0.48, 0), (0.56, 120), (0.66, 520), (0.8, 620)]);
    final op = _kf(t, [(0.48, 0), (0.56, 1), (0.66, 1), (0.8, 0)]);
    if (w > 1 && op > 0.01) {
      final rect = Rect.fromCenter(center: ctr, width: w, height: 2);
      final shader = LinearGradient(
        colors: [
          b.withValues(alpha: 0),
          b.withValues(alpha: op),
          Colors.white.withValues(alpha: op),
          a.withValues(alpha: op),
          a.withValues(alpha: 0),
        ],
        stops: const [0, 0.3, 0.5, 0.7, 1],
      ).createShader(rect);
      canvas.drawRect(
        rect.inflate(4),
        Paint()
          ..shader = shader
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(1)), Paint()..shader = shader);
    }
  }

  @override
  bool shouldRepaint(_OrbsPainter old) => old.t != t || old.a != a || old.b != b || old.cc != cc;
}
