import 'package:flutter/foundation.dart';

/// Proportional dials on a border beam's prominence — the equivalent of the
/// web library's `--pulse-glow-boost`, `--beam-stroke-opacity`,
/// `--beam-core-blur` and friends. Applied by the pulse family.
///
/// The web demo's `pulse-outside` card is not stock output: it runs
/// [webDemoPulsePreset], which is why an untuned beam is softer than the demo.
@immutable
class BeamTuning {
  /// Leave any value out to keep the preset's.
  const BeamTuning({
    this.glowBoost = 1,
    this.strokeOpacity = 1,
    this.innerOpacity = 1,
    this.bloomOpacity = 1,
    this.coreBlur,
    this.bloomBlur,
    this.glowBrightness,
    this.glowSaturate,
  });

  /// Multiplier on the per-element glow scale; changes the pulse blobs' size.
  final double glowBoost;

  /// Multiplier on the stroke layer's opacity. The result is still clamped to
  /// 1, as CSS `opacity` is.
  final double strokeOpacity;

  /// Multiplier on the inner layer's opacity.
  final double innerOpacity;

  /// Multiplier on the bloom layer's opacity.
  final double bloomOpacity;

  /// Blur of the `pulseOutside` core, logical pixels.
  final double? coreBlur;

  /// Blur of the pulse bloom, logical pixels.
  final double? bloomBlur;

  /// Brightness of the outward glow layers only; the stroke ring keeps the
  /// beam's own, so ring and halo stay in step.
  final double? glowBrightness;

  /// Saturation of the outward glow layers only.
  final double? glowSaturate;

  /// No tuning: the library's defaults.
  static const none = BeamTuning();

  @override
  bool operator ==(Object other) =>
      other is BeamTuning &&
      other.glowBoost == glowBoost &&
      other.strokeOpacity == strokeOpacity &&
      other.innerOpacity == innerOpacity &&
      other.bloomOpacity == bloomOpacity &&
      other.coreBlur == coreBlur &&
      other.bloomBlur == bloomBlur &&
      other.glowBrightness == glowBrightness &&
      other.glowSaturate == glowSaturate;

  @override
  int get hashCode => Object.hash(
    glowBoost,
    strokeOpacity,
    innerOpacity,
    bloomOpacity,
    coreBlur,
    bloomBlur,
    glowBrightness,
    glowSaturate,
  );
}

/// The tuning the border-beam web demo gives its `pulse-outside` card.
const BeamTuning webDemoPulsePreset = BeamTuning(
  glowBoost: 1.05,
  strokeOpacity: 1.71,
  innerOpacity: 1.71,
  bloomOpacity: 1.71,
  glowBrightness: 1.3 * 1.71,
  glowSaturate: 1.2 * 1.71,
);
