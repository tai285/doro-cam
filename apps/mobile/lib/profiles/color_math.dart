/// Color math shared by the LUT compiler, the CPU renderer and the parity tests.
library;

import 'dart:math' as math;

/// sRGB transfer functions on values in [0, 1].
double srgbToLinear(double v) => v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();

double linearToSrgb(double v) {
  final c = v < 0 ? 0.0 : v;
  return c <= 0.0031308 ? c * 12.92 : 1.055 * math.pow(c, 1 / 2.4).toDouble() - 0.055;
}

double clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);

/// Rec. 709 luma weights, applied to sRGB-encoded values (as photographers' "luminosity" does).
double luma(double r, double g, double b) => 0.2126 * r + 0.7152 * g + 0.0722 * b;

/// An RGB triple of doubles.
class Rgb {
  const Rgb(this.r, this.g, this.b);

  final double r;
  final double g;
  final double b;

  Rgb map(double Function(double) f) => Rgb(f(r), f(g), f(b));

  Rgb get clamped => Rgb(clamp01(r), clamp01(g), clamp01(b));

  @override
  bool operator ==(Object other) => other is Rgb && other.r == r && other.g == g && other.b == b;

  @override
  int get hashCode => Object.hash(r, g, b);

  @override
  String toString() => 'Rgb($r, $g, $b)';
}

/// Hue (degrees, 0–360), saturation and lightness of an sRGB color in [0, 1].
class Hsl {
  const Hsl(this.h, this.s, this.l);

  final double h;
  final double s;
  final double l;
}

Hsl rgbToHsl(double r, double g, double b) {
  final max = math.max(r, math.max(g, b));
  final min = math.min(r, math.min(g, b));
  final l = (max + min) / 2;
  final d = max - min;
  if (d < 1e-12) {
    return Hsl(0, 0, l);
  }
  final s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
  double h;
  if (max == r) {
    h = (g - b) / d + (g < b ? 6 : 0);
  } else if (max == g) {
    h = (b - r) / d + 2;
  } else {
    h = (r - g) / d + 4;
  }
  return Hsl(h * 60, s, l);
}

Rgb hslToRgb(double h, double s, double l) {
  if (s <= 0) {
    return Rgb(l, l, l);
  }
  final q = l < 0.5 ? l * (1 + s) : l + s - l * s;
  final p = 2 * l - q;
  double channel(double t) {
    var x = t;
    if (x < 0) x += 1;
    if (x > 1) x -= 1;
    if (x < 1 / 6) return p + (q - p) * 6 * x;
    if (x < 1 / 2) return q;
    if (x < 2 / 3) return p + (q - p) * (2 / 3 - x) * 6;
    return p;
  }

  final hn = (h % 360) / 360;
  return Rgb(channel(hn + 1 / 3), channel(hn), channel(hn - 1 / 3));
}

/// A fully saturated color of the given hue (degrees), used as a split-tone tint.
Rgb hueToRgb(double hueDegrees) => hslToRgb(hueDegrees, 1, 0.5);

/// Smallest angular distance between two hues in degrees (0–180).
double hueDistance(double a, double b) {
  final d = ((a - b) % 360 + 540) % 360 - 180;
  return d.abs();
}

// ---- CIE Lab and ΔE2000 (for parity tests, PRF-009) --------------------------------------------

/// CIE L*a*b* (D65) of an sRGB color in [0, 1].
class Lab {
  const Lab(this.l, this.a, this.b);

  final double l;
  final double a;
  final double b;
}

Lab srgbToLab(double r, double g, double b) {
  final lr = srgbToLinear(clamp01(r));
  final lg = srgbToLinear(clamp01(g));
  final lb = srgbToLinear(clamp01(b));
  final x = (0.4124564 * lr + 0.3575761 * lg + 0.1804375 * lb) / 0.95047;
  final y = 0.2126729 * lr + 0.7151522 * lg + 0.0721750 * lb;
  final z = (0.0193339 * lr + 0.1191920 * lg + 0.9503041 * lb) / 1.08883;
  double f(double t) => t > 216 / 24389 ? math.pow(t, 1 / 3).toDouble() : (24389 / 27 * t + 16) / 116;
  final fx = f(x);
  final fy = f(y);
  final fz = f(z);
  return Lab(116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz));
}

/// CIEDE2000 color difference (Sharma, Wu & Dalal 2005), the standard measure for the parity thresholds.
double deltaE2000(Lab x, Lab y) {
  const kL = 1.0, kC = 1.0, kH = 1.0;
  final c1 = math.sqrt(x.a * x.a + x.b * x.b);
  final c2 = math.sqrt(y.a * y.a + y.b * y.b);
  final cBar = (c1 + c2) / 2;
  final cBar7 = math.pow(cBar, 7).toDouble();
  final g = 0.5 * (1 - math.sqrt(cBar7 / (cBar7 + math.pow(25, 7).toDouble())));
  final a1p = (1 + g) * x.a;
  final a2p = (1 + g) * y.a;
  final c1p = math.sqrt(a1p * a1p + x.b * x.b);
  final c2p = math.sqrt(a2p * a2p + y.b * y.b);
  double hp(double b, double a) {
    if (b == 0 && a == 0) return 0;
    final h = math.atan2(b, a) * 180 / math.pi;
    return h < 0 ? h + 360 : h;
  }

  final h1p = hp(x.b, a1p);
  final h2p = hp(y.b, a2p);
  final dLp = y.l - x.l;
  final dCp = c2p - c1p;
  double dhp;
  if (c1p * c2p == 0) {
    dhp = 0;
  } else if ((h2p - h1p).abs() <= 180) {
    dhp = h2p - h1p;
  } else if (h2p - h1p > 180) {
    dhp = h2p - h1p - 360;
  } else {
    dhp = h2p - h1p + 360;
  }
  final dHp = 2 * math.sqrt(c1p * c2p) * math.sin(dhp * math.pi / 360);
  final lBarP = (x.l + y.l) / 2;
  final cBarP = (c1p + c2p) / 2;
  double hBarP;
  if (c1p * c2p == 0) {
    hBarP = h1p + h2p;
  } else if ((h1p - h2p).abs() <= 180) {
    hBarP = (h1p + h2p) / 2;
  } else if (h1p + h2p < 360) {
    hBarP = (h1p + h2p + 360) / 2;
  } else {
    hBarP = (h1p + h2p - 360) / 2;
  }
  double rad(double d) => d * math.pi / 180;
  final t = 1 -
      0.17 * math.cos(rad(hBarP - 30)) +
      0.24 * math.cos(rad(2 * hBarP)) +
      0.32 * math.cos(rad(3 * hBarP + 6)) -
      0.20 * math.cos(rad(4 * hBarP - 63));
  final dTheta = 30 * math.exp(-math.pow((hBarP - 275) / 25, 2).toDouble());
  final cBarP7 = math.pow(cBarP, 7).toDouble();
  final rC = 2 * math.sqrt(cBarP7 / (cBarP7 + math.pow(25, 7).toDouble()));
  final sL = 1 + 0.015 * math.pow(lBarP - 50, 2) / math.sqrt(20 + math.pow(lBarP - 50, 2));
  final sC = 1 + 0.045 * cBarP;
  final sH = 1 + 0.015 * cBarP * t;
  final rT = -math.sin(rad(2 * dTheta)) * rC;
  final lTerm = dLp / (kL * sL);
  final cTerm = dCp / (kC * sC);
  final hTerm = dHp / (kH * sH);
  return math.sqrt(lTerm * lTerm + cTerm * cTerm + hTerm * hTerm + rT * cTerm * hTerm);
}

/// ΔE2000 between two sRGB colors in [0, 1].
double deltaESrgb(Rgb a, Rgb b) => deltaE2000(srgbToLab(a.r, a.g, a.b), srgbToLab(b.r, b.g, b.b));
