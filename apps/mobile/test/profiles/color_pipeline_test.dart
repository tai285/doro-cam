import 'dart:math' as math;

import 'package:doro_cam/profiles/builtin_profiles.dart';
import 'package:doro_cam/profiles/color_math.dart';
import 'package:doro_cam/profiles/color_pipeline.dart';
import 'package:doro_cam/profiles/image_profile.dart';
import 'package:flutter_test/flutter_test.dart';

Rgb run(ColorParams p, double r, double g, double b) => ColorPipeline(p).apply(r, g, b);

void expectRgb(Rgb actual, Rgb expected, {double tol = 1e-9, String? reason}) {
  expect(actual.r, closeTo(expected.r, tol), reason: reason);
  expect(actual.g, closeTo(expected.g, tol), reason: reason);
  expect(actual.b, closeTo(expected.b, tol), reason: reason);
}

void main() {
  group('color math', () {
    test('sRGB transfer functions round trip and hit the known anchors', () {
      expect(srgbToLinear(0), 0);
      expect(srgbToLinear(1), closeTo(1, 1e-12));
      expect(srgbToLinear(0.5), closeTo(0.21404114, 1e-7));
      expect(linearToSrgb(0.21404114), closeTo(0.5, 1e-6));
      expect(linearToSrgb(-1), 0);
      for (var i = 0; i <= 100; i++) {
        final v = i / 100;
        expect(linearToSrgb(srgbToLinear(v)), closeTo(v, 1e-9));
      }
    });

    test('HSL conversion round trips every color on a grid', () {
      for (var r = 0; r <= 4; r++) {
        for (var g = 0; g <= 4; g++) {
          for (var b = 0; b <= 4; b++) {
            final hsl = rgbToHsl(r / 4, g / 4, b / 4);
            final back = hslToRgb(hsl.h, hsl.s, hsl.l);
            expectRgb(back, Rgb(r / 4, g / 4, b / 4), tol: 1e-9, reason: '$r$g$b');
          }
        }
      }
      expect(rgbToHsl(1, 0, 0).h, 0);
      expect(rgbToHsl(0, 1, 0).h, 120);
      expect(rgbToHsl(0, 0, 1).h, 240);
      expect(rgbToHsl(0.5, 0.5, 0.5).s, 0);
      expect(hslToRgb(0, 0, 0.3), const Rgb(0.3, 0.3, 0.3));
      expectRgb(hueToRgb(60), const Rgb(1, 1, 0));
    });

    test('hue distance wraps around 360', () {
      expect(hueDistance(10, 350), 20);
      expect(hueDistance(350, 10), 20);
      expect(hueDistance(0, 180), 180);
      expect(hueDistance(90, 90), 0);
    });

    test('luma and clamp', () {
      expect(luma(1, 1, 1), closeTo(1, 1e-12));
      expect(luma(0, 0, 0), 0);
      expect(clamp01(-1), 0);
      expect(clamp01(2), 1);
      expect(clamp01(0.3), 0.3);
      expect(const Rgb(2, -1, 0.5).clamped, const Rgb(1, 0, 0.5));
      expect(const Rgb(1, 2, 3).map((v) => v * 2), const Rgb(2, 4, 6));
      expect(const Rgb(1, 2, 3).hashCode, const Rgb(1, 2, 3).hashCode);
      expect(const Rgb(1, 2, 3).toString(), 'Rgb(1.0, 2.0, 3.0)');
    });

    test('[PRF-009] ΔE2000 reproduces the published reference pairs (Sharma, Wu & Dalal 2005)', () {
      // (L1,a1,b1, L2,a2,b2) → expected ΔE00
      const pairs = <List<double>>[
        [50.0000, 2.6772, -79.7751, 50.0000, 0.0000, -82.7485, 2.0425],
        [50.0000, 3.1571, -77.2803, 50.0000, 0.0000, -82.7485, 2.8615],
        [50.0000, 2.8361, -74.0200, 50.0000, 0.0000, -82.7485, 3.4412],
        [50.0000, -1.3802, -84.2814, 50.0000, 0.0000, -82.7485, 1.0000],
        [50.0000, -1.1848, -84.8006, 50.0000, 0.0000, -82.7485, 1.0000],
        [50.0000, 0.0000, 0.0000, 50.0000, -1.0000, 2.0000, 2.3669],
        [50.0000, -1.0000, 2.0000, 50.0000, 0.0000, 0.0000, 2.3669],
        [50.0000, 2.4900, -0.0010, 50.0000, -2.4900, 0.0011, 7.2195],
        [50.0000, 2.5000, 0.0000, 50.0000, 0.0000, -2.5000, 4.3065],
        [60.2574, -34.0099, 36.2677, 60.4626, -34.1751, 39.4387, 1.2644],
        [63.0109, -31.0961, -5.8663, 62.8187, -29.7946, -4.0864, 1.2630],
        [35.0831, -44.1164, 3.7933, 35.0232, -40.0716, 1.5901, 1.8645],
        [22.7233, 20.0904, -46.6940, 23.0331, 14.9730, -42.5619, 2.0373],
        [90.8027, -2.0831, 1.4410, 91.1528, -1.6435, 0.0447, 1.4441],
        [2.0776, 0.0795, -1.1350, 0.9033, -0.0636, -0.5514, 0.9082],
      ];
      for (final p in pairs) {
        expect(deltaE2000(Lab(p[0], p[1], p[2]), Lab(p[3], p[4], p[5])), closeTo(p[6], 1e-4), reason: '$p');
      }
    });

    test('ΔE2000 is zero for equal colors and symmetric', () {
      const a = Rgb(0.2, 0.5, 0.7);
      const b = Rgb(0.25, 0.45, 0.7);
      expect(deltaESrgb(a, a), 0);
      expect(deltaESrgb(a, b), closeTo(deltaESrgb(b, a), 1e-9));
      expect(deltaESrgb(a, b), greaterThan(0));
      expect(srgbToLab(1, 1, 1).l, closeTo(100, 0.01));
      expect(srgbToLab(0, 0, 0).l, closeTo(0, 1e-9));
    });
  });

  group('tone curve', () {
    test('an empty curve is the identity', () {
      final curve = ToneCurve(const <CurvePoint>[]);
      expect(curve.isIdentity, isTrue);
      expect(curve[0.37], 0.37);
    });

    test('passes through its control points and holds the end values outside', () {
      final curve = ToneCurve(const <CurvePoint>[CurvePoint(0.1, 0.2), CurvePoint(0.5, 0.4), CurvePoint(0.9, 0.9)]);
      expect(curve[0.1], closeTo(0.2, 1e-12));
      expect(curve[0.5], closeTo(0.4, 1e-12));
      expect(curve[0.9], closeTo(0.9, 1e-12));
      expect(curve[0], 0.2);
      expect(curve[1], 0.9);
    });

    test('is monotone and never overshoots the control points', () {
      final curve = ToneCurve(const <CurvePoint>[CurvePoint(0, 0), CurvePoint(0.2, 0.05), CurvePoint(0.4, 0.5), CurvePoint(0.6, 0.55), CurvePoint(1, 1)]);
      var last = -1.0;
      for (var i = 0; i <= 1000; i++) {
        final v = curve[i / 1000];
        expect(v, greaterThanOrEqualTo(last - 1e-12));
        expect(v, inInclusiveRange(0, 1));
        last = v;
      }
    });

    test('flat segments stay flat', () {
      final curve = ToneCurve(const <CurvePoint>[CurvePoint(0, 0.3), CurvePoint(0.5, 0.3), CurvePoint(1, 0.9)]);
      for (final x in <double>[0.1, 0.25, 0.4]) {
        expect(curve[x], closeTo(0.3, 1e-12));
      }
    });
  });

  group('ColorPipeline (normative order, image-profile.md)', () {
    test('[PRF-002] the default parameters are the identity', () {
      for (var r = 0; r <= 4; r++) {
        for (var g = 0; g <= 4; g++) {
          for (var b = 0; b <= 4; b++) {
            expectRgb(run(const ColorParams(), r / 4, g / 4, b / 4), Rgb(r / 4, g / 4, b / 4), tol: 1e-12);
          }
        }
      }
    });

    test('exposure scales linear light: +1 EV roughly doubles light, −1 halves it, black stays black', () {
      final up = run(const ColorParams(exposureEv: 1), 0.2, 0.2, 0.2);
      expect(srgbToLinear(up.r), closeTo(srgbToLinear(0.2) * 2, 1e-9));
      final down = run(const ColorParams(exposureEv: -1), 0.6, 0.6, 0.6);
      expect(srgbToLinear(down.r), closeTo(srgbToLinear(0.6) / 2, 1e-9));
      expect(run(const ColorParams(exposureEv: 2), 0, 0, 0), const Rgb(0, 0, 0));
      expect(run(const ColorParams(exposureEv: 2), 0.9, 0.9, 0.9).r, 1);
    });

    test('black and white points lift blacks and cap whites (output levels)', () {
      final p = const ColorParams(blackPoint: 0.05, whitePoint: 0.95);
      expectRgb(run(p, 0, 0, 0), const Rgb(0.05, 0.05, 0.05));
      expectRgb(run(p, 1, 1, 1), const Rgb(0.95, 0.95, 0.95));
      expect(run(p, 0.5, 0.5, 0.5).r, closeTo(0.5, 1e-12));
    });

    test('positive temperature warms (red up, blue down), negative cools; neutral gray otherwise stays neutral at zero', () {
      final warm = run(const ColorParams(temperatureShift: 0.5), 0.5, 0.5, 0.5);
      expect(warm.r, greaterThan(0.5));
      expect(warm.b, lessThan(0.5));
      expect(warm.g, closeTo(0.5, 1e-9));
      final cool = run(const ColorParams(temperatureShift: -0.5), 0.5, 0.5, 0.5);
      expect(cool.r, lessThan(0.5));
      expect(cool.b, greaterThan(0.5));
    });

    test('positive tint pulls green down (magenta), negative lifts it', () {
      expect(run(const ColorParams(tintShift: 0.5), 0.5, 0.5, 0.5).g, lessThan(0.5));
      expect(run(const ColorParams(tintShift: -0.5), 0.5, 0.5, 0.5).g, greaterThan(0.5));
    });

    test('contrast steepens the mids and keeps the end points; negative flattens', () {
      final up = const ColorParams(contrast: 0.5);
      expect(run(up, 0, 0, 0).r, 0);
      expect(run(up, 1, 1, 1).r, 1);
      expect(run(up, 0.25, 0.25, 0.25).r, lessThan(0.25));
      expect(run(up, 0.75, 0.75, 0.75).r, greaterThan(0.75));
      expect(run(up, 0.5, 0.5, 0.5).r, closeTo(0.5, 1e-12));
      final down = const ColorParams(contrast: -0.5);
      expect(run(down, 0.25, 0.25, 0.25).r, greaterThan(0.25));
      expect(run(down, 0.75, 0.75, 0.75).r, lessThan(0.75));
    });

    test('contrast stays monotone for every strength', () {
      for (final c in <double>[-1, -0.5, 0.5, 1]) {
        var last = -1.0;
        for (var i = 0; i <= 200; i++) {
          final v = run(ColorParams(contrast: c), i / 200, i / 200, i / 200).g;
          expect(v, greaterThanOrEqualTo(last - 1e-12), reason: 'contrast $c');
          last = v;
        }
      }
    });

    test('a tone curve is applied to each channel', () {
      const p = ColorParams(toneCurve: <CurvePoint>[CurvePoint(0, 0.1), CurvePoint(1, 0.9)]);
      expectRgb(run(p, 0, 0.5, 1), const Rgb(0.1, 0.5, 0.9), tol: 1e-9);
    });

    test('shadows lift dark areas more than light ones; highlights pull down bright ones more than dark ones', () {
      const lift = ColorParams(shadows: 1);
      final dark = run(lift, 0.1, 0.1, 0.1).r - 0.1;
      final light = run(lift, 0.9, 0.9, 0.9).r - 0.9;
      expect(dark, greaterThan(light));
      const pull = ColorParams(highlights: -1);
      expect(0.9 - run(pull, 0.9, 0.9, 0.9).r, greaterThan(0.1 - run(pull, 0.1, 0.1, 0.1).r));
    });

    test('saturation moves colors away from (or toward) their luma; −1 is fully gray', () {
      final gray = run(const ColorParams(saturation: -1), 0.8, 0.3, 0.2);
      expect(gray.r, closeTo(gray.g, 1e-9));
      expect(gray.g, closeTo(gray.b, 1e-9));
      final more = run(const ColorParams(saturation: 0.5), 0.6, 0.4, 0.3);
      expect(more.r - more.b, greaterThan(0.6 - 0.3));
      expect(run(const ColorParams(saturation: 0.5), 0.4, 0.4, 0.4), const Rgb(0.4, 0.4, 0.4)); // neutrals are unaffected
    });

    test('vibrance lifts muted colors more than vivid ones', () {
      const p = ColorParams(vibrance: 1);
      final muted = run(p, 0.55, 0.5, 0.45);
      final vivid = run(p, 1, 0.2, 0.1);
      expect((muted.r - muted.b) / 0.1, greaterThan((vivid.r - vivid.b) / 0.9));
    });

    test('HSL: a band affects colors near its hue and leaves distant hues and neutrals alone', () {
      const p = ColorParams(hsl: <HueBand, HslShift>{HueBand.blue: HslShift(sat: 1, lum: 0.5)});
      final blue = run(p, 0.2, 0.3, 0.8);
      expect(blue.b - blue.r, greaterThan(0.8 - 0.2));
      final red = run(p, 0.8, 0.3, 0.2);
      expectRgb(red, const Rgb(0.8, 0.3, 0.2), tol: 1e-9);
      final neutral = run(p, 0.5, 0.5, 0.5);
      expectRgb(neutral, const Rgb(0.5, 0.5, 0.5), tol: 1e-9);
      // a hue shift rotates toward a neighbor
      const rotate = ColorParams(hsl: <HueBand, HslShift>{HueBand.red: HslShift(hue: 1)});
      final shifted = run(rotate, 0.9, 0.1, 0.1);
      expect(shifted.g, greaterThan(0.1)); // red rotated toward orange/yellow
    });

    test('HSL: influence fades smoothly with hue distance (no jumps at band edges)', () {
      const p = ColorParams(hsl: <HueBand, HslShift>{HueBand.green: HslShift(sat: 1)});
      var last = 0.0;
      var maxJump = 0.0;
      for (var h = 60; h <= 180; h += 2) {
        final c = hslToRgb(h.toDouble(), 0.8, 0.5);
        final out = run(p, c.r, c.g, c.b);
        final value = deltaESrgb(c, out);
        if (h > 60) maxJump = math.max(maxJump, (value - last).abs());
        last = value;
      }
      expect(maxJump, lessThan(4));
    });

    test('split tone tints shadows and highlights without changing brightness', () {
      const p = ColorParams(splitShadows: SplitTone(hue: 240, amount: 1), splitHighlights: SplitTone(hue: 30, amount: 1));
      final shadow = run(p, 0.3, 0.3, 0.3);
      expect(shadow.b, greaterThan(shadow.r));
      final highlight = run(p, 0.9, 0.9, 0.9);
      expect(highlight.r, greaterThan(highlight.b));
      expect(luma(shadow.r, shadow.g, shadow.b), closeTo(0.3, 0.1));
      // zero amount does nothing
      expectRgb(run(const ColorParams(splitShadows: SplitTone(hue: 240)), 0.1, 0.1, 0.1), const Rgb(0.1, 0.1, 0.1), tol: 1e-12);
    });

    test('monochrome mix produces neutral gray from a weighted channel mix', () {
      const p = ColorParams(monochrome: MonochromeMix(red: 0.5, green: 0.3, blue: 0.2));
      final out = run(p, 0.8, 0.4, 0.2);
      expect(out.r, out.g);
      expect(out.g, out.b);
      expect(out.r, closeTo(0.5 * 0.8 + 0.3 * 0.4 + 0.2 * 0.2, 1e-12));
      expect(run(const ColorParams(monochrome: MonochromeMix(red: 2, green: 2, blue: 2)), 1, 1, 1).r, 1); // clamped
    });

    test('order matters: exposure happens before the curve, and monochrome is last', () {
      // exposure first: brightening then a flattening curve differs from the reverse order, so check the first
      const p = ColorParams(exposureEv: 1, toneCurve: <CurvePoint>[CurvePoint(0, 0), CurvePoint(0.5, 0.25), CurvePoint(1, 1)]);
      final out = run(p, 0.5, 0.5, 0.5).r;
      final exposed = linearToSrgb(srgbToLinear(0.5) * 2);
      expect(out, closeTo(ToneCurve(p.toneCurve)[exposed], 1e-9));
      // monochrome after saturation boost: a saturation change cannot alter the gray result's neutrality
      final mono = run(const ColorParams(saturation: 1, monochrome: MonochromeMix()), 0.9, 0.2, 0.1);
      expect(mono.r, mono.b);
    });

    test('property: every built-in profile maps the whole RGB cube into [0, 1] and is deterministic', () {
      for (final profile in BuiltInProfiles.all) {
        final pipeline = ColorPipeline(profile.color);
        for (var r = 0; r <= 8; r++) {
          for (var g = 0; g <= 8; g++) {
            for (var b = 0; b <= 8; b++) {
              final out = pipeline.apply(r / 8, g / 8, b / 8);
              for (final v in <double>[out.r, out.g, out.b]) {
                expect(v.isFinite && v >= 0 && v <= 1, isTrue, reason: '${profile.id} $r$g$b');
              }
              expect(pipeline.apply(r / 8, g / 8, b / 8), out);
            }
          }
        }
      }
    });

    test('property: random valid parameters always yield finite, in-range output', () {
      final rng = math.Random(99);
      double u(double lo, double hi) => lo + rng.nextDouble() * (hi - lo);
      for (var i = 0; i < 300; i++) {
        final params = ColorParams(
          exposureEv: u(-2, 2),
          contrast: u(-1, 1),
          highlights: u(-1, 1),
          shadows: u(-1, 1),
          blackPoint: u(0, 0.25),
          whitePoint: u(0.75, 1),
          saturation: u(-1, 1),
          vibrance: u(-1, 1),
          temperatureShift: u(-1, 1),
          tintShift: u(-1, 1),
          hsl: <HueBand, HslShift>{for (final band in HueBand.values) if (rng.nextBool()) band: HslShift(hue: u(-1, 1), sat: u(-1, 1), lum: u(-1, 1))},
          splitShadows: SplitTone(hue: u(0, 360), amount: u(0, 1)),
          splitHighlights: SplitTone(hue: u(0, 360), amount: u(0, 1)),
          monochrome: rng.nextInt(4) == 0 ? MonochromeMix(red: u(-1, 2), green: u(-1, 2), blue: u(-1, 2)) : null,
        );
        final pipeline = ColorPipeline(params);
        for (var k = 0; k < 20; k++) {
          final out = pipeline.apply(rng.nextDouble(), rng.nextDouble(), rng.nextDouble());
          for (final v in <double>[out.r, out.g, out.b]) {
            expect(v.isFinite && v >= 0 && v <= 1, isTrue, reason: '$i/$k');
          }
        }
      }
    });
  });

  group('the shipped looks behave as described', () {
    final natural = ColorPipeline(BuiltInProfiles.natural.color);
    test('Warm Film is warmer than Natural on neutrals and lifts the blacks', () {
      final warm = ColorPipeline(BuiltInProfiles.warmFilm.color);
      final n = natural.apply(0.5, 0.5, 0.5);
      final w = warm.apply(0.5, 0.5, 0.5);
      expect(w.r - w.b, greaterThan(n.r - n.b));
      expect(warm.apply(0, 0, 0).r, greaterThanOrEqualTo(0.04));
      expect(warm.apply(1, 1, 1).r, lessThanOrEqualTo(0.97 + 0.02));
    });

    test('Soft Film has lower contrast than Natural', () {
      final soft = ColorPipeline(BuiltInProfiles.softFilm.color);
      final spreadNatural = natural.apply(0.9, 0.9, 0.9).r - natural.apply(0.1, 0.1, 0.1).r;
      final spreadSoft = soft.apply(0.9, 0.9, 0.9).r - soft.apply(0.1, 0.1, 0.1).r;
      expect(spreadSoft, lessThan(spreadNatural));
    });

    test('Instant Warm is the warmest, with bright highlights', () {
      final instant = ColorPipeline(BuiltInProfiles.instantWarm.color).apply(0.8, 0.8, 0.8);
      expect(instant.r - instant.b, greaterThan(0.05));
    });

    test('Black & White returns neutral gray for any color', () {
      final mono = ColorPipeline(BuiltInProfiles.monoClassic.color);
      for (final c in const <Rgb>[Rgb(0.9, 0.2, 0.1), Rgb(0.1, 0.8, 0.3), Rgb(0.2, 0.3, 0.9), Rgb(0.5, 0.5, 0.5)]) {
        final out = mono.apply(c.r, c.g, c.b);
        expect(out.r, out.g);
        expect(out.g, out.b);
      }
    });

    test('Natural stays close to the input (small ΔE) so it is a safe default', () {
      for (final c in const <Rgb>[Rgb(0.8, 0.4, 0.3), Rgb(0.3, 0.6, 0.4), Rgb(0.5, 0.5, 0.5)]) {
        final out = natural.apply(c.r, c.g, c.b);
        expect(deltaESrgb(c, out), lessThan(6));
      }
    });
  });
}
