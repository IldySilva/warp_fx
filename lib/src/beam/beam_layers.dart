import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'beam_math.dart';
import 'beam_spec.dart';
import 'beam_tuning.dart';

/// The two compiled beam programs.
class BeamPrograms {
  const BeamPrograms(this.rotate, this.blob);
  final ui.FragmentProgram rotate;
  final ui.FragmentProgram blob;
}

/// Everything a beam's look depends on, resolved from the widget.
class BeamConfig {
  const BeamConfig({
    required this.size,
    required this.variant,
    required this.theme,
    required this.staticColors,
    required this.duration,
    required this.radius,
    required this.brightness,
    required this.saturation,
    required this.hueRange,
    required this.strength,
    required this.tuning,
    required this.reduceMotion,
  });

  /// Spec key: `sm`, `md`, `line`, `pulse-inner` or `pulse-outside`.
  final String size;

  /// Spec key: `colorful`, `mono`, `ocean` or `sunset`.
  final String variant;

  /// `dark` or `light`.
  final String theme;
  final bool staticColors;
  final double duration;
  final double radius;
  final double brightness;
  final double saturation;
  final double hueRange;
  final double strength;
  final BeamTuning tuning;
  final bool reduceMotion;

  bool get isDark => theme == 'dark';
  bool get isPulse => size == 'pulse-inner' || size == 'pulse-outside';
  double get monoMul =>
      variant == 'mono' ? num_(BeamSpec.defaults['monoOpacityMultiplier']) : 1;

  @override
  bool operator ==(Object other) =>
      other is BeamConfig &&
      other.size == size &&
      other.variant == variant &&
      other.theme == theme &&
      other.staticColors == staticColors &&
      other.duration == duration &&
      other.radius == radius &&
      other.brightness == brightness &&
      other.saturation == saturation &&
      other.hueRange == hueRange &&
      other.strength == strength &&
      other.tuning == tuning &&
      other.reduceMotion == reduceMotion;

  @override
  int get hashCode => Object.hash(
    size,
    variant,
    theme,
    staticColors,
    duration,
    radius,
    brightness,
    saturation,
    hueRange,
    strength,
    tuning,
    reduceMotion,
  );
}

/// The layers of one beam, drawn at a time and a fade.
abstract class BeamLayers {
  BeamLayers(this.config);

  /// Builds the layers for `config`.
  factory BeamLayers.of(BeamConfig config, BeamPrograms programs) =>
      switch (config.size) {
        'line' => LineLayers(config, programs),
        'pulse-inner' || 'pulse-outside' => PulseLayers(config, programs),
        _ => RotateLayers(config, programs),
      };

  final BeamConfig config;

  /// What is drawn behind the child: only `pulse-outside` has anything.
  void paintBehind(Canvas canvas, Size size, double t, double fade) {}

  /// What is drawn over the child.
  void paintFront(Canvas canvas, Size size, double t, double fade);

  /// Releases the shaders.
  void dispose();
}

// ── Uniform writing ──────────────────────────────────────────────────────────

class _Uniforms {
  _Uniforms(this.shader);
  final ui.FragmentShader shader;
  int _i = 0;

  void f(double v) => shader.setFloat(_i++, v);
  void v2(double a, double b) {
    f(a);
    f(b);
  }

  void v4(double a, double b, double c, double d) {
    f(a);
    f(b);
    f(c);
    f(d);
  }

  /// The colour matrix as three vec4 rows; `w0` goes in the first row's w.
  void matrix(List<double> m, [double w0 = 0]) {
    v4(m[0], m[1], m[2], w0);
    v4(m[3], m[4], m[5], 0);
    v4(m[6], m[7], m[8], 0);
  }

  /// `values`, zero-padded or cut to `length` floats.
  void padded(List<double> values, int length) {
    for (var k = 0; k < length; k++) {
      f(k < values.length ? values[k] : 0);
    }
  }
}

void _fill(Canvas canvas, Rect rect, ui.FragmentShader shader) {
  canvas.drawRect(rect, Paint()..shader = shader);
}

void _blurred(Canvas canvas, Rect rect, double sigma, void Function() draw) {
  if (sigma <= 0) {
    draw();
    return;
  }
  canvas.saveLayer(
    rect.inflate(sigma * 3),
    Paint()
      ..imageFilter = ui.ImageFilter.blur(
        sigmaX: sigma,
        sigmaY: sigma,
        tileMode: TileMode.decal,
      ),
  );
  draw();
  canvas.restore();
}

// ── Blob encoding (beam_blob.frag: 16 floats per blob) ───────────────────────

const int _maxLayerBlobs = 16;
const int _blobFloats = 16;

/// A plain CSS `color → transparent` blob.
List<double> simpleBlob(
  double rx,
  double ry,
  double cx,
  double cy,
  double r,
  double g,
  double b,
  double a, {
  double end = 1,
}) {
  return [
    rx,
    ry,
    cx,
    cy,
    r,
    g,
    b,
    a,
    end / 3,
    a * 2 / 3,
    end * 2 / 3,
    a / 3,
    end,
    0,
    0,
    0,
  ];
}

/// A gradient stop, colour channels 0–255.
typedef BlobStop = ({double r, double g, double b, double a, double pos});

/// A blob from 2–4 CSS stops; its colour is the first stop's.
List<double> stopsBlob(
  double rx,
  double ry,
  double cx,
  double cy,
  List<BlobStop> stops,
) {
  final first = stops.first;
  final r = first.r / 255, g = first.g / 255, b = first.b / 255;
  final a0 = first.a;
  if (stops.length == 3) {
    final midA = stops[1].a / 2, midPos = (stops[1].pos + stops[2].pos) / 2;
    return [
      rx,
      ry,
      cx,
      cy,
      r,
      g,
      b,
      a0,
      stops[1].pos,
      stops[1].a,
      midPos,
      midA,
      stops[2].pos,
      0,
      0,
      0,
    ];
  }
  if (stops.length >= 4) {
    return [
      rx,
      ry,
      cx,
      cy,
      r,
      g,
      b,
      a0,
      stops[1].pos,
      stops[1].a,
      stops[2].pos,
      stops[2].a,
      stops[3].pos,
      0,
      0,
      0,
    ];
  }
  final end = stops.length > 1 ? stops[1].pos : 1.0;
  return [
    rx,
    ry,
    cx,
    cy,
    r,
    g,
    b,
    a0,
    end / 3,
    a0 * 2 / 3,
    end * 2 / 3,
    a0 / 3,
    end,
    0,
    0,
    0,
  ];
}

/// Writes one beam_blob.frag draw.
void _blobLayer(
  ui.FragmentShader shader, {
  required Rect box,
  required double radius,
  required double borderWidth,
  required int geomKind,
  required double edgeMaskPx,
  List<double>? radial, // cx, cy, rx, ry, midPos, midAlpha
  required List<double> blobs,
  required List<double> matrix,
  required double opacity,
}) {
  final u = _Uniforms(shader)
    ..v4(box.left, box.top, box.width, box.height)
    ..v4(radius, borderWidth, geomKind.toDouble(), edgeMaskPx);
  if (radial != null) {
    u
      ..v4(radial[0], radial[1], radial[2], radial[3])
      ..v4(radial[4], radial[5], 1, blobs.length / _blobFloats);
  } else {
    u
      ..v4(0, 0, 1, 1)
      ..v4(0.5, 0.5, 0, blobs.length / _blobFloats);
  }
  u
    ..matrix(matrix, opacity)
    ..padded(blobs, _maxLayerBlobs * _blobFloats);
}

// ── Rotate family: sm, md ────────────────────────────────────────────────────

const int _maxRotateBlobs = 12;
const int _maxBgVec4 = 8;
const int _maxMaskVec4 = 6;

List<double> _rotateBlobs(
  List<GradientBlob> blobs, {
  double sizeScale = 1,
  double? alpha,
}) {
  final out = <double>[];
  for (final blob in blobs) {
    final c = parseCssColor(blob.color);
    if (c == null) continue;
    final pos = parsePercentPair(blob.pos);
    final radii = parsePixelPair(blob.size);
    // The web rounds scaled sizes to whole pixels.
    final rx = sizeScale == 1 ? radii.w : (radii.w * sizeScale).roundToDouble();
    final ry = sizeScale == 1 ? radii.h : (radii.h * sizeScale).roundToDouble();
    out.addAll([rx, ry, pos.x, pos.y, c.r, c.g, c.b, alpha ?? c.a]);
  }
  return out;
}

List<double> _flattenStops(Object? stops) => [
  for (final s in stops as List) ...[
    ((s as List)[0] as num) / 100,
    (s[1] as num).toDouble(),
  ],
];

/// The travelling beam: inner glow, stroke ring and a blurred bloom ring.
class RotateLayers extends BeamLayers {
  RotateLayers(super.config, BeamPrograms programs)
    : _inner = programs.rotate.fragmentShader(),
      _stroke = programs.rotate.fragmentShader(),
      _bloom = programs.rotate.fragmentShader() {
    final rotate = BeamSpec.rotate;
    final small = config.size == 'sm';
    final derivation =
        rotate['innerGradientDerivation'] as Map<String, dynamic>;
    _strokeBlobs = small
        ? _rotateBlobs(BeamSpec.smallPalette(config.variant).border)
        : _rotateBlobs(BeamSpec.borderPalette(config.variant));
    _innerBlobs = small
        ? _rotateBlobs(BeamSpec.smallPalette(config.variant).inner)
        : _rotateBlobs(
            BeamSpec.borderPalette(config.variant),
            sizeScale: num_(derivation['sizeScale']),
            alpha: num_(
              config.variant == 'mono'
                  ? derivation['monoAlpha']
                  : derivation['alpha'],
            ),
          );
    _whiteStops = _flattenStops(
      (rotate['whiteGradientStops'] as Map)[config.theme],
    );
    _bloomStops = _flattenStops(
      (rotate['bloomGradientStops'] as Map)[config.theme],
    );
    _beamMask = _flattenStops(rotate['beamMaskStops']);
    _smallMask = _flattenStops(rotate['smallMaskStops']);
    _shadow =
        parseCssColor(
          BeamSpec.themePreset(config.size, config.theme).innerShadow,
        ) ??
        Rgba.clear;
    _shadowBlur = num_((rotate['innerShadowBlur'] as Map)[small ? 'sm' : 'md']);
    _edgeMaskPx = small ? 0 : num_(rotate['innerEdgeMaskPx']);
    _bloomBlur = num_(rotate['bloomBlurPx']);
    _hueShiftPeriod = num_(BeamSpec.defaults['rotateHueShiftPeriod']);
    _colors = BeamSpec.themePreset(config.size, config.theme);
    _borderWidth = BeamSpec.sizePreset(config.size).borderWidth;
    _bloomMatrix = composedFilterMatrix(
      0,
      config.brightness,
      config.saturation,
    );
  }

  final ui.FragmentShader _inner;
  final ui.FragmentShader _stroke;
  final ui.FragmentShader _bloom;
  late final List<double> _strokeBlobs;
  late final List<double> _innerBlobs;
  late final List<double> _whiteStops;
  late final List<double> _bloomStops;
  late final List<double> _beamMask;
  late final List<double> _smallMask;
  late final Rgba _shadow;
  late final double _shadowBlur;
  late final double _edgeMaskPx;
  late final double _bloomBlur;
  late final double _hueShiftPeriod;
  late final ThemeColors _colors;
  late final double _borderWidth;
  late final List<double> _bloomMatrix;

  void _layer(
    ui.FragmentShader shader,
    Size size, {
    required double angle,
    required int kind,
    required double edgeMaskPx,
    required List<double> blobs,
    required List<double> bg,
    required bool bgIsBlack,
    required List<double> mask,
    required List<double> matrix,
    required double opacity,
    Rgba shadow = Rgba.clear,
    double shadowBlur = 0,
  }) {
    _Uniforms(shader)
      ..v2(size.width, size.height)
      ..v4(angle, config.radius, _borderWidth, kind.toDouble())
      ..v4(edgeMaskPx, blobs.length / 8, bg.length / 2, bgIsBlack ? 1 : 0)
      ..v4(mask.length / 2, opacity, shadowBlur, 0)
      ..v4(shadow.r, shadow.g, shadow.b, shadow.a)
      ..matrix(matrix)
      ..padded(blobs, _maxRotateBlobs * 8)
      ..padded(bg, _maxBgVec4 * 4)
      ..padded(mask, _maxMaskVec4 * 4);
  }

  @override
  void paintFront(Canvas canvas, Size size, double t, double fade) {
    final angle = cycle(t, config.duration);
    // With static colours the web layers have no filter at all.
    final matrix = config.staticColors
        ? identityMatrix
        : composedFilterMatrix(
            -config.hueRange +
                2 * config.hueRange * pingPong(t / _hueShiftPeriod),
            config.brightness,
            config.saturation,
          );
    final base = fade * config.strength * config.monoMul;
    final rect = Offset.zero & size;

    _layer(
      _inner,
      size,
      angle: angle,
      kind: 1,
      edgeMaskPx: _edgeMaskPx,
      blobs: _innerBlobs,
      bg: const [],
      bgIsBlack: false,
      mask: config.size == 'sm' ? _smallMask : _beamMask,
      matrix: matrix,
      opacity: base * _colors.innerOpacity,
      shadow: _shadow,
      shadowBlur: _shadowBlur,
    );
    _fill(canvas, rect, _inner);

    _layer(
      _stroke,
      size,
      angle: angle,
      kind: 0,
      edgeMaskPx: 0,
      blobs: _strokeBlobs,
      bg: _whiteStops,
      bgIsBlack: !config.isDark,
      mask: _beamMask,
      matrix: matrix,
      opacity: base * _colors.strokeOpacity,
    );
    _fill(canvas, rect, _stroke);

    // The bloom has no hue-rotate on the web: static brightness and saturate.
    _layer(
      _bloom,
      size,
      angle: angle,
      kind: 2,
      edgeMaskPx: 0,
      blobs: const [],
      bg: _bloomStops,
      bgIsBlack: !config.isDark,
      mask: const [],
      matrix: _bloomMatrix,
      opacity: base * _colors.bloomOpacity,
    );
    _blurred(canvas, rect, _bloomBlur, () => _fill(canvas, rect, _bloom));
  }

  @override
  void dispose() {
    _inner.dispose();
    _stroke.dispose();
    _bloom.dispose();
  }
}

// ── Line family ──────────────────────────────────────────────────────────────

class _LineBlob {
  _LineBlob(Map<String, dynamic> m)
    : color = parseCssColor(m['color'] as String) ?? Rgba.white,
      w = num_(m['sizeW']),
      h = num_(m['sizeH']),
      dx = num_(m['offsetX']),
      dy = num_(m['offsetY']);
  final Rgba color;
  final double w;
  final double h;
  final double dx;
  final double dy;
}

class _BloomGradient {
  _BloomGradient(Map<String, dynamic> m)
    : xPct = m['xPct'] == null ? null : num_(m['xPct']),
      yOff = num_(m['yOffPx']),
      wBase = num_((m['w'] as Map)['base']),
      wMult = (m['w'] as Map)['mult'] as String,
      hBase = num_((m['h'] as Map)['base']),
      hMult = (m['h'] as Map)['mult'] as String,
      stops = [
        for (final s in m['stops'] as List)
          (
            r: num_((s as Map)['r']),
            g: num_(s['g']),
            b: num_(s['b']),
            a: num_(s['a']),
            pos: num_(s['pos']),
          ),
      ];
  final double? xPct;
  final double yOff;
  final double wBase;
  final String wMult;
  final double hBase;
  final String hMult;
  final List<BlobStop> stops;
}

/// The travelling glow along the bottom edge, breathing and spiking.
class LineLayers extends BeamLayers {
  LineLayers(super.config, BeamPrograms programs)
    : _inner = programs.blob.fragmentShader(),
      _stroke = programs.blob.fragmentShader(),
      _bloom = programs.blob.fragmentShader() {
    final line = BeamSpec.line;
    final palettes = BeamSpec.palettes;
    _tables = LineKeyframes.fromJson(line['keyframes'] as Map<String, dynamic>);
    _strokeBlobs = [
      for (final e
          in ((palettes['line'] as Map)[config.variant] as Map)[config.theme]
              as List)
        _LineBlob(e as Map<String, dynamic>),
    ];
    _innerBlobs = [
      for (final e in (palettes['lineInner'] as Map)[config.variant] as List)
        _LineBlob(e as Map<String, dynamic>),
    ];
    _bloomDefs = [
      for (final e
          in ((line['bloomGradients'] as Map)[config.variant]
                  as Map)[config.theme]
              as List)
        _BloomGradient(e as Map<String, dynamic>),
    ];
    final wh =
        (line['whiteHighlight'] as Map)[config.theme] as Map<String, dynamic>;
    _whW = num_(wh['w']);
    _whH = num_(wh['h']);
    _whY = num_(wh['yOffset']);
    final whColor = wh['onBlack'] == true ? 0.0 : 255.0;
    _whStops = [
      for (final s in wh['stops'] as List)
        (
          r: whColor,
          g: whColor,
          b: whColor,
          a: num_((s as List)[1]),
          pos: num_(s[0]) / 100,
        ),
    ];
    final mask = line['beamMaskEllipse'] as Map;
    _mask = [
      num_(mask['w']),
      num_(mask['h']),
      num_((mask['softStop'] as List)[0]) / 100,
      num_(mask['softStop'][1]),
    ];
    final bloomMask = line['bloomMaskEllipse'] as Map;
    _bloomMask = [
      num_(bloomMask['w']),
      num_(bloomMask['h']),
      num_((bloomMask['softStop'] as List)[0]) / 100,
      num_(bloomMask['softStop'][1]),
    ];
    final d = BeamSpec.defaults;
    _hueShiftPeriod = num_(d['rotateHueShiftPeriod']);
    _bloomHuePeriod = num_(d['lineBloomHueShiftPeriod']);
    _bloomHueBonus = num_(d['lineBloomHueRangeBonus']);
    _innerEdge = num_(BeamSpec.rotate['innerEdgeMaskPx']);
    _colors = BeamSpec.themePreset('line', config.theme);
    _borderWidth = BeamSpec.sizePreset('line').borderWidth;
    // The animated bloom filter includes blur(8px); mono with static colours
    // keeps a base blur(6px); other static colours none.
    _bloomBlur = config.staticColors
        ? (config.variant == 'mono' ? num_(line['monoBloomExtraBlurPx']) : 0)
        : num_(line['bloomBlurPx']);
  }

  final ui.FragmentShader _inner;
  final ui.FragmentShader _stroke;
  final ui.FragmentShader _bloom;
  late final LineKeyframes _tables;
  late final List<_LineBlob> _strokeBlobs;
  late final List<_LineBlob> _innerBlobs;
  late final List<_BloomGradient> _bloomDefs;
  late final double _whW, _whH, _whY;
  late final List<BlobStop> _whStops;
  late final List<double> _mask;
  late final List<double> _bloomMask;
  late final double _hueShiftPeriod,
      _bloomHuePeriod,
      _bloomHueBonus,
      _innerEdge;
  late final ThemeColors _colors;
  late final double _borderWidth;
  late final double _bloomBlur;

  @override
  void paintFront(Canvas canvas, Size size, double t, double fade) {
    final w = size.width, h = size.height;
    final v = _tables.at(t, config.duration);
    final hr = config.hueRange;
    final matrix = config.staticColors
        ? identityMatrix
        : composedFilterMatrix(
            -hr + 2 * hr * pingPong(t / _hueShiftPeriod),
            config.brightness,
            config.saturation,
          );
    final bloomHr = hr + _bloomHueBonus;
    final bloomMatrix = config.staticColors
        ? identityMatrix
        : composedFilterMatrix(
            -bloomHr + 2 * bloomHr * pingPong(t / _bloomHuePeriod),
            config.brightness,
            config.saturation,
          );
    final bx = v.x * w;
    final base = fade * v.edge * config.strength;
    final rect = Offset.zero & size;
    final radial = [bx, h, _mask[0] * v.w, _mask[1] * v.h, _mask[2], _mask[3]];

    // Inner glow.
    _blobLayer(
      _inner,
      box: rect,
      radius: config.radius,
      borderWidth: _borderWidth,
      geomKind: 1,
      edgeMaskPx: _innerEdge,
      radial: radial,
      blobs: [
        for (final e in _innerBlobs)
          ...simpleBlob(
            e.w * v.w,
            e.h * v.h,
            bx + e.dx,
            h - e.dy.abs(),
            e.color.r,
            e.color.g,
            e.color.b,
            e.color.a,
          ),
      ],
      matrix: matrix,
      opacity: base * _colors.innerOpacity,
    );
    _fill(canvas, rect, _inner);

    // Stroke band: the white travelling highlight first, so on top.
    _blobLayer(
      _stroke,
      box: rect,
      radius: config.radius,
      borderWidth: _borderWidth,
      geomKind: 0,
      edgeMaskPx: 0,
      radial: radial,
      blobs: [
        ...stopsBlob(_whW * v.w, _whH * v.h, bx, h + _whY, _whStops),
        for (final e in _strokeBlobs)
          ...simpleBlob(
            e.w * v.w,
            e.h * v.h,
            bx + e.dx,
            h + e.dy,
            e.color.r,
            e.color.g,
            e.color.b,
            e.color.a,
          ),
      ],
      matrix: matrix,
      opacity: base * _colors.strokeOpacity,
    );
    _fill(canvas, rect, _stroke);

    // Bloom.
    _blobLayer(
      _bloom,
      box: rect,
      radius: config.radius,
      borderWidth: _borderWidth,
      geomKind: 1,
      edgeMaskPx: 0,
      radial: [
        bx,
        h,
        _bloomMask[0] * v.w,
        _bloomMask[1] * v.h,
        _bloomMask[2],
        _bloomMask[3],
      ],
      blobs: [
        for (final g in _bloomDefs)
          ...stopsBlob(
            g.wBase * v.mult(g.wMult),
            g.hBase * v.mult(g.hMult),
            g.xPct != null ? g.xPct! / 100 * w : bx,
            h + g.yOff,
            g.stops,
          ),
      ],
      matrix: bloomMatrix,
      opacity: base * _colors.bloomOpacity,
    );
    _blurred(canvas, rect, _bloomBlur, () => _fill(canvas, rect, _bloom));
  }

  @override
  void dispose() {
    _inner.dispose();
    _stroke.dispose();
    _bloom.dispose();
  }
}

// ── Pulse family ─────────────────────────────────────────────────────────────

class _PulseBlob {
  const _PulseBlob({
    required this.region,
    required this.quad,
    required this.w,
    required this.h,
    required this.xFrac,
    required this.yFrac,
    required this.color,
    this.fadeEnd = 1,
  });

  /// 1–3: the oscillator region for size and drift; 0 is static.
  final int region;

  /// Opacity quadrant: tl, tr, bl or br.
  final String quad;
  final double w;
  final double h;
  final double xFrac;
  final double yFrac;
  final Rgba color;
  final double fadeEnd;

  _PulseBlob withSize(double w, double h) => _PulseBlob(
    region: region,
    quad: quad,
    w: w,
    h: h,
    xFrac: xFrac,
    yFrac: yFrac,
    color: color,
    fadeEnd: fadeEnd,
  );
}

class _Box {
  const _Box(
    this.rect,
    this.radius,
    this.geomKind,
    this.borderWidth,
    this.edgeMaskPx,
  );
  final Rect rect;
  final double radius;
  final int geomKind;
  final double borderWidth;
  final double edgeMaskPx;
}

/// The breathing glow: no rotation, blobs drifting and swelling round the
/// edge while the hue turns.
class PulseLayers extends BeamLayers {
  PulseLayers(super.config, BeamPrograms programs)
    : _inner = programs.blob.fragmentShader(),
      _stroke = programs.blob.fragmentShader(),
      _bloom = programs.blob.fragmentShader() {
    final pulse = BeamSpec.pulse;
    _outside = config.size == 'pulse-outside';
    _oc = pulse['outsideConstants'] as Map<String, dynamic>;
    final ring = _ringDefs();
    final outerCore = _tableDefs(pulse['outerCore'] as List);
    _strokeDefs = _outside ? outerCore : ring;
    _innerDefs = _outside ? outerCore : _innerLayerDefs(ring);
    _bloomDefs = _tableDefs(
      (_outside ? pulse['outerBloom'] : pulse['innerBloom']) as List,
    );
    final section =
        ((_outside ? pulse['outside'] : pulse['inner']) as Map)[config.theme]
            as Map<String, dynamic>;
    _oscillators = [
      for (final o in section['oscillators'] as List)
        Oscillator.fromJson(o as Map<String, dynamic>),
    ];
    _frozenBloomAlpha = section['frozenBloomAlpha'] == null
        ? null
        : num_(section['frozenBloomAlpha']);
    _huePeriod = num_((pulse['huePeriod'] as Map)[config.size]);
    _colors = BeamSpec.themePreset(config.size, config.theme);
    _borderWidth = BeamSpec.sizePreset(config.size).borderWidth;
    _innerBloomBlur = num_(pulse['innerBloomBlurPx']);
    _innerEdge = num_(BeamSpec.rotate['innerEdgeMaskPx']);
  }

  final ui.FragmentShader _inner;
  final ui.FragmentShader _stroke;
  final ui.FragmentShader _bloom;
  late final bool _outside;
  late final Map<String, dynamic> _oc;
  late final List<_PulseBlob> _strokeDefs;
  late final List<_PulseBlob> _innerDefs;
  late final List<_PulseBlob> _bloomDefs;
  late final List<Oscillator> _oscillators;
  late final double? _frozenBloomAlpha;
  late final double _huePeriod;
  late final ThemeColors _colors;
  late final double _borderWidth;
  late final double _innerBloomBlur;
  late final double _innerEdge;

  static const double _defaultPulseDuration = 2.3;

  List<_PulseBlob> _ringDefs() {
    final ringMap = BeamSpec.pulse['ringMap'] as List;
    final palette = BeamSpec.borderPalette(config.variant);
    return [
      for (var i = 0; i < palette.length; i++)
        () {
          final pos = parsePercentPair(palette[i].pos);
          final size = parsePixelPair(palette[i].size);
          final m = ringMap[i] as Map;
          return _PulseBlob(
            region: (m['region'] as num).toInt(),
            quad: m['quad'] as String,
            w: size.w,
            h: size.h,
            xFrac: pos.x,
            yFrac: pos.y,
            color: parseCssColor(palette[i].color) ?? Rgba.white,
          );
        }(),
    ];
  }

  List<_PulseBlob> _tableDefs(List table) {
    final palette = BeamSpec.borderPalette(config.variant);
    return [
      for (final raw in table)
        () {
          final e = raw as Map<String, dynamic>;
          final src = palette[(e['ci'] as num).toInt()];
          final srcPos = parsePercentPair(src.pos);
          double? pct(Object? s) => s == null
              ? null
              : double.parse((s as String).replaceAll('%', '')) / 100;
          return _PulseBlob(
            region: (e['region'] as num).toInt(),
            quad: e['quad'] as String,
            w: num_(e['w']),
            h: num_(e['h']),
            xFrac: pct(e['x']) ?? srcPos.x,
            yFrac: pct(e['y']) ?? srcPos.y,
            color: parseCssColor(src.color) ?? Rgba.white,
          );
        }(),
    ];
  }

  /// pulse-inner's inner layer: the ring at smaller sizes, plus four corner
  /// accents.
  List<_PulseBlob> _innerLayerDefs(List<_PulseBlob> ring) {
    final sizes = BeamSpec.pulse['innerSizes'] as List;
    final accent = BeamSpec.pulse['innerCornerAccent'] as Map;
    final c = config.isDark ? 1.0 : 0.0;
    final alpha = num_((accent['alpha'] as Map)[config.theme]);
    final size = num_(accent['sizePx']);
    final fadeEnd = num_(accent['fadeStop']) / 100;
    return [
      for (var i = 0; i < ring.length; i++)
        ring[i].withSize(num_((sizes[i] as List)[0]), num_(sizes[i][1])),
      for (final (x, y, quad) in const [
        (0.0, 0.0, 'tl'),
        (1.0, 0.0, 'tr'),
        (0.0, 1.0, 'bl'),
        (1.0, 1.0, 'br'),
      ])
        _PulseBlob(
          region: 0,
          quad: quad,
          w: size,
          h: size,
          xFrac: x,
          yFrac: y,
          color: Rgba(c, c, c, alpha),
          fadeEnd: fadeEnd,
        ),
    ];
  }

  double get _pad => _outside ? num_(_oc['bloomInsetPx']) : 0;

  double _clampScale(double v) => v
      .clamp(
        num_((_oc['scaleClamp'] as Map)['min']),
        num_((_oc['scaleClamp'] as Map)['max']),
      )
      .toDouble();

  List<double> _blobs(
    List<_PulseBlob> defs,
    _Box box,
    Map<String, double> osc,
    double? frozenAlpha,
    double sx,
    double sy,
  ) {
    final out = <double>[];
    final b = box.rect;
    for (final d in defs) {
      double rx, ry, cx, cy, alpha;
      if (frozenAlpha != null) {
        // The web's blurred bloom never re-rasterises: literal geometry with a
        // time-averaged alpha.
        rx = d.w * sx;
        ry = d.h * sy;
        cx = b.left + d.xFrac * b.width;
        cy = b.top + d.yFrac * b.height;
        alpha = frozenAlpha;
      } else {
        final r = d.region;
        final bw = r > 0 ? osc['bw$r'] ?? 1 : 1.0;
        final bh = r > 0 ? (osc['bh$r'] ?? 1) * (osc['bgh'] ?? 1) : 1.0;
        final dx = r > 0 ? osc['bx$r'] ?? 0 : 0.0;
        final dy = r > 0 ? osc['by$r'] ?? 0 : 0.0;
        final bop = osc['bop-${d.quad}'] ?? 1;
        // Ring and table blobs take the quadrant's opacity as their alpha;
        // the static corner accents multiply their own.
        alpha = r == 0 ? d.color.a * bop : bop;
        rx = d.w * bw * sx;
        ry = d.h * bh * sy;
        cx = b.left + d.xFrac * b.width + dx;
        cy = b.top + d.yFrac * b.height + dy;
      }
      out.addAll(
        simpleBlob(
          rx,
          ry,
          cx,
          cy,
          d.color.r,
          d.color.g,
          d.color.b,
          alpha,
          end: d.fadeEnd,
        ),
      );
    }
    return out;
  }

  ({
    _Box stroke,
    _Box inner,
    _Box bloom,
    Map<String, double> osc,
    List<double> matrix,
    List<double> glowMatrix,
    double sx,
    double sy,
    double base,
  })
  _frame(Size size, double t, double fade) {
    final w = size.width, h = size.height;
    final pad = _pad;
    final tuning = config.tuning;
    final reduce = config.reduceMotion;
    final time = reduce ? 0.0 : t;
    final scale = config.duration / _defaultPulseDuration;
    final osc = <String, double>{
      for (final o in _oscillators)
        o.prop: reduce ? o.a : o.valueAt(time, scale),
    };
    final hue = config.staticColors || reduce
        ? 0.0
        : pulseHueDegrees(time, _huePeriod);
    final matrix = composedFilterMatrix(
      hue,
      config.brightness,
      config.saturation,
    );
    // Glow layers take their own brightness and saturation but the shared hue.
    final glowMatrix = _outside
        ? composedFilterMatrix(
            hue,
            tuning.glowBrightness ?? config.brightness,
            tuning.glowSaturate ?? config.saturation,
          )
        : matrix;
    final ref = _oc['referenceSize'] as Map;
    // The web clamps the measured ratio and applies the boost on top.
    final sx = _outside
        ? _clampScale(w / num_(ref['w'])) * tuning.glowBoost
        : 1.0;
    final sy = _outside
        ? _clampScale(h / num_(ref['h'])) * tuning.glowBoost
        : 1.0;
    final core = num_(_oc['coreInsetPx']);
    final element = Rect.fromLTWH(pad, pad, w, h);
    return (
      stroke: _Box(element, config.radius, 0, _outside ? 1 : _borderWidth, 0),
      inner: _outside
          ? _Box(element.inflate(core), config.radius + core, 1, 1, 0)
          : _Box(element, config.radius, 1, _borderWidth, _innerEdge),
      bloom: _outside
          ? _Box(
              Rect.fromLTWH(0, 0, w + pad * 2, h + pad * 2),
              config.radius + pad,
              1,
              1,
              0,
            )
          : _Box(element, config.radius, 0, _borderWidth, 0),
      osc: osc,
      matrix: matrix,
      glowMatrix: glowMatrix,
      sx: sx,
      sy: sy,
      base: fade * config.strength * config.monoMul,
    );
  }

  void _write(
    ui.FragmentShader shader,
    _Box box,
    List<double> blobs,
    List<double> matrix,
    double opacity,
  ) {
    _blobLayer(
      shader,
      box: box.rect,
      radius: box.radius,
      borderWidth: box.borderWidth,
      geomKind: box.geomKind,
      edgeMaskPx: box.edgeMaskPx,
      blobs: blobs,
      matrix: matrix,
      opacity: opacity,
    );
  }

  double get _glowBlur =>
      config.tuning.coreBlur ??
      (_outside ? num_((_oc['glowBlurPx'] as Map)[config.theme]) : 0);

  double get _bloomBlur =>
      config.tuning.bloomBlur ??
      (_outside
          ? num_((_oc['bloomBlurPx'] as Map)[config.theme])
          : _innerBloomBlur);

  @override
  void paintBehind(Canvas canvas, Size size, double t, double fade) {
    if (!_outside) return;
    final f = _frame(size, t, fade);
    final pad = _pad;
    final full = Rect.fromLTWH(
      0,
      0,
      size.width + pad * 2,
      size.height + pad * 2,
    );
    final tuning = config.tuning;
    final scale = _oc['glowScale'] as Map;

    _write(
      _bloom,
      f.bloom,
      _blobs(_bloomDefs, f.bloom, f.osc, _frozenBloomAlpha, f.sx, f.sy),
      f.glowMatrix,
      f.base * _colors.bloomOpacity * tuning.bloomOpacity,
    );
    _write(
      _inner,
      f.inner,
      _blobs(_innerDefs, f.inner, f.osc, null, f.sx, f.sy),
      f.glowMatrix,
      f.base * _colors.innerOpacity * tuning.innerOpacity,
    );

    canvas.save();
    // The glow canvas reaches `pad` past the element on every side; core and
    // bloom carry `scale(0.95, 0.9)` about its centre.
    canvas.translate(-pad, -pad);
    canvas.translate(full.width / 2, full.height / 2);
    canvas.scale(num_(scale['x']), num_(scale['y']));
    canvas.translate(-full.width / 2, -full.height / 2);
    _blurred(canvas, full, _bloomBlur, () => _fill(canvas, full, _bloom));
    _blurred(canvas, full, _glowBlur, () => _fill(canvas, full, _inner));
    canvas.restore();
  }

  @override
  void paintFront(Canvas canvas, Size size, double t, double fade) {
    final f = _frame(size, t, fade);
    final tuning = config.tuning;
    final stroke = _blobs(_strokeDefs, f.stroke, f.osc, null, f.sx, f.sy);
    _write(
      _stroke,
      f.stroke,
      stroke,
      f.matrix,
      f.base * _colors.strokeOpacity * tuning.strokeOpacity,
    );

    if (_outside) {
      // Only the 1px ring is over the content, on the element's own edge.
      final pad = _pad;
      canvas.save();
      canvas.translate(-pad, -pad);
      _fill(canvas, f.stroke.rect, _stroke);
      canvas.restore();
      return;
    }

    final rect = Offset.zero & size;
    _write(
      _inner,
      f.inner,
      _blobs(_innerDefs, f.inner, f.osc, null, 1, 1),
      f.matrix,
      f.base * _colors.innerOpacity * tuning.innerOpacity,
    );
    _write(
      _bloom,
      f.bloom,
      _blobs(_bloomDefs, f.bloom, f.osc, _frozenBloomAlpha, 1, 1),
      f.matrix,
      f.base * _colors.bloomOpacity * tuning.bloomOpacity,
    );
    _fill(canvas, rect, _inner);
    _fill(canvas, rect, _stroke);
    _blurred(canvas, rect, _bloomBlur, () => _fill(canvas, rect, _bloom));
  }

  @override
  void dispose() {
    _inner.dispose();
    _stroke.dispose();
    _bloom.dispose();
  }
}
