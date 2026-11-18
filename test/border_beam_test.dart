import 'package:warp_fx/src/beam/beam_layers.dart';
import 'package:warp_fx/src/beam/beam_math.dart';
import 'package:warp_fx/src/beam/beam_spec.dart';
import 'package:warp_fx/src/beam/border_beam.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('colour matrix', () {
    test('no hue, brightness or saturation change is the identity', () {
      final m = composedFilterMatrix(0, 1, 1);
      for (var i = 0; i < 9; i++) {
        expect(m[i], closeTo(identityMatrix[i], 1e-9));
      }
    });

    test('brightness scales every coefficient', () {
      final m = composedFilterMatrix(0, 2, 1);
      expect(m[0], closeTo(2, 1e-9));
      expect(m[1], closeTo(0, 1e-9));
      expect(m[8], closeTo(2, 1e-9));
    });

    test('saturate(0) turns every row into the same luma weights', () {
      final m = composedFilterMatrix(0, 1, 0);
      for (var row = 0; row < 3; row++) {
        expect(m[row * 3], closeTo(0.213, 1e-9));
        expect(m[row * 3 + 1], closeTo(0.715, 1e-9));
        expect(m[row * 3 + 2], closeTo(0.072, 1e-9));
      }
    });

    test('a hue rotation keeps greys grey', () {
      final m = composedFilterMatrix(73, 1, 1);
      for (var row = 0; row < 3; row++) {
        expect(m[row * 3] + m[row * 3 + 1] + m[row * 3 + 2], closeTo(1, 1e-9));
      }
    });

    test('multiply3x3 with the identity is a no-op', () {
      final a = <double>[1, 2, 3, 4, 5, 6, 7, 8, 9];
      expect(multiply3x3(a, identityMatrix), a);
      expect(multiply3x3(identityMatrix, a), a);
    });
  });

  group('timing', () {
    test('pingPong runs 0 → 1 → 0 over a phase', () {
      expect(pingPong(0), closeTo(0, 1e-12));
      expect(pingPong(0.5), closeTo(1, 1e-12));
      expect(pingPong(1), closeTo(0, 1e-12));
      expect(pingPong(0.25), closeTo(0.5, 1e-12));
    });

    test('cssEaseInOut is symmetric and pinned at its ends', () {
      expect(cssEaseInOut(0), 0);
      expect(cssEaseInOut(1), 1);
      expect(cssEaseInOut(0.5), closeTo(0.5, 1e-3));
      expect(cssEaseInOut(0.2) + cssEaseInOut(0.8), closeTo(1, 1e-3));
      expect(cssEaseInOut(0.2), lessThan(0.2));
    });

    test('sampleKeyframes interpolates each segment', () {
      final table = [
        [0.0, 0.0],
        [50.0, 10.0],
        [100.0, 0.0],
      ];
      expect(sampleKeyframes(table, 0), 0);
      expect(sampleKeyframes(table, 0.25), closeTo(5, 1e-9));
      expect(sampleKeyframes(table, 0.5), closeTo(10, 1e-9));
      expect(sampleKeyframes(table, 0.75), closeTo(5, 1e-9));
      expect(sampleKeyframes(table, 0.25, easeInOut: true), closeTo(5, 1e-2));
      expect(sampleKeyframes(table, 0.1, easeInOut: true), lessThan(2));
    });

    test('an oscillator swings from a to b and back over its period', () {
      const o = Oscillator(prop: 'bw1', a: 1, b: 3, period: 2);
      expect(o.valueAt(0, 1), closeTo(1, 1e-9));
      expect(o.valueAt(1, 1), closeTo(3, 1e-9));
      expect(o.valueAt(2, 1), closeTo(1, 1e-9));
      // Twice the duration, twice the period.
      expect(o.valueAt(2, 2), closeTo(3, 1e-9));
    });

    test('line keyframes travel across and fade at the ends', () {
      final tables = LineKeyframes.fromJson(
        BeamSpec.line['keyframes'] as Map<String, dynamic>,
      );
      final start = tables.at(0, 3.1);
      final middle = tables.at(3.1 / 2, 3.1);
      expect(start.edge, 0);
      expect(middle.edge, 1);
      expect(middle.x, closeTo(0.5, 1e-9));
      expect(start.x, lessThan(middle.x));
    });
  });

  group('spec', () {
    test('parses CSS colours', () {
      expect(parseCssColor('rgb(255, 0, 51)'), const Rgba(1, 0, 0.2, 1));
      expect(parseCssColor('rgba(0, 0, 0, 0.14)'), const Rgba(0, 0, 0, 0.14));
      expect(parseCssColor('transparent'), Rgba.clear);
      expect(parseCssColor('#fff'), isNull);
    });

    test('parses percent and pixel pairs', () {
      final p = parsePercentPair('33% -7.4%');
      expect(p.x, closeTo(0.33, 1e-9));
      expect(p.y, closeTo(-0.074, 1e-9));
      final s = parsePixelPair('70px 40px');
      expect(s.w, 70);
      expect(s.h, 40);
    });

    test('has every size, variant and theme', () {
      for (final size in BorderBeamSize.values) {
        expect(BeamSpec.sizePreset(size.key).borderWidth, greaterThan(0));
        for (final theme in ['dark', 'light']) {
          expect(
            BeamSpec.themePreset(size.key, theme).strokeOpacity,
            greaterThan(0),
          );
        }
      }
      for (final variant in BorderBeamColorVariant.values) {
        expect(BeamSpec.borderPalette(variant.name), hasLength(9));
        expect(BeamSpec.smallPalette(variant.name).inner, isNotEmpty);
      }
    });

    test('stopsBlob normalises 2, 3 and 4 stops to 16 floats', () {
      BlobStop s(double a, double pos) => (r: 255, g: 0, b: 0, a: a, pos: pos);
      expect(stopsBlob(1, 1, 0, 0, [s(1, 0), s(0, 0.8)]), hasLength(16));
      final three = stopsBlob(1, 1, 0, 0, [s(1, 0), s(0.5, 0.3), s(0, 0.9)]);
      expect(three[8], 0.3);
      expect(three[12], 0.9);
      final four = stopsBlob(1, 1, 0, 0, [
        s(1, 0),
        s(0.6, 0.2),
        s(0.3, 0.5),
        s(0, 0.7),
      ]);
      expect(four.sublist(8, 13), [0.2, 0.6, 0.5, 0.3, 0.7]);
      expect(four[4], 1);
    });
  });

  group('BorderBeam widget', () {
    for (final size in BorderBeamSize.values) {
      testWidgets('renders its child as ${size.name}', (tester) async {
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: BorderBeam(
                size: size,
                theme: BorderBeamTheme.auto,
                child: const SizedBox(
                  width: 200,
                  height: 80,
                  child: Text('card'),
                ),
              ),
            ),
          ),
        );
        // Let the shaders load, then run a second of animation.
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)),
        );
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(find.text('card'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('fades out and back in with callbacks', (tester) async {
      var activated = 0;
      var deactivated = 0;
      Widget build(bool active) => Directionality(
        textDirection: TextDirection.ltr,
        child: BorderBeam(
          active: active,
          colorVariant: BorderBeamColorVariant.mono,
          onActivate: () => activated++,
          onDeactivate: () => deactivated++,
          child: const SizedBox(width: 100, height: 40),
        ),
      );
      await tester.pumpWidget(build(true));
      await tester.pump(const Duration(milliseconds: 700));
      expect(activated, 1);
      await tester.pumpWidget(build(false));
      await tester.pump(const Duration(milliseconds: 600));
      expect(deactivated, 1);
      await tester.pumpWidget(build(true));
      await tester.pump(const Duration(milliseconds: 700));
      expect(activated, 2);
    });

    testWidgets('the child still takes taps', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: BorderBeam(
              size: BorderBeamSize.pulseOutside,
              child: GestureDetector(
                onTap: () => taps++,
                child: const SizedBox(
                  width: 120,
                  height: 60,
                  child: ColoredBox(color: Color(0xFF111111)),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byType(GestureDetector));
      expect(taps, 1);
    });
  });

  test('BeamConfig equality drives layer reuse', () {
    BeamConfig c(double radius) => BeamConfig(
      size: 'md',
      variant: 'colorful',
      theme: 'dark',
      staticColors: false,
      duration: 1.96,
      radius: radius,
      brightness: 1.3,
      saturation: 1.2,
      hueRange: 30,
      strength: 1,
      tuning: BeamTuning.none,
      reduceMotion: false,
    );
    expect(c(16), c(16));
    expect(c(16), isNot(c(20)));
    expect(webDemoPulsePreset, isNot(BeamTuning.none));
  });
}
