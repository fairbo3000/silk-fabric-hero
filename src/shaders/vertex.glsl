// ============================================================
//  VERTEX SHADER — Silk Fabric Hero
//  Sheer silk hanging panel — gentle wind sway, scroll-driven
//  UV offset, velocity-based stretch, mouse wind bias.
//
//  Target: Three.js ShaderMaterial
//  Mesh:   PlaneGeometry, high density (128×256 segments)
//          scaled to 3× the viewport height
// ============================================================

// ── Uniforms ────────────────────────────────────────────────
uniform float uTime;            // elapsed seconds
uniform float uScrollVelocity;  // signed scroll speed, -1..1
uniform float uScrollPosition;  // normalised scroll, 0..1
uniform float uMouseX;          // normalised horizontal mouse, -1..1
uniform vec2  uResolution;      // viewport dimensions (px)

// ── Varyings ────────────────────────────────────────────────
varying vec2  vUv;              // scrolled UV for fragment
varying vec3  vNormal;          // world-space normal for lighting
varying float vSway;            // sway magnitude (for shimmer in frag)

// ── Constants ───────────────────────────────────────────────
// Max X-displacement — near zero, fabric hangs straight
const float MAX_SWAY  = 0.012;

// Max vertical stretch factor (as a fraction)
const float MAX_STRETCH = 0.06;


// ── Utility: smooth hash (for micro-variation) ───────────────
float hash(float n) {
    return fract(sin(n) * 43758.5453123);
}

void main() {

    // ── 1. Amplitude falloff from top to bottom ──────────────
    //
    // The fabric is hung from the top. Physics dictates that the
    // upper portion swings more freely. We map this with a smooth
    // falloff: uv.y = 0 is the top, 1 is the bottom.
    //
    // amplitudeFactor: 1.0 at top, 0.0 at bottom, using a smooth
    // curve so the lower quarter is almost perfectly still.
    float t = uv.y;                               // 0 = top, 1 = bottom
    float amplitudeFactor = pow(1.0 - t, 1.4);   // gentle curve

    // ── 2. Mouse wind bias ───────────────────────────────────
    //
    // uMouseX (-1..1) subtly shifts the mean rest position of the
    // fabric, as if the viewer's presence disturbs the air.
    // We apply a fraction so the effect is barely perceptible.
    float mouseBias = uMouseX * 0.006;            // very subtle tilt only

    // ── 3. Multi-frequency wind sway (X + Z) ────────────────
    //
    // Three overlapping sine waves with incommensurable frequencies
    // produce an organic, non-repeating drift. Amplitudes are
    // weighted so no single wave dominates.
    //
    // Wave 1 — slow, primary body sway
    float wave1 = sin(uTime * 0.45 + uv.y * 2.8)
                * 0.500;

    // Wave 2 — mid-frequency ripple
    float wave2 = sin(uTime * 0.92 + uv.y * 5.2 + 1.57)
                * 0.350;

    // Wave 3 — faster surface ripple across grain
    float wave3 = sin(uTime * 1.7 + uv.y * 9.1 + uv.x * 5.5)
                * 0.250;

    // Wave 4 — high-freq flutter, subtle cross-ripple
    float wave4 = sin(uTime * 2.3 + uv.x * 7.0 + uv.y * 4.2)
                * 0.150;

    // Sum, normalise to -1..1 range (theoretical max ~1.25),
    // then scale to MAX_SWAY units, modulate by height falloff.
    float swaySum = (wave1 + wave2 + wave3 + wave4) * 0.8; // approx -1..1
    float swayX   = (swaySum * MAX_SWAY + mouseBias) * amplitudeFactor;

    // Z displacement — a second independent trio for depth shiver.
    // Much smaller: just enough to catch the light differently.
    // Z ripples are the main deformation — tight waves across the surface
    float waveZ1  = sin(uTime * 0.4  + uv.y * 5.0 + 0.9)           * 0.40;
    float waveZ2  = sin(uTime * 0.85 + uv.y * 9.5 + 2.1)           * 0.30;
    float waveZ3  = sin(uTime * 1.4  + uv.x * 6.0 + uv.y * 4.0)   * 0.20;
    float waveZ4  = sin(uTime * 2.2  + uv.x * 10.0 + uv.y * 7.0)  * 0.10;
    // Mouse adds a travelling ripple across the surface
    float waveZMouse = sin(uTime * 1.0 + uv.x * 8.0 + uMouseX * 5.0) * 0.18;
    float swayZ   = (waveZ1 + waveZ2 + waveZ3 + waveZ4 + waveZMouse)
                  * 0.045                          // deeper Z deformation
                  * amplitudeFactor;

    // ── 4. Scroll-driven vertical stretch (inertia) ──────────
    //
    // At high |uScrollVelocity|, the fabric momentarily elongates
    // along Y (like a flag snapping in wind). The center of the
    // mesh is the pivot. We interpolate gently with smoothstep.
    //
    // velocity comes in as a -1..1 value; we use |v| for magnitude.
    float velMag      = abs(uScrollVelocity);
    float stretchAmt  = smoothstep(0.0, 1.0, velMag) * MAX_STRETCH;

    // Pivot at the vertical centre of the geometry (assume Y range
    // is symmetric around 0 in local space).
    float centredY    = position.y;               // pivot already at 0
    float stretchedY  = centredY * (1.0 + stretchAmt);

    // ── 5. Final displaced position ──────────────────────────
    vec3 displaced = vec3(
        position.x + swayX,
        stretchedY,
        position.z + swayZ
    );

    // ── 6. UV pass-through ───────────────────────────────────
    //
    // Scroll is handled by moving mesh.position.y in JS — the
    // whole fabric lifts as a physical object. UVs are fixed to
    // the mesh so the weave deformation travels with the geometry.
    vUv = uv;

    // ── 7. Varyings ──────────────────────────────────────────
    //
    // Pass a perturbed normal to the fragment for lighting calcs.
    // We approximate the surface normal from the sway gradient.
    // dSwayX/dy is roughly the partial derivative we need.
    float dSwayDy = cos(uTime * 0.31 + uv.y * 2.1) * 0.31 * 2.1 * 0.500
                  + cos(uTime * 0.67 + uv.y * 3.7 + 1.57) * 0.67 * 3.7 * 0.300
                  + cos(uTime * 1.13 + uv.y * 6.3 + uv.x * 4.1) * 1.13 * 6.3 * 0.200;
    dSwayDy *= MAX_SWAY * amplitudeFactor;

    // Perturbed normal: tilt in X based on the slope of the wave.
    vec3 perturbedNormal = normalize(vec3(-dSwayDy, 1.0, -swayZ * 5.0));
    vNormal = normalMatrix * perturbedNormal;

    // sway magnitude for specular shimmer in the fragment shader
    vSway = abs(swayX) / MAX_SWAY;               // 0..1

    // ── 8. Output ────────────────────────────────────────────
    gl_Position = projectionMatrix * modelViewMatrix * vec4(displaced, 1.0);
}
