import 'dart:math' as math;

/// The identity colour matrix, row-major 3x3.
const List<double> identityMatrix = [1, 0, 0, 0, 1, 0, 0, 0, 1];

/// The CSS filter chain `hue-rotate(hue) brightness(b) saturate(s)` as one
/// row-major 3x3 matrix, with the W3C feColorMatrix maths browsers use (not a
/// true HSL rotation).
List<double> composedFilterMatrix(
  double hueDegrees,
  double brightness,
  double saturation,
) {
  final rad = hueDegrees * math.pi / 180;
  final c = math.cos(rad);
  final s = math.sin(rad);
  final b = brightness;
  final hue = <double>[
    (0.213 + c * 0.787 - s * 0.213) * b,
    (0.715 - c * 0.715 - s * 0.715) * b,
    (0.072 - c * 0.072 + s * 0.928) * b,
    (0.213 - c * 0.213 + s * 0.143) * b,
    (0.715 + c * 0.285 + s * 0.140) * b,
    (0.072 - c * 0.072 - s * 0.283) * b,
    (0.213 - c * 0.213 - s * 0.787) * b,
    (0.715 - c * 0.715 + s * 0.715) * b,
    (0.072 + c * 0.928 + s * 0.072) * b,
  ];
  final t = saturation;
  final sat = <double>[
    0.213 + 0.787 * t,
    0.715 - 0.715 * t,
    0.072 - 0.072 * t,
    0.213 - 0.213 * t,
    0.715 + 0.285 * t,
    0.072 - 0.072 * t,
    0.213 - 0.213 * t,
    0.715 - 0.715 * t,
    0.072 + 0.928 * t,
  ];
  return multiply3x3(sat, hue);
}

/// `a × b` for row-major 3x3 matrices.
List<double> multiply3x3(List<double> a, List<double> b) {
  final out = List<double>.filled(9, 0);
  for (var row = 0; row < 3; row++) {
    for (var col = 0; col < 3; col++) {
      var sum = 0.0;
      for (var k = 0; k < 3; k++) {
        sum += a[row * 3 + k] * b[k * 3 + col];
      }
      out[row * 3 + col] = sum;
    }
  }
  return out;
}

/// Cosine ping-pong in [0, 1]: 0 at phase 0 and 1, 1 at phase 0.5.
double pingPong(double phase) => (1 - math.cos(2 * math.pi * phase)) / 2;

/// CSS `ease-in-out`, cubic-bezier(0.42, 0, 0.58, 1): y at progress x.
double cssEaseInOut(double x) {
  if (x <= 0) return 0;
  if (x >= 1) return 1;
  var lo = 0.0;
  var hi = 1.0;
  var t = x;
  for (var i = 0; i < 16; i++) {
    final mt = 1 - t;
    final bx = 3 * mt * mt * t * 0.42 + 3 * mt * t * t * 0.58 + t * t * t;
    if (bx < x) {
      lo = t;
    } else {
      hi = t;
    }
    t = (lo + hi) / 2;
  }
  final mt = 1 - t;
  return 3 * mt * t * t + t * t * t;
}

/// Samples a keyframe table `[[percent, value], …]` at cycle progress `p`,
/// 0–1, with CSS keyframe semantics: each segment eased on its own.
double sampleKeyframes(
  List<List<double>> table,
  double p, {
  bool easeInOut = false,
}) {
  final pct = p * 100;
  if (pct <= table.first[0]) return table.first[1];
  for (var i = 1; i < table.length; i++) {
    final p0 = table[i - 1][0], v0 = table[i - 1][1];
    final p1 = table[i][0], v1 = table[i][1];
    if (pct <= p1) {
      final f = p1 > p0 ? (pct - p0) / (p1 - p0) : 1.0;
      return v0 + (v1 - v0) * (easeInOut ? cssEaseInOut(f) : f);
    }
  }
  return table.last[1];
}

/// Positive remainder of `t / period`, 0–1.
double cycle(double t, double period) {
  if (period <= 0) return 0;
  final r = (t / period) % 1;
  return r < 0 ? r + 1 : r;
}

/// One pulse oscillator: a cosine ping-pong between [a] and [b].
class Oscillator {
  const Oscillator({
    required this.prop,
    required this.a,
    required this.b,
    required this.period,
    this.delay = 0,
  });

  factory Oscillator.fromJson(Map<String, dynamic> m) => Oscillator(
    prop: m['prop'] as String,
    a: (m['a'] as num).toDouble(),
    b: (m['b'] as num).toDouble(),
    period: (m['period'] as num).toDouble(),
    delay: (m['delay'] as num? ?? 0).toDouble(),
  );

  final String prop;
  final double a;
  final double b;
  final double period;
  final double delay;

  /// The value at `t` seconds. `durationScale` is `duration / 2.3`: the spec's
  /// periods and delays are for the default pulse duration and scale with it.
  double valueAt(double t, double durationScale) {
    final period = this.period * durationScale;
    final delay = this.delay * durationScale;
    return a + (b - a) * pingPong((t - delay) / period);
  }
}

/// Continuous full-circle hue rotation, degrees (pulse family).
double pulseHueDegrees(double t, double period) => cycle(t, period) * 360;

/// Per-frame values of the `line` family.
class LineFrameValues {
  const LineFrameValues({
    required this.x,
    required this.w,
    required this.h,
    required this.spike,
    required this.spike2,
    required this.edge,
  });

  /// Beam x, a fraction of the width.
  final double x;

  /// Width multiplier.
  final double w;

  /// Height multiplier (breathe).
  final double h;
  final double spike;
  final double spike2;

  /// Edge-fade opacity, 0–1.
  final double edge;

  /// Resolves a bloom-gradient size multiplier name to its current value.
  double mult(String name) => switch (name) {
    'spike' => spike,
    'spike2' => spike2,
    'inv-spike' => 2 - spike,
    'inv-spike2' => 2 - spike2,
    'h' => h,
    'w' => w,
    _ => 1,
  };
}

/// The `line` family's keyframe tables.
class LineKeyframes {
  LineKeyframes.fromJson(Map<String, dynamic> m)
    : travelX = _table((m['travel'] as Map)['x']),
      travelW = _table((m['travel'] as Map)['w']),
      edgeFade = _table(m['edgeFade']),
      breathe = _table(m['breathe']),
      spike = _table(m['spike']),
      spike2 = _table(m['spike2']),
      scale = (m['durationScale'] as Map).map(
        (k, v) => MapEntry(k as String, (v as num).toDouble()),
      );

  final List<List<double>> travelX;
  final List<List<double>> travelW;
  final List<List<double>> edgeFade;
  final List<List<double>> breathe;
  final List<List<double>> spike;
  final List<List<double>> spike2;
  final Map<String, double> scale;

  static List<List<double>> _table(Object? o) => (o as List)
      .map((r) => (r as List).map((v) => (v as num).toDouble()).toList())
      .toList();

  /// Every line animation at `t` seconds.
  LineFrameValues at(double t, double duration) {
    double cyc(String key) => cycle(t, duration * (scale[key] ?? 1));
    return LineFrameValues(
      x: sampleKeyframes(travelX, cyc('travel')),
      w: sampleKeyframes(travelW, cyc('travel')),
      h: sampleKeyframes(breathe, cyc('breathe'), easeInOut: true),
      spike: sampleKeyframes(spike, cyc('spike'), easeInOut: true),
      spike2: sampleKeyframes(spike2, cyc('spike2'), easeInOut: true),
      edge: sampleKeyframes(edgeFade, cyc('edgeFade')),
    );
  }
}
