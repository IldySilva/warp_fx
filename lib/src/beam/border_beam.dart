import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'beam_layers.dart';
import 'beam_spec.dart';
import 'beam_tuning.dart';

export 'beam_tuning.dart' show BeamTuning, webDemoPulsePreset;

/// The shape and motion of a [BorderBeam].
enum BorderBeamSize {
  /// A compact travelling glow, for small controls such as an icon button.
  sm('sm'),

  /// A travelling glow round the whole border. The default.
  md('md'),

  /// A glow travelling along the bottom edge only, as under a search bar.
  line('line'),

  /// A breathing glow kept inside the border.
  pulseInner('pulse-inner'),

  /// A breathing halo blooming outward behind the element. The child must be
  /// opaque: the halo is drawn behind it and shows only where it spills past.
  pulseOutside('pulse-outside');

  const BorderBeamSize(this.key);

  /// The size's key in the border-beam spec.
  final String key;

  /// True for the breathing family.
  bool get isPulse => this == pulseInner || this == pulseOutside;
}

/// The colours of a [BorderBeam].
enum BorderBeamColorVariant {
  /// A rainbow spectrum. The default.
  colorful,

  /// Greys. Never shifts hue, at half the opacity.
  mono,

  /// Blues and purples.
  ocean,

  /// Oranges, yellows and reds.
  sunset,
}

/// The background a [BorderBeam] is tuned for.
enum BorderBeamTheme {
  /// A dark background. The default.
  dark,

  /// A light background.
  light,

  /// Follows the platform's brightness.
  auto,
}

/// An animated glow on the border of [child]: a beam travelling round it, or
/// a slow breathing light.
///
/// ```dart
/// BorderBeam(
///   size: BorderBeamSize.md,
///   colorVariant: BorderBeamColorVariant.ocean,
///   borderRadius: 16,
///   child: Card(...),
/// )
/// ```
///
/// Pass the child's own corner radius as [borderRadius]; the beam cannot
/// read it from the child. The beam layers take no touches and are hidden
/// from accessibility. They are drawn with fragment shaders: until those
/// have loaded, and where they cannot, only [child] is shown.
class BorderBeam extends StatefulWidget {
  /// Wraps [child] in a beam.
  const BorderBeam({
    super.key,
    required this.child,
    this.size = BorderBeamSize.md,
    this.colorVariant = BorderBeamColorVariant.colorful,
    this.theme = BorderBeamTheme.dark,
    this.staticColors = false,
    this.duration,
    this.active = true,
    this.borderRadius,
    this.brightness,
    this.saturation,
    this.hueRange = 30,
    this.strength = 1,
    this.tuning = BeamTuning.none,
    this.onActivate,
    this.onDeactivate,
  });

  /// What the beam goes round.
  final Widget child;

  /// The shape and motion. Defaults to [BorderBeamSize.md].
  final BorderBeamSize size;

  /// The palette. Defaults to [BorderBeamColorVariant.colorful].
  final BorderBeamColorVariant colorVariant;

  /// The background the colours are tuned for. Defaults to dark.
  final BorderBeamTheme theme;

  /// Turns off the slow hue shift. Always on for [BorderBeamColorVariant.mono].
  final bool staticColors;

  /// Seconds for one turn, travel or breath. Defaults to 1.96 for `sm` and
  /// `md`, 3.1 for `line` and 2.3 for the pulse family.
  final double? duration;

  /// Whether the beam shows. Changing it fades the beam in over 0.6 s or out
  /// over 0.5 s.
  final bool active;

  /// The child's corner radius, logical pixels. Defaults to the size's
  /// preset: 32 for `sm`, 16 for the others.
  final double? borderRadius;

  /// Glow brightness multiplier. Defaults to the size and theme's preset.
  final double? brightness;

  /// Glow saturation multiplier. Defaults to the size and theme's preset.
  final double? saturation;

  /// How far the hue shift swings either way, degrees. `line` caps it at 13.
  final double hueRange;

  /// Opacity of the whole effect, 0–1. The child is never affected.
  final double strength;

  /// Proportional dials on the pulse family's prominence.
  final BeamTuning tuning;

  /// Called once a fade-in has finished.
  final VoidCallback? onActivate;

  /// Called once a fade-out has finished.
  final VoidCallback? onDeactivate;

  @override
  State<BorderBeam> createState() => _BorderBeamState();
}

class _BorderBeamState extends State<BorderBeam> with TickerProviderStateMixin {
  static Future<BeamPrograms?>? _loading;
  static BeamPrograms? _programs;

  static Future<BeamPrograms?> _load() => _loading ??= () async {
    try {
      final programs = BeamPrograms(
        await _program('beam_rotate.frag'),
        await _program('beam_blob.frag'),
      );
      return _programs = programs;
    } catch (error) {
      // Degrade to the plain child rather than fail the app.
      debugPrint(
        'warp_fx: border beam shaders unavailable ($error); showing the child alone.',
      );
      return null;
    }
  }();

  /// From an app the package's shaders are under `packages/`; in the
  /// package's own tests and example they are at the root.
  static Future<ui.FragmentProgram> _program(String name) async {
    try {
      return await ui.FragmentProgram.fromAsset(
        'packages/warp_fx/shaders/$name',
      );
    } catch (_) {
      return ui.FragmentProgram.fromAsset('shaders/$name');
    }
  }

  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: Duration(
      milliseconds: (num_(BeamSpec.defaults['fadeInSeconds']) * 1000).round(),
    ),
    reverseDuration: Duration(
      milliseconds: (num_(BeamSpec.defaults['fadeOutSeconds']) * 1000).round(),
    ),
  );
  // CSS `ease`.
  late final Animation<double> _fadeCurve = CurvedAnimation(
    parent: _fade,
    curve: Curves.ease,
  );
  final ValueNotifier<double> _time = ValueNotifier(0);
  late final Ticker _ticker = createTicker(
    (elapsed) => _time.value = elapsed.inMicroseconds / 1e6,
  );

  bool _showing = false;
  BeamLayers? _layers;

  @override
  void initState() {
    super.initState();
    if (_programs == null) {
      _load().then((p) {
        if (mounted && p != null) setState(() {});
      });
    }
    if (widget.active) _activate();
  }

  @override
  void didUpdateWidget(BorderBeam old) {
    super.didUpdateWidget(old);
    if (widget.active != old.active) {
      widget.active ? _activate() : _deactivate();
    }
  }

  void _activate() {
    _showing = true;
    if (!_ticker.isActive) _ticker.start();
    _fade.forward().then((_) {
      if (mounted && widget.active) widget.onActivate?.call();
    }, onError: (_) {});
  }

  void _deactivate() {
    _fade.reverse().then((_) {
      if (!mounted || widget.active) return;
      setState(() => _showing = false);
      _ticker.stop();
      widget.onDeactivate?.call();
    }, onError: (_) {});
  }

  BeamConfig _config(BuildContext context) {
    final w = widget;
    final brightness =
        MediaQuery.maybePlatformBrightnessOf(context) ?? Brightness.dark;
    final theme = switch (w.theme) {
      BorderBeamTheme.dark => 'dark',
      BorderBeamTheme.light => 'light',
      BorderBeamTheme.auto => brightness == Brightness.light ? 'light' : 'dark',
    };
    final size = w.size.key;
    final preset = BeamSpec.sizePreset(size);
    final colors = BeamSpec.themePreset(size, theme);
    final durations = BeamSpec.defaults['duration'] as Map;
    final duration =
        w.duration ??
        num_(
          durations[w.size == BorderBeamSize.line
              ? 'line'
              : (w.size.isPulse ? 'pulse' : 'rotate')],
        );
    final hueRange = w.size == BorderBeamSize.line
        ? w.hueRange
              .clamp(
                double.negativeInfinity,
                num_(BeamSpec.defaults['lineHueRangeCap']),
              )
              .toDouble()
        : w.hueRange;
    return BeamConfig(
      size: size,
      variant: w.colorVariant.name,
      theme: theme,
      staticColors:
          w.colorVariant == BorderBeamColorVariant.mono || w.staticColors,
      duration: duration,
      radius: w.borderRadius ?? preset.borderRadius,
      brightness:
          w.brightness ??
          colors.brightness ??
          num_(BeamSpec.defaults['brightnessFallback']),
      saturation: w.saturation ?? colors.saturation,
      hueRange: hueRange,
      strength: w.strength.clamp(0, 1).toDouble(),
      tuning: w.tuning,
      // Web parity: only the pulse family honours reduced motion.
      reduceMotion:
          w.size.isPulse &&
          (MediaQuery.maybeDisableAnimationsOf(context) ?? false),
    );
  }

  BeamLayers _layersFor(BeamConfig config, BeamPrograms programs) {
    final current = _layers;
    if (current != null && current.config == config) return current;
    if (current != null) {
      // The last frame may still be drawing with it.
      SchedulerBinding.instance.addPostFrameCallback((_) => current.dispose());
    }
    return _layers = BeamLayers.of(config, programs);
  }

  @override
  void dispose() {
    _layers?.dispose();
    _ticker.dispose();
    _fade.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final programs = _programs;
    if (programs == null || !_showing) return widget.child;
    final layers = _layersFor(_config(context), programs);
    final repaint = Listenable.merge([_time, _fadeCurve]);
    return CustomPaint(
      painter: widget.size == BorderBeamSize.pulseOutside
          ? _BeamPainter(
              layers,
              behind: true,
              time: _time,
              fade: _fadeCurve,
              repaint: repaint,
            )
          : null,
      foregroundPainter: _BeamPainter(
        layers,
        behind: false,
        time: _time,
        fade: _fadeCurve,
        repaint: repaint,
      ),
      child: widget.child,
    );
  }
}

class _BeamPainter extends CustomPainter {
  _BeamPainter(
    this.layers, {
    required this.behind,
    required this.time,
    required this.fade,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final BeamLayers layers;
  final bool behind;
  final ValueListenable<double> time;
  final Animation<double> fade;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    if (behind) {
      layers.paintBehind(canvas, size, time.value, fade.value);
    } else {
      layers.paintFront(canvas, size, time.value, fade.value);
    }
  }

  @override
  bool shouldRepaint(_BeamPainter old) =>
      old.layers != layers || old.behind != behind;

  // Decorative: never takes a touch.
  @override
  bool? hitTest(Offset position) => false;
}
