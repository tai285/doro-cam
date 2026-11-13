/// The color pipeline: one sRGB pixel in, one sRGB pixel out, in the normative order of image-profile.md.
///
/// exposure → white/black point → temperature/tint → tone curve and contrast → highlights/shadows → HSL →
/// saturation/vibrance → split tone → monochrome mix.
///
/// This is the *definition* of a profile's look. The LUT compiler samples it, the CPU renderer can call it
/// directly, and the GPU path reproduces it through the compiled LUT (parity, PRF-009).
library;

import 'dart:math' as math;

import 'package:doro_cam/profiles/color_math.dart';
import 'package:doro_cam/profiles/image_profile.dart';

/// A monotone cubic Hermite curve through control points (Fritsch–Carlson), so a curve never overshoots.
class ToneCurve {
  ToneCurve(List<CurvePoint> points)
      : _x = <double>[for (final p in points) p.x],
        _y = <double>[for (final p in points) p.y],
        _m = <double>[] {
    final n = _x.length;
    if (n < 2) {
      return;
    }
    final d = <double>[for (var i = 0; i < n - 1; i++) (_y[i + 1] - _y[i]) / (_x[i + 1] - _x[i])];
    final m = List<double>.filled(n, 0);
    m[0] = d[0];
    m[n - 1] = d[n - 2];
    for (var i = 1; i < n - 1; i++) {
      m[i] = d[i - 1] * d[i] <= 0 ? 0 : (d[i - 1] + d[i]) / 2;
    }
    for (var i = 0; i < n - 1; i++) {
      if (d[i] == 0) {
        m[i] = 0;
        m[i + 1] = 0;
        continue;
      }
      final a = m[i] / d[i];
      final b = m[i + 1] / d[i];
      final s = a * a + b * b;
      if (s > 9) {
        final tau = 3 / math.sqrt(s);
        m[i] = tau * a * d[i];
        m[i + 1] = tau * b * d[i];
      }
    }
    _m.addAll(m);
  }

  final List<double> _x;
  final List<double> _y;
  final List<double> _m;

  bool get isIdentity => _x.length < 2;

  /// Output for input [v] in [0, 1]. Outside the control points the end values hold.
  double operator [](double v) {
    if (isIdentity) {
      return v;
    }
    if (v <= _x.first) {
      return _y.first;
    }
    if (v >= _x.last) {
      return _y.last;
    }
    var i = 0;
    while (i < _x.length - 2 && v > _x[i + 1]) {
      i++;
    }
    final h = _x[i + 1] - _x[i];
    final t = (v - _x[i]) / h;
    final t2 = t * t;
    final t3 = t2 * t;
    return (2 * t3 - 3 * t2 + 1) * _y[i] + (t3 - 2 * t2 + t) * h * _m[i] + (-2 * t3 + 3 * t2) * _y[i + 1] + (t3 - t2) * h * _m[i + 1];
  }
}

class ColorPipeline {
  ColorPipeline(this.params)
      : _curve = ToneCurve(params.toneCurve),
        _exposureGain = math.pow(2, params.exposureEv).toDouble(),
        _activeBands = <MapEntry<HueBand, HslShift>>[
          for (final entry in params.hsl.entries)
            if (!entry.value.isIdentity) entry,
        ],
        _shadowTint = hueToRgb(params.splitShadows.hue),
        _highlightTint = hueToRgb(params.splitHighlights.hue);

  final ColorParams params;
  final ToneCurve _curve;
  final double _exposureGain;
  final List<MapEntry<HueBand, HslShift>> _activeBands;
  final Rgb _shadowTint;
  final Rgb _highlightTint;

  /// Width of a hue band's influence on each side of its center, in degrees.
  static const double bandWidthDegrees = 45;

  /// Applies the profile's color look to an sRGB-encoded pixel (each channel in [0, 1]).
  Rgb apply(double r, double g, double b) {
    final p = params;

    // 1. exposure (in linear light)
    var cr = r;
    var cg = g;
    var cb = b;
    if (p.exposureEv != 0) {
      cr = clamp01(linearToSrgb(srgbToLinear(clamp01(cr)) * _exposureGain));
      cg = clamp01(linearToSrgb(srgbToLinear(clamp01(cg)) * _exposureGain));
      cb = clamp01(linearToSrgb(srgbToLinear(clamp01(cb)) * _exposureGain));
    }

    // 2. black/white point: output levels
    if (p.blackPoint != 0 || p.whitePoint != 1) {
      final span = p.whitePoint - p.blackPoint;
      cr = p.blackPoint + clamp01(cr) * span;
      cg = p.blackPoint + clamp01(cg) * span;
      cb = p.blackPoint + clamp01(cb) * span;
    }

    // 3. temperature / tint (linear-light channel gains)
    if (p.temperatureShift != 0 || p.tintShift != 0) {
      final rGain = 1 + 0.15 * p.temperatureShift;
      final bGain = 1 - 0.15 * p.temperatureShift;
      final gGain = 1 - 0.10 * p.tintShift;
      cr = clamp01(linearToSrgb(srgbToLinear(cr) * rGain));
      cg = clamp01(linearToSrgb(srgbToLinear(cg) * gGain));
      cb = clamp01(linearToSrgb(srgbToLinear(cb) * bGain));
    }

    // 4. tone curve, then contrast (a smoothstep S-curve blend, monotone for |contrast| ≤ 1)
    if (!_curve.isIdentity) {
      cr = clamp01(_curve[cr]);
      cg = clamp01(_curve[cg]);
      cb = clamp01(_curve[cb]);
    }
    if (p.contrast != 0) {
      double contrast(double v) {
        final s = v * v * (3 - 2 * v);
        return clamp01(v + p.contrast * (s - v));
      }

      cr = contrast(cr);
      cg = contrast(cg);
      cb = contrast(cb);
    }

    // 5. highlights / shadows, weighted by luminance
    if (p.highlights != 0 || p.shadows != 0) {
      final l = luma(cr, cg, cb);
      final delta = 0.3 * (p.shadows * (1 - l) * (1 - l) + p.highlights * l * l);
      cr = clamp01(cr + delta);
      cg = clamp01(cg + delta);
      cb = clamp01(cb + delta);
    }

    // 6. per-hue HSL response
    if (_activeBands.isNotEmpty) {
      final hsl = rgbToHsl(cr, cg, cb);
      var hueShift = 0.0;
      var satScale = 1.0;
      var lumShift = 0.0;
      for (final entry in _activeBands) {
        final d = hueDistance(hsl.h, entry.key.centerDegrees);
        if (d >= bandWidthDegrees) {
          continue;
        }
        // Cosine falloff, scaled by saturation so neutrals are not tinted by a hue they do not have.
        final w = 0.5 * (1 + math.cos(math.pi * d / bandWidthDegrees)) * math.min(1.0, hsl.s * 2);
        hueShift += entry.value.hue * 30 * w;
        satScale += entry.value.sat * w;
        lumShift += entry.value.lum * 0.25 * w;
      }
      final out = hslToRgb(hsl.h + hueShift, clamp01(hsl.s * math.max(0, satScale)), clamp01(hsl.l + lumShift));
      cr = out.r;
      cg = out.g;
      cb = out.b;
    }

    // 7. saturation and vibrance (vibrance lifts muted colors more than vivid ones)
    if (p.saturation != 0 || p.vibrance != 0) {
      final l = luma(cr, cg, cb);
      final chroma = math.max(cr, math.max(cg, cb)) - math.min(cr, math.min(cg, cb));
      final factor = math.max(0, (1 + p.saturation) * (1 + p.vibrance * (1 - chroma)));
      cr = clamp01(l + (cr - l) * factor);
      cg = clamp01(l + (cg - l) * factor);
      cb = clamp01(l + (cb - l) * factor);
    }

    // 8. split tone: zero-mean tint offsets so brightness is preserved
    if (p.splitShadows.amount > 0 || p.splitHighlights.amount > 0) {
      final l = luma(cr, cg, cb);
      final shadowWeight = p.splitShadows.amount * (1 - l) * (1 - l);
      final highlightWeight = p.splitHighlights.amount * l * l;
      final sMean = (_shadowTint.r + _shadowTint.g + _shadowTint.b) / 3;
      final hMean = (_highlightTint.r + _highlightTint.g + _highlightTint.b) / 3;
      cr = clamp01(cr + 0.5 * (shadowWeight * (_shadowTint.r - sMean) + highlightWeight * (_highlightTint.r - hMean)));
      cg = clamp01(cg + 0.5 * (shadowWeight * (_shadowTint.g - sMean) + highlightWeight * (_highlightTint.g - hMean)));
      cb = clamp01(cb + 0.5 * (shadowWeight * (_shadowTint.b - sMean) + highlightWeight * (_highlightTint.b - hMean)));
    }

    // 9. monochrome mix
    final mono = p.monochrome;
    if (mono != null) {
      final gray = clamp01(mono.red * cr + mono.green * cg + mono.blue * cb);
      return Rgb(gray, gray, gray);
    }
    return Rgb(cr, cg, cb);
  }
}
