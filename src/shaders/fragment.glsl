// ============================================================
//  FRAGMENT SHADER — Silk Fabric Hero
//  Sheer silk hanging panel — creamy base, woven twill texture,
//  specular shimmer, Fresnel edge luminance, subtle translucency.
//
//  Aesthetic reference: Hermès La Maison des Carrés,
//                       Loewe editorial, European high fashion.
//
//  Target: Three.js ShaderMaterial (transparent: true)
// ============================================================

// ── Precision ────────────────────────────────────────────────
precision highp float;

// ── Uniforms ─────────────────────────────────────────────────
uniform float uTime;           // elapsed seconds
uniform float uMouseX;         // normalised horizontal mouse, -1..1
uniform float uWeaveScale;     // weave density (default 200.0)

// ── Varyings from vertex shader ──────────────────────────────
varying vec2  vUv;             // scrolled UV coordinates
varying vec3  vNormal;         // world-space perturbed normal
varying float vSway;           // sway magnitude 0..1

// ── Colour constants ─────────────────────────────────────────

// Base silk — creamy, warm, ever so slightly ivory.
// #F5F0E8 → rgb(245, 240, 232) → vec3(0.961, 0.941, 0.910)
const vec3  SILK_BASE   = vec3(0.961, 0.941, 0.910);

// Highlight tint — slightly cooler, used for the sheer lifted areas
const vec3  SILK_LIGHT  = vec3(0.985, 0.980, 0.975);

// Specular hot spot — barely warm white
const vec3  SPEC_COLOR  = vec3(1.000, 0.998, 0.993);

// Shadow tint for weave valleys — ever so slightly darker/warmer
const vec3  WEAVE_DARK  = vec3(0.930, 0.910, 0.880);

// ── Utility functions ────────────────────────────────────────

// Remap x from [inLo,inHi] to [outLo,outHi], clamped.
float remap(float x, float inLo, float inHi, float outLo, float outHi) {
    return outLo + (outHi - outLo) * clamp((x - inLo) / (inHi - inLo), 0.0, 1.0);
}

// Smooth absolute value — avoids hard crease at x=0.
float smoothAbs(float x, float k) {
    return sqrt(x * x + k * k) - k;
}

// ── Procedural weave (twill-bias crosshatch) ─────────────────
//
// A silk twill has two interleaved thread families running at
// roughly ±45°. We build it by sampling a diagonal grid in
// both orientations and combining them.
//
// Parameters
//   st       — UV in weave space (already scaled)
//   returns a 0..1 value: 0 = valley between threads, 1 = thread peak
float weavePattern(vec2 st) {

    // ── Warp threads (running diagonally at +45°) ────────────
    // Rotate UV by +45° (multiply by rotation matrix)
    vec2 stWarp = vec2(st.x + st.y, st.y - st.x) * 0.7071;

    // Periodic position within one thread repeat
    float warpPhase = fract(stWarp.x);

    // A thin raised ridge: thread width = ~55% of the period.
    // smoothstep edges give a soft, lenticular cross-section.
    float warpThread  = smoothstep(0.00, 0.18, warpPhase)
                      - smoothstep(0.55, 0.73, warpPhase);

    // ── Weft threads (running diagonally at −45°) ────────────
    vec2 stWeft = vec2(st.x - st.y, st.y + st.x) * 0.7071;
    float weftPhase = fract(stWeft.x);

    float weftThread  = smoothstep(0.00, 0.18, weftPhase)
                      - smoothstep(0.55, 0.73, weftPhase);

    // ── Twill interleave ─────────────────────────────────────
    // In a 2/2 twill the warp floats over two weft threads then
    // under two. We approximate this by using a low-frequency
    // modulation to swap which family is "on top".
    float twillShift = fract(stWarp.x * 0.5);
    float warpOver   = step(0.5, twillShift);   // 0 or 1, alternating

    // Combine: wherever warp is over, warp thread wins and weft
    // is suppressed; otherwise weft wins.
    float combined = mix(
        max(weftThread, warpThread * 0.5),   // weft-dominant
        max(warpThread, weftThread * 0.5),   // warp-dominant
        warpOver
    );

    return clamp(combined, 0.0, 1.0);
}

// ── Specular shimmer band ────────────────────────────────────
//
// A soft highlight that sweeps across the fabric surface with
// time and mouse position. Silk reflects a very directional
// highlight because of its satin weave structure.
float silkSpecular(vec2 uv, float time, float mouseX) {
    // The highlight is a gentle band on U — moved by time and mouse.
    // It oscillates slowly back and forth, biased by the mouse.
    float bandCenter = 0.5
                     + sin(time * 0.18) * 0.22
                     + mouseX * 0.12;

    // Soft falloff around the band centre
    float dist    = abs(uv.x - bandCenter);
    float band    = exp(-dist * dist * 28.0);   // tight Gaussian

    // Modulate along V so the shimmer fades toward the bottom
    float vFade   = smoothstep(1.0, 0.0, uv.y);
    band *= 0.6 + 0.4 * vFade;

    // Fine specular sparkle: a second narrower pass that shifts faster
    float bandCenter2 = 0.5
                      + cos(time * 0.31 + 1.2) * 0.18
                      + mouseX * 0.08;
    float dist2   = abs(uv.x - bandCenter2);
    float band2   = exp(-dist2 * dist2 * 70.0) * 0.55;

    return clamp(band + band2, 0.0, 1.0);
}

// ── Main ─────────────────────────────────────────────────────
void main() {

    // ── 1. Weave texture ─────────────────────────────────────
    //
    // Scale UV to weave density. Use non-uniform aspect correction
    // (assume the fabric is roughly portrait in aspect ratio).
    vec2 weaveST  = vUv * uWeaveScale;

    // Add a very gentle time drift so the weave appears to have
    // micro-vibration — just barely perceptible.
    weaveST      += vec2(sin(uTime * 0.05) * 0.3, cos(uTime * 0.07) * 0.2);

    float weave   = weavePattern(weaveST);

    // ── 2. Base colour — mix between thread peak and valley ──
    //
    // Thread peaks catch a touch more light; valleys are very
    // slightly darker. The difference is intentionally tiny —
    // luxury fabric has fine weave, not burlap.
    vec3 fabricColor = mix(WEAVE_DARK, SILK_BASE, weave);

    // ── 3. Sheer translucency gradient ───────────────────────
    //
    // Silk is sheer — held up to the light, the centre glows and
    // the edges catch a cool rim. We approximate this with the
    // perturbed normal's Z component (how directly it faces camera)
    // and a UV-based centre falloff.
    float normalFacing  = dot(normalize(vNormal), vec3(0.0, 0.0, 1.0));
    normalFacing        = clamp(normalFacing, 0.0, 1.0);

    // Centre of fabric faces camera more directly → slightly lighter
    float centerLift    = normalFacing * 0.5
                        + (1.0 - abs(vUv.x - 0.5) * 2.0) * 0.5;
    centerLift          = clamp(centerLift, 0.0, 1.0);

    fabricColor = mix(fabricColor, SILK_LIGHT, centerLift * 0.12);

    // ── 4. Fresnel-like edge luminance ───────────────────────
    //
    // At the left and right edges of the hanging fabric, light
    // grazes the surface and reflects strongly — a classic Fresnel
    // effect on a near-vertical surface. We use proximity to
    // UV extremes as our surrogate angle.
    float edgeDist  = min(vUv.x, 1.0 - vUv.x);       // 0 at edges, 0.5 at centre
    float fresnel   = 1.0 - smoothstep(0.0, 0.18, edgeDist);
    fresnel         = pow(fresnel, 1.4);               // sharpen the falloff

    // Edge luminance: barely visible brightening, very restrained
    fabricColor    += SILK_LIGHT * fresnel * 0.055;

    // ── 5. Specular shimmer ──────────────────────────────────
    //
    // A barely-there highlight band — like afternoon light
    // catching a Hermès scarf in a boutique window.
    float spec      = silkSpecular(vUv, uTime, uMouseX);

    // Only add the specular where the surface is smooth (high weave
    // value — thread peaks), so the shimmer reads as surface gloss.
    spec           *= mix(0.4, 1.0, weave);

    // Extremely restrained — a hint, not a glare.
    fabricColor    += SPEC_COLOR * spec * 0.038;

    // ── 6. Alpha — translucency with weave variation ─────────
    //
    // Base alpha is 0.92–0.97 (mostly opaque, slightly sheer).
    // Weave valleys are very marginally more transparent — in
    // natural silk the thread crossings are denser than gaps.
    float baseAlpha     = 0.945;
    float weaveAlpha    = mix(0.015, 0.0, weave);     // max 1.5% variation
    float edgeAlpha     = fresnel * 0.018;             // edges fractionally more opaque

    // Sway adds a tiny translucency pulse as the fabric ripples —
    // in motion, silk catches light differently, briefly appearing
    // more luminous and slightly less dense.
    float swayAlpha     = vSway * 0.012;

    float alpha         = clamp(baseAlpha - weaveAlpha + edgeAlpha + swayAlpha,
                                0.92, 0.97);

    // ── 7. Tone mapping / colour correction ─────────────────
    //
    // Very mild contrast enhancement and warmth. Keeps the palette
    // squarely in the ivory-cream register rather than sliding cool.
    fabricColor         = pow(fabricColor, vec3(0.97));   // gentle gamma lift
    fabricColor.r      += 0.004;                           // barely perceptible warmth

    // Ensure we stay in gamut
    fabricColor         = clamp(fabricColor, 0.0, 1.0);

    // ── 8. Output ────────────────────────────────────────────
    gl_FragColor = vec4(fabricColor, alpha);
}
