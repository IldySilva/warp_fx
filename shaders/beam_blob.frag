// Border beam — generic blob layer (the `line` and pulse families).
//
// Port of border-beam-native's BLOB_LAYER_SKSL. A layer is a stack of
// radial-gradient ellipse "blobs" with up-to-4-stop alpha falloffs,
// composited source-over (first blob on top, CSS multiple-background order),
// inside a geometry mask (border ring band / rounded-rect fill / none),
// optionally windowed by a radial ellipse mask (the line family's travelling
// window), then the CSS filter colour matrix.
//
// Blob record: 4 vec4s —
//   [rx, ry, cx, cy] [r, g, b, a0] [p1, a1, p2, a2] [p3, -, -, -]
// Alpha over normalised ellipse distance t is piecewise linear through
// (0, a0) → (p1, a1) → (p2, a2) → (p3, 0), and 0 after.

#include <flutter/runtime_effect.glsl>

#define MAX_BLOBS 16

uniform vec4 uRect;     // element rect: originX, originY, w, h
uniform vec4 uGeom;     // radius, borderWidth, geomKind (0 ring, 1 fill, 2 none), edgeMaskPx
uniform vec4 uRadialA;  // radial window: cx, cy, rx, ry
uniform vec4 uRadialB;  // midPos, midAlpha, enabled, blobCount
uniform vec4 uCM0;      // colour matrix row 0; w = opacity
uniform vec4 uCM1;      // colour matrix row 1
uniform vec4 uCM2;      // colour matrix row 2
uniform vec4 uBlobs[MAX_BLOBS * 4];

out vec4 fragColor;

float roundedRectSDF(vec2 p, vec2 halfSize, float radius) {
  vec2 q = abs(p) - halfSize + radius;
  return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
}

vec4 srcOver(vec4 src, vec4 dst) {
  return src + dst * (1.0 - src.a);
}

float stopAlpha(float t, float a0, float p1, float a1, float p2, float a2, float p3) {
  if (t >= p3) { return 0.0; }
  if (t <= 0.0) { return a0; }
  if (t < p1) { return mix(a0, a1, t / max(p1, 0.0001)); }
  if (t < p2) { return mix(a1, a2, (t - p1) / max(p2 - p1, 0.0001)); }
  return mix(a2, 0.0, (t - p2) / max(p3 - p2, 0.0001));
}

// All the work, in a helper: main() keeps a single exit, which some
// backends need.
vec4 shade(vec2 position) {
  vec2 rectOrigin = uRect.xy;
  vec2 rectSize = uRect.zw;
  vec2 rel = position - (rectOrigin + rectSize * 0.5);
  float radius = uGeom.x;
  float borderWidth = uGeom.y;
  float kind = uGeom.z;
  float edgeMaskPx = uGeom.w;

  // Geometry mask.
  float geom = 1.0;
  if (kind < 1.5) {
    float outerSDF = roundedRectSDF(rel, rectSize * 0.5, radius);
    float outerCov = 1.0 - smoothstep(-1.0, 0.0, outerSDF);
    if (kind > 0.5) {
      geom = outerCov;
    } else {
      float innerRadius = max(radius - borderWidth, 0.0);
      float innerSDF = roundedRectSDF(rel, rectSize * 0.5 - borderWidth, innerRadius);
      float innerCov = 1.0 - smoothstep(-1.0, 0.0, innerSDF);
      geom = outerCov - innerCov;
    }
    if (geom <= 0.0) { return vec4(0.0); }
  }

  float mask = 1.0;

  // Edge fade (rounded-rect fill only): solid at the edges, clear
  // edgeMaskPx inward, vertical and horizontal summed.
  if (kind > 0.5 && kind < 1.5 && edgeMaskPx > 0.0) {
    vec2 lp = position - rectOrigin;
    float ev = max(1.0 - lp.y / edgeMaskPx, 1.0 - (rectSize.y - lp.y) / edgeMaskPx);
    float eh = max(1.0 - lp.x / edgeMaskPx, 1.0 - (rectSize.x - lp.x) / edgeMaskPx);
    mask *= clamp(max(ev, 0.0) + max(eh, 0.0), 0.0, 1.0);
  }

  // Radial window mask (line family): 1 at 0 → midAlpha at midPos → 0 at 1.
  if (uRadialB.z > 0.5) {
    float t = length((position - uRadialA.xy) / vec2(max(uRadialA.z, 0.001), max(uRadialA.w, 0.001)));
    float midPos = uRadialB.x;
    float midAlpha = uRadialB.y;
    float m;
    if (t >= 1.0) {
      m = 0.0;
    } else if (t < midPos) {
      m = mix(1.0, midAlpha, t / max(midPos, 0.0001));
    } else {
      m = mix(midAlpha, 0.0, (t - midPos) / max(1.0 - midPos, 0.0001));
    }
    mask *= m;
  }
  if (mask <= 0.001) { return vec4(0.0); }

  // Blob stack: premultiplied source-over, FIRST blob on top, so it is
  // composited last.
  vec4 acc = vec4(0.0);
  float blobCount = uRadialB.w;
  for (int i = MAX_BLOBS - 1; i >= 0; i--) {
    if (float(i) < blobCount) {
      vec4 g = uBlobs[i * 4];
      vec4 c = uBlobs[i * 4 + 1];
      vec4 s = uBlobs[i * 4 + 2];
      vec4 e = uBlobs[i * 4 + 3];
      float t = length((position - g.zw) / vec2(max(g.x, 0.001), max(g.y, 0.001)));
      float alpha = stopAlpha(t, c.a, s.x, s.y, s.z, s.w, e.x);
      if (alpha > 0.0) {
        acc = srcOver(vec4(c.rgb * alpha, alpha), acc);
      }
    }
  }

  // CSS filter chain (3x3 matrix on unpremultiplied RGB).
  if (acc.a > 0.0001) {
    vec3 rgb = acc.rgb / acc.a;
    vec3 outRGB = vec3(dot(uCM0.xyz, rgb), dot(uCM1.xyz, rgb), dot(uCM2.xyz, rgb));
    acc.rgb = clamp(outRGB, 0.0, 1.0) * acc.a;
  }

  // Clamped as the CSS `opacity` property is.
  float finalA = acc.a * geom * mask * clamp(uCM0.w, 0.0, 1.0);
  if (acc.a > 0.0001) {
    return vec4(acc.rgb / acc.a * finalA, finalA);
  }
  return vec4(0.0);
}

void main() {
  fragColor = shade(FlutterFragCoord().xy);
}
