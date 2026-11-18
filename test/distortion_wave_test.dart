import 'package:warp_fx/warp_fx.dart';
import 'package:warp_fx/src/wave/wave_front.dart';
import 'package:warp_fx/src/wave/wave_particles.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const size = Size(390, 844);
  final source = Rect.fromCenter(
    center: const Offset(195, 788),
    width: 320,
    height: 52,
  );

  WaveFront at(
    double p, [
    DistortionWaveStyle style = DistortionWaveStyle.vertical,
  ]) => WaveFront(progress: p, source: source, size: size, style: style);

  group('WaveFront', () {
    test('rests on the source at the start', () {
      final f = at(0);
      expect(f.launched, isFalse);
      expect(f.energy, 0);
      expect(f.glow, 0);
      expect(f.origin, source.center);
    });

    test('pulls toward the source in the anticipation, then launches', () {
      final style = DistortionWaveStyle.vertical;
      final mid = at(style.anticipation * 0.9 / style.duration);
      expect(mid.launched, isFalse);
      expect(mid.gravity, greaterThan(0));
      final after = at((style.anticipation + 0.3) / style.duration);
      expect(after.launched, isTrue);
      expect(after.energy, greaterThan(0));
    });

    test('has crossed the area and settled by the end', () {
      final f = at(1);
      expect(f.hasCleared, isTrue);
      expect(f.energy, 0);
      expect(f.rim, closeTo(0, 1e-9));
    });

    test('radius grows monotonically after launch', () {
      var last = 0.0;
      for (var p = 0.25; p <= 1; p += 0.05) {
        final r = at(p).radius;
        expect(r, greaterThanOrEqualTo(last));
        last = r;
      }
    });

    test('center type is a ring that holds its source', () {
      final f = at(0.5, DistortionWaveStyle.center);
      expect(f.ring, isTrue);
      expect(f.hold, 26);
      expect(f.spine, 0);
    });

    test('leans toward an off-centre touch', () {
      final f = WaveFront(
        progress: 0.6,
        source: source,
        size: size,
        style: DistortionWaveStyle.vertical,
        focus: source.centerRight,
      );
      expect(f.tilt, greaterThan(0));
      expect(f.origin.dx, greaterThan(source.center.dx));
    });

    test('packs 20 floats for the shader', () {
      expect(at(0.5).packed, hasLength(20));
    });
  });

  test('rim lumps are 7 triplets', () {
    expect(rimLumps(time: 1, size: size, cornerRadius: 62), hasLength(21));
  });

  test('particles stay finite through the whole run', () {
    final style = DistortionWaveStyle.vertical;
    final ps = List.generate(
      style.particleCount,
      (i) => WaveParticle(i, style),
    );
    for (var p = 0.0; p <= 1; p += 0.02) {
      final f = at(p);
      for (final particle in ps) {
        final o = particle.opacityOn(f);
        final pt = particle.pointOn(f, source);
        expect(o.isFinite && pt.dx.isFinite && pt.dy.isFinite, isTrue);
      }
    }
  });

  test('style duration covers the travel and the edges', () {
    const s = DistortionWaveStyle.vertical;
    expect(s.duration, greaterThan(s.anticipation + s.travel * 0.6 - 1e-9));
    expect(DistortionWaveStyle.center.resolvedPalette, WavePalette.green);
    expect(s.copyWith(blur: 4).blur, 4);
  });

  testWidgets(
    'flips views and reports finish (crossfade under reduced motion)',
    (tester) async {
      bool? finished;
      Widget build(bool revealed) => Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: DistortionWave(
            isRevealed: revealed,
            onFinish: (v) => finished = v,
            revealed: const ColoredBox(
              color: Color(0xFF00AA00),
              child: Text('after'),
            ),
            child: const ColoredBox(
              color: Color(0xFF0000AA),
              child: Text('before'),
            ),
          ),
        ),
      );
      await tester.pumpWidget(build(false));
      expect(find.text('before').hitTestable(), findsOneWidget);
      expect(find.text('after').hitTestable(), findsNothing);

      await tester.pumpWidget(build(true));
      await tester.pumpAndSettle();
      expect(finished, isTrue);
      expect(find.text('after').hitTestable(), findsOneWidget);
      expect(find.text('before').hitTestable(), findsNothing);
    },
  );
}
