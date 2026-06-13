// Aurora as a few whole, continuously flowing curtains over a near-black sky.
//
// Each curtain is ONE soft ribbon: a smoothly waving lower edge, soft vertical
// filaments, and a long upward fade — green body shading through lime to a
// pink/magenta top. A height-dependent horizontal "flow" warps each curtain
// so it sways as a single organic object.
// Foreground: dark mountain ridge with a row of pine-tree silhouettes.
// All look/tuning knobs are grouped in the constants block below.

struct Uniforms {
    resolution: vec2<f32>,
    time: f32,
    _pad: f32,
};

@group(0) @binding(0) var<uniform> u: Uniforms;

// ---- Look & tuning constants -----------------------------------------------
// The whole "look" lives here so it can be tuned in one place instead of
// hunting for literals at their use sites.

// Post-processing
const AURORA_GAIN    = 3.0;   // brightness multiplier on the aurora layer
const EXPOSURE       = 1.3;   // tonemap exposure: 1 - exp(-col * EXPOSURE)
const CONTRAST       = 1.1;   // S-curve strength around CONTRAST_PIVOT
const CONTRAST_PIVOT = 0.25;  // value the contrast curve pivots about

// Sky & ground (linear values; the sRGB surface applies gamma on present)
const SKY_HORIZON  = vec3<f32>(0.012, 0.022, 0.050);
const SKY_ZENITH   = vec3<f32>(0.002, 0.006, 0.016);
const GROUND_COLOR = vec3<f32>(0.004, 0.008, 0.016);

// Curtain palette: green body shading up through lime to a pink/magenta top
const COL_GREEN = vec3<f32>(0.10, 1.0, 0.20);
const COL_LIME  = vec3<f32>(0.40, 1.0, 0.40);
const COL_PINK  = vec3<f32>(1.0, 0.30, 0.70);

struct VsOut {
    @builtin(position) pos: vec4<f32>,
    @location(0) uv: vec2<f32>,
};

@vertex
fn vs_main(@builtin(vertex_index) vi: u32) -> VsOut {
    // Writing a single triangle that covers the entire screen
    var out: VsOut;
    let x = f32((vi << 1u) & 2u);
    let y = f32(vi & 2u);
    out.uv = vec2<f32>(x, y);
    out.pos = vec4<f32>(x * 2.0 - 1.0, 1.0 - y * 2.0, 0.0, 1.0);
    return out;
}

// Cheap pseudo-rng based on positiont
fn hash21(p_in: vec2<f32>) -> f32 {
    var p = fract(p_in * vec2<f32>(123.34, 456.21));
    p = p + dot(p, p + 45.32);
    return fract(p.x * p.y);
}

// Random gradient vector (components in [-1,1]) for a lattice point.
fn hash22(p: vec2<f32>) -> vec2<f32> {
    let q = vec2<f32>(dot(p, vec2<f32>(127.1, 311.7)),
                      dot(p, vec2<f32>(269.5, 183.3)));
    return -1.0 + 2.0 * fract(sin(q) * 43758.5453123);
}

// Gradient (Perlin) noise. Unlike value noise it pins the field to zero at the
// lattice points and randomizes the gradient there, so features no longer line
// up into visible grid rows/columns. Remapped to [0,1] to match the old range.
fn noise2(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    // Quintic interpolant (C2-continuous) for smooth, crease-free noise.
    let u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    let ga = hash22(i + vec2<f32>(0.0, 0.0));
    let gb = hash22(i + vec2<f32>(1.0, 0.0));
    let gc = hash22(i + vec2<f32>(0.0, 1.0));
    let gd = hash22(i + vec2<f32>(1.0, 1.0));
    let va = dot(ga, f - vec2<f32>(0.0, 0.0));
    let vb = dot(gb, f - vec2<f32>(1.0, 0.0));
    let vc = dot(gc, f - vec2<f32>(0.0, 1.0));
    let vd = dot(gd, f - vec2<f32>(1.0, 1.0));
    let n = va + u.x * (vb - va) + u.y * (vc - va) + u.x * u.y * (va - vb - vc + vd);
    return 0.5 + 0.5 * n;
}

fn fbm2(p_in: vec2<f32>) -> f32 {
    var v = 0.0;
    var amp = 0.5;
    var p = p_in;
    // Rotate (and scale x2) each octave so successive octaves never line up
    // into axis-aligned seams across the frame.
    let m = mat2x2<f32>(1.6, 1.2, -1.2, 1.6);
    for (var i = 0; i < 5; i = i + 1) {
        v = v + amp * noise2(p);
        p = m * p;
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
    // The vertical coordinate depends on xw too, so any noise iso-line follows
    // the wavy curtain instead of forming a flat horizontal seam mid-frame.
    let body = fbm2(vec2<f32>(xw * 3.0, xw * 0.6 + p.y * 0.5 + seed * 5.0 + t * 0.04));
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
    var col = mix(COL_GREEN, COL_LIME, smoothstep(0.0, 0.30, frac));
    col = mix(col, COL_PINK, 0.8 * smoothstep(0.5, 1.0, frac));

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

// Height of the layered mountain ridge silhouette at horizontal position x.
// Two octaves of fbm (a far and a near range) max'd together.
fn ridge_height(x: f32) -> f32 {
    let far = 0.10 + 0.04 * fbm2(vec2<f32>(x * 1.3 + 20.0, 0.0));
    let near = 0.05 + 0.05 * fbm2(vec2<f32>(x * 0.8 + 50.0, 0.0));
    return max(far, near);
}

// Silhouette top height of a row of Christmas trees at horizontal position x.
// Each tree is built from stacked triangular tiers (widest at the bottom,
// pointed at the top) for the classic conifer look.
fn pines(x: f32) -> f32 {
    var top = 0.0;
    for (var k = 0.0; k < 24.0; k = k + 1.0) {
        let cx = hash21(vec2<f32>(k, 1.0)) * 2.0;            // across screen (0..2)
        let h = 0.0375 + 0.025 * hash21(vec2<f32>(k, 2.0)); // tree height
        let w = 0.011 + 0.006 * hash21(vec2<f32>(k, 3.0)); // half-width at base
        // Stand each tree on the ridge line at its position so small trees
        // still poke above the mountain silhouette.
        let base = ridge_height(cx) - 0.005;
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

    // Night sky, lifted off pure black so it survives the contrast curve and
    // reads as a deep blue dusk.
    var col = mix(SKY_HORIZON, SKY_ZENITH, clamp(p.y, 0.0, 1.0));

    col = col + starfield(p, t);
    col = col + aurora_sky(p, t) * AURORA_GAIN;

    // Mountain ridge with pine trees standing on it.
    let ground = max(ridge_height(p.x), pines(p.x));
    if (p.y < ground) {
        col = GROUND_COLOR;
    }

    // High-contrast exposure tonemap. Output is LINEAR (sRGB surface encodes).
    col = vec3<f32>(1.0) - exp(-col * EXPOSURE);

    // Contrast S-curve. Low pivot so the bright aurora gains punch without
    // crushing the dark sky/ground down to flat black.
    col = clamp((col - vec3<f32>(CONTRAST_PIVOT)) * CONTRAST + vec3<f32>(CONTRAST_PIVOT),
                vec3<f32>(0.0), vec3<f32>(1.0));

    // Triangular-PDF dither (sum of two hashes) to break up 8-bit banding in
    // the smooth sky/aurora gradients — better than a single uniform sample.
    let d1 = hash21(in.uv * u.resolution);
    let d2 = hash21(in.uv * u.resolution + 19.7);
    let dither = (d1 + d2 - 1.0) / 255.0;
    col = col + vec3<f32>(dither);
    return vec4<f32>(col, 1.0);
}
