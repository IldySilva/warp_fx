// Border beam — rotate family layers (`sm`, `md`).
//
// Port of border-beam-native's ROTATE_LAYER_SKSL (itself a translation of
// BorderBeamKit's BeamShaders.metal): CSS radial-gradient blob stacks, a
// conic gradient, the rotating beam-window mask, rounded-rect ring geometry
// and the CSS filter chain as a colour matrix.
//
// Blob: 2 vec4s — [rx, ry, cxFrac, cyFrac] [r, g, b, a].
// Stops: [pos 0..1, alpha] pairs, two per vec4.

#include <flutter/runtime_effect.glsl>

#define MAX_BLOBS 12
#define MAX_BG_VEC4 8
#define MAX_MASK_VEC4 6

const float PI = 3.14159265358979;

uniform vec2 uSize;
uniform vec4 uParams;   // angle (fraction of a turn), radius, borderWidth, kind (0 stroke, 1 inner, 2 bloom)
uniform vec4 uParams2;  // edgeMaskPx, blobCount, bgPairs, bgIsBlack
uniform vec4 uParams3;  // maskPairs, opacity, shadowBlur, -
uniform vec4 uShadow;   // inner inset shadow colour, straight alpha
uniform vec4 uCM0;
uniform vec4 uCM1;
uniform vec4 uCM2;
uniform vec4 uBlobs[MAX_BLOBS * 2];
uniform vec4 uBg[MAX_BG_VEC4];
uniform vec4 uMask[MAX_MASK_VEC4];

out vec4 fragColor;

float roundedRectSDF(vec2 p, vec2 halfSize, float radius) {
  vec2 q = abs(p) - halfSize + radius;
  return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
}

float conicFraction(vec2 p, vec2 center) {
  vec2 d = p - center;
  float theta = atan(d.x, -d.y);  // 0 at the top, clockwise (y down)
  return fract(theta / (2.0 * PI) + 1.0);
}

// Piecewise linear through the stop pairs, CSS gradient style.
float bgStopsAlpha(float t) {
  float n = uParams2.z;
  if (n < 0.5) { return 1.0; }
  vec2 prev = uBg[0].xy;
  float result = prev.y;
  for (int j = 0; j < MAX_BG_VEC4; j++) {
    vec4 q = uBg[j];
    float k0 = float(j * 2);
    if (j > 0 && k0 < n && t > prev.x) {
      float f = q.x > prev.x ? clamp((t - prev.x) / (q.x - prev.x), 0.0, 1.0) : 1.0;
      result = mix(prev.y, q.y, f);
    }
    if (k0 + 1.0 < n && t > q.x) {
      float f = q.z > q.x ? clamp((t - q.x) / (q.z - q.x), 0.0, 1.0) : 1.0;
      result = mix(q.y, q.w, f);
    }
    prev = q.zw;
  }
  return result;
}

float maskStopsAlpha(float t) {
  float n = uParams3.x;
  if (n < 0.5) { return 1.0; }
  vec2 prev = uMask[0].xy;
  float result = prev.y;
  for (int j = 0; j < MAX_MASK_VEC4; j++) {
    vec4 q = uMask[j];
    float k0 = float(j * 2);
    if (j > 0 && k0 < n && t > prev.x) {
      float f = q.x > prev.x ? clamp((t - prev.x) / (q.x - prev.x), 0.0, 1.0) : 1.0;
      result = mix(prev.y, q.y, f);
    }
    if (k0 + 1.0 < n && t > q.x) {
      float f = q.z > q.x ? clamp((t - q.x) / (q.z - q.x), 0.0, 1.0) : 1.0;
      result = mix(q.y, q.w, f);
    }
    prev = q.zw;
  }
  return result;
}

vec4 srcOver(vec4 src, vec4 dst) {
  return src + dst * (1.0 - src.a);
}

// All the work, in a helper: main() keeps a single exit, which some
// backends need.
vec4 shade(vec2 position) {
  vec2 center = uSize * 0.5;
  vec2 rel = position - center;
  float angle = uParams.x;
  float radius = uParams.y;
  float borderWidth = uParams.z;
  float kind = uParams.w;

  // Geometry: ring band for stroke and bloom, the whole rounded rect for inner.
  float outerSDF = roundedRectSDF(rel, center, radius);
  float outerCov = 1.0 - smoothstep(-1.0, 0.0, outerSDF);
  float geom;
  if (kind > 0.5 && kind < 1.5) {
    geom = outerCov;
  } else {
    float innerRadius = max(radius - borderWidth, 0.0);
    float innerSDF = roundedRectSDF(rel, center - borderWidth, innerRadius);
    float innerCov = 1.0 - smoothstep(-1.0, 0.0, innerSDF);
    geom = outerCov - innerCov;
  }
  if (geom <= 0.0) { return vec4(0.0); }

  float conic = conicFraction(position, center);

  // Rotating conic beam-window mask.
  float mask = 1.0;
  if (uParams3.x > 0.5) {
    mask = maskStopsAlpha(fract(conic - angle));
  }

  // Inner layer: edge fade.
  float edgeMaskPx = uParams2.x;
  if (kind > 0.5 && kind < 1.5 && edgeMaskPx > 0.0) {
    float ev = max(1.0 - position.y / edgeMaskPx, 1.0 - (uSize.y - position.y) / edgeMaskPx);
    float eh = max(1.0 - position.x / edgeMaskPx, 1.0 - (uSize.x - position.x) / edgeMaskPx);
    mask *= clamp(max(ev, 0.0) + max(eh, 0.0), 0.0, 1.0);
  }
  if (mask <= 0.001) { return vec4(0.0); }

  // Blob stack: premultiplied source-over, FIRST blob on top.
  vec4 acc = vec4(0.0);
  float blobCount = uParams2.y;
  for (int i = MAX_BLOBS - 1; i >= 0; i--) {
    if (float(i) < blobCount) {
      vec4 g = uBlobs[i * 2];
      vec4 c = uBlobs[i * 2 + 1];
      vec2 bc = g.zw * uSize;
      float d = length((position - bc) / vec2(max(g.x, 0.001), max(g.y, 0.001)));
      float alpha = c.a * clamp(1.0 - d, 0.0, 1.0);
      if (alpha > 0.0) {
        acc = srcOver(vec4(c.rgb * alpha, alpha), acc);
      }
    }
  }

  // Conic gradient on top (white beam highlight / bloom ring pattern).
  if (uParams2.z > 0.5) {
    float a = bgStopsAlpha(fract(conic - angle));
    vec3 rgb = uParams2.w > 0.5 ? vec3(0.0) : vec3(1.0);
    acc = srcOver(vec4(rgb * a, a), acc);
  }

  // Inner inset shadow approximation.
  float shadowBlur = uParams3.z;
  if (kind > 0.5 && kind < 1.5 && uShadow.a > 0.0 && shadowBlur > 0.0) {
    float depth = -outerSDF;
    float fall = clamp(1.0 - depth / (shadowBlur + 1.0), 0.0, 1.0);
    float a = uShadow.a * fall * fall;
    acc = srcOver(vec4(uShadow.rgb * a, a), acc);
  }

  // CSS filter chain (3x3 matrix on unpremultiplied RGB).
  if (acc.a > 0.0001) {
    vec3 rgb = acc.rgb / acc.a;
    vec3 outRGB = vec3(dot(uCM0.xyz, rgb), dot(uCM1.xyz, rgb), dot(uCM2.xyz, rgb));
    acc.rgb = clamp(outRGB, 0.0, 1.0) * acc.a;
  }

  // CSS clamps `opacity` to [0, 1]; several presets exceed 1.
  float finalA = acc.a * geom * mask * clamp(uParams3.y, 0.0, 1.0);
  if (acc.a > 0.0001) {
    return vec4(acc.rgb / acc.a * finalA, finalA);
  }
  return vec4(0.0);
}

void main() {
  fragColor = shade(FlutterFragCoord().xy);
}
