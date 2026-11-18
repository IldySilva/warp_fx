import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

/// The blur radius of the near blurred copy, in logical pixels; the far copy
/// has the style's full radius.
const double nearBlur = 7;

/// One view as the shader reads it: sharp, and two blurred copies.
class WavePictures {
  WavePictures._(this.sharp, this.near, this.far);

  /// Pictures [boundary] as it was last painted, at [pixelRatio], with the
  /// far copy blurred by [blur] logical pixels.
  factory WavePictures.capture(
    RenderRepaintBoundary boundary, {
    required double pixelRatio,
    required double blur,
  }) {
    final sharp = boundary.toImageSync(pixelRatio: pixelRatio);
    return WavePictures._(
      sharp,
      _blurred(sharp, nearBlur * pixelRatio),
      _blurred(sharp, math.max(blur, nearBlur) * pixelRatio),
    );
  }

  final ui.Image sharp;
  final ui.Image near;
  final ui.Image far;

  void dispose() {
    sharp.dispose();
    near.dispose();
    far.dispose();
  }

  /// A blurred copy of [sharp], downsampled so the kernel stays short, as
  /// the web renderer does. [sigma] is in the picture's own pixels.
  static ui.Image _blurred(ui.Image sharp, double sigma) {
    final f = math.max(1, (sigma / 5).round());
    final w = math.max(1, (sharp.width / f).ceil());
    final h = math.max(1, (sharp.height / f).ceil());
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final s = math.max(sigma / f, 0.01);
    canvas.drawImageRect(
      sharp,
      Rect.fromLTWH(0, 0, sharp.width.toDouble(), sharp.height.toDouble()),
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Paint()
        ..filterQuality = FilterQuality.medium
        ..imageFilter = ui.ImageFilter.blur(
          sigmaX: s,
          sigmaY: s,
          tileMode: TileMode.clamp,
        ),
    );
    final picture = recorder.endRecording();
    final image = picture.toImageSync(w, h);
    picture.dispose();
    return image;
  }
}

/// The wave's shader program, loaded once for the whole app.
class WaveProgram {
  WaveProgram._();

  static const String asset = 'packages/warp_fx/shaders/wave.frag';

  static Future<ui.FragmentProgram?>? _loading;
  static ui.FragmentProgram? _program;
  static bool _failed = false;

  /// The program, once loaded; null before that, or where it can't load.
  static ui.FragmentProgram? get program => _program;

  /// True once loading has failed: the wave falls back to a crossfade.
  static bool get failed => _failed;

  /// Loads the program, once.
  static Future<ui.FragmentProgram?> load() {
    return _loading ??= _load();
  }

  static Future<ui.FragmentProgram?> _load() async {
    // From an app the package's assets are under packages/; from the
    // package's own tests and example they are at the root.
    for (final key in [asset, 'shaders/wave.frag']) {
      try {
        return _program = await ui.FragmentProgram.fromAsset(key);
      } catch (_) {}
    }
    _failed = true;
    debugPrint('warp_fx: wave shader unavailable; using a crossfade.');
    return null;
  }
}
