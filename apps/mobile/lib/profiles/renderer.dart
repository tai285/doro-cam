/// The CPU reference renderer (PRF-003, PRF-009). It defines what a rendered photo must look like; GPU and
/// worker paths are tested against it.
library;

import 'dart:typed_data';

import 'package:doro_cam/profiles/color_math.dart';
import 'package:doro_cam/profiles/color_pipeline.dart';
import 'package:doro_cam/profiles/effects.dart';
import 'package:doro_cam/profiles/image_profile.dart';
import 'package:doro_cam/profiles/lut.dart';

/// A tightly packed RGBA8 image (alpha is carried through unchanged).
class ImageBuffer {
  ImageBuffer(this.width, this.height, [Uint8List? pixels])
      : rgba = pixels ?? Uint8List(width * height * 4) {
    if (width <= 0 || height <= 0) {
      throw ArgumentError('An image needs a positive size.');
    }
    if (rgba.length != width * height * 4) {
      throw ArgumentError('Pixel data must be width × height × 4 bytes.');
    }
  }

  final int width;
  final int height;
  final Uint8List rgba;

  int _offset(int x, int y) => (y * width + x) * 4;

  Rgb pixel(int x, int y) {
    final o = _offset(x, y);
    return Rgb(rgba[o] / 255, rgba[o + 1] / 255, rgba[o + 2] / 255);
  }

  void setPixel(int x, int y, Rgb c, [int alpha = 255]) {
    final o = _offset(x, y);
    rgba[o] = (clamp01(c.r) * 255).round();
    rgba[o + 1] = (clamp01(c.g) * 255).round();
    rgba[o + 2] = (clamp01(c.b) * 255).round();
    rgba[o + 3] = alpha;
  }

  ImageBuffer copy() => ImageBuffer(width, height, Uint8List.fromList(rgba));
}

/// How a render treats the color step.
enum ColorPath {
  /// Evaluate the profile's pipeline per pixel. The reference ("ground truth") look.
  exact,

  /// Sample the compiled 33³ LUT with trilinear interpolation: what the GPU and capture render do.
  lut,
}

class ProfileRenderer {
  const ProfileRenderer();

  /// Renders [source] with [profile]. Grain is seeded with [seed] (use [seedFromMemoryId]).
  ImageBuffer render(
    ImageBuffer source,
    ImageProfile profile, {
    ColorPath colorPath = ColorPath.lut,
    Lut3d? lut,
    int seed = 0,
    bool applyEffects = true,
  }) {
    final out = ImageBuffer(source.width, source.height);
    final pipeline = colorPath == ColorPath.exact ? ColorPipeline(profile.color) : null;
    final table = colorPath == ColorPath.lut ? (lut ?? compileProfile(profile)) : null;
    final effects = profile.effects;
    for (var y = 0; y < source.height; y++) {
      for (var x = 0; x < source.width; x++) {
        final o = (y * source.width + x) * 4;
        final r = source.rgba[o] / 255;
        final g = source.rgba[o + 1] / 255;
        final b = source.rgba[o + 2] / 255;
        var c = pipeline != null ? pipeline.apply(r, g, b) : table!.sample(r, g, b);
        if (applyEffects) {
          if (effects.vignette.isActive) {
            final f = vignetteFactor(x.toDouble(), y.toDouble(), source.width, source.height, effects.vignette);
            c = Rgb(c.r * f, c.g * f, c.b * f);
          }
          c = applyGrain(c, x, y, source.width, source.height, effects.grain, seed);
        }
        out.setPixel(x, y, c, source.rgba[o + 3]);
      }
    }
    return out;
  }
}

/// Mean and 95th-percentile ΔE2000 between two same-size images (PRF-009).
class ParityResult {
  const ParityResult({required this.mean, required this.p95, required this.max});

  final double mean;
  final double p95;
  final double max;

  bool passes({double meanLimit = 2.0, double p95Limit = 4.0}) => mean <= meanLimit && p95 <= p95Limit;

  @override
  String toString() => 'ParityResult(mean: ${mean.toStringAsFixed(3)}, p95: ${p95.toStringAsFixed(3)}, max: ${max.toStringAsFixed(3)})';
}

ParityResult measureParity(ImageBuffer a, ImageBuffer b) {
  if (a.width != b.width || a.height != b.height) {
    throw ArgumentError('Images must have the same size.');
  }
  final values = <double>[];
  for (var y = 0; y < a.height; y++) {
    for (var x = 0; x < a.width; x++) {
      values.add(deltaESrgb(a.pixel(x, y), b.pixel(x, y)));
    }
  }
  values.sort();
  final sum = values.fold<double>(0, (s, v) => s + v);
  final p95Index = ((values.length - 1) * 0.95).ceil();
  return ParityResult(mean: sum / values.length, p95: values[p95Index], max: values.last);
}
