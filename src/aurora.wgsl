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

// One softly flowing aurora curtain (vertical wavy drapery that drifts/snakes).
//   seed     : decorrelates this curtain from the others
//   baseEdge : nominal height of its (wavy) lower edge
//   depth    : 0 = front (brighter/faster), higher = back
fn curtain(p: vec2<f32>, t: f32, seed: f32, baseEdge: f32, depth: f32) -> vec3<f32> {
    // Horizontal warp built from pure sines (no creases). Several height
    // frequencies make each curtain snake left/right multiple times.
    let flow =
        0.18 * sin(p.y * 3.0 + t * 0.5 + seed)
        + 0.11 * sin(p.y * 5.5 - t * 0.7 + seed * 2.0)
        + 0.06 * sin(p.y * 9.0 + t * 1.0 + seed * 3.3);
    let xw = p.x * (0.9 + 0.12 * depth) + t * (0.025 + 0.015 * depth) + flow + seed * 3.0;

    let cov = 0.375 + 0.05 * sin(t * 0.13) + 0.025 * sin(t * 0.31 + 1.0);
    let lo = mix(0.58, 0.30, clamp((cov - 0.30) / 0.30, 0.0, 1.0));

    // Soft vertical filaments (no hard ridges) — some columns brighter, gaps
    // fade smoothly so the black sky shows through without sharp borders.
    let body = fbm2(vec2<f32>(xw * 3.0, p.y * 0.5 + seed * 5.0 + t * 0.04));
    let rays = smoothstep(lo, lo + 0.38, body);

    // Gently waving lower edge of the ribbon (sines only).
    let edge = baseEdge
        + 0.09 * sin(xw * 1.2 + t * 0.3 + seed)
        + 0.05 * sin(xw * 2.3 - t * 0.2 + seed * 1.7);
    let hh = p.y - edge;

    // Soft bottom + exponential fade up.
    let topLen = 0.36;
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
    // Slow everything down: feed the curtains a half-speed clock.
    let ts = t * 0.5;
    c = c + curtain(p, ts, 0.0, 0.34, 0.0);
    c = c + curtain(p, ts, 1.7, 0.44, 1.0);
    c = c + curtain(p, ts, 3.9, 0.28, 2.0);

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

// Silhouette top height of a row of Christmas trees at horizontal position x.
// Each tree is built from stacked triangular tiers (widest at the bottom,
// pointed at the top) for the classic conifer look.
fn pines(x: f32) -> f32 {
    var top = 0.0;
    for (var k = 0.0; k < 16.0; k = k + 1.0) {
        let cx = hash21(vec2<f32>(k, 1.0)) * 2.0;            // across screen (0..2)
        let h = 0.0375 + 0.025 * hash21(vec2<f32>(k, 2.0)); // tree height
        let w = 0.011 + 0.006 * hash21(vec2<f32>(k, 3.0)); // half-width at base
        // Stand each tree on the ridge line at its position so small trees
        // still poke above the mountain silhouette.
        let rfar = 0.10 + 0.04 * fbm2(vec2<f32>(cx * 1.3 + 20.0, 0.0));
        let rnear = 0.05 + 0.05 * fbm2(vec2<f32>(cx * 0.8 + 50.0, 0.0));
        let base = max(rfar, rnear) - 0.005;
        let d = abs(x - cx);

        // Three overlapping tiers, each higher up and narrower than the last.
        for (var s = 0.0; s < 3.0; s = s + 1.0) {
            let wj = w * (1.0 - 0.27 * s);
            let basej = base + h * 0.26 * s;
            let apexj = basej + h * 0.5;
            if (d < wj) {
                top = max(top, basej + (apexj - basej) * (1.0 - d / wj));
            }
        }
        // Thin trunk poking down to the ground.
        if (d < 0.00125) {
            top = max(top, base + 0.01);
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

    // Triangular-PDF dither (sum of two hashes) to break up 8-bit banding in
    // the smooth sky/aurora gradients — better than a single uniform sample.
    let d1 = hash21(in.uv * u.resolution);
    let d2 = hash21(in.uv * u.resolution + 19.7);
    let dither = (d1 + d2 - 1.0) / 255.0;
    col = col + vec3<f32>(dither);
    return vec4<f32>(col, 1.0);
}
