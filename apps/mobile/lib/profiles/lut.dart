/// 3D LUT compilation and serialization (image-profile.md "Compilation").
///
/// A profile's color look compiles to a 33×33×33 LUT (sRGB-encoded input → output). The binary `.lut`
/// format stores float16 RGB, little-endian, with a small header. A `.cube` export serves tooling and ffmpeg.
library;

import 'dart:typed_data';

import 'package:doro_cam/profiles/color_math.dart';
import 'package:doro_cam/profiles/color_pipeline.dart';
import 'package:doro_cam/profiles/image_profile.dart';

/// Converts a double to IEEE 754 half precision bits, rounding to nearest even. Values beyond the half
/// range saturate to infinity; NaN stays NaN.
int doubleToHalfBits(double value) {
  final bytes = ByteData(4)..setFloat32(0, value);
  final f = bytes.getUint32(0);
  final sign = (f >> 16) & 0x8000;
  final exp = (f >> 23) & 0xff;
  final mant = f & 0x7fffff;
  if (exp == 0xff) {
    return sign | 0x7c00 | (mant != 0 ? 0x200 : 0);
  }
  final e = exp - 127 + 15;
  if (e >= 0x1f) {
    return sign | 0x7c00;
  }
  if (e <= 0) {
    if (e < -10) {
      return sign;
    }
    final m = mant | 0x800000;
    final shift = 14 - e;
    var half = m >> shift;
    final rem = m & ((1 << shift) - 1);
    final halfway = 1 << (shift - 1);
    if (rem > halfway || (rem == halfway && (half & 1) == 1)) {
      half++;
    }
    return sign | half;
  }
  var half = (e << 10) | (mant >> 13);
  final rem = mant & 0x1fff;
  if (rem > 0x1000 || (rem == 0x1000 && (half & 1) == 1)) {
    half++;
  }
  return sign | half;
}

double halfBitsToDouble(int bits) {
  final sign = (bits & 0x8000) != 0 ? -1.0 : 1.0;
  final exp = (bits >> 10) & 0x1f;
  final mant = bits & 0x3ff;
  if (exp == 0) {
    return sign * mant * 5.960464477539063e-8; // 2^-24
  }
  if (exp == 0x1f) {
    return mant == 0 ? sign * double.infinity : double.nan;
  }
  return sign * (1 + mant / 1024) * _pow2(exp - 15);
}

double _pow2(int e) {
  var result = 1.0;
  if (e >= 0) {
    for (var i = 0; i < e; i++) {
      result *= 2;
    }
  } else {
    for (var i = 0; i < -e; i++) {
      result /= 2;
    }
  }
  return result;
}

/// FNV-1a over bytes: a cheap, stable checksum for golden tests and asset freshness checks.
int fnv1a32(List<int> bytes) {
  var hash = 0x811c9dc5;
  for (final byte in bytes) {
    hash ^= byte & 0xff;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash;
}

class LutFormatException implements Exception {
  LutFormatException(this.message);

  final String message;

  @override
  String toString() => 'LutFormatException: $message';
}

class Lut3d {
  Lut3d(this.size, this.data) {
    if (size < 2) {
      throw ArgumentError('A LUT needs at least 2 points per axis.');
    }
    if (data.length != size * size * size * 3) {
      throw ArgumentError('LUT data length must be size³ × 3.');
    }
  }

  /// Compiles [params] into a LUT. Deterministic: the same input always yields identical values.
  factory Lut3d.compile(ColorParams params, {int size = defaultSize}) {
    final pipeline = ColorPipeline(params);
    final data = Float32List(size * size * size * 3);
    var i = 0;
    for (var b = 0; b < size; b++) {
      for (var g = 0; g < size; g++) {
        for (var r = 0; r < size; r++) {
          final out = pipeline.apply(r / (size - 1), g / (size - 1), b / (size - 1));
          data[i++] = out.r;
          data[i++] = out.g;
          data[i++] = out.b;
        }
      }
    }
    return Lut3d(size, data);
  }

  /// The identity LUT (output equals input), the reference for tests.
  factory Lut3d.identity({int size = defaultSize}) {
    final data = Float32List(size * size * size * 3);
    var i = 0;
    for (var b = 0; b < size; b++) {
      for (var g = 0; g < size; g++) {
        for (var r = 0; r < size; r++) {
          data[i++] = r / (size - 1);
          data[i++] = g / (size - 1);
          data[i++] = b / (size - 1);
        }
      }
    }
    return Lut3d(size, data);
  }

  static const int defaultSize = 33;

  /// Points per axis.
  final int size;

  /// RGB triples, red varying fastest, then green, then blue (the `.cube` order).
  final Float32List data;

  /// Output at lattice point (r, g, b).
  Rgb at(int r, int g, int b) {
    final i = ((b * size + g) * size + r) * 3;
    return Rgb(data[i], data[i + 1], data[i + 2]);
  }

  /// Trilinear interpolation, what a GPU 3D texture lookup does.
  Rgb sample(double r, double g, double b) {
    final max = size - 1;
    final fr = clamp01(r) * max;
    final fg = clamp01(g) * max;
    final fb = clamp01(b) * max;
    final r0 = fr.floor().clamp(0, max - 1);
    final g0 = fg.floor().clamp(0, max - 1);
    final b0 = fb.floor().clamp(0, max - 1);
    final dr = fr - r0;
    final dg = fg - g0;
    final db = fb - b0;
    double lerp(double a, double c, double t) => a + (c - a) * t;
    Rgb mix(Rgb a, Rgb c, double t) => Rgb(lerp(a.r, c.r, t), lerp(a.g, c.g, t), lerp(a.b, c.b, t));
    final c000 = at(r0, g0, b0);
    final c100 = at(r0 + 1, g0, b0);
    final c010 = at(r0, g0 + 1, b0);
    final c110 = at(r0 + 1, g0 + 1, b0);
    final c001 = at(r0, g0, b0 + 1);
    final c101 = at(r0 + 1, g0, b0 + 1);
    final c011 = at(r0, g0 + 1, b0 + 1);
    final c111 = at(r0 + 1, g0 + 1, b0 + 1);
    return mix(mix(mix(c000, c100, dr), mix(c010, c110, dr), dg), mix(mix(c001, c101, dr), mix(c011, c111, dr), dg), db);
  }

  static const List<int> _magic = <int>[0x44, 0x4c, 0x55, 0x54]; // "DLUT"
  static const int _formatVersion = 1;

  /// The compact binary asset: `DLUT`, format version (u8), channels (u8 = 3), size (u16 LE), then
  /// float16 RGB values, little-endian.
  Uint8List toBinary() {
    final out = ByteData(8 + data.length * 2);
    for (var i = 0; i < 4; i++) {
      out.setUint8(i, _magic[i]);
    }
    out.setUint8(4, _formatVersion);
    out.setUint8(5, 3);
    out.setUint16(6, size, Endian.little);
    for (var i = 0; i < data.length; i++) {
      out.setUint16(8 + i * 2, doubleToHalfBits(data[i]), Endian.little);
    }
    return out.buffer.asUint8List();
  }

  /// Parses [toBinary] output. Throws [LutFormatException] for anything corrupt (the UI then falls back to `natural`).
  factory Lut3d.fromBinary(Uint8List bytes) {
    if (bytes.length < 8) {
      throw LutFormatException('LUT file is too short.');
    }
    final view = ByteData.sublistView(bytes);
    for (var i = 0; i < 4; i++) {
      if (view.getUint8(i) != _magic[i]) {
        throw LutFormatException('Not a Doro Cam LUT file.');
      }
    }
    if (view.getUint8(4) != _formatVersion) {
      throw LutFormatException('Unsupported LUT format version ${view.getUint8(4)}.');
    }
    if (view.getUint8(5) != 3) {
      throw LutFormatException('Only RGB LUTs are supported.');
    }
    final size = view.getUint16(6, Endian.little);
    if (size < 2 || size > 65) {
      throw LutFormatException('Unreasonable LUT size $size.');
    }
    final count = size * size * size * 3;
    if (bytes.length != 8 + count * 2) {
      throw LutFormatException('LUT file length does not match its size.');
    }
    final data = Float32List(count);
    for (var i = 0; i < count; i++) {
      data[i] = halfBitsToDouble(view.getUint16(8 + i * 2, Endian.little));
    }
    return Lut3d(size, data);
  }

  /// Adobe/Resolve `.cube` text for tooling and ffmpeg's `lut3d` filter.
  String toCube({String title = 'Doro Cam'}) {
    final buffer = StringBuffer()
      ..writeln('TITLE "$title"')
      ..writeln('LUT_3D_SIZE $size')
      ..writeln('DOMAIN_MIN 0.0 0.0 0.0')
      ..writeln('DOMAIN_MAX 1.0 1.0 1.0');
    for (var i = 0; i < data.length; i += 3) {
      buffer.writeln('${data[i].toStringAsFixed(6)} ${data[i + 1].toStringAsFixed(6)} ${data[i + 2].toStringAsFixed(6)}');
    }
    return buffer.toString();
  }

  /// The LUT as an RGBA8 image for the GPU preview path where 3D textures are unavailable (S2): `size`
  /// slices of `size × size` laid side by side — width `size²`, height `size`; texel (x = b·size + r, y = g).
  Uint8List toTiledRgba8() {
    final width = size * size;
    final out = Uint8List(width * size * 4);
    for (var b = 0; b < size; b++) {
      for (var g = 0; g < size; g++) {
        for (var r = 0; r < size; r++) {
          final rgb = at(r, g, b);
          final o = (g * width + b * size + r) * 4;
          out[o] = (clamp01(rgb.r) * 255).round();
          out[o + 1] = (clamp01(rgb.g) * 255).round();
          out[o + 2] = (clamp01(rgb.b) * 255).round();
          out[o + 3] = 255;
        }
      }
    }
    return out;
  }

  /// Checksum of the binary form: byte-stable across runs and platforms.
  int get checksum => fnv1a32(toBinary());
}

/// Compiles a profile's LUT.
Lut3d compileProfile(ImageProfile profile, {int size = Lut3d.defaultSize}) => Lut3d.compile(profile.color, size: size);
