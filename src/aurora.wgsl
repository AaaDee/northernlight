// Aurora matching a near-black night sky with intense green curtains, after a
// frame from an aurora timelapse: vivid green ribbons sweeping diagonally with
// white-hot cores, vertical ray striations, a mountain ridge, faint stars.
// High contrast, sky crushed to near-black.
//
// Motion: each curtain layer drifts sideways (parallax), its baseline meanders
// like a rippling ribbon, rays flicker/pulse, and bands sweep diagonally.

struct Uniforms {
    resolution: vec2<f32>,
    time: f32,
    _pad: f32,
};

@group(0) @binding(0) var<uniform> u: Uniforms;

struct VsOut {
    @builtin(position) pos: vec4<f32>,
    @location(0) uv: vec2<f32>,
};

@vertex
fn vs_main(@builtin(vertex_index) vi: u32) -> VsOut {
    var out: VsOut;
    let x = f32((vi << 1u) & 2u);
    let y = f32(vi & 2u);
    out.uv = vec2<f32>(x, y);
    out.pos = vec4<f32>(x * 2.0 - 1.0, 1.0 - y * 2.0, 0.0, 1.0);
    return out;
}

fn hash21(p_in: vec2<f32>) -> f32 {
    var p = fract(p_in * vec2<f32>(123.34, 456.21));
    p = p + dot(p, p + 45.32);
    return fract(p.x * p.y);
}

fn noise2(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    // Quintic interpolant (C2-continuous). Cubic smoothstep leaves a 2nd-
    // derivative kink at every cell boundary which, because this noise warps
    // the ray positions, shows up as horizontal creases across the frame.
    let w = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    let a = hash21(i);
    let b = hash21(i + vec2<f32>(1.0, 0.0));
    let c = hash21(i + vec2<f32>(0.0, 1.0));
    let d = hash21(i + vec2<f32>(1.0, 1.0));
    return mix(mix(a, b, w.x), mix(c, d, w.x), w.y);
}

fn fbm2(p_in: vec2<f32>) -> f32 {
    var v = 0.0;
    var amp = 0.5;
    var p = p_in;
    for (var i = 0; i < 5; i = i + 1) {
        v = v + amp * noise2(p);
        p = p * 2.0;
        amp = amp * 0.5;
    }
    return v;
}

// Accumulated aurora colour for sky point p (p.y: 0 = horizon, 1 = zenith).
fn aurora_sky(p: vec2<f32>, t: f32) -> vec3<f32> {
    var acc = vec3<f32>(0.0);
    // Pure-green palette (almost no blue) so cores read green, not teal.
    let green = vec3<f32>(0.10, 1.0, 0.18);
    let lime = vec3<f32>(0.30, 1.0, 0.30);
    let pink = vec3<f32>(1.0, 0.25, 0.65);

    for (var i = 0.0; i < 4.0; i = i + 1.0) {
        // Sideways drift (alternating per layer) -> parallax.
        let dir = select(1.0, -1.0, (i % 2.0) < 0.5);
        let scroll = t * (0.03 + 0.02 * i) * dir;
        let xx = p.x * (1.0 + 0.2 * i) + scroll;

        // Diagonal sweep + meandering baseline (the rippling ribbon edge).
        let slope = (i - 1.0) * 0.06;
        let baseY = 0.30 + 0.10 * i
            + p.x * slope
            + 0.10 * (fbm2(vec2<f32>(xx * 0.5, i * 3.7)) - 0.5)
            + 0.03 * sin(p.x * 2.0 + t * 0.4 + i);

        let h = p.y - baseY;

        // Horizontal sway that grows with height so curtains bend and flow into
        // wavy ribbons instead of straight columns. Driven by height + time so
        // the waves travel/undulate.
        let sway = (0.10 + 0.18 * h) * sin(p.y * 2.6 + t * 0.6 + i * 2.0)
            + 0.22 * (fbm2(vec2<f32>(p.y * 1.6 + t * 0.12, i * 5.0 + 9.0)) - 0.5);
        let cx = xx + sway;

        // SPARSE, SHARP, FINE vertical rays: warp x so rays meander, take a
        // triangle ridge for crisp filaments, then pick only some ridges
        // (gaps -> the black sky shows through between curtains).
        let warp = fbm2(vec2<f32>(cx * 0.7 + t * 0.05, i * 2.0));
        let q = cx * 3.2 + warp * 1.6;
        let ridge = 1.0 - abs(fract(q) - 0.5) * 2.0;
        // Lower threshold -> more ridges lit -> aurora covers more of the sky.
        let pick = smoothstep(0.30, 0.80, fbm2(vec2<f32>(floor(q) * 0.35, i * 1.7)));
        let ray = pow(max(ridge, 0.0), 6.0) * pick;

        // Vertical profile: bright sharp bottom edge, fade upward. Longer rays
        // reach higher up the sky.
        let topLen = 0.30 + 0.35 * fbm2(vec2<f32>(xx * 1.2 + 5.0, i));
        let vert = clamp(h / 0.015, 0.0, 1.0) * exp(-max(h, 0.0) / topLen);

        // Thin bright band hugging the baseline (the concentrated streak).
        let band = exp(-(h * h) / 0.0015);

        let pulse = 0.7 + 0.3 * sin(t * 0.8 + i + xx * 0.7);
        let intensity = (ray * vert * 2.6 + band * ray * 1.2) * pulse;

        // Colour ramps with height: green body fading to pink/magenta at the
        // upper edges, as in the reference photos.
        let frac = clamp(h / topLen, 0.0, 1.0);
        var col = mix(green, lime, smoothstep(0.0, 0.35, frac));
        col = mix(col, pink, 0.85 * smoothstep(0.5, 1.0, frac));

        acc = acc + col * intensity / (1.0 + i * 0.4);
    }

    // White-hot cores where rays stack up brightest.
    let lum = max(acc.r, max(acc.g, acc.b));
    acc = acc + vec3<f32>(1.0) * smoothstep(1.7, 3.0, lum) * 0.7;
    return acc;
}

fn starfield(p: vec2<f32>, t: f32) -> vec3<f32> {
    let g = floor(p * 180.0);
    let s = hash21(g);
    let twinkle = step(0.992, s) * pow(hash21(g + 7.3), 25.0);
    let flicker = 0.6 + 0.4 * sin(t * 3.0 + s * 100.0);
    return vec3<f32>(twinkle * flicker) * smoothstep(0.15, 0.5, p.y);
}

@fragment
fn fs_main(in: VsOut) -> @location(0) vec4<f32> {
    let aspect = u.resolution.x / u.resolution.y;
    // p.y: 0 at bottom (horizon), 1 at top (zenith).
    let p = vec2<f32>(in.uv.x * aspect, 1.0 - in.uv.y);
    let t = u.time;

    // Near-black night sky (these are linear values; the sRGB surface applies
    // gamma on write, so keep them tiny).
    let horizon = vec3<f32>(0.004, 0.008, 0.018);
    let zenith = vec3<f32>(0.0, 0.001, 0.004);
    var col = mix(horizon, zenith, clamp(p.y, 0.0, 1.0));

    col = col + starfield(p, t);
    col = col + aurora_sky(p, t);

    // Mountain ridge silhouette.
    let far = 0.11 + 0.045 * fbm2(vec2<f32>(p.x * 1.3 + 20.0, 0.0));
    let near = 0.06 + 0.06 * fbm2(vec2<f32>(p.x * 0.8 + 50.0, 0.0));
    let ridge = max(far, near);

    if (p.y < ridge) {
        col = vec3<f32>(0.0, 0.002, 0.004);
    }

    // High-contrast exposure tonemap. Output is LINEAR — the sRGB surface
    // applies gamma encoding on write, so we must NOT gamma-correct here
    // (doing both was washing the darks into a grey haze).
    col = vec3<f32>(1.0) - exp(-col * 1.3);

    // Ordered-ish dither to break up 8-bit banding in the dark sky gradient.
    let dither = (hash21(in.uv * u.resolution) - 0.5) / 255.0;
    col = col + vec3<f32>(dither);
    return vec4<f32>(col, 1.0);
}
