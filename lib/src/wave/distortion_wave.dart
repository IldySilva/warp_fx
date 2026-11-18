import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'wave_front.dart';
import 'wave_particles.dart';
import 'wave_pictures.dart';
import 'wave_style.dart';

/// A colourful distortion wave that opens from a source (the button, edge or
/// avatar that started it) and carries one view into another.
///
/// Everything falls toward the source for a moment, tiny sparks with it. Then
/// the front leaves the source and travels out as one soft swell, lifting and
/// bending what it passes, with a progressive blur and chromatic aberration
/// peaking on it. Its colour stays on the edges, with a hairline, after the
/// middle has cleared.
///
/// ```dart
/// DistortionWave(
///   isRevealed: sent,
///   sourceKey: confirmButtonKey,
///   revealed: const ReceiptScreen(),
///   child: const ReviewScreen(),
/// )
/// ```
///
/// Flip [isRevealed] to send the wave out; flip it back to collapse it into
/// the source.
///
/// The wave bends a picture of the views, taken as it starts, so what
/// animates inside a view stands still while the wave passes, unless [live]
/// is set. Give both views an opaque background. Platform views (maps, web
/// views, video players backed by a texture on some platforms) can't be
/// pictured.
///
/// Where fragment shaders aren't available, and when the platform asks for
/// reduced motion, it is a plain crossfade.
class DistortionWave extends StatefulWidget {
  /// A wave between [child] and [revealed].
  const DistortionWave({
    super.key,
    required this.isRevealed,
    required this.child,
    this.revealed,
    this.source,
    this.sourceKey,
    this.focus,
    this.style = DistortionWaveStyle.vertical,
    this.scrub,
    this.live = false,
    this.onFinish,
  });

  /// Which view shows. Changing it runs the wave: forwards to [revealed],
  /// backwards to [child].
  final bool isRevealed;

  /// The view that shows first. The wave fills its size.
  final Widget child;

  /// The view the wave leaves behind it, laid out to [child]'s size. Without
  /// one the wave passes over [child] and leaves it as it was.
  final Widget? revealed;

  /// Where the wave opens from, in this widget's own coordinates. Ignored
  /// when [sourceKey] finds a widget.
  final Rect? source;

  /// The widget the wave opens from, such as the button that started it,
  /// anywhere on screen. Measured as the wave starts.
  final GlobalKey? sourceKey;

  /// Where the source was touched, in this widget's coordinates. The
  /// vertical and horizontal waves lean toward it as much as the style's
  /// [DistortionWaveStyle.orientation] says.
  final Offset? focus;

  /// How the wave looks and moves. Start from [DistortionWaveStyle.vertical],
  /// [DistortionWaveStyle.horizontal] or [DistortionWaveStyle.center].
  final DistortionWaveStyle style;

  /// Holds the wave at this point of its run, 0–1, instead of playing.
  final double? scrub;

  /// Whether the pictures of the views follow them on every frame of the
  /// wave, so what animates inside them keeps moving. Costs a capture and two
  /// blurs per view per frame.
  final bool live;

  /// Called when a wave ends, with the view it ended on: `true` for
  /// [revealed]. Not called for a run interrupted by flipping [isRevealed]
  /// again.
  final ValueChanged<bool>? onFinish;

  @override
  State<DistortionWave> createState() => _DistortionWaveState();
}

enum _Phase { rest, preparing, waving, fading }

class _DistortionWaveState extends State<DistortionWave>
    with SingleTickerProviderStateMixin {
  final _area = GlobalKey();
  final _contentBoundary = GlobalKey();
  final _revealedBoundary = GlobalKey();

  late final AnimationController _progress = AnimationController(
    vsync: this,
    value: widget.isRevealed ? 1 : 0,
  );

  _Phase _phase = _Phase.rest;
  int _run = 0;
  WavePictures? _content;
  WavePictures? _revealed;
  ui.FragmentShader? _shader;
  Rect _sourceRect = Rect.zero;
  Offset? _heldFocus;
  bool _capturePending = false;
  List<WaveParticle> _particles = const [];

  @override
  void initState() {
    super.initState();
    _particles = _makeParticles(widget.style);
    if (WaveProgram.program == null && !WaveProgram.failed) {
      WaveProgram.load().then((_) {
        if (mounted) setState(() {});
      });
    }
    if (widget.scrub != null) _scheduleCapture();
  }

  @override
  void didUpdateWidget(DistortionWave old) {
    super.didUpdateWidget(old);
    if (old.style.particleCount != widget.style.particleCount ||
        old.style != widget.style) {
      _particles = _makeParticles(widget.style);
    }
    if (widget.scrub != null) {
      if (_content == null || widget.live) _scheduleCapture();
      return;
    }
    if (old.scrub != null) _release();
    if (old.isRevealed != widget.isRevealed) _start(widget.isRevealed);
  }

  @override
  void dispose() {
    _progress.dispose();
    _release();
    _shader?.dispose();
    super.dispose();
  }

  static List<WaveParticle> _makeParticles(DistortionWaveStyle style) =>
      List.generate(style.particleCount, (i) => WaveParticle(i, style));

  bool get _plain =>
      MediaQuery.maybeDisableAnimationsOf(context) == true ||
      WaveProgram.failed;

  bool get _hasRevealed => widget.revealed != null;

  void _start(bool revealing) {
    final atRest = _phase == _Phase.rest;
    final thisRun = ++_run;

    if (_plain || (WaveProgram.program == null)) {
      // A crossfade, without the shader.
      setState(() => _phase = _Phase.fading);
      _progress
          .animateTo(
            revealing ? 1 : 0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.linear,
          )
          .then((_) => _finish(thisRun));
      return;
    }

    if (atRest) {
      _heldFocus = widget.focus;
      setState(() => _phase = _Phase.preparing);
      // Pictured once this frame has painted the views as they now are.
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!mounted || thisRun != _run) return;
        if (!_capture()) {
          _finish(thisRun, jump: revealing);
          return;
        }
        setState(() => _phase = _Phase.waving);
        _animate(revealing, thisRun);
      });
      SchedulerBinding.instance.ensureVisualUpdate();
    } else {
      // Mid-wave: the same pictures, the other way.
      if (_phase == _Phase.waving) _animate(revealing, thisRun);
    }
  }

  void _animate(bool revealing, int thisRun) {
    final style = widget.style;
    if (widget.live) _scheduleLiveCapture(thisRun);
    if (revealing) {
      final remaining = style.duration * (1 - _progress.value);
      _progress
          .animateTo(1, duration: _seconds(remaining), curve: Curves.linear)
          .then((_) => _finish(thisRun));
    } else {
      // On the wave's easing too, quick through the end of its life where
      // little is on screen: the collapse answers the tap at once.
      _progress
          .animateTo(
            0,
            duration: _seconds(style.duration / style.returnSpeed),
            curve: style.easing,
          )
          .then((_) => _finish(thisRun));
    }
  }

  static Duration _seconds(double s) =>
      Duration(microseconds: (math.max(s, 0) * 1e6).round());

  void _finish(int thisRun, {bool? jump}) {
    if (!mounted || thisRun != _run) return;
    if (jump != null) _progress.value = jump ? 1 : 0;
    _release();
    setState(() => _phase = _Phase.rest);
    widget.onFinish?.call(_progress.value >= 1);
  }

  void _release() {
    _content?.dispose();
    _revealed?.dispose();
    _content = null;
    _revealed = null;
  }

  /// Pictures both views and measures the source. False if they can't be
  /// pictured yet.
  bool _capture() {
    final area = _area.currentContext?.findRenderObject() as RenderBox?;
    final content =
        _contentBoundary.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    final revealed =
        _revealedBoundary.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (area == null || !area.hasSize || content == null) return false;
    if (_hasRevealed && revealed == null) return false;
    // Called after a frame has painted, so both boundaries are up to date.

    final ratio =
        MediaQuery.maybeDevicePixelRatioOf(context) ??
        View.of(context).devicePixelRatio;
    final blur = widget.style.blur;
    final nextContent = WavePictures.capture(
      content,
      pixelRatio: ratio,
      blur: blur,
    );
    final nextRevealed = revealed == null
        ? null
        : WavePictures.capture(revealed, pixelRatio: ratio, blur: blur);
    _release();
    _content = nextContent;
    _revealed = nextRevealed;
    _sourceRect = _measureSource(area);
    _shader ??= WaveProgram.program?.fragmentShader();
    return true;
  }

  void _scheduleCapture() {
    if (_capturePending) return;
    _capturePending = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _capturePending = false;
      if (!mounted || widget.scrub == null) return;
      if (_capture()) {
        setState(() {});
      } else {
        _scheduleCapture();
      }
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  void _scheduleLiveCapture(int thisRun) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted || thisRun != _run || _phase != _Phase.waving) return;
      _capture();
      _scheduleLiveCapture(thisRun);
    });
  }

  Rect _measureSource(RenderBox area) {
    final key = widget.sourceKey;
    final box = key?.currentContext?.findRenderObject();
    if (box is RenderBox && box.hasSize && box.attached) {
      final transform = box.getTransformTo(area);
      return MatrixUtils.transformRect(transform, Offset.zero & box.size);
    }
    return widget.source ?? defaultSource(area.size, widget.style.type);
  }

  /// Where a wave of [type] opens from over an area of [size] when no source
  /// is given: a button at the bottom, the left edge, or the centre.
  static Rect defaultSource(Size size, WaveType type) => switch (type) {
    WaveType.vertical => Rect.fromCenter(
      center: Offset(size.width / 2, size.height - 56),
      width: math.min(size.width - 48, 320),
      height: 52,
    ),
    WaveType.horizontal => Rect.fromCenter(
      center: Offset(12, size.height / 2),
      width: 24,
      height: math.min(size.height * 0.6, 320),
    ),
    WaveType.center => Rect.fromCenter(
      center: size.center(Offset.zero),
      width: 72,
      height: 72,
    ),
  };

  @override
  Widget build(BuildContext context) {
    _shader ??= WaveProgram.program?.fragmentShader();
    final scrubbing =
        widget.scrub != null && _content != null && _shader != null;
    final drawing =
        scrubbing ||
        (_phase == _Phase.waving && _content != null && _shader != null);
    final fading = _phase == _Phase.fading;
    final onRevealed = _progress.value >= 0.5;

    final showContent = !drawing && (!_hasRevealed || !onRevealed || fading);
    final showRevealed = !drawing && _hasRevealed && (onRevealed || fading);

    Widget view(Widget child, GlobalKey key, bool shown, bool revealedSide) {
      Widget out = RepaintBoundary(key: key, child: child);
      if (fading) {
        out = FadeTransition(
          opacity: revealedSide ? _progress : ReverseAnimation(_progress),
          child: out,
        );
      }
      return _Hideable(
        hidden: !shown,
        child: IgnorePointer(
          ignoring: !shown || (fading && revealedSide != onRevealed),
          child: ExcludeSemantics(excluding: !shown, child: out),
        ),
      );
    }

    return Stack(
      key: _area,
      clipBehavior: Clip.none,
      children: [
        view(widget.child, _contentBoundary, showContent, false),
        if (_hasRevealed)
          Positioned.fill(
            child: view(
              widget.revealed!,
              _revealedBoundary,
              showRevealed,
              true,
            ),
          ),
        if (drawing)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _WavePainter(
                  progress: _progress,
                  scrub: widget.scrub,
                  style: widget.style,
                  source: _sourceRect,
                  focus: scrubbing ? widget.focus : _heldFocus,
                  shader: _shader!,
                  content: _content!,
                  revealed: _revealed,
                  particles: _particles,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Paints its child into a layer at zero opacity when [hidden]: unseen, but
/// still painted, so its repaint boundary can be pictured.
class _Hideable extends SingleChildRenderObjectWidget {
  const _Hideable({required this.hidden, super.child});

  final bool hidden;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderHideable(hidden);

  @override
  void updateRenderObject(BuildContext context, _RenderHideable renderObject) {
    renderObject.hidden = hidden;
  }
}

class _RenderHideable extends RenderProxyBox {
  _RenderHideable(this._hidden);

  bool _hidden;
  bool get hidden => _hidden;
  set hidden(bool value) {
    if (value == _hidden) return;
    _hidden = value;
    markNeedsCompositingBitsUpdate();
    markNeedsPaint();
  }

  @override
  bool get alwaysNeedsCompositing => child != null && _hidden;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) return;
    if (!_hidden) {
      layer = null;
      context.paintChild(child!, offset);
      return;
    }
    layer = context.pushOpacity(
      offset,
      0,
      super.paint,
      oldLayer: layer as OpacityLayer?,
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter({
    required this.progress,
    required this.scrub,
    required this.style,
    required this.source,
    required this.focus,
    required this.shader,
    required this.content,
    required this.revealed,
    required this.particles,
  }) : super(repaint: progress);

  final Animation<double> progress;
  final double? scrub;
  final DistortionWaveStyle style;
  final Rect source;
  final Offset? focus;
  final ui.FragmentShader shader;
  final WavePictures content;
  final WavePictures? revealed;
  final List<WaveParticle> particles;

  @override
  void paint(Canvas canvas, Size size) {
    final value = scrub ?? progress.value;
    final front = WaveFront(
      progress: value,
      source: source,
      size: size,
      style: style,
      focus: focus,
    );
    _setUniforms(front, size);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
    if (value > 0 && value < 1) {
      paintParticles(canvas, particles, front, source);
    }
  }

  void _setUniforms(WaveFront front, Size size) {
    var i = 0;
    void put(double v) => shader.setFloat(i++, v);
    void putAll(Iterable<double> vs) => vs.forEach(put);

    final same = revealed == null;
    final palette = style.resolvedPalette;
    final colors = palette.colors;

    putAll([size.width, size.height]);
    putAll(front.packed);
    // uLens
    putAll([
      style.amplitude,
      style.lensWidth,
      style.aberration,
      front.energy > 0 || front.gravity > 0 ? 1 : 0,
    ]);
    // uBlur
    putAll([style.blur, style.blurAhead, style.blurBehind, nearBlur]);
    // uViews
    putAll([
      front.hasCleared ? 0 : 1,
      front.launched ? 1 : 0,
      same ? 1 : 0,
      style.continuousCorners ? 1 : 0,
    ]);
    // uBand
    putAll([style.lead, style.tail, style.strength, colors.length.toDouble()]);
    // uRim
    putAll([
      style.rimWidth,
      style.rimSoftness,
      style.cornerRadius,
      style.rimUnevenness,
    ]);
    // uHair
    putAll([
      style.rimPulse,
      style.hairlineWidth,
      style.hairlineOpacity,
      style.hairlineWhite,
    ]);
    // uPal[8]
    for (var k = 0; k < WavePalette.maxColors; k++) {
      final lab = k < colors.length
          ? oklabOf(colors[k])
          : const [0.0, 0.0, 0.0];
      putAll([...lab, 0]);
    }
    putAll([...oklabOf(palette.ahead), 0]);
    putAll([...oklabOf(palette.behind), 0]);
    // uLumps[7]
    final lumps = rimLumps(
      time: front.time,
      size: size,
      cornerRadius: style.cornerRadius,
      pulse: style.rimPulse,
    );
    for (var k = 0; k < lumps.length; k += 3) {
      putAll([lumps[k], lumps[k + 1], lumps[k + 2], 0]);
    }

    final other = revealed ?? content;
    const q = FilterQuality.low;
    shader
      ..setImageSampler(0, content.sharp, filterQuality: q)
      ..setImageSampler(1, content.near, filterQuality: q)
      ..setImageSampler(2, content.far, filterQuality: q)
      ..setImageSampler(3, other.sharp, filterQuality: q)
      ..setImageSampler(4, other.near, filterQuality: q)
      ..setImageSampler(5, other.far, filterQuality: q);
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.scrub != scrub ||
      old.style != style ||
      old.source != source ||
      old.focus != focus ||
      old.content != content ||
      old.revealed != revealed ||
      old.shader != shader;
}
