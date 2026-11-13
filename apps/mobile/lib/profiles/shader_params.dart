/// Packs a profile into the uniforms of `assets/shaders/profile.frag` (the GPU preview path, PRF-001).
///
/// The shader and this packer share one contract: the float order below. `ui.FragmentShader.setFloat` is
/// called by the UI layer with [ProfileShaderParams.floats] in order; the images (camera frame, tiled LUT)
/// are bound as the two samplers.
library;

import 'dart:typed_data';

import 'package:doro_cam/profiles/color_math.dart';
import 'package:doro_cam/profiles/effects.dart';
import 'package:doro_cam/profiles/image_profile.dart';
import 'package:doro_cam/profiles/lut.dart';

/// Asset path of the fragment shader.
const String profileShaderAsset = 'assets/shaders/profile.frag';

class ProfileShaderParams {
  ProfileShaderParams._(this.floats);

  /// Packs [profile] for a frame of [width] × [height]. [seed] comes from [seedFromMemoryId]; the shader
  /// uses its low 16 bits (floats cannot hold more exactly).
  factory ProfileShaderParams.from(
    ImageProfile profile, {
    required double width,
    required double height,
    int seed = 0,
    bool effects = true,
    int lutSize = Lut3d.defaultSize,
  }) {
    final grain = profile.effects.grain;
    final vignette = profile.effects.vignette;
    final shortEdge = width < height ? width : height;
    return ProfileShaderParams._(<double>[
      width, // uSize.x
      height, // uSize.y
      lutSize.toDouble(), // uLutSize
      grain.amount, // uGrainAmount
      grainCellSize(grain, shortEdge.round()).toDouble(), // uGrainCell
      grain.chroma, // uGrainChroma
      (seed & 0xffff).toDouble(), // uSeed
      vignette.amount, // uVignetteAmount
      vignette.midpoint, // uVignetteMidpoint
      vignette.roundness, // uVignetteRoundness
      effects ? 1 : 0, // uEffectsEnabled
    ]);
  }

  /// Uniform floats in shader declaration order.
  final List<double> floats;

  static const int floatCount = 11;

  /// Names in order, for documentation and tests.
  static const List<String> uniformNames = <String>[
    'uSize.x',
    'uSize.y',
    'uLutSize',
    'uGrainAmount',
    'uGrainCell',
    'uGrainChroma',
    'uSeed',
    'uVignetteAmount',
    'uVignetteMidpoint',
    'uVignetteRoundness',
    'uEffectsEnabled',
  ];
}

/// The RGBA8 pixels of the tiled LUT texture for [profile], and its size (width `size²`, height `size`).
class TiledLutTexture {
  TiledLutTexture(this.size, this.pixels);

  factory TiledLutTexture.forLut(Lut3d lut) => TiledLutTexture(lut.size, lut.toTiledRgba8());

  final int size;
  final Uint8List pixels;

  int get width => size * size;
  int get height => size;

  Rgb _texel(int x, int y) {
    final cx = x.clamp(0, width - 1);
    final cy = y.clamp(0, height - 1);
    final o = (cy * width + cx) * 4;
    return Rgb(pixels[o] / 255, pixels[o + 1] / 255, pixels[o + 2] / 255);
  }

  /// Bilinear sample at texture coordinates (u, v) in [0, 1], as a GPU sampler with linear filtering and
  /// clamp-to-edge would do.
  Rgb sampleBilinear(double u, double v) {
    final fx = u * width - 0.5;
    final fy = v * height - 0.5;
    final x0 = fx.floor();
    final y0 = fy.floor();
    final tx = fx - x0;
    final ty = fy - y0;
    final a = _texel(x0, y0);
    final b = _texel(x0 + 1, y0);
    final c = _texel(x0, y0 + 1);
    final d = _texel(x0 + 1, y0 + 1);
    double mix(double p, double q, double t) => p + (q - p) * t;
    Rgb mixRgb(Rgb p, Rgb q, double t) => Rgb(mix(p.r, q.r, t), mix(p.g, q.g, t), mix(p.b, q.b, t));
    return mixRgb(mixRgb(a, b, tx), mixRgb(c, d, tx), ty);
  }

  /// What `lutLookup` in `profile.frag` computes for an sRGB color: the GPU color path, reproduced on the CPU
  /// so tests can check it against the float LUT and the exact pipeline.
  Rgb lookup(double r, double g, double b) {
    final s = size.toDouble();
    final bScaled = clamp01(b) * (s - 1);
    final b0 = bScaled.floorToDouble();
    final b1 = b0 + 1 < s - 1 ? b0 + 1 : s - 1;
    final fb = bScaled - b0;
    final x = clamp01(r) * (s - 1) + 0.5;
    final y = (clamp01(g) * (s - 1) + 0.5) / s;
    final c0 = sampleBilinear((b0 * s + x) / (s * s), y);
    final c1 = sampleBilinear((b1 * s + x) / (s * s), y);
    return Rgb(c0.r + (c1.r - c0.r) * fb, c0.g + (c1.g - c0.g) * fb, c0.b + (c1.b - c0.b) * fb);
  }
}
