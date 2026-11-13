/// The standard fixture images for parity and golden tests (image-profile.md "Parity"): a color chart and
/// three procedurally generated natural-looking scenes. Deterministic, original, and free of any camera data.
library;

import 'dart:math' as math;

import 'package:doro_cam/profiles/color_math.dart';
import 'package:doro_cam/profiles/renderer.dart';

abstract final class Fixtures {
  /// 24 patches (6 × 4): primaries, secondaries, skin-like tones, foliage/sky-like colors and a gray ramp.
  static const List<List<int>> chartColors = <List<int>>[
    [115, 82, 68], [194, 150, 130], [98, 122, 157], [87, 108, 67], [133, 128, 177], [103, 189, 170],
    [214, 126, 44], [80, 91, 166], [193, 90, 99], [94, 60, 108], [157, 188, 64], [224, 163, 46],
    [56, 61, 150], [70, 148, 73], [175, 54, 60], [231, 199, 31], [187, 86, 149], [8, 133, 161],
    [243, 243, 242], [200, 200, 200], [160, 160, 160], [122, 122, 121], [85, 85, 85], [52, 52, 52],
  ];

  /// A 6×4 grid of flat patches, each [patch] pixels square.
  static ImageBuffer colorChart({int patch = 12}) {
    final image = ImageBuffer(6 * patch, 4 * patch);
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final c = chartColors[(y ~/ patch) * 6 + (x ~/ patch)];
        image.setPixel(x, y, Rgb(c[0] / 255, c[1] / 255, c[2] / 255));
      }
    }
    return image;
  }

  /// A smooth ramp across the full tonal and hue range (every column a different hue and lightness).
  static ImageBuffer rampImage({int width = 64, int height = 32}) {
    final image = ImageBuffer(width, height);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final hue = x / width * 360;
        final lightness = 0.1 + 0.8 * (1 - y / (height - 1));
        image.setPixel(x, y, hslToRgb(hue, 0.7, lightness));
      }
    }
    return image;
  }

  /// A landscape: sky gradient, sun glow, distant hills and green ground with gentle texture.
  static ImageBuffer landscape({int width = 64, int height = 48}) {
    final image = ImageBuffer(width, height);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final v = y / (height - 1);
        final u = x / (width - 1);
        Rgb c;
        if (v < 0.55) {
          final sky = Rgb(0.25 + 0.55 * v, 0.45 + 0.35 * v, 0.85 - 0.25 * v);
          final glow = math.exp(-(math.pow(u - 0.7, 2) + math.pow(v - 0.45, 2)) * 25);
          c = Rgb(sky.r + glow * 0.5, sky.g + glow * 0.3, sky.b - glow * 0.2);
        } else if (v < 0.65) {
          c = Rgb(0.30, 0.38 + 0.1 * math.sin(u * 9), 0.34);
        } else {
          final tex = 0.04 * math.sin(u * 40 + v * 23);
          c = Rgb(0.18 + tex, 0.42 + tex * 1.5, 0.14 + tex);
        }
        image.setPixel(x, y, c.clamped);
      }
    }
    return image;
  }

  /// A portrait-like scene: a skin-toned oval against a muted background with a warm light gradient.
  static ImageBuffer portrait({int width = 48, int height = 64}) {
    final image = ImageBuffer(width, height);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final nx = (x / (width - 1) - 0.5) / 0.28;
        final ny = (y / (height - 1) - 0.42) / 0.34;
        final inFace = nx * nx + ny * ny < 1;
        final light = 0.85 + 0.15 * (1 - x / (width - 1));
        final c = inFace
            ? Rgb(0.86 * light, 0.64 * light, 0.52 * light)
            : Rgb(0.30 + 0.1 * y / height, 0.34 + 0.08 * y / height, 0.40);
        image.setPixel(x, y, c.clamped);
      }
    }
    return image;
  }

  /// An indoor scene: warm lamp light falling off into dark corners, with a bright window and shelf details.
  static ImageBuffer indoor({int width = 64, int height = 48}) {
    final image = ImageBuffer(width, height);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final u = x / (width - 1);
        final v = y / (height - 1);
        final lamp = math.exp(-(math.pow(u - 0.3, 2) + math.pow(v - 0.35, 2)) * 9);
        var c = Rgb(0.10 + 0.8 * lamp, 0.07 + 0.55 * lamp, 0.04 + 0.28 * lamp);
        if (u > 0.68 && u < 0.92 && v > 0.15 && v < 0.6) {
          c = const Rgb(0.78, 0.86, 0.95); // window
        }
        if (v > 0.8) {
          c = Rgb(c.r * 0.6 + 0.05, c.g * 0.5 + 0.03, c.b * 0.4 + 0.02); // floor
        }
        image.setPixel(x, y, c.clamped);
      }
    }
    return image;
  }

  /// The standard set used for parity: chart + three natural scenes.
  static Map<String, ImageBuffer> standardSet() => <String, ImageBuffer>{
        'chart': colorChart(),
        'landscape': landscape(),
        'portrait': portrait(),
        'indoor': indoor(),
      };
}
