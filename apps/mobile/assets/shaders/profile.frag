// Doro Cam image profile shader (docs/specs/image-profile.md, ADR-0004).
//
// Applies a profile's compiled 3D LUT, then vignette and grain, to an image or a camera preview frame.
// The LUT arrives as a 2D "tiled" texture because Flutter fragment shaders have no 3D samplers: `size`
// slices of `size x size` laid side by side (width size*size, height size); texel (x = b*size + r, y = g).
// The Dart side packs uniforms with ProfileShaderParams (lib/profiles/shader_params.dart) in this exact order.
#version 460 core

#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec2 uSize;             // image size in pixels
uniform float uLutSize;         // points per LUT axis (33)
uniform float uGrainAmount;     // 0..1
uniform float uGrainCell;       // grain cell edge in pixels (relative to the short edge)
uniform float uGrainChroma;     // 0..1
uniform float uSeed;            // 0..65535, derived from the Memory id
uniform float uVignetteAmount;  // 0..1
uniform float uVignetteMidpoint;// 0..1
uniform float uVignetteRoundness; // -1..1
uniform float uEffectsEnabled;  // 1 = effects on, 0 = LUT only

uniform sampler2D uImage;
uniform sampler2D uLut;

out vec4 fragColor;

// Samples the tiled LUT with trilinear interpolation (bilinear in r,g by the sampler, linear in b by hand).
vec3 lutLookup(vec3 c) {
  float s = uLutSize;
  float b = clamp(c.b, 0.0, 1.0) * (s - 1.0);
  float b0 = floor(b);
  float b1 = min(b0 + 1.0, s - 1.0);
  float fb = b - b0;
  float x = clamp(c.r, 0.0, 1.0) * (s - 1.0) + 0.5;
  float y = (clamp(c.g, 0.0, 1.0) * (s - 1.0) + 0.5) / s;
  vec2 uv0 = vec2((b0 * s + x) / (s * s), y);
  vec2 uv1 = vec2((b1 * s + x) / (s * s), y);
  return mix(texture(uLut, uv0).rgb, texture(uLut, uv1).rgb, fb);
}

float hash12(vec2 p, float seed) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031 + seed * 0.0001);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

float vignetteDistance(vec2 px, float roundness) {
  vec2 half_ = uSize * 0.5;
  vec2 n = (px - half_) / half_;
  float ellipse = length(n) / sqrt(2.0);
  if (roundness >= 0.0) {
    float circle = length(px - half_) / length(half_);
    return mix(ellipse, circle, roundness);
  }
  float p = 2.0 + (-roundness) * 4.0;
  float superEllipse = pow(pow(abs(n.x), p) + pow(abs(n.y), p), 1.0 / p) / pow(2.0, 1.0 / p);
  return mix(ellipse, superEllipse, -roundness);
}

void main() {
  vec2 px = FlutterFragCoord().xy;
  vec2 uv = px / uSize;
  vec4 src = texture(uImage, uv);
  vec3 color = lutLookup(src.rgb);

  if (uEffectsEnabled > 0.5) {
    if (uVignetteAmount > 0.0) {
      float d = vignetteDistance(px, uVignetteRoundness);
      float f = 1.0 - uVignetteAmount * smoothstep(uVignetteMidpoint, 1.0, d);
      color *= f;
    }
    if (uGrainAmount > 0.0) {
      vec2 cell = floor(px / max(uGrainCell, 1.0));
      float l = dot(color, vec3(0.2126, 0.7152, 0.0722));
      float midtone = 1.0 - 0.7 * (2.0 * l - 1.0) * (2.0 * l - 1.0);
      float strength = uGrainAmount * 0.18 * midtone;
      float mono = hash12(cell, uSeed) + hash12(cell + 17.0, uSeed) - 1.0;
      vec3 chroma = vec3(
        hash12(cell + 31.0, uSeed) + hash12(cell + 47.0, uSeed) - 1.0,
        hash12(cell + 59.0, uSeed) + hash12(cell + 71.0, uSeed) - 1.0,
        hash12(cell + 83.0, uSeed) + hash12(cell + 97.0, uSeed) - 1.0);
      color += strength * ((1.0 - uGrainChroma) * vec3(mono) + uGrainChroma * chroma);
    }
  }

  fragColor = vec4(clamp(color, 0.0, 1.0), src.a);
}
