import 'dart:convert';

import 'beam_spec_data.dart';

/// Typed access to the border-beam spec, parsed once on first use.
class BeamSpec {
  BeamSpec._();

  static Map<String, dynamic>? _root;

  /// The whole spec.
  static Map<String, dynamic> get root =>
      _root ??= jsonDecode(kBeamSpecJson) as Map<String, dynamic>;

  static Map<String, dynamic> get defaults => _map(root['defaults']);
  static Map<String, dynamic> get rotate => _map(root['rotate']);
  static Map<String, dynamic> get line => _map(root['line']);
  static Map<String, dynamic> get pulse => _map(root['pulse']);
  static Map<String, dynamic> get palettes => _map(root['palettes']);

  /// Opacities, saturation and brightness of `size` (a spec key such as
  /// `pulse-outside`) on `theme` (`dark` or `light`).
  static ThemeColors themePreset(String size, String theme) =>
      ThemeColors._(_map(_map(_map(root['sizeThemePresets'])[size])[theme]));

  /// Radius and border width of `size`.
  static ({double borderRadius, double borderWidth}) sizePreset(String size) {
    final m = _map(_map(root['sizePresets'])[size]);
    return (
      borderRadius: num_(m['borderRadius']),
      borderWidth: num_(m['borderWidth']),
    );
  }

  /// The nine CSS radial gradients round a full-size beam.
  static List<GradientBlob> borderPalette(String variant) =>
      _list(_map(_map(palettes['border'])[variant])['border'])
          .map((e) => GradientBlob._(_map(e)))
          .toList();

  /// The `sm` beam's stroke and inner gradients.
  static ({List<GradientBlob> border, List<GradientBlob> inner}) smallPalette(
    String variant,
  ) {
    final m = _map(_map(palettes['small'])[variant]);
    return (
      border: _list(m['border']).map((e) => GradientBlob._(_map(e))).toList(),
      inner: _list(m['inner']).map((e) => GradientBlob._(_map(e))).toList(),
    );
  }

  static Map<String, dynamic> _map(Object? o) => o as Map<String, dynamic>;
  static List<dynamic> _list(Object? o) => o as List<dynamic>;
}

/// A number from the spec as a double.
double num_(Object? o) => (o as num).toDouble();

/// A CSS radial gradient from the spec: colour, position and radii as CSS
/// strings.
class GradientBlob {
  GradientBlob._(Map<String, dynamic> m)
    : color = m['color'] as String,
      pos = m['pos'] as String,
      size = m['size'] as String;

  final String color;
  final String pos;
  final String size;
}

/// Per size and theme opacities and filter values.
class ThemeColors {
  ThemeColors._(Map<String, dynamic> m)
    : strokeOpacity = num_(m['strokeOpacity']),
      innerOpacity = num_(m['innerOpacity']),
      bloomOpacity = num_(m['bloomOpacity']),
      innerShadow = m['innerShadow'] as String,
      saturation = num_(m['saturation']),
      brightness = m['brightness'] == null ? null : num_(m['brightness']);

  final double strokeOpacity;
  final double innerOpacity;
  final double bloomOpacity;
  final String innerShadow;
  final double saturation;
  final double? brightness;
}

/// A colour with channels 0–1.
class Rgba {
  const Rgba(this.r, this.g, this.b, this.a);
  final double r;
  final double g;
  final double b;
  final double a;

  static const white = Rgba(1, 1, 1, 1);
  static const clear = Rgba(0, 0, 0, 0);

  @override
  bool operator ==(Object other) =>
      other is Rgba &&
      other.r == r &&
      other.g == g &&
      other.b == b &&
      other.a == a;

  @override
  int get hashCode => Object.hash(r, g, b, a);

  @override
  String toString() => 'Rgba($r, $g, $b, $a)';
}

final _cssColor = RegExp(
  r'^rgba?\(\s*([\d.]+)\s*,\s*([\d.]+)\s*,\s*([\d.]+)\s*(?:,\s*([\d.]+)\s*)?\)$',
);

/// Parses `rgb(r, g, b)`, `rgba(r, g, b, a)` or `transparent`; null for
/// anything else.
Rgba? parseCssColor(String css) {
  final s = css.trim();
  if (s == 'transparent') return Rgba.clear;
  final m = _cssColor.firstMatch(s);
  if (m == null) return null;
  return Rgba(
    double.parse(m[1]!) / 255,
    double.parse(m[2]!) / 255,
    double.parse(m[3]!) / 255,
    m[4] != null ? double.parse(m[4]!) : 1,
  );
}

/// Parses `"33% -7.4%"` into fractions: (0.33, -0.074).
({double x, double y}) parsePercentPair(String value) {
  final parts = value.split(' ');
  double pct(String p) => double.parse(p.replaceAll('%', '')) / 100;
  return (
    x: pct(parts.isNotEmpty ? parts[0] : '0'),
    y: pct(parts.length > 1 ? parts[1] : '0'),
  );
}

/// Parses `"70px 40px"` into (70, 40).
({double w, double h}) parsePixelPair(String value) {
  final parts = value.split(' ');
  double px(String p) => double.parse(p.replaceAll('px', ''));
  return (
    w: px(parts.isNotEmpty ? parts[0] : '0'),
    h: px(parts.length > 1 ? parts[1] : '0'),
  );
}
