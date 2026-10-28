// Adapted from Aurora by tornikegomareli (MIT, upstream README).
// Upstream a3f9296a1e7744529b69d8a9f9e360bf3c8c81bf / AuroraGlow.metal.
// Metal -> Flutter GLSL: constant anchor lookup functions for Skia compatibility;
// standard thicknessGrow intro; transparent, premultiplied output; no screen wash.
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform float uTime;
uniform float uSpeed;
uniform float uBorder;
uniform float uGlow;
uniform float uIntensity;
uniform float uPalette;
uniform float uStyle;
out vec4 fragColor;
vec3 anchorColorAt(int i, vec3 a, vec3 b, vec3 c, vec3 d) {
  if (i == 0)  return a;
  if (i == 1)  return b;
  if (i == 2)  return c;
  if (i == 3)  return d;
  if (i == 4)  return c;
  if (i == 5)  return a;
  if (i == 6)  return b;
  if (i == 7)  return d;
  if (i == 8)  return b;
  if (i == 9)  return c;
  return a;
}

vec2 anchorFreq(int i) {
  if (i == 0) return vec2(0.31, 0.27);
  if (i == 1) return vec2(0.43, 0.19);
  if (i == 2) return vec2(0.17, 0.37);
  if (i == 3) return vec2(0.29, 0.23);
  if (i == 4) return vec2(0.41, 0.31);
  if (i == 5) return vec2(0.19, 0.43);
  if (i == 6) return vec2(0.37, 0.17);
  if (i == 7) return vec2(0.23, 0.29);
  if (i == 8) return vec2(0.31, 0.41);
  if (i == 9) return vec2(0.27, 0.19);
  return vec2(0.43, 0.37);
}

vec2 anchorPhase(int i) {
  if (i == 0) return vec2(0.0, 1.7);
  if (i == 1) return vec2(1.3, 0.4);
  if (i == 2) return vec2(2.1, 2.6);
  if (i == 3) return vec2(0.7, 1.1);
  if (i == 4) return vec2(2.8, 0.2);
  if (i == 5) return vec2(1.8, 2.3);
  if (i == 6) return vec2(0.3, 1.5);
  if (i == 7) return vec2(2.5, 0.8);
  if (i == 8) return vec2(1.2, 2.0);
  if (i == 9) return vec2(0.5, 1.9);
  return vec2(2.7, 0.6);
}

const float kBurstDuration = 3.5;

float burstAmplitude(float t, float ampBoost, float decay) {
  if (t < 0.0 || t >= kBurstDuration) return 1.0;
  float d = exp(-t * decay);
  float wave = cos(t * 6.28318 * 1.3);
  return 1.0 + ampBoost * d * wave;
}

float burstSpeed(float t, float speedBoost, float decay) {
  if (t < 0.0 || t >= kBurstDuration) return 1.0;
  return 1.0 + speedBoost * exp(-t * (decay + 0.2));
}

float burstBrightness(float t, float pop, float decay) {
  if (t < 0.0 || t >= kBurstDuration) return 1.0;
  return 1.0 + pop * exp(-t * (decay + 1.4));
}

/// Flame overlay amplitude during burst. Always >= waveBaseline so flames
/// exist in steady state at a low level too.
float burstFlameAmp(float t, float ampBoost, float baseline, float decay) {
  if (t < 0.0 || t >= kBurstDuration) return baseline;
  return baseline + ampBoost * exp(-t * decay);
}

float burstNoiseSpeed(float t, float decay) {
  if (t < 0.0 || t >= kBurstDuration) return 1.0;
  return 1.0 + 3.0 * exp(-t * (decay + 0.1));
}

// Intro envelope (thicknessGrow style): scales the band from invisible
// to full thickness with a tiny overshoot before settling. `duration`
// is the wall time the animation takes. `t < 0` (intro not playing)
// or `t >= duration` (intro finished) return 1.0 so the band renders
// at full size.
float introScale(float t, float duration) {
  if (t < 0.0 || t >= duration) return 1.0;
  float p = t / duration;
  float ease = 1.0 - pow(1.0 - p, 3.0);
  float bump = 0.08 * sin(p * 3.14159);
  return ease * (1.0 + bump);
}

// Heartbeat envelope: base growth with damped oscillations on top, so
// the band visibly pulses 2–3 times before settling. The exponential
// decay term reduces the amplitude of each successive pulse.
float introScaleHeartbeat(float t, float duration) {
  if (t < 0.0 || t >= duration) return 1.0;
  float p = t / duration;
  float base = 1.0 - pow(1.0 - p, 2.0);
  float pulses = 0.35 * exp(-p * 3.5) * cos(p * 6.28318 * 2.8);
  return clamp(base + pulses, 0.0, 1.5);
}

// Intro envelope (borderFill style): mask that "fills" the perimeter
// from the direction's start edge, sweeping around both ways and
// meeting itself at the opposite side. Uses the angle from the
// rectangle's centre as a proxy for the perimeter position — a fair
// approximation for rounded rects without measuring true arc length.
//   t            — elapsed time since intro started
//   duration     — total intro time
//   startPerimT  — where on the perimeter the fill originates (0..1)
float borderFillMask(
  vec2 position, vec2 size, float startPerimT, float t, float duration
) {
  if (t < 0.0 || t >= duration) return 1.0;

  vec2 p = position - size * 0.5;
  float angle = atan(p.y, p.x);                 // -pi..pi
  float perimT = (angle + 3.14159) * 0.15915494;  // /(2*pi) → 0..1

  // Distance around the loop from the start position (both ways);
  // *2 normalises to 0..1.
  float dist = abs(perimT - startPerimT);
  dist = min(dist, 1.0 - dist) * 2.0;

  float normT = t / duration;
  float softness = 0.08;
  return 1.0 - smoothstep(normT - softness, normT + softness, dist);
}

// Convert a direction vector to its origin's perimeter position. The
// direction points where the wave travels TO, so the perimeter start
// is in the *opposite* direction from the centre.
float perimeterStartFromDirection(vec2 dir) {
  return (atan(-dir.y, -dir.x) + 3.14159) * 0.15915494;
}

// Intro wash: a fast semi-transparent pulse that *travels outward*
// from the centre of the frame. Each pixel sees its own short sine
// pulse, delayed by its normalised distance from centre, so the
// effect reads as a wave sweeping across the screen. All three
// parameters are passed in as a uniform so callers can tune the
// feel without recompiling:
//   sweepDuration — seconds for the wave front to reach the corners
//   pulseWidth    — seconds each pixel stays lit as the wave passes
//   peak          — maximum alpha contribution at pulse peak (0..1)
// Linear directional wash: a single travelling wavefront perpendicular
// to `direction` that crosses the rectangle once. Each pixel sees a
// brief sine pulse as the front passes through it. Direction (-1, 0)
// is right-to-left, (0, -1) is bottom-to-top, etc.
//   sweepDuration — seconds for the front to cross the rectangle
//   pulseWidth    — seconds each pixel stays lit as the front passes
//   peak          — max alpha at pulse centre
float introWashAlpha(
  float t, vec2 position, vec2 size, vec2 direction,
  float sweepDuration, float pulseWidth, float peak
) {
  if (t < 0.0 || peak <= 0.0) return 0.0;

  float proj = dot(position, direction);
  float minProj = min(0.0, size.x * direction.x) + min(0.0, size.y * direction.y);
  float maxProj = max(0.0, size.x * direction.x) + max(0.0, size.y * direction.y);
  float range = max(maxProj - minProj, 1.0);

  float normT = (proj - minProj) / range;
  float arrival = normT * sweepDuration;
  float localT  = t - arrival;
  if (localT < 0.0 || localT > pulseWidth) return 0.0;

  float u = localT / pulseWidth;
  return peak * sin(u * 3.14159);
}

/// 3D gradient noise + FBM, computed procedurally
vec3 hash33(vec3 p) {
  p = vec3(
             dot(p, vec3(127.1, 311.7,  74.7)),
             dot(p, vec3(269.5, 183.3, 246.1)),
             dot(p, vec3(113.5, 271.9, 124.6))
             );
  return -1.0 + 2.0 * fract(sin(p) * 43758.5453123);
}

float gradientNoise3D(vec3 p) {
  vec3 i = floor(p);
  vec3 f = fract(p);
  vec3 u = f * f * (3.0 - 2.0 * f);
  
  return mix(
             mix(
                 mix(dot(hash33(i + vec3(0,0,0)), f - vec3(0,0,0)),
                     dot(hash33(i + vec3(1,0,0)), f - vec3(1,0,0)), u.x),
                 mix(dot(hash33(i + vec3(0,1,0)), f - vec3(0,1,0)),
                     dot(hash33(i + vec3(1,1,0)), f - vec3(1,1,0)), u.x),
                 u.y),
             mix(
                 mix(dot(hash33(i + vec3(0,0,1)), f - vec3(0,0,1)),
                     dot(hash33(i + vec3(1,0,1)), f - vec3(1,0,1)), u.x),
                 mix(dot(hash33(i + vec3(0,1,1)), f - vec3(0,1,1)),
                     dot(hash33(i + vec3(1,1,1)), f - vec3(1,1,1)), u.x),
                 u.y),
             u.z);
}

float fbm3D(vec3 p) {
  float v = 0.0;
  float a = 0.6;
  v += a * gradientNoise3D(p);
  p *= 2.1;
  a *= 0.55;
  v += a * gradientNoise3D(p);
  return v;
}

float roundedRectSDF(vec2 p, vec2 floatSize, float cornerRadius) {
  vec2 q = abs(p) - floatSize + cornerRadius;
  return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - cornerRadius;
}

vec2 anchorPosition(
                             int i, float time, float burstT,
                             float ampBoost, float speedBoost, float decay,
                             vec2 size
                             ) {
  float ampScale   = burstAmplitude(burstT, ampBoost, decay);
  float speedScale = burstSpeed(burstT, speedBoost, decay);
  
  vec2 phase = anchorPhase(i);
  vec2 freq  = anchorFreq(i);
  
  float extra = (burstT >= 0.0 && burstT < kBurstDuration)
  ? (1.0 - exp(-burstT * (decay + 0.2))) * 6.28
  : 0.0;
  
  float t = time * speedScale + extra;
  float amp = clamp(0.42 * ampScale, 0.0, 0.48);
  
  vec2 norm = vec2(
                       0.5 + amp * sin(t * freq.x + phase.x),
                       0.5 + amp * cos(t * freq.y + phase.y)
                       );
  return norm * size;
}

vec3 intelligenceLightColor(
                                    vec2 xyPos, vec2 size,
                                    float time, float burstT,
                                    float ampBoost, float speedBoost, float decay,
                                    float reach, float power,
                                    vec3 paletteBase,
                                    vec3 paletteA, vec3 paletteB,
                                    vec3 paletteC, vec3 paletteD
                                    ) {
  vec3 color = paletteBase;
  for (int i = 0; i < 11; ++i) {
    vec2 a = anchorPosition(i, time, burstT, ampBoost, speedBoost, decay, size);
    float d = length(a - xyPos) / reach;
    float fall = clamp(1.0 - d, 0.0, 1.0);
    float t = fall * fall * (3.0 - 2.0 * fall);
    color = mix(color, anchorColorAt(i, paletteA, paletteB, paletteC, paletteD), float(t));
  }
  color = min(color, vec3(1.0));
  
  float  luma = dot(color, vec3(0.213, 0.716, 0.072));
  float  satFactor = float(1.0 + power * 0.2);
  color = mix(vec3(luma), color, satFactor);
  
  return color;
}


void main() {
  vec2 position = FlutterFragCoord().xy;
  vec2 center = uSize * 0.5;
  float decay = uStyle < 0.5 ? 1.4 : (uStyle > 1.5 ? 1.5 : 1.6);
  float ampBoost = uStyle < 0.5 ? 0.22 : (uStyle > 1.5 ? 0.55 : 0.38);
  float speedBoost = uStyle < 0.5 ? 1.4 : (uStyle > 1.5 ? 3.5 : 2.2);
  float flameBoost = uStyle < 0.5 ? 1.2 : (uStyle > 1.5 ? 4.0 : 2.0);
  float baseline = uStyle < 0.5 ? 0.30 : (uStyle > 1.5 ? 0.55 : 0.45);
  float intro = introScale(uTime, 0.45);
  float glow = max(0.01, uGlow * intro);
  float border = uBorder * intro;
  vec2 uv = position / max(uSize.x, uSize.y);
  float scroll = 0.30 * burstNoiseSpeed(uTime, decay);
  float wave = fbm3D(vec3(uv * 2.0, uTime * scroll)) * 0.7
    + gradientNoise3D(vec3(uv * 3.6 + vec2(11.7, 5.3), uTime * scroll * 0.55)) * 0.35;
  float clean = roundedRectSDF(position - center, center - vec2(1.5), 28.0);
  float warped = clean + wave * glow * burstFlameAmp(uTime, flameBoost, baseline, decay);
  float distance = min(abs(clean), abs(warped));
  float core = 1.0 - smoothstep(max(0.0, border - 1.0), border + 1.0, distance);
  float mid = (1.0 - smoothstep(0.0, glow * 0.6, distance)) * 0.55;
  float wide = (1.0 - smoothstep(0.0, glow * 1.4, distance)) * 0.30;
  float alpha = clamp((core + mid + wide) * (0.88 + 0.18 * (wave * 0.5 + 0.5)) * uIntensity, 0.0, 0.92);
  vec3 base = vec3(0.000, 0.588, 1.000);
  vec3 a = vec3(0.983, 0.392, 1.000), b = vec3(1.000, 0.145, 0.333);
  vec3 c = vec3(1.000, 0.577, 0.000), d = vec3(0.000, 0.588, 1.000);
  if (uPalette > 0.5 && uPalette < 1.5) {
    base = vec3(0.10, 0.40, 0.60); a = vec3(0.20, 0.80, 0.90); b = vec3(0.30, 0.90, 0.85); c = vec3(0.15, 0.50, 0.85); d = vec3(0.20, 0.75, 0.70);
  } else if (uPalette > 1.5) {
    base = vec3(0.95, 0.55, 0.25); a = vec3(1.0, 0.45, 0.15); b = vec3(0.95, 0.25, 0.35); c = vec3(0.85, 0.20, 0.55); d = vec3(1.0, 0.70, 0.30);
  }
  vec3 lit = intelligenceLightColor(position, uSize, uTime * uSpeed, uTime,
    ampBoost, speedBoost, decay, 0.55 * max(uSize.x, uSize.y), 0.0, base, a, b, c, d);
  lit = clamp(lit * 0.95 * burstBrightness(uTime, 0.32, decay), 0.0, 1.0);
  fragColor = vec4(lit * alpha, alpha);
}
