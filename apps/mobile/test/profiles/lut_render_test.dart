import 'dart:io';
import 'dart:typed_data';

import 'package:doro_cam/profiles/builtin_profiles.dart';
import 'package:doro_cam/profiles/color_math.dart';
import 'package:doro_cam/profiles/color_pipeline.dart';
import 'package:doro_cam/profiles/effects.dart';
import 'package:doro_cam/profiles/fixtures.dart';
import 'package:doro_cam/profiles/image_profile.dart';
import 'package:doro_cam/profiles/lut.dart';
import 'package:doro_cam/profiles/renderer.dart';
import 'package:doro_cam/profiles/shader_params.dart';
import 'package:flutter_test/flutter_test.dart';

/// Golden checksums of the compiled 33³ LUT of each shipped profile version (FNV-1a over the .lut bytes).
/// A change here means a profile's output changed: bump its version and add the new checksum.
const Map<String, int> lutGoldens = <String, int>{
  'natural@v1': 2628729431,
  'warm-film@v1': 3738553357,
  'soft-film@v1': 168511322,
  'instant-warm@v1': 3399358557,
  'mono-classic@v1': 3345519879,
};

void main() {
  group('half-float conversion', () {
    test('round trips representative values and rounds to nearest even', () {
      for (final v in <double>[0, 1, 0.5, 0.25, 0.123, 0.999, 2, -1, 65504, 6.1035e-5]) {
        expect(halfBitsToDouble(doubleToHalfBits(v)), closeTo(v, v.abs() * 1e-3 + 1e-7), reason: '$v');
      }
      expect(doubleToHalfBits(1), 0x3c00);
      expect(doubleToHalfBits(0), 0);
      expect(doubleToHalfBits(-2), 0xc000);
      expect(doubleToHalfBits(70000), 0x7c00);
      expect(halfBitsToDouble(0x7c00), double.infinity);
      expect(halfBitsToDouble(0xfc00), double.negativeInfinity);
      expect(halfBitsToDouble(0x7e00).isNaN, isTrue);
      expect(doubleToHalfBits(double.nan) & 0x7c00, 0x7c00);
      expect(doubleToHalfBits(double.infinity), 0x7c00);
      expect(doubleToHalfBits(1e-10), 0); // underflow
      expect(halfBitsToDouble(1), closeTo(5.96e-8, 1e-9)); // smallest subnormal
      expect(halfBitsToDouble(doubleToHalfBits(1e-6)), closeTo(1e-6, 1e-7)); // subnormal range
      expect(halfBitsToDouble(0x3555), closeTo(0.3333, 1e-3));
    });

    test('every half value with a finite number round-trips exactly', () {
      for (var bits = 0; bits < 0x7c00; bits += 7) {
        expect(doubleToHalfBits(halfBitsToDouble(bits)), bits);
      }
    });
  });

  group('Lut3d', () {
    test('rejects invalid sizes and data lengths', () {
      expect(() => Lut3d(1, Float32List(3)), throwsArgumentError);
      expect(() => Lut3d(2, Float32List(5)), throwsArgumentError);
    });

    test('the identity LUT returns its input everywhere (lattice and between)', () {
      final id = Lut3d.identity();
      expect(id.size, 33);
      for (final c in const <Rgb>[Rgb(0, 0, 0), Rgb(1, 1, 1), Rgb(0.3, 0.6, 0.9), Rgb(0.123, 0.456, 0.789)]) {
        final out = id.sample(c.r, c.g, c.b);
        expect(out.r, closeTo(c.r, 1e-6));
        expect(out.g, closeTo(c.g, 1e-6));
        expect(out.b, closeTo(c.b, 1e-6));
      }
      expect(id.sample(-1, 2, 0.5).g, closeTo(1, 1e-6)); // out-of-range inputs clamp
      expect(id.at(32, 0, 16).r, closeTo(1, 1e-6));
    });

    test('[PRF-002] compiling the default parameters gives the identity LUT', () {
      final lut = Lut3d.compile(const ColorParams());
      final id = Lut3d.identity();
      for (var i = 0; i < lut.data.length; i++) {
        expect(lut.data[i], closeTo(id.data[i], 1e-6));
      }
    });

    test('compilation is deterministic: two compiles are bit-identical', () {
      for (final p in BuiltInProfiles.all) {
        final a = Lut3d.compile(p.color);
        final b = Lut3d.compile(p.color);
        expect(a.toBinary(), b.toBinary(), reason: p.id);
        expect(a.checksum, b.checksum);
      }
    });

    test('each profile compiles to a different LUT', () {
      expect(BuiltInProfiles.all.map((p) => compileProfile(p).checksum).toSet().length, BuiltInProfiles.all.length);
    });

    test('[PRF-009] trilinear sampling of the compiled LUT stays close to the exact pipeline', () {
      for (final p in BuiltInProfiles.all) {
        final lut = compileProfile(p);
        final exact = ColorPipeline(p.color);
        for (var i = 0; i < 400; i++) {
          final r = (i * 37 % 101) / 100;
          final g = (i * 53 % 103) / 102;
          final b = (i * 71 % 107) / 106;
          expect(deltaESrgb(lut.sample(r, g, b), exact.apply(r, g, b)), lessThan(3), reason: '${p.id} $r $g $b');
        }
      }
    });

    test('binary format: header, size and float16 payload, and an exact round trip of the stored values', () {
      final lut = compileProfile(BuiltInProfiles.warmFilm);
      final bytes = lut.toBinary();
      expect(bytes.length, 8 + 33 * 33 * 33 * 3 * 2);
      expect(String.fromCharCodes(bytes.sublist(0, 4)), 'DLUT');
      expect(bytes[4], 1);
      expect(bytes[5], 3);
      expect(ByteData.sublistView(bytes).getUint16(6, Endian.little), 33);
      final back = Lut3d.fromBinary(bytes);
      expect(back.size, 33);
      expect(back.toBinary(), bytes);
      for (var i = 0; i < lut.data.length; i += 97) {
        expect(back.data[i], closeTo(lut.data[i], 1e-3));
      }
    });

    test('[PRF-002] corrupt or foreign LUT files are rejected with a typed error (the UI then falls back to natural)', () {
      final good = compileProfile(BuiltInProfiles.natural).toBinary();
      Uint8List mutate(void Function(Uint8List) f) {
        final copy = Uint8List.fromList(good);
        f(copy);
        return copy;
      }

      expect(() => Lut3d.fromBinary(Uint8List(3)), throwsA(isA<LutFormatException>()));
      expect(() => Lut3d.fromBinary(mutate((b) => b[0] = 0)), throwsA(isA<LutFormatException>()));
      expect(() => Lut3d.fromBinary(mutate((b) => b[4] = 9)), throwsA(isA<LutFormatException>()));
      expect(() => Lut3d.fromBinary(mutate((b) => b[5] = 4)), throwsA(isA<LutFormatException>()));
      expect(() => Lut3d.fromBinary(mutate((b) => b[6] = 1)), throwsA(isA<LutFormatException>())); // size 1
      expect(() => Lut3d.fromBinary(mutate((b) => b[7] = 99)), throwsA(isA<LutFormatException>())); // absurd size
      expect(() => Lut3d.fromBinary(Uint8List.sublistView(good, 0, good.length - 2)), throwsA(isA<LutFormatException>()));
      expect(LutFormatException('x').toString(), contains('x'));
    });

    test('.cube export has the standard header and one line per lattice point', () {
      final cube = Lut3d.identity(size: 3).toCube(title: 'Test');
      final lines = cube.trim().split('\n');
      expect(lines[0], 'TITLE "Test"');
      expect(lines[1], 'LUT_3D_SIZE 3');
      expect(lines[2], 'DOMAIN_MIN 0.0 0.0 0.0');
      expect(lines[3], 'DOMAIN_MAX 1.0 1.0 1.0');
      expect(lines.length, 4 + 27);
      expect(lines[4], '0.000000 0.000000 0.000000');
      expect(lines[5], '0.500000 0.000000 0.000000'); // red varies fastest
      expect(lines[7], '0.000000 0.500000 0.000000');
      expect(lines.last, '1.000000 1.000000 1.000000');
    });

    test('tiled RGBA8 layout: width size², height size, texel (b·size + r, g)', () {
      final lut = Lut3d.identity(size: 5);
      final tiled = lut.toTiledRgba8();
      expect(tiled.length, 25 * 5 * 4);
      int at(int r, int g, int b, int channel) => tiled[(g * 25 + b * 5 + r) * 4 + channel];
      expect(at(4, 0, 0, 0), 255);
      expect(at(0, 4, 0, 1), 255);
      expect(at(0, 0, 4, 2), 255);
      expect(at(2, 2, 2, 0), 128);
      expect(at(1, 3, 2, 3), 255);
    });

    test('[PRF-009] the GPU color path (tiled 8-bit texture, bilinear + slice lerp) matches the float LUT within ΔE 1', () {
      for (final p in BuiltInProfiles.all) {
        final lut = compileProfile(p);
        final texture = TiledLutTexture.forLut(lut);
        expect(texture.width, 1089);
        expect(texture.height, 33);
        var worst = 0.0;
        for (var i = 0; i < 600; i++) {
          final r = (i * 37 % 101) / 100;
          final g = (i * 53 % 103) / 102;
          final b = (i * 71 % 107) / 106;
          worst = worst > deltaESrgb(texture.lookup(r, g, b), lut.sample(r, g, b)) ? worst : deltaESrgb(texture.lookup(r, g, b), lut.sample(r, g, b));
        }
        expect(worst, lessThan(1.0), reason: p.id);
      }
    });

    test('[PRF-002] compiled LUT goldens: each shipped profile version is byte-stable', () {
      // The goldens are filled in from the first verified compile and then guard against accidental changes.
      for (final p in BuiltInProfiles.all) {
        final golden = lutGoldens['${p.id}@v${p.version}'];
        if (golden != null) {
          expect(compileProfile(p).checksum, golden, reason: '${p.id} output changed: bump its version');
        }
      }
      expect(lutGoldens.length, BuiltInProfiles.all.length, reason: 'a golden is required for every shipped profile');
    });
  });

  group('effects', () {
    test('seeds are stable per Memory id and differ between ids', () {
      expect(seedFromMemoryId('0192a7c0-1b2c-7d3e-8f4a-5b6c7d8e9f01'), seedFromMemoryId('0192a7c0-1b2c-7d3e-8f4a-5b6c7d8e9f01'));
      expect(seedFromMemoryId('a'), isNot(seedFromMemoryId('b')));
      expect(seedFromMemoryId(''), 0x811c9dc5);
      expect(seedFromMemoryId('é'), isNot(seedFromMemoryId('e')));
    });

    test('hash noise is uniform-ish in [0, 1), deterministic and varies with every input', () {
      var sum = 0.0;
      for (var i = 0; i < 4000; i++) {
        final v = hashNoise(i % 63, i ~/ 63, 5, i % 3);
        expect(v, inInclusiveRange(0, 1));
        sum += v;
        expect(hashNoise(i % 63, i ~/ 63, 5, i % 3), v);
      }
      expect(sum / 4000, closeTo(0.5, 0.03));
      expect(hashNoise(1, 2, 3, 4), isNot(hashNoise(2, 2, 3, 4)));
      expect(hashNoise(1, 2, 3, 4), isNot(hashNoise(1, 3, 3, 4)));
      expect(hashNoise(1, 2, 3, 4), isNot(hashNoise(1, 2, 4, 4)));
      expect(hashNoise(1, 2, 3, 4), isNot(hashNoise(1, 2, 3, 5)));
      final samples = <double>[for (var i = 0; i < 2000; i++) grainSample(i, i * 7, 1, 0)];
      expect(samples.every((s) => s >= -1 && s <= 1), isTrue);
      expect(samples.fold<double>(0, (a, b) => a + b) / samples.length, closeTo(0, 0.05));
    });

    test('[PRF-006] grain with zero amount does nothing', () {
      const c = Rgb(0.4, 0.5, 0.6);
      expect(applyGrain(c, 3, 4, 100, 100, const GrainParams(), 1), c);
    });

    test('[PRF-006] grain is reproducible for a seed, differs across seeds and positions, and respects strength', () {
      const grain = GrainParams(amount: 0.8, size: 1, chroma: 0.3);
      const c = Rgb(0.5, 0.5, 0.5);
      final a = applyGrain(c, 10, 10, 200, 200, grain, 7);
      expect(applyGrain(c, 10, 10, 200, 200, grain, 7), a);
      expect(applyGrain(c, 10, 10, 200, 200, grain, 8), isNot(a));
      expect(applyGrain(c, 11, 10, 200, 200, grain, 7), isNot(a));
      var maxDev = 0.0;
      for (var i = 0; i < 500; i++) {
        final o = applyGrain(c, i % 50, i ~/ 50, 200, 200, grain, 3);
        maxDev = maxDev > (o.r - 0.5).abs() ? maxDev : (o.r - 0.5).abs();
      }
      expect(maxDev, greaterThan(0.01));
      expect(maxDev, lessThan(0.2));
      final weak = applyGrain(c, 10, 10, 200, 200, const GrainParams(amount: 0.1), 7);
      expect((weak.r - 0.5).abs(), lessThan((a.r - 0.5).abs() + 1e-9));
    });

    test('[PRF-006] grain is mostly in the midtones and mostly absent in pure black and white', () {
      const grain = GrainParams(amount: 1, size: 1);
      double spread(double v) {
        var m = 0.0;
        for (var i = 0; i < 400; i++) {
          m = m > (applyGrain(Rgb(v, v, v), i % 20, i ~/ 20, 100, 100, grain, 1).r - v).abs() ? m : (applyGrain(Rgb(v, v, v), i % 20, i ~/ 20, 100, 100, grain, 1).r - v).abs();
        }
        return m;
      }

      expect(spread(0.5), greaterThan(spread(1.0)));
      expect(spread(0.5), greaterThan(spread(0.0)));
    });

    test('grain chroma 0 is monochrome (equal on all channels); chroma 1 decorrelates channels', () {
      const mono = GrainParams(amount: 1, chroma: 0);
      final m = applyGrain(const Rgb(0.5, 0.5, 0.5), 5, 5, 100, 100, mono, 2);
      expect(m.r, m.g);
      expect(m.g, m.b);
      const colored = GrainParams(amount: 1, chroma: 1);
      var differing = 0;
      for (var i = 0; i < 50; i++) {
        final c = applyGrain(const Rgb(0.5, 0.5, 0.5), i, 3, 100, 100, colored, 2);
        if (c.r != c.g) differing++;
      }
      expect(differing, greaterThan(40));
    });

    test('[PRF-009] grain size is relative to the short edge so a preview and a full render look alike', () {
      const grain = GrainParams(amount: 1, size: 1);
      expect(grainCellSize(grain, 1080), 1);
      expect(grainCellSize(grain, 4320), 4);
      expect(grainCellSize(grain, 100), 1);
      expect(grainCellSize(const GrainParams(amount: 1, size: 2), 1080), 2);
      // pixels in the same cell share the same noise
      const big = GrainParams(amount: 1, size: 2);
      expect(applyGrain(const Rgb(0.5, 0.5, 0.5), 0, 0, 2160, 2160, big, 1), applyGrain(const Rgb(0.5, 0.5, 0.5), 3, 3, 2160, 2160, big, 1));
    });

    test('[PRF-006] vignette leaves the center alone and darkens the corners, monotonically outward', () {
      const v = VignetteParams(amount: 0.6, midpoint: 0.4, roundness: 0);
      expect(vignetteFactor(100, 75, 200, 150, v), closeTo(1, 1e-9));
      final corner = vignetteFactor(0, 0, 200, 150, v);
      expect(corner, closeTo(0.4, 0.02));
      var last = 1.0;
      for (var x = 100; x >= 0; x -= 5) {
        final f = vignetteFactor(x.toDouble(), 75, 200, 150, v);
        expect(f, lessThanOrEqualTo(last + 1e-12));
        last = f;
      }
      expect(vignetteFactor(0, 0, 200, 150, const VignetteParams()), 1);
    });

    test('vignette roundness: 1 is a circle (edge midpoints of the long axis darker than for the ellipse), negative is boxier', () {
      const ellipse = VignetteParams(amount: 1, midpoint: 0.2, roundness: 0);
      const circle = VignetteParams(amount: 1, midpoint: 0.2, roundness: 1);
      const boxy = VignetteParams(amount: 1, midpoint: 0.2, roundness: -1);
      // on the left edge midpoint of a wide image the circle is farther (relative) than the ellipse
      expect(vignetteDistance(0, 50, 400, 100, 1), greaterThan(vignetteDistance(0, 50, 400, 100, 0) - 1e-9));
      expect(vignetteFactor(0, 50, 400, 100, circle), lessThan(vignetteFactor(0, 50, 400, 100, ellipse) + 1e-9));
      // the boxy shape reaches the corners at distance 1 as well
      expect(vignetteDistance(0, 0, 400, 100, -1), closeTo(1, 0.02));
      expect(vignetteFactor(0, 0, 400, 100, boxy), closeTo(0, 0.05));
      for (final r in <double>[-1, -0.5, 0, 0.5, 1]) {
        final d = vignetteDistance(200, 50, 400, 100, r);
        expect(d, lessThan(0.05), reason: 'center at roundness $r');
      }
      expect(vignetteFactor(0, 0, 100, 100, const VignetteParams(amount: 1, midpoint: 1)), lessThanOrEqualTo(1));
    });
  });

  group('ProfileRenderer (CPU reference, PRF-003)', () {
    const renderer = ProfileRenderer();

    test('[PRF-002] never modifies the source image', () {
      final src = Fixtures.landscape();
      final before = Uint8List.fromList(src.rgba);
      renderer.render(src, BuiltInProfiles.warmFilm, seed: 3);
      expect(src.rgba, before);
    });

    test('output has the same size, alpha is carried through, and rendering is deterministic', () {
      final src = ImageBuffer(8, 6, Uint8List.fromList(List<int>.generate(8 * 6 * 4, (i) => i % 4 == 3 ? 200 : (i * 5) % 256)));
      final out = renderer.render(src, BuiltInProfiles.instantWarm, seed: 9);
      expect((out.width, out.height), (8, 6));
      for (var i = 3; i < out.rgba.length; i += 4) {
        expect(out.rgba[i], 200);
      }
      expect(renderer.render(src, BuiltInProfiles.instantWarm, seed: 9).rgba, out.rgba);
    });

    test('[PRF-006] grain is seeded per Memory: same seed same pixels, different seed different pixels', () {
      final src = Fixtures.portrait();
      final a = renderer.render(src, BuiltInProfiles.warmFilm, seed: seedFromMemoryId('m1'));
      final b = renderer.render(src, BuiltInProfiles.warmFilm, seed: seedFromMemoryId('m1'));
      final c = renderer.render(src, BuiltInProfiles.warmFilm, seed: seedFromMemoryId('m2'));
      expect(a.rgba, b.rgba);
      expect(a.rgba, isNot(c.rgba));
    });

    test('effects can be switched off, leaving only the color look', () {
      final src = Fixtures.landscape();
      final withEffects = renderer.render(src, BuiltInProfiles.warmFilm, seed: 1);
      final without = renderer.render(src, BuiltInProfiles.warmFilm, applyEffects: false);
      expect(withEffects.rgba, isNot(without.rgba));
      expect(renderer.render(src, BuiltInProfiles.warmFilm, applyEffects: false).rgba, without.rgba);
      // natural has no effects, so effects on/off is identical
      expect(renderer.render(src, BuiltInProfiles.natural, seed: 5).rgba, renderer.render(src, BuiltInProfiles.natural, applyEffects: false).rgba);
    });

    test('a vignette darkens the corners of a flat gray image and not its center', () {
      final gray = ImageBuffer(64, 64, Uint8List.fromList(List<int>.generate(64 * 64 * 4, (i) => i % 4 == 3 ? 255 : 128)));
      final p = ImageProfile(id: 'vig', version: 1, name: 'Vig', description: 'd', effects: const ProfileEffects(vignette: VignetteParams(amount: 0.8, midpoint: 0.3)));
      final out = renderer.render(gray, p);
      expect(out.pixel(32, 32).r, closeTo(128 / 255, 0.01));
      expect(out.pixel(0, 0).r, lessThan(0.3));
    });

    test('[PRF-001] a LUT can be supplied (preview path) and must equal the default compiled one', () {
      final src = Fixtures.rampImage();
      final lut = compileProfile(BuiltInProfiles.softFilm);
      expect(renderer.render(src, BuiltInProfiles.softFilm, lut: lut, applyEffects: false).rgba, renderer.render(src, BuiltInProfiles.softFilm, applyEffects: false).rgba);
    });

    test('ImageBuffer validates its size and pixel data and copies deeply', () {
      expect(() => ImageBuffer(0, 5), throwsArgumentError);
      expect(() => ImageBuffer(2, 2, Uint8List(3)), throwsArgumentError);
      final a = ImageBuffer(2, 2);
      final b = a.copy();
      b.setPixel(0, 0, const Rgb(1, 0, 0));
      expect(a.pixel(0, 0), const Rgb(0, 0, 0));
      expect(b.pixel(0, 0), const Rgb(1, 0, 0));
      b.setPixel(1, 1, const Rgb(2, -1, 0.5), 10);
      expect(b.pixel(1, 1), Rgb(1, 0, 128 / 255));
      expect(b.rgba[(1 * 2 + 1) * 4 + 3], 10);
    });

    test('Black & White renders any image to neutral gray (before grain)', () {
      final out = renderer.render(Fixtures.colorChart(), BuiltInProfiles.monoClassic, applyEffects: false);
      for (var i = 0; i < out.rgba.length; i += 4) {
        expect(out.rgba[i], out.rgba[i + 1]);
        expect(out.rgba[i + 1], out.rgba[i + 2]);
      }
    });
  });

  group('parity (PRF-009): preview/GPU path vs the reference renderer', () {
    const renderer = ProfileRenderer();

    test('[PRF-009] LUT path vs exact path: mean ΔE2000 ≤ 2.0 and p95 ≤ 4.0 on the standard fixtures, for every profile', () {
      for (final p in BuiltInProfiles.all) {
        for (final entry in Fixtures.standardSet().entries) {
          final exact = renderer.render(entry.value, p, colorPath: ColorPath.exact, applyEffects: false);
          final lut = renderer.render(entry.value, p, colorPath: ColorPath.lut, applyEffects: false);
          final result = measureParity(exact, lut);
          expect(result.passes(), isTrue, reason: '${p.id} / ${entry.key}: $result');
        }
      }
    });

    test('[PRF-009] the tiled 8-bit GPU texture path matches the LUT path within the same thresholds', () {
      for (final p in BuiltInProfiles.all) {
        final lut = compileProfile(p);
        final texture = TiledLutTexture.forLut(lut);
        for (final entry in Fixtures.standardSet().entries) {
          final reference = renderer.render(entry.value, p, lut: lut, applyEffects: false);
          final gpu = ImageBuffer(entry.value.width, entry.value.height);
          for (var y = 0; y < gpu.height; y++) {
            for (var x = 0; x < gpu.width; x++) {
              final c = entry.value.pixel(x, y);
              gpu.setPixel(x, y, texture.lookup(c.r, c.g, c.b));
            }
          }
          final result = measureParity(reference, gpu);
          expect(result.passes(meanLimit: 1.0, p95Limit: 2.0), isTrue, reason: '${p.id} / ${entry.key}: $result');
        }
      }
    });

    test('[PRF-009] parity does not depend on resolution: grain cells scale with the image', () {
      const grain = GrainParams(amount: 1, size: 1);
      final small = <int>{for (var y = 0; y < 270; y += 3) for (var x = 0; x < 270; x += 3) grainCellSize(grain, 270)};
      final large = <int>{for (var y = 0; y < 1080; y += 40) grainCellSize(grain, 1080)};
      expect(small, <int>{1});
      expect(large, <int>{1});
      expect(grainCellSize(grain, 2160) / grainCellSize(grain, 1080), 2);
    });

    test('measureParity: identical images are 0, size mismatch throws, thresholds are respected', () {
      final a = Fixtures.landscape();
      expect(measureParity(a, a.copy()).mean, 0);
      expect(measureParity(a, a.copy()).passes(), isTrue);
      expect(() => measureParity(a, Fixtures.portrait()), throwsArgumentError);
      final shifted = renderer.render(a, BuiltInProfiles.instantWarm, applyEffects: false);
      final r = measureParity(a, shifted);
      expect(r.mean, greaterThan(2));
      expect(r.passes(), isFalse);
      expect(r.passes(meanLimit: 100, p95Limit: 100), isTrue);
      expect(r.toString(), contains('mean'));
      expect(r.max, greaterThanOrEqualTo(r.p95));
    });
  });

  group('GPU shader contract (PRF-001)', () {
    test('packs uniforms in the order the shader declares them', () {
      final p = ProfileShaderParams.from(BuiltInProfiles.warmFilm, width: 1920, height: 1080, seed: 0x12345);
      expect(p.floats.length, ProfileShaderParams.floatCount);
      expect(p.floats.length, ProfileShaderParams.uniformNames.length);
      expect(p.floats[0], 1920);
      expect(p.floats[1], 1080);
      expect(p.floats[2], 33);
      expect(p.floats[3], 0.25); // grain amount
      expect(p.floats[4], 1); // grain cell at 1080 px
      expect(p.floats[5], 0.1); // grain chroma
      expect(p.floats[6], 0x2345); // seed low 16 bits
      expect(p.floats[7], 0.2); // vignette amount
      expect(p.floats[8], 0.6);
      expect(p.floats[9], 0.2);
      expect(p.floats[10], 1);
      expect(ProfileShaderParams.from(BuiltInProfiles.natural, width: 100, height: 200, effects: false).floats[10], 0);
      expect(ProfileShaderParams.from(BuiltInProfiles.warmFilm, width: 4320, height: 2160).floats[4], 2); // relative to the short edge
    });

    test('the shader asset declares exactly the packed uniforms, in order, plus the two samplers', () {
      final source = File('assets/shaders/profile.frag').readAsStringSync();
      final declared = RegExp(r'^uniform (?:float|vec2) (\w+);', multiLine: true).allMatches(source).map((m) => m.group(1)!).toList();
      // uSize is a vec2 and expands to two floats
      final expanded = <String>[for (final name in declared) ...(name == 'uSize' ? <String>['uSize.x', 'uSize.y'] : <String>[name])];
      expect(expanded, ProfileShaderParams.uniformNames);
      expect(source, contains('uniform sampler2D uImage;'));
      expect(source, contains('uniform sampler2D uLut;'));
      expect(source, contains('#include <flutter/runtime_effect.glsl>'));
      expect(source.indexOf('uniform sampler2D uImage;'), lessThan(source.indexOf('uniform sampler2D uLut;')));
      expect(profileShaderAsset, 'assets/shaders/profile.frag');
    });

    test('the shader and the CPU reference use the same effect constants (grain strength, midtone weight, vignette smoothstep)', () {
      final source = File('assets/shaders/profile.frag').readAsStringSync();
      expect(source, contains('uGrainAmount * 0.18 * midtone'));
      expect(source, contains('1.0 - 0.7 * (2.0 * l - 1.0) * (2.0 * l - 1.0)'));
      expect(source, contains('smoothstep(uVignetteMidpoint, 1.0, d)'));
      expect(source, contains('0.2126, 0.7152, 0.0722'));
    });

    test('TiledLutTexture clamps at the edges and reproduces lattice colors exactly', () {
      final lut = compileProfile(BuiltInProfiles.natural);
      final texture = TiledLutTexture.forLut(lut);
      final corner = texture.lookup(1, 1, 1);
      final expected = lut.at(32, 32, 32);
      expect(corner.r, closeTo(expected.r, 1 / 255));
      expect(texture.lookup(-1, -1, -1).r, closeTo(lut.at(0, 0, 0).r, 1 / 255));
      expect(texture.sampleBilinear(0, 0).r, closeTo(lut.at(0, 0, 0).r, 1 / 255));
      expect(texture.sampleBilinear(1, 1).g, closeTo(lut.at(32, 32, 32).g, 1 / 255));
    });
  });
}
