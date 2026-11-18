import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Which way a distortion wave travels.
enum WaveType {
  /// Bottom to top, from a wide source's own outline (a button) into an arc
  /// bowed so it crosses a tall screen as a curve. Leans with the touch.
  vertical,

  /// Left to right: the vertical wave on its side, from a tall source at the
  /// left (an edge, a tab, a side button). Leans with the touch too.
  horizontal,

  /// A ring spreading evenly from the source's centre, as from an avatar. The
  /// source itself is left alone, so it can morph in plain view at the centre.
  center,
}

/// The colours of a wave: several flowing along the front and round the
/// edges, a fringe riding ahead of the front and one trailing behind it.
@immutable
class WavePalette {
  /// A palette of up to eight [colors], with a fringe [ahead] of the front
  /// and one [behind] it.
  WavePalette({
    required List<Color> colors,
    required this.ahead,
    required this.behind,
  }) : colors = List.unmodifiable(
         (colors.isEmpty ? [ahead] : colors).take(maxColors),
       );

  /// The most colours a palette carries along the front.
  static const int maxColors = 8;

  /// The colours flowing along the front and round the edges.
  final List<Color> colors;

  /// The fringe riding ahead of the front.
  final Color ahead;

  /// The fringe trailing behind the front.
  final Color behind;

  /// Yellows, blues, purples and pinks, with a pink fringe ahead and a blue
  /// one behind.
  static final WavePalette colorful = WavePalette(
    colors: const [
      Color(0xFFFFC915),
      Color(0xFF7EC4FF),
      Color(0xFFB428E6),
      Color(0xFFEB64A0),
      Color(0xFFFFB07A),
      Color(0xFF9AA0FF),
      Color(0xFF7FD9EE),
    ],
    ahead: const Color(0xFFFF7AB6),
    behind: const Color(0xFF5ABEFF),
  );

  /// Greens only, from a success badge's #35BA00 out to lime and mint.
  static final WavePalette green = WavePalette(
    colors: const [
      Color(0xFF35BA00),
      Color(0xFF8CEB5A),
      Color(0xFF00C46E),
      Color(0xFFBEFA82),
      Color(0xFF28A03C),
      Color(0xFF6EE1A0),
      Color(0xFF5AD228),
    ],
    ahead: const Color(0xFFC4FF78),
    behind: const Color(0xFF009646),
  );

  /// Blues and teals.
  static final WavePalette ocean = WavePalette(
    colors: const [
      Color(0xFF2878FF),
      Color(0xFF5AC8FF),
      Color(0xFF1450C8),
      Color(0xFF78E6F0),
      Color(0xFF3C96FF),
      Color(0xFF96B4FF),
      Color(0xFF00B4DC),
    ],
    ahead: const Color(0xFF96E6FF),
    behind: const Color(0xFF1E46DC),
  );

  /// Oranges, pinks and magentas.
  static final WavePalette sunset = WavePalette(
    colors: const [
      Color(0xFFFF8C3C),
      Color(0xFFFF5A78),
      Color(0xFFFFC850),
      Color(0xFFF0465A),
      Color(0xFFFFAA78),
      Color(0xFFDC5AC8),
      Color(0xFFFF7850),
    ],
    ahead: const Color(0xFFFFDC78),
    behind: const Color(0xFFC83CA0),
  );

  /// Whites and silvers.
  static final WavePalette mono = WavePalette(
    colors: const [
      Color(0xFFF0F0F5),
      Color(0xFFC8CDD7),
      Color(0xFFFFFFFF),
      Color(0xFFAAAFBE),
      Color(0xFFE1E4EB),
      Color(0xFFBEC3CD),
      Color(0xFFF5F5FA),
    ],
    ahead: const Color(0xFFFFFFFF),
    behind: const Color(0xFFA0A5B4),
  );

  /// A single colour, lighter ahead of the front and deeper behind it.
  factory WavePalette.single(Color color) {
    const white = Color(0xFFFFFFFF);
    const black = Color(0xFF000000);
    return WavePalette(
      colors: [
        color,
        Color.lerp(color, white, 0.25)!,
        color,
        Color.lerp(color, black, 0.15)!,
      ],
      ahead: Color.lerp(color, white, 0.45)!,
      behind: Color.lerp(color, black, 0.3)!,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is WavePalette &&
      listEquals(other.colors, colors) &&
      other.ahead == ahead &&
      other.behind == behind;

  @override
  int get hashCode => Object.hash(Object.hashAll(colors), ahead, behind);
}

/// How a distortion wave looks and moves.
///
/// Start from the tuned defaults of a type, [DistortionWaveStyle.vertical],
/// [DistortionWaveStyle.horizontal] or [DistortionWaveStyle.center], and
/// change what you need with [copyWith]. Lengths are in logical pixels and
/// times in seconds.
@immutable
class DistortionWaveStyle {
  /// The tuned defaults for a full screen opened from a button at the bottom.
  /// Use [DistortionWaveStyle.of] for the other types' defaults.
  const DistortionWaveStyle({
    this.type = WaveType.vertical,
    this.anticipation = 0.5,
    this.travel = 2.28,
    this.launchGap = 0,
    this.linger = -0.35,
    this.rimFade = 3.03,
    this.rimEasing = const Cubic(0.42, 0, 0.58, 1),
    this.returnSpeed = 1.45,
    this.easing = const Cubic(0.22, 1, 0.36, 1),
    this.pull = 24,
    this.inhale = 56,
    this.gatherGlow = 0.33,
    this.gatherDots = 1,
    this.amplitude = 34,
    this.lensWidth = 150,
    this.aberration = 0.78,
    this.swell = 22,
    this.blur = 18,
    this.blurAhead = 90,
    this.blurBehind = 240,
    this.lead = 130,
    this.tail = 300,
    this.strength = 0.92,
    this.rimWidth = 14,
    this.rimUnevenness = 1,
    this.rimStrength = 0.82,
    this.rimSoftness = 343,
    this.cornerRadius = 62,
    this.continuousCorners = true,
    this.rimPulse = 0.6,
    this.hairlineWidth = 1.5,
    this.hairlineOpacity = 0.9,
    this.hairlineWhite = 0.95,
    this.hairlineLinger = 0.47,
    this.hairlineFade = 3,
    this.orientation = 0.5,
    this.particleCount = 64,
    this.particleSize = 1.8,
    this.particleReach = 150,
    this.particleFlight = 30,
    this.particleGap = 24,
    this.particleLife = 2.19,
    this.particleSpread = 1,
    this.palette,
  });

  /// The tuned defaults for [type].
  ///
  /// - [WaveType.vertical] and [WaveType.horizontal]: a full screen, opened
  ///   from a button, in the colourful palette.
  /// - [WaveType.center]: a sheet or card about 500 tall, opened from an
  ///   avatar or icon, in greens: a slower ring, only the pull before it
  ///   leaves, softer colour, no chromatic aberration, and dots that stay in
  ///   view.
  factory DistortionWaveStyle.of(WaveType type) => switch (type) {
    WaveType.vertical => vertical,
    WaveType.horizontal => horizontal,
    WaveType.center => center,
  };

  /// Up the screen from a button at the bottom.
  static const DistortionWaveStyle vertical = DistortionWaveStyle();

  /// Across the screen from a tall source at the left.
  static const DistortionWaveStyle horizontal = DistortionWaveStyle(
    type: WaveType.horizontal,
  );

  /// Out from an avatar or icon, round a sheet or card.
  static const DistortionWaveStyle center = DistortionWaveStyle(
    type: WaveType.center,
    anticipation: 0.25,
    travel: 3.43,
    rimFade: 2.51,
    hairlineLinger: 0.96,
    strength: 0.6,
    rimStrength: 0.6,
    aberration: 0,
    gatherGlow: 0,
    gatherDots: 0,
    particleCount: 89,
    particleLife: 3.93,
    particleSpread: 0.64,
    cornerRadius: 48,
    // A sheet is about 0.6 the height of a screen: its lengths are too.
    pull: 14.4,
    inhale: 33.6,
    amplitude: 20.4,
    lensWidth: 90,
    swell: 13.2,
    blur: 10.8,
    blurAhead: 54,
    blurBehind: 144,
    lead: 78,
    tail: 180,
    rimSoftness: 205.8,
    particleReach: 90,
    particleFlight: 18,
    particleGap: 11,
  );

  // Type

  /// Which way the wave travels.
  final WaveType type;

  // Timing

  /// Seconds everything is pulled toward the source before the wave leaves it.
  final double anticipation;

  /// Seconds from the wave leaving the source to its front having settled.
  final double travel;

  /// How far out from the source's outline the front starts: 0 leaves the
  /// source itself, more starts it clear of the source.
  final double launchGap;

  /// Seconds after the wave leaves the source that the colour on the edges
  /// starts to be wiped away. Below 0 it starts before, following close
  /// behind the front.
  final double linger;

  /// Seconds the colour on the edges takes to be wiped away once it goes.
  final double rimFade;

  /// How the wipe moves over [rimFade].
  final Curve rimEasing;

  /// How much faster the wave collapses back than it opened.
  final double returnSpeed;

  /// How the front covers its way over [travel]: it leaves the source at full
  /// speed and settles softly at the far side.
  final Curve easing;

  // Gravity

  /// How far the anticipation pulls content toward the source.
  final double pull;

  /// How far out the ring of colour that falls onto the source starts.
  final double inhale;

  /// How strong the colour is through the anticipation, 0–2. 1 has gathered
  /// half the front's colour by the launch, 2 all of it, 0 none.
  final double gatherGlow;

  /// How visible the dots hopping toward the source in the anticipation are,
  /// 0–1. 0 leaves only the dots that fly out with the front.
  final double gatherDots;

  // Swell

  /// How far the swell lifts content as it passes.
  final double amplitude;

  /// Width of the swell.
  final double lensWidth;

  /// How far red and blue part, as a share of how far the content has moved:
  /// where nothing is distorted, the colours stay together.
  final double aberration;

  /// How far the front bends along its length.
  final double swell;

  // Progressive blur

  /// Blur radius on the front.
  final double blur;

  /// Distance ahead of the front over which the blur gathers.
  final double blurAhead;

  /// Distance behind the front over which the blur clears.
  final double blurBehind;

  // Colour on the front

  /// Distance the colour feathers out ahead of the front.
  final double lead;

  /// Length of the colour trailing behind the front.
  final double tail;

  /// Peak opacity of the colour, 0–1.
  final double strength;

  // Colour on the edges

  /// How far in from the edges the colour reaches.
  final double rimWidth;

  /// How unequal the colour's thickness is along the edges, 0–2: 0 is even,
  /// 1 drifting lumps with thin stretches between, past 1 the thinnest
  /// stretches break off.
  final double rimUnevenness;

  /// Peak opacity of the colour on the edges, 0–1.
  final double rimStrength;

  /// How softly the colour on the edges is wiped away.
  final double rimSoftness;

  /// The corner radius of the area the wave fills (the screen's, or a
  /// sheet's), which the colour on the edges and its hairline follow.
  final double cornerRadius;

  /// Whether the corners are continuous (as an iPhone's screen, or Flutter's
  /// [ContinuousRectangleBorder]) rather than circular arcs.
  final bool continuousCorners;

  /// How alive the colour on the edges is, 0–1: its lumps drift and breathe,
  /// a soft brightness runs round the edge, and its colours flow.
  final double rimPulse;

  /// Width of a hairline right on the edge, over the colour. 0 draws none.
  final double hairlineWidth;

  /// Peak opacity of the hairline, 0–1.
  final double hairlineOpacity;

  /// How far the hairline whitens where the pulse's light runs, 0–1.
  final double hairlineWhite;

  /// Seconds the hairline holds on after the colour on the edges starts to
  /// be wiped away.
  final double hairlineLinger;

  /// Seconds the hairline takes to be wiped away once it goes.
  final double hairlineFade;

  // Touch

  /// How much the wave leans with where the source was touched, 0–1. The
  /// center type never leans.
  final double orientation;

  // Particles

  /// How many dots fall into the source and fly out of it with the wave.
  final int particleCount;

  /// Diameter of the largest dot.
  final double particleSize;

  /// How far from the source the farthest dot is born in the anticipation.
  final double particleReach;

  /// How far each dot flies toward the source in one hop.
  final double particleFlight;

  /// How close to the source a dot comes before it has faded.
  final double particleGap;

  /// Seconds after the launch by which the last dot has faded out.
  final double particleLife;

  /// How far the dots are thrown, as a share of the front's way, 0–1.
  final double particleSpread;

  // Colour

  /// The colours. Null takes the type's own: green for [WaveType.center],
  /// colourful for the others.
  final WavePalette? palette;

  /// The palette in use.
  WavePalette get resolvedPalette =>
      palette ??
      (type == WaveType.center ? WavePalette.green : WavePalette.colorful);

  /// Seconds for the whole of it, by when the swell has settled, the edges
  /// have cleared and the last dot has faded.
  double get duration =>
      anticipation +
      [
        travel * 0.6,
        linger + rimFade,
        linger + hairlineLinger + hairlineFade,
        particleLife,
      ].reduce(math.max);

  /// A copy with the given fields replaced.
  DistortionWaveStyle copyWith({
    WaveType? type,
    double? anticipation,
    double? travel,
    double? launchGap,
    double? linger,
    double? rimFade,
    Curve? rimEasing,
    double? returnSpeed,
    Curve? easing,
    double? pull,
    double? inhale,
    double? gatherGlow,
    double? gatherDots,
    double? amplitude,
    double? lensWidth,
    double? aberration,
    double? swell,
    double? blur,
    double? blurAhead,
    double? blurBehind,
    double? lead,
    double? tail,
    double? strength,
    double? rimWidth,
    double? rimUnevenness,
    double? rimStrength,
    double? rimSoftness,
    double? cornerRadius,
    bool? continuousCorners,
    double? rimPulse,
    double? hairlineWidth,
    double? hairlineOpacity,
    double? hairlineWhite,
    double? hairlineLinger,
    double? hairlineFade,
    double? orientation,
    int? particleCount,
    double? particleSize,
    double? particleReach,
    double? particleFlight,
    double? particleGap,
    double? particleLife,
    double? particleSpread,
    WavePalette? palette,
  }) {
    return DistortionWaveStyle(
      type: type ?? this.type,
      anticipation: anticipation ?? this.anticipation,
      travel: travel ?? this.travel,
      launchGap: launchGap ?? this.launchGap,
      linger: linger ?? this.linger,
      rimFade: rimFade ?? this.rimFade,
      rimEasing: rimEasing ?? this.rimEasing,
      returnSpeed: returnSpeed ?? this.returnSpeed,
      easing: easing ?? this.easing,
      pull: pull ?? this.pull,
      inhale: inhale ?? this.inhale,
      gatherGlow: gatherGlow ?? this.gatherGlow,
      gatherDots: gatherDots ?? this.gatherDots,
      amplitude: amplitude ?? this.amplitude,
      lensWidth: lensWidth ?? this.lensWidth,
      aberration: aberration ?? this.aberration,
      swell: swell ?? this.swell,
      blur: blur ?? this.blur,
      blurAhead: blurAhead ?? this.blurAhead,
      blurBehind: blurBehind ?? this.blurBehind,
      lead: lead ?? this.lead,
      tail: tail ?? this.tail,
      strength: strength ?? this.strength,
      rimWidth: rimWidth ?? this.rimWidth,
      rimUnevenness: rimUnevenness ?? this.rimUnevenness,
      rimStrength: rimStrength ?? this.rimStrength,
      rimSoftness: rimSoftness ?? this.rimSoftness,
      cornerRadius: cornerRadius ?? this.cornerRadius,
      continuousCorners: continuousCorners ?? this.continuousCorners,
      rimPulse: rimPulse ?? this.rimPulse,
      hairlineWidth: hairlineWidth ?? this.hairlineWidth,
      hairlineOpacity: hairlineOpacity ?? this.hairlineOpacity,
      hairlineWhite: hairlineWhite ?? this.hairlineWhite,
      hairlineLinger: hairlineLinger ?? this.hairlineLinger,
      hairlineFade: hairlineFade ?? this.hairlineFade,
      orientation: orientation ?? this.orientation,
      particleCount: particleCount ?? this.particleCount,
      particleSize: particleSize ?? this.particleSize,
      particleReach: particleReach ?? this.particleReach,
      particleFlight: particleFlight ?? this.particleFlight,
      particleGap: particleGap ?? this.particleGap,
      particleLife: particleLife ?? this.particleLife,
      particleSpread: particleSpread ?? this.particleSpread,
      palette: palette ?? this.palette,
    );
  }
}

/// An sRGB colour in OKLab, as the shader mixes colours.
List<double> oklabOf(Color color) {
  double linear(double c) =>
      c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  double cbrt(double x) =>
      x < 0 ? -math.pow(-x, 1 / 3).toDouble() : math.pow(x, 1 / 3).toDouble();
  final lr = linear(color.r), lg = linear(color.g), lb = linear(color.b);
  final l = cbrt(0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb);
  final m = cbrt(0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb);
  final s = cbrt(0.0883024619 * lr + 0.2817188376 * lg + 0.6299787005 * lb);
  return [
    0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
    1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
    0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s,
  ];
}
