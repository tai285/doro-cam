/// Spatial effects applied after the LUT: vignette and grain (PRF-006).
///
/// Effects are resolution independent: sizes are relative to the image's short edge, so a preview and a
/// full-resolution render look the same. Grain is seeded from the Memory id, so re-renders are reproducible.
library;

import 'dart:math' as math;

import 'package:doro_cam/profiles/color_math.dart';
import 'package:doro_cam/profiles/image_profile.dart';

/// A stable 32-bit seed from a Memory id (FNV-1a over its UTF-16 code units).
int seedFromMemoryId(String id) {
  var hash = 0x811c9dc5;
  for (final unit in id.codeUnits) {
    hash ^= unit & 0xff;
    hash = (hash * 0x01000193) & 0xffffffff;
    hash ^= (unit >> 8) & 0xff;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash;
}

/// An integer hash of a lattice cell → a double in [0, 1). Pure integer math, identical on every platform.
double hashNoise(int x, int y, int seed, int channel) {
  var h = (x * 0x27d4eb2d) & 0xffffffff;
  h ^= (y * 0x165667b1) & 0xffffffff;
  h ^= (seed * 0x9e3779b1) & 0xffffffff;
  h ^= (channel * 0x85ebca6b) & 0xffffffff;
  h ^= h >> 15;
  h = (h * 0x2c1b3c6d) & 0xffffffff;
  h ^= h >> 12;
  h = (h * 0x297a2d39) & 0xffffffff;
  h ^= h >> 15;
  return (h & 0xffffff) / 0x1000000;
}

/// Roughly Gaussian noise in [-1, 1] from two uniform samples (triangular distribution).
double grainSample(int x, int y, int seed, int channel) =>
    hashNoise(x, y, seed, channel * 2) + hashNoise(x, y, seed, channel * 2 + 1) - 1;

/// Grain cell edge in pixels for an image with the given short edge, so grain scales with the image (PRF-009).
int grainCellSize(GrainParams grain, int shortEdge) => math.max(1, (grain.size * shortEdge / 1080).round());

/// Adds grain to the pixel at ([x], [y]). Grain is strongest in the midtones and fades in deep shadows and
/// highlights, like film.
Rgb applyGrain(Rgb c, int x, int y, int width, int height, GrainParams grain, int seed) {
  if (!grain.isActive) {
    return c;
  }
  final cell = grainCellSize(grain, math.min(width, height));
  final cx = x ~/ cell;
  final cy = y ~/ cell;
  final l = luma(c.r, c.g, c.b);
  final midtone = 1 - 0.7 * (2 * l - 1) * (2 * l - 1);
  final strength = grain.amount * 0.18 * midtone;
  final mono = grainSample(cx, cy, seed, 0);
  double channel(int k) => strength * ((1 - grain.chroma) * mono + grain.chroma * grainSample(cx, cy, seed, k));
  return Rgb(clamp01(c.r + channel(1)), clamp01(c.g + channel(2)), clamp01(c.b + channel(3)));
}

double _smoothstep(double edge0, double edge1, double x) {
  if (edge1 <= edge0) {
    return x >= edge1 ? 1 : 0;
  }
  final t = clamp01((x - edge0) / (edge1 - edge0));
  return t * t * (3 - 2 * t);
}

/// Normalized distance of pixel center ([x], [y]) from the image center: 0 in the middle, 1 at the corners
/// (for an ellipse that follows the frame). [roundness] blends toward a circle (positive) or a rounded
/// rectangle (negative).
double vignetteDistance(double x, double y, int width, int height, double roundness) {
  final hw = width / 2;
  final hh = height / 2;
  final nx = (x + 0.5 - hw) / hw;
  final ny = (y + 0.5 - hh) / hh;
  final ellipse = math.sqrt(nx * nx + ny * ny) / math.sqrt2;
  if (roundness >= 0) {
    final dx = x + 0.5 - hw;
    final dy = y + 0.5 - hh;
    final circle = math.sqrt(dx * dx + dy * dy) / math.sqrt(hw * hw + hh * hh);
    return ellipse + (circle - ellipse) * roundness;
  }
  final p = 2 + (-roundness) * 4;
  final superEllipse = math.pow(math.pow(nx.abs(), p) + math.pow(ny.abs(), p), 1 / p).toDouble() / math.pow(2, 1 / p).toDouble();
  return ellipse + (superEllipse - ellipse) * (-roundness);
}

/// Brightness multiplier (≤ 1) of the vignette at a pixel.
double vignetteFactor(double x, double y, int width, int height, VignetteParams v) {
  if (!v.isActive) {
    return 1;
  }
  final d = vignetteDistance(x, y, width, height, v.roundness);
  return 1 - v.amount * _smoothstep(v.midpoint, 1.0, d);
}
