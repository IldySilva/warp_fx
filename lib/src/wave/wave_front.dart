import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'wave_style.dart';

/// Half the zone over which the two views crossfade (`coverZone` in the
/// shader).
const double coverZone = 60;

double _clamp01(double x) => x < 0 ? 0 : (x > 1 ? 1 : x);

/// Hermite smoothstep of [x] between [a] and [b].
double smooth(double a, double b, double x) {
  final t = _clamp01((x - a) / (b - a));
  return t * t * (3 - 2 * t);
}

/// Where the wave is at one moment of its life: a pure function of progress,
/// so it can be scrubbed, reversed and frozen for a screenshot.
///
/// Its life, in order: gravity pulls everything toward the source; the front
/// launches off the source's outline, crosses the area on the style's easing,
/// and settles past the far side as its swell, blur and colour die away; the
/// colour it left on the edges is wiped away by a second front, `linger`
/// seconds behind.
@immutable
class WaveFront {
  const WaveFront._({
    required this.origin,
    required this.tilt,
    required this.spine,
    required this.radius,
    required this.moved,
    required this.squash,
    required this.time,
    required this.energy,
    required this.swell,
    required this.size,
    required this.gravity,
    required this.glow,
    required this.clearRadius,
    required this.hairClearRadius,
    required this.rim,
    required this.fallen,
    required this.sparkle,
    required this.flying,
    required this.launched,
    required this.hasCleared,
    required this.ring,
    required this.sideways,
    required this.hold,
  });

  /// The most an arc's x axis is ever squashed; a ring's never is.
  static const double _arcSquash = 1.4;

  /// Seconds gravity takes to let go after the launch.
  static const double _release = 0.22;

  /// How strong the colour gathering round the source gets before the launch.
  static const double _gatheredGlow = 0.5;

  /// How far past having crossed the area the front settles.
  static const double _overshoot = 100;

  /// How far the wave turns, at full orientation, touched at the source's end.
  static const double _maxTilt = 0.45;

  /// The part of the travel over which swell, blur and colour die away.
  static const double _settleStart = 0.2, _settleEnd = 0.55;

  /// The wave at [progress] (0–1) over an area of [size], opening from
  /// [source]. [focus] is where the source was touched, if it is to lean.
  factory WaveFront({
    required double progress,
    required Rect source,
    required Size size,
    required DistortionWaveStyle style,
    Offset? focus,
  }) {
    final t = _clamp01(progress) * style.duration;
    final sinceLaunch = t - style.anticipation;
    final gathered = smooth(0, math.max(style.anticipation, 0.001), t);
    final x = _clamp01(sinceLaunch / style.travel);
    final moved = style.easing.transform(x);

    final ring = style.type == WaveType.center;
    final sideways = style.type == WaveType.horizontal;
    final fullSquash = ring ? 1.0 : _arcSquash;
    final startRadius = math.min(source.width, source.height) / 2;
    // The source's long side, along which the front starts as a pill.
    final length = sideways ? source.height : source.width;
    final startSpine = ring ? 0.0 : math.max(0.0, length / 2 - startRadius);
    // The horizontal wave is the vertical one turned a quarter.
    final turned = sideways ? math.pi / 2 : 0.0;
    final axisX = math.cos(turned), axisY = math.sin(turned);

    // Touched off-centre, the wave opens from under the finger and leans.
    var lean = 0.0;
    if (!ring && focus != null) {
      final off = sideways
          ? focus.dy - source.center.dy
          : focus.dx - source.center.dx;
      lean = (off / math.max(length / 2, 1)).clamp(-1.0, 1.0);
    }
    final fullShift = lean * length / 2 * style.orientation;
    final fullLean = lean * style.orientation * _maxTilt;
    final fullTilt = turned + fullLean;
    final opening = smooth(0, 0.45, moved);

    // The radius at which the front has left the farthest corner, in the
    // wave's own frame once it has finished leaning.
    final cs = math.cos(fullTilt), sn = math.sin(fullTilt);
    var reach = 0.0;
    for (final corner in [
      Offset.zero,
      Offset(size.width, 0),
      Offset(0, size.height),
      Offset(size.width, size.height),
    ]) {
      final dx = corner.dx - source.center.dx - fullShift * axisX;
      final dy = corner.dy - source.center.dy - fullShift * axisY;
      final r = math.sqrt(
        math.pow((cs * dx + sn * dy) * fullSquash, 2) +
            math.pow(-sn * dx + cs * dy, 2),
      );
      reach = math.max(reach, r);
    }
    // …and has taken the outgoing view with it.
    final crossed = reach + (style.swell + coverZone) * fullSquash;
    final settling = 1 - smooth(_settleStart, _settleEnd, x);

    final facing = smooth(0, 0.1, moved);
    final origin = Offset(
      source.center.dx + fullShift * facing * axisX,
      source.center.dy + fullShift * facing * axisY,
    );
    final launchRadius = startRadius + math.max(style.launchGap, 0);
    final radius = sinceLaunch < 0
        ? launchRadius + style.inhale * (1 - gathered)
        : launchRadius + (crossed + _overshoot - launchRadius) * moved;

    final gatheredGlow = math.min(
      _gatheredGlow * math.max(style.gatherGlow, 0),
      1.0,
    );
    final glow = sinceLaunch < 0
        ? gatheredGlow * gathered
        : (gatheredGlow + (1 - gatheredGlow) * smooth(0, 0.07, x)) * settling;

    final clearStart = startRadius - style.rimSoftness;
    final clearEnd = reach + (style.rimSoftness + style.swell) * fullSquash;
    double wipe(double delay, double fade) => style.rimEasing.transform(
      _clamp01((sinceLaunch - delay) / math.max(fade, 0.01)),
    );
    final clearRadius =
        clearStart +
        (clearEnd - clearStart) * wipe(style.linger, style.rimFade);
    final hairClearRadius =
        clearStart +
        (clearEnd - clearStart) *
            wipe(style.linger + style.hairlineLinger, style.hairlineFade);

    final falling = math.min(t / math.max(style.anticipation, 0.001), 1.0);

    return WaveFront._(
      origin: origin,
      tilt: turned + fullLean * facing,
      spine: startSpine * (1 - opening),
      radius: radius,
      moved: moved,
      squash: 1 + (fullSquash - 1) * smooth(0, 0.5, moved),
      time: t,
      energy: smooth(0, 0.05, x) * settling,
      swell: style.swell * smooth(0, 0.3, moved),
      size: size,
      gravity: style.pull * gathered * (1 - smooth(0, _release, sinceLaunch)),
      glow: glow,
      clearRadius: clearRadius,
      hairClearRadius: hairClearRadius,
      rim:
          style.rimStrength *
          smooth(0, 0.1, x) *
          (1 - smooth(0.9, 1, t / style.duration)),
      fallen: falling * falling,
      sparkle: smooth(0, math.max(style.anticipation, 0.001) * 0.35, t),
      flying: math.max(sinceLaunch, 0),
      launched: sinceLaunch > 0,
      hasCleared: radius > crossed,
      ring: ring,
      sideways: sideways,
      hold: ring ? startRadius : 0,
    );
  }

  /// Where the wave's frame is centred.
  final Offset origin;

  /// How far the wave's frame is turned, radians: positive leans it right.
  final double tilt;

  /// Half-length of the straight part of the pill the front is an offset of.
  final double spine;

  /// Distance of the front from that spine.
  final double radius;

  /// How far the front is along its way, 0–1.
  final double moved;

  /// Scale of the x axis in the field: above 1 the front bows.
  final double squash;

  /// Seconds into the wave's life.
  final double time;

  /// How strongly the swell and the blur act, 0–1.
  final double energy;

  /// How far the front bends along its length now.
  final double swell;

  /// The area the wave fills.
  final Size size;

  /// How far content is pulled toward the source.
  final double gravity;

  /// How strong the colour on the front is, 0–1.
  final double glow;

  /// Distance of the later front that wipes the colour off the edges.
  final double clearRadius;

  /// Distance of the front that wipes the hairline off them, later still.
  final double hairClearRadius;

  /// Opacity of the colour on the edges, 0–1.
  final double rim;

  /// How far the particles have fallen into the source, 0–1.
  final double fallen;

  /// How far the particles have faded in, 0–1.
  final double sparkle;

  /// Seconds since the front left the source, 0 before that.
  final double flying;

  /// True once the front has left the source.
  final bool launched;

  /// True once the front has crossed the whole area: nothing of the view it
  /// leaves behind can show any more.
  final bool hasCleared;

  /// True for a ring spreading from the source's centre, rather than an arc.
  final bool ring;

  /// True for an arc travelling left to right, rather than bottom to top.
  final bool sideways;

  /// Radius of the source the wave leaves alone: a ring's, 0 for an arc.
  final double hold;

  /// The field as the shader reads it, five vec4s.
  List<double> get packed => [
    origin.dx, origin.dy, spine, radius, //
    squash, time, energy, swell, //
    size.width, size.height, gravity, glow, //
    clearRadius, rim, tilt, ring ? 1 : 0, //
    hold, launched ? 1 : 0, hairClearRadius, 0,
  ];
}

/// The lumps that make the colour on the edges uneven: seven round the
/// perimeter, each with its own length and depth, drifting and breathing.
/// Centre along the perimeter, length and depth of each, flattened.
List<double> rimLumps({
  required double time,
  required Size size,
  required double cornerRadius,
  double pulse = 0,
}) {
  const count = 7;
  final ex = math.max(size.width / 2 - cornerRadius, 0.0);
  final ey = math.max(size.height / 2 - cornerRadius, 0.0);
  final perimeter = 4 * (ex + ey + 0.5 * math.pi * cornerRadius);
  double hash(double i, double a, double b) {
    final v = math.sin(i * a + b) * 43758.5453;
    return v - v.floorToDouble();
  }

  final out = <double>[];
  for (var i = 0; i < count; i++) {
    final fi = i.toDouble();
    final a = hash(fi, 12.9898, 1.3);
    final b = hash(fi, 78.233, 4.1);
    final c = hash(fi, 39.425, 2.7);
    final centre =
        perimeter * (fi + 0.35 * a) / count +
        time * (-22 + 44 * b) * (1 + 2 * pulse);
    final length = perimeter / count * (0.2 + 0.25 * c);
    final breath =
        (0.25 + 0.3 * pulse) *
        math.sin(time * (1.1 + 1.2 * a) * (1 + pulse) + fi * 2.4);
    final depth = (0.2 + 2.6 * b) * (1 + breath);
    out.addAll([centre, length, depth]);
  }
  return out;
}
