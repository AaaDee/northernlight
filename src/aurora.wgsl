// Aurora as a few whole, continuously flowing curtains over a near-black sky.
//
// Each curtain is ONE soft ribbon: a smoothly waving lower edge, soft vertical
// filaments, and a long upward fade — green body shading to pink at the top
// edge (as in the reference photos). A height-dependent horizontal "flow" warps
// each curtain so it sways as a single organic object. No hard edges, no
// per-layer baseline streaks (which previously read as horizontal scan lines).
// Foreground: dark mountain ridge with a row of pine-tree silhouettes.

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
    // Quintic interpolant (C2-continuous) for smooth, crease-free noise.
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

// One continuous, softly flowing aurora curtain.
//   seed     : decorrelates this curtain from the others
//   baseEdge : nominal height of its (wavy) lower edge
//   depth    : 0 = front (brighter/faster), higher = back
fn curtain(p: vec2<f32>, t: f32, seed: f32, baseEdge: f32, depth: f32) -> vec3<f32> {
    // Smooth flowing horizontal warp. Depends mostly on height so the whole
    // curtain leans/sways as one body; animated so the waves travel.
    let flow =
        0.10 * sin(p.y * 2.0 + t * 0.5 + seed)
        + 0.06 * sin(p.y * 3.3 - t * 0.7 + seed * 2.0)
        + 0.14 * (fbm2(vec2<f32>(p.y * 0.9 + seed, t * 0.08)) - 0.5);
    let xw = p.x * (0.9 + 0.12 * depth) + t * (0.025 + 0.015 * depth) + flow + seed * 3.0;

    // Soft vertical filaments (no hard ridges) — some columns brighter, gaps
    // fade smoothly so the black sky shows through without sharp borders.
    let streak = fbm2(vec2<f32>(xw * 3.0, seed * 5.0 + t * 0.04));
    let rays = smoothstep(0.30, 0.72, streak);

    // Gently waving lower edge of the ribbon.
    let edge = baseEdge
        + 0.10 * sin(xw * 1.2 + t * 0.3 + seed)
        + 0.08 * (fbm2(vec2<f32>(xw * 0.6, t * 0.05 + seed)) - 0.5);
    let hh = p.y - edge;

    // Soft bottom (smoothstep, not a hard clamp) + long exponential fade up.
    let topLen = 0.5;
    let vprofile = smoothstep(-0.06, 0.05, hh) * exp(-max(hh, 0.0) / topLen);

    let pulse = 0.78 + 0.22 * sin(t * 0.6 + xw * 0.5 + seed);
    let intensity = rays * vprofile * pulse;

    // Green body -> pink/magenta upper edge.
    let frac = clamp(hh / topLen, 0.0, 1.0);
    let green = vec3<f32>(0.10, 1.0, 0.20);
    let lime = vec3<f32>(0.40, 1.0, 0.40);
    let pink = vec3<f32>(1.0, 0.30, 0.70);
    var col = mix(green, lime, smoothstep(0.0, 0.30, frac));
    col = mix(col, pink, 0.8 * smoothstep(0.5, 1.0, frac));

    return col * intensity / (1.0 + depth * 0.4);
}

fn aurora_sky(p: vec2<f32>, t: f32) -> vec3<f32> {
    var c = vec3<f32>(0.0);
    c = c + curtain(p, t, 0.0, 0.34, 0.0);
    c = c + curtain(p, t, 1.7, 0.44, 1.0);
    c = c + curtain(p, t, 3.9, 0.28, 2.0);

    // White-hot cores where the brightest filaments stack up.
    let lum = max(c.r, max(c.g, c.b));
    c = c + vec3<f32>(1.0) * smoothstep(1.7, 3.0, lum) * 0.6;
    return c;
}

fn starfield(p: vec2<f32>, t: f32) -> vec3<f32> {
    let g = floor(p * 180.0);
    let s = hash21(g);
    let twinkle = step(0.992, s) * pow(hash21(g + 7.3), 25.0);
    let flicker = 0.6 + 0.4 * sin(t * 3.0 + s * 100.0);
    return vec3<f32>(twinkle * flicker) * smoothstep(0.15, 0.5, p.y);
}

// Silhouette top height of a row of pine trees at horizontal position x.
fn pines(x: f32) -> f32 {
    var top = 0.0;
    for (var k = 0.0; k < 7.0; k = k + 1.0) {
        let cx = hash21(vec2<f32>(k, 1.0)) * 2.0;          // across screen (0..2)
        let h = 0.13 + 0.10 * hash21(vec2<f32>(k, 2.0));   // tree height
        let w = 0.030 + 0.020 * hash21(vec2<f32>(k, 3.0)); // half-width at base
        let base = 0.045 + 0.025 * hash21(vec2<f32>(k, 4.0));
        let d = abs(x - cx);
        if (d < w) {
            let dn = d / w;                 // 0 at trunk, 1 at edge
            // Conical fir profile with a little branch wobble on the edge.
            let g = (1.0 - dn) + 0.08 * sin(dn * 22.0) * (1.0 - dn);
            top = max(top, base + h * g);
        }
        // Thin trunk poking down to the ground.
        if (abs(x - cx) < 0.004) {
            top = max(top, base + 0.02);
        }
    }
    return top;
}

@fragment
fn fs_main(in: VsOut) -> @location(0) vec4<f32> {
    let aspect = u.resolution.x / u.resolution.y;
    // p.y: 0 at bottom (horizon), 1 at top (zenith).
    let p = vec2<f32>(in.uv.x * aspect, 1.0 - in.uv.y);
    let t = u.time;

    // Near-black night sky (linear values; sRGB surface applies gamma).
    let horizon = vec3<f32>(0.004, 0.008, 0.018);
    let zenith = vec3<f32>(0.0, 0.001, 0.004);
    var col = mix(horizon, zenith, clamp(p.y, 0.0, 1.0));

    col = col + starfield(p, t);
    col = col + aurora_sky(p, t);

    // Mountain ridge silhouette.
    let far = 0.10 + 0.04 * fbm2(vec2<f32>(p.x * 1.3 + 20.0, 0.0));
    let near = 0.05 + 0.05 * fbm2(vec2<f32>(p.x * 0.8 + 50.0, 0.0));
    let ridge = max(far, near);

    // Pine trees stand on the ridge line.
    let trees = pines(p.x);
    let ground = max(ridge, trees);
    if (p.y < ground) {
        col = vec3<f32>(0.0, 0.001, 0.002);
    }

    // High-contrast exposure tonemap. Output is LINEAR (sRGB surface encodes).
    col = vec3<f32>(1.0) - exp(-col * 1.3);

    // Dither to break up 8-bit banding in the dark sky.
    let dither = (hash21(in.uv * u.resolution) - 0.5) / 255.0;
    col = col + vec3<f32>(dither);
    return vec4<f32>(col, 1.0);
}
