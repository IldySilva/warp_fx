// Distortion wave — one pass.
//
// A port of distortion-waves (libraries.dev/waves): its WebGL main pass, which
// is the SwiftUI kit's waveLens, waveBlurMask and waveBand in one shader.
//
// Everything the wave does is read from the same signed distance to its front,
// so the swell, the blur and the colour can never drift apart:
//
//   d > 0  the wave has not got here yet
//   d = 0  the front
//   d < 0  the wave has passed
//
// Each view comes in as three pictures: sharp, and two blurred copies. Blur is
// the copies laid over the sharp one, each taking over where the last ends.
// Pictures are premultiplied; so is the output.

#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec2 uSize;
// The front (WaveFront.packed):
// f0: originX, originY, spine, radius
// f1: squash, time, energy, swell
// f2: width, height, gravity, glow
// f3: clearRadius, rim, tilt, ring
// f4: hold, launched, hairClearRadius, unused
uniform vec4 uF0;
uniform vec4 uF1;
uniform vec4 uF2;
uniform vec4 uF3;
uniform vec4 uF4;
// Lens: amplitude, lensWidth, aberration, lens on (0/1)
uniform vec4 uLens;
// Blur: blur, blurAhead, blurBehind, near
uniform vec4 uBlur;
// Views: content shown (0/1), revealed shown (0/1), same view both sides (0/1), continuous corners (0/1)
uniform vec4 uViews;
// Band: lead, tail, strength, palette count
uniform vec4 uBand;
// Rim: rimWidth, rimSoftness, cornerRadius, unevenness
uniform vec4 uRim;
// Hairline: pulse, hairWidth, hairOpacity, hairWhite
uniform vec4 uHair;
// OKLab colours along the front (xyz), up to 8.
uniform vec4 uPal[8];
// The fringe ahead of the front and the one behind it, OKLab.
uniform vec4 uAhead;
uniform vec4 uBehind;
// The lumps along the edges: centre, length, depth.
uniform vec4 uLumps[7];

uniform sampler2D uC0;
uniform sampler2D uC1;
uniform sampler2D uC2;
uniform sampler2D uR0;
uniform sampler2D uR1;
uniform sampler2D uR2;

out vec4 fragColor;

const float coverZone = 60.0;
const float PI = 3.14159265;

float heldAt(vec2 p) {
  float hold = uF4.x;
  if (hold <= 0.0) return 1.0;
  return smoothstep(hold * 0.9, hold * 1.8, length(p - uF0.xy));
}

// The front's field at p. Out: d, the screen normal n, the position q in the
// wave's frame, the raw offset from the origin, and the gradient g.
float fieldAt(vec2 p, out vec2 n, out vec2 q, out vec2 raw, out float g) {
  raw = p - uF0.xy;
  float tilt = uF3.z;
  float cs = cos(tilt), sn = sin(tilt);
  q = vec2(cs * raw.x + sn * raw.y, -sn * raw.x + cs * raw.y);
  float spine = uF0.z, radius = uF0.w, squash = uF1.x, time = uF1.y, swell = uF1.w;

  // A narrower x metric bows the front.
  float mx = q.x * squash;
  vec2 v = vec2(max(abs(mx) - spine, 0.0), q.y);
  float l = max(length(v), 1e-3);
  vec2 grad = vec2(v.x * sign(q.x) * squash, v.y) / l;
  g = max(length(grad), 1e-3);

  // A slow bend along the front, so it never looks drawn with a compass.
  float bend;
  if (uF3.w > 0.5) {
    float a = atan(q.y, q.x);
    bend = 0.62 * sin(2.0 * a + time * 1.1) + 0.38 * sin(3.0 * a - time * 1.5 + 1.7);
  } else {
    float s = mx * 0.0058;
    bend = 0.62 * sin(s + time * 1.1) + 0.38 * sin(s * 2.1 - time * 1.5 + 1.7);
  }
  vec2 nn = grad / g;
  n = vec2(cs * nn.x - sn * nn.y, sn * nn.x + cs * nn.y);
  return (l - radius) / g + swell * bend;
}

vec4 contentAt(vec2 s, float tn, float tf) {
  vec2 uv = clamp(s, vec2(0.5), uSize - 0.5) / uSize;
  vec4 col = texture(uC0, uv);
  if (tn > 0.0) col = mix(col, texture(uC1, uv), tn);
  if (tf > 0.0) col = mix(col, texture(uC2, uv), tf);
  return col;
}

vec4 revealedAt(vec2 s, float tn, float tf) {
  vec2 uv = clamp(s, vec2(0.5), uSize - 0.5) / uSize;
  vec4 col = texture(uR0, uv);
  if (tn > 0.0) col = mix(col, texture(uR1, uv), tn);
  if (tf > 0.0) col = mix(col, texture(uR2, uv), tf);
  return col;
}

// How much each sample, from the red end to the blue end, gives to each channel.
vec3 spectrum(int i) {
  if (i == 0) return vec3(0.571, 0.0, 0.0);
  if (i == 1) return vec3(0.343, 0.206, 0.0);
  if (i == 2) return vec3(0.086, 0.588, 0.086);
  if (i == 3) return vec3(0.0, 0.206, 0.343);
  return vec3(0.0, 0.0, 0.571);
}

// One view through the swell: the colours part along the way a pixel has been
// moved, in proportion to how far, so only what is distorted splits.
vec4 lensed(float revealed, vec2 s, vec2 split, float tn, float tf) {
  if (dot(split, split) < 0.0625) {
    return revealed > 0.5 ? revealedAt(s, tn, tf) : contentAt(s, tn, tf);
  }
  vec4 o = vec4(0.0);
  for (int i = 0; i < 5; i++) {
    float along = float(i) / 4.0 * 2.0 - 1.0;
    vec2 at = s + split * along;
    vec4 c = revealed > 0.5 ? revealedAt(at, tn, tf) : contentAt(at, tn, tf);
    o += vec4(c.rgb * spectrum(i), c.a * 0.2);
  }
  return o;
}

// Signed distance to a rect with continuous (squircle-like) corners, as an
// iPhone's screen has.
float continuousRectSDF(vec2 p, vec2 halfSize, float radius) {
  float a = min(radius * 1.528665, min(halfSize.x, halfSize.y));
  vec2 q = abs(p) - (halfSize - a);
  if (q.x <= 0.0 || q.y <= 0.0) return max(abs(p.x) - halfSize.x, abs(p.y) - halfSize.y);
  float n = 3.26;
  vec2 u = q / a;
  float norm = pow(pow(u.x, n) + pow(u.y, n), 1.0 / n);
  vec2 gg = pow(u / max(norm, 1e-4), vec2(n - 1.0));
  return (norm - 1.0) * a / max(length(gg), 1e-3);
}

float edgeSDF(vec2 p, vec2 halfSize, float radius) {
  if (uViews.w > 0.5) return continuousRectSDF(p, halfSize, radius);
  float r = min(radius, min(halfSize.x, halfSize.y));
  vec2 q = abs(p) - (halfSize - r);
  return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

// Where a point is along the rounded-rect edge: clockwise from the top centre.
// .y is the whole perimeter.
vec2 perimeterAt(vec2 p, vec2 halfSize, float r) {
  float ex = max(halfSize.x - r, 0.0);
  float ey = max(halfSize.y - r, 0.0);
  float arc = 0.5 * PI * r;
  float P = 4.0 * (ex + ey + arc);
  float ax = abs(p.x), ay = abs(p.y);
  if (ax > ex && ay > ey) {
    vec2 v = p - vec2(sign(p.x) * ex, sign(p.y) * ey);
    float a;
    float base;
    if (p.x >= 0.0 && p.y < 0.0) { a = atan(v.x, -v.y); base = ex; }
    else if (p.x >= 0.0) { a = atan(v.y, v.x); base = ex + arc + 2.0 * ey; }
    else if (p.y >= 0.0) { a = atan(-v.x, v.y); base = 3.0 * ex + 2.0 * arc + 2.0 * ey; }
    else { a = atan(-v.y, -v.x); base = 3.0 * ex + 3.0 * arc + 4.0 * ey; }
    return vec2(base + r * clamp(a, 0.0, 0.5 * PI), P);
  }
  bool sideHit = ax > ex ? true : (ay > ey ? false : (halfSize.x - ax) < (halfSize.y - ay));
  if (sideHit) return vec2(p.x >= 0.0 ? ex + arc + (p.y + ey) : 3.0 * ex + 3.0 * arc + 2.0 * ey + (ey - p.y), P);
  return vec2(p.y < 0.0 ? (p.x >= 0.0 ? p.x : P + p.x) : ex + 2.0 * arc + 2.0 * ey + (ex - p.x), P);
}

// How thick the colour on the edges is at s along the perimeter, as a share of
// rimWidth: lumps of their own length and depth, thin stretches between.
float rimThickness(float s, float P) {
  float t = 0.08;
  for (int i = 0; i < 7; i++) {
    vec4 lump = uLumps[i];
    float ds = s - lump.x;
    ds -= P * floor(ds / P + 0.5);
    float k = ds / lump.y;
    t += lump.z * exp(-k * k);
  }
  return t / 1.0498;
}

float dither(vec2 p) {
  return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715)))) - 0.5;
}

// One colour from the ring of palette colours, mixed so neighbours never pass
// through grey. Constant-index loop: SkSL allows no other array reads.
vec3 paletteAt(float u) {
  float count = uBand.w;
  float x = fract(u) * count;
  float fi = min(floor(x), count - 1.0);
  float fj = fi + 1.0 >= count ? 0.0 : fi + 1.0;
  float m = fract(x);
  m = m * m * (3.0 - 2.0 * m);
  vec3 a = uPal[0].xyz;
  vec3 b = uPal[0].xyz;
  for (int k = 0; k < 8; k++) {
    float fk = float(k);
    if (fk == fi) a = uPal[k].xyz;
    if (fk == fj) b = uPal[k].xyz;
  }
  return mix(a, b, m);
}

vec3 oklabToSRGB(vec3 c) {
  float l = c.x + 0.3963377774 * c.y + 0.2158037573 * c.z;
  float m = c.x - 0.1055613458 * c.y - 0.0638541728 * c.z;
  float s = c.x - 0.0894841775 * c.y - 1.2914855480 * c.z;
  l = l * l * l; m = m * m * m; s = s * s * s;
  vec3 lin = clamp(vec3(
    4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
    -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
    -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
  ), 0.0, 1.0);
  return mix(12.92 * lin, 1.055 * pow(lin, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), lin));
}

float sq(float x) { return x * x; }

// The colour over the views: a band riding the front, a rim it leaves on the
// edges and a hairline on them. Premultiplied.
vec4 colourOver(vec4 col, vec2 p, float d, vec2 q, float g, float held) {
  // ─── The colour: a band riding the front, a rim it leaves on the edges ───
  float time = uF1.y, glow = uF2.w, rim = uF3.y;
  float rimWidth = uRim.x, rimSoftness = uRim.y, corner = uRim.z, uneven = uRim.w;
  float pulse = uHair.x, hairW = uHair.y, hairO = uHair.z, hairWhite = uHair.w;
  float lead = uBand.x, tail = uBand.y, strength = uBand.z;
  vec2 c = p - uSize * 0.5;
  float inset = max(-edgeSDF(c, uSize * 0.5, corner), 0.0);
  bool nearEdge = rim > 0.0 && inset < max(rimWidth * 2.2 * (1.0 + 1.9 * uneven), hairW * 0.5 + 0.75);
  if (glow <= 0.0 && !nearEdge) {
    return col;
  }
  bool ring = uF3.w > 0.5;
  float turn = atan(q.y, q.x);
  float along = q.x * 0.0068;
  float lobes = ring
    ? 0.5 + 0.5 * sin(2.0 * turn + time * 1.4) * cos(turn - time * 0.7 + 1.2)
    : 0.5 + 0.5 * sin(along * 1.3 + time * 1.4) * cos(along * 0.6 - time * 0.7 + 1.2);
  float bandA = 0.0;
  if (glow > 0.0 && d < lead) {
    if (d >= 0.0) {
      float k = 1.0 - d / lead;
      bandA = k * k * k * (k * (k * 6.0 - 15.0) + 10.0);
    } else {
      bandA = pow(1.0 - clamp(-d / (tail * mix(0.6, 1.3, lobes)), 0.0, 1.0), 2.3);
    }
    bandA *= glow * strength * mix(0.6, 1.0, exp(-inset / 140.0)) * held;
  }
  float aroundA = atan(c.y / uSize.y, c.x / uSize.x);
  float rimA = 0.0;
  float hairA = 0.0;
  float shimmer = 0.5;
  if (nearEdge) {
    vec2 edge = perimeterAt(c, uSize * 0.5, corner);
    float thickness = 1.0;
    if (uneven > 0.0) thickness = max(1.0 + (rimThickness(edge.x, edge.y) - 1.0) * uneven, 0.04);
    float hug = exp(-sq(inset / (rimWidth * thickness)));
    float reached = 1.0 - smoothstep(-lead * 0.7, lead * 0.5, d);
    float kept = smoothstep(-rimSoftness, rimSoftness, d + (uF0.w - uF3.x) / g);
    shimmer = 0.5 + 0.5 * sin(time * 3.4 - edge.x / edge.y * 4.0 * PI);
    rimA = hug * reached * kept * rim * mix(1.0, 0.7 + 0.3 * shimmer, pulse);
    if (hairW > 0.0) {
      float line = 1.0 - smoothstep(hairW * 0.5, hairW * 0.5 + 0.75, inset);
      float hairKept = smoothstep(-rimSoftness, rimSoftness, d + (uF0.w - uF4.z) / g);
      hairA = line * reached * hairKept * rim * hairO
        * mix(0.5, 1.0, smoothstep(0.1, 1.5, thickness))
        * mix(1.0, 0.55 + 0.45 * shimmer, pulse);
    }
  }
  float a = 1.0 - (1.0 - bandA) * (1.0 - rimA);
  float total = 1.0 - (1.0 - a) * (1.0 - hairA);
  if (total <= 0.0005) {
    return col;
  }
  float flow = 0.62 + (ring ? turn / (2.0 * PI) : along * 0.2) + time * 0.13 + d * 0.0015
    + (ring ? 0.0 : 0.05 * sin(q.y * 0.009 + time));
  vec3 lab = paletteAt(flow);
  lab = mix(lab, uAhead.xyz, 0.5 * exp(-sq((d - 30.0) / 50.0)));
  lab = mix(lab, uBehind.xyz, 0.5 * exp(-sq((d + 84.0) / 72.0)));
  lab.yz *= 1.22;
  lab = mix(lab, vec3(0.99, 0.0, 0.0), 0.7 * exp(-sq((d + 8.0) / 26.0)));
  vec3 rimLab = paletteAt(aroundA / (2.0 * PI) + time * (0.12 + 0.25 * pulse) + inset * 0.0012);
  rimLab.yz *= 1.1;
  lab = mix(lab, rimLab, rimA / (rimA + bandA + 1e-4));
  vec3 rgb = oklabToSRGB(lab);
  if (hairA > 0.0) {
    vec3 hair = mix(oklabToSRGB(rimLab), vec3(1.0), hairWhite * (0.5 + 0.5 * shimmer));
    rgb = (rgb * a * (1.0 - hairA) + hair * hairA) / total;
  }
  float noise = dither(p) * 2.0 / 255.0;
  float over = clamp(total + noise, 0.0, 1.0);
  // The colour over the views, premultiplied.
  return vec4(col.rgb * (1.0 - over) + clamp(rgb + noise, 0.0, 1.0) * over, 1.0 - (1.0 - col.a) * (1.0 - over));
}

void main() {
  vec2 p = FlutterFragCoord().xy;

  vec2 n;
  vec2 q;
  vec2 raw;
  float g;
  float d = fieldAt(p, n, q, raw, g);
  float energy = uF1.z, gravity = uF2.z;
  float held = heldAt(p);

  // ─── The two views, through the swell ───
  vec2 s = p;
  vec2 split = vec2(0.0);
  if (uLens.w > 0.5) {
    float u = d / (uLens.y * (d > 0.0 ? 0.85 : 1.5));
    float lift = exp(-u * u);
    float r = max(length(raw), 1.0);
    vec2 swollen = n * energy * uLens.x * lift * held;
    vec2 inward = raw / r;
    s = p - swollen + inward * gravity * exp(-r / 900.0) * held;
    split = (swollen - inward * gravity * exp(-r / 240.0) * held) * uLens.z;
  }
  // The progressive blur: gathers ahead of the front, peaks on it, clears behind.
  float bu = d / (d > 0.0 ? uBlur.y : uBlur.z);
  float radius = energy * uBlur.x * exp(-bu * bu) * held;
  float tn = clamp(radius / max(uBlur.w, 1e-3), 0.0, 1.0);
  tn = tn * tn * (3.0 - 2.0 * tn);
  float tf = clamp((radius - uBlur.w) / max(uBlur.x - uBlur.w, 1e-3), 0.0, 1.0);
  tf = tf * tf * (3.0 - 2.0 * tf);

  // Ahead of the cover zone the outgoing view covers the incoming one.
  float cover = 1.0;
  if (uViews.x > 0.5 && uF4.y > 0.5) cover = smoothstep(-coverZone, coverZone, d);
  if (uViews.x < 0.5) cover = 0.0;

  vec4 col = vec4(0.0);
  if (uViews.z > 0.5) {
    col = lensed(0.0, s, split, tn, tf);
  } else {
    if (uViews.y > 0.5 && d <= coverZone + 6.0 && cover < 1.0) col = lensed(1.0, s, split, tn, tf);
    if (cover > 0.0) col = mix(col, lensed(0.0, s, split, tn, tf), cover);
  }

  fragColor = colourOver(col, p, d, q, g, held);
}
