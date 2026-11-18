import 'dart:math' as math;
import 'dart:ui';

import 'wave_front.dart';
import 'wave_style.dart';

/// One tiny white dot. Where it is follows from the front alone, so it scrubs
/// and reverses with the rest.
///
/// In the anticipation it makes short hops toward the source, each fading out
/// short of it. When the front leaves, it is thrown out with it: the quickest
/// ride the front, the slowest trail behind, swaying and twinkling until they
/// fade.
class WaveParticle {
  /// The [index]th dot of a wave in [style]: the same on every run.
  WaveParticle(int index, DistortionWaveStyle style)
    : index = index + 1.0,
      reach = style.particleReach,
      flight = style.particleFlight,
      gap = style.particleGap,
      anticipation = style.anticipation,
      gatherDots = style.gatherDots,
      spread = style.particleSpread.clamp(0.0, 1.0),
      column = (_scatter(index, 0.7548776662) * 2 - 1) * 0.92,
      heading = _scatter(index, 0.7548776662) * 2 * math.pi,
      pace = 0.35 + 0.72 * math.sqrt(_scatter(index, 0.8191725134)),
      drift = 15 + 50 * _scatter(index, 0.6710436067),
      sway = 3 + 11 * _scatter(index, 0.4142135624),
      swayRate = 2.5 + 3.5 * _scatter(index, 0.7320508076),
      twinkleRate = 8 + 12 * _scatter(index, 0.2360679775),
      phase = _scatter(index, 0.6180339887) * 2 * math.pi,
      life = style.particleLife * (0.4 + 0.6 * _scatter(index, 0.6457513111)),
      size =
          style.particleSize *
          (0.55 + 0.45 * math.pow(_scatter(index, 0.5497004779), 2)),
      brightness = 0.3 + 0.7 * _scatter(index, 0.6055512755),
      hop = 0.16 + 0.14 * _scatter(index, 0.1231056256),
      hopOffset = _scatter(index, 0.4721359550);

  /// Low-discrepancy: evenly scattered, the same on every run.
  static double _scatter(int index, double step) => ((index + 1) * step) % 1;

  /// How much wider than the source the quickest end up.
  static const double _fan = 0.22;

  /// How much lower they fly at the source's ends than in its middle.
  static const double _bow = 0.3;

  final double index;
  final double reach, flight, gap, anticipation, gatherDots, spread;

  /// Where across the source it leaves from, -1…1.
  final double column;

  /// Which way it leaves a ring, radians.
  final double heading;

  /// Its share of the front's way: 1 rides the front.
  final double pace;
  final double drift, sway, swayRate, twinkleRate, phase;

  /// Seconds after the launch by which it has faded out.
  final double life;

  /// Its diameter.
  final double size;
  final double brightness;

  /// Seconds each hop toward the source lasts.
  final double hop;
  final double hopOffset;

  /// Where it is on [front].
  Offset pointOn(WaveFront front, Rect source) {
    if (front.ring) {
      return front.launched
          ? _ringOutflow(front, source)
          : _ringInflow(front, source);
    }
    return front.launched ? _outflow(front, source) : _inflow(front, source);
  }

  /// How visible it is on [front], 0–1.
  double opacityOn(WaveFront front) {
    final twinkle = 0.5 + 0.5 * math.sin(front.time * twinkleRate + phase);
    final glint = brightness * (0.7 + 0.3 * twinkle);
    if (!front.launched) {
      final along = _hopAt(front.time).$2;
      final hopping = smooth(0, 0.25, along) * (1 - smooth(0.55, 1, along));
      final ending = 1 - smooth(anticipation * 0.75, anticipation, front.time);
      return front.sparkle * hopping * ending * glint * gatherDots;
    }
    final burning = 1 - smooth(life * 0.55, life, front.flying);
    return burning * glint;
  }

  (double, double) _hopAt(double time) {
    final hops = time / hop + hopOffset;
    final count = hops.floorToDouble();
    return (count, hops - count);
  }

  Offset _onSource(Rect source, bool sideways, double along, double out) =>
      sideways
      ? Offset(source.center.dx + out, source.center.dy + along)
      : Offset(source.center.dx + along, source.center.dy - out);

  Offset _inflow(WaveFront front, Rect source) {
    final (count, along) = _hopAt(front.time);
    final half = (front.sideways ? source.height : source.width) / 2;
    final face = (front.sideways ? source.width : source.height) / 2;
    final x = (_hash(index, count, 1) * 2 - 1) * (half + 24);
    final nearest = gap + flight;
    final away =
        nearest + math.max(reach - nearest, 0) * _hash(index, count, 2);
    final start = _onSource(source, front.sideways, x, face + away);
    final corner = math.min(source.width, source.height) / 2;
    final target = _onSource(
      source,
      front.sideways,
      math.min(math.max(x, -half + corner), half - corner),
      face,
    );
    final delta = target - start;
    final length = math.max(delta.distance, 1.0);
    final travelled = flight * along * along;
    return start + delta / length * travelled;
  }

  Offset _outflow(WaveFront front, Rect source) {
    final start = math.min(source.width, source.height) / 2;
    final widening = 1 + _fan * front.moved * pace * spread;
    final swaying =
        sway *
        math.sin(swayRate * front.flying + phase) *
        math.min(front.flying / 0.25, 1);
    final x =
        column *
            (front.sideways ? source.height : source.width) /
            2 *
            widening +
        swaying;
    final height =
        (start + (front.radius - start) * pace * spread) *
            (1 - _bow * column * column) +
        drift * front.flying * spread;
    final cs = math.cos(front.tilt), sn = math.sin(front.tilt);
    return Offset(
      front.origin.dx + cs * x + sn * height,
      front.origin.dy + sn * x - cs * height,
    );
  }

  Offset _ringInflow(WaveFront front, Rect source) {
    final (count, along) = _hopAt(front.time);
    final angle = _hash(index, count, 1) * 2 * math.pi;
    final nearest = math.min(source.width, source.height) / 2 + gap + flight;
    final away =
        nearest + math.max(reach - nearest, 0) * _hash(index, count, 2);
    final distance = away - flight * along * along;
    return source.center +
        Offset(math.cos(angle) * distance, math.sin(angle) * distance);
  }

  Offset _ringOutflow(WaveFront front, Rect source) {
    final edge = math.min(source.width, source.height) / 2;
    final distance =
        edge + ((front.radius - edge) * pace + drift * front.flying) * spread;
    final swaying =
        sway *
        math.sin(swayRate * front.flying + phase) *
        math.min(front.flying / 0.25, 1);
    final dx = math.cos(heading), dy = math.sin(heading);
    return Offset(
      front.origin.dx + dx * distance - dy * swaying,
      front.origin.dy + dy * distance + dx * swaying,
    );
  }

  static double _hash(double i, double n, double salt) {
    final x = math.sin(i * 12.9898 + n * 78.233 + salt * 37.719) * 43758.5453;
    return x - x.floorToDouble();
  }
}

/// Draws every dot of [particles] on [front]: flat white, nothing round them.
void paintParticles(
  Canvas canvas,
  List<WaveParticle> particles,
  WaveFront front,
  Rect source,
) {
  final paint = Paint()..isAntiAlias = true;
  for (final particle in particles) {
    final opacity = particle.opacityOn(front);
    if (opacity <= 0) continue;
    paint.color = Color.fromRGBO(255, 255, 255, opacity.clamp(0.0, 1.0));
    canvas.drawCircle(
      particle.pointOn(front, source),
      particle.size / 2,
      paint,
    );
  }
}
