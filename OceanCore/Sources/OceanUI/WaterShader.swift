import Foundation

/// The water fragment shader.
///
/// SpriteKit accepts GLSL ES source and compiles it to Metal internally — which
/// is the only per-pixel shading available on watchOS, since both `Metal` and
/// SwiftUI's `colorEffect` are absent there.
///
/// The view is straight down into the water. Everything visible derives from
/// one analytic height field:
///
///   - the **surface normal** comes from the field's gradient, accumulated
///     alongside the height rather than sampled, so it is exact and nearly free;
///   - the **sea bed** is sampled through that normal, which is the refraction;
///   - **caustics** are the bed's own light web, bent by the same normal;
///   - **foam** appears where the surface gets too steep to hold together;
///   - **glitter** is a specular highlight off the normal;
///   - **depth** darkens away from the bowl's centre.
///
/// Optional layers — bed texture, shadows below, shafts, reflected sky,
/// lightning — sit behind `if` tests on uniforms. Uniform branches are coherent
/// across the entire draw, so a mode that leaves a feature off genuinely does
/// not pay for it.
///
/// Two constraints come from SpriteKit's GLSL-to-Metal translation, both
/// learned by reading the compiler's complaints:
///
///   1. **Uniforms must not be declared here.** SpriteKit generates the
///      declarations from `shader.uniforms`; declaring them again collides with
///      Metal's own `uniform<T>` template and the whole shader fails to build,
///      leaving a plain white sprite and one line in the log.
///   2. **No `inout` parameters.** Wave functions return a `vec3` instead —
///      `.x` is the height contribution, `.yz` the gradient.
public enum WaterShader {
    /// Names every uniform the source reads. `WaterScene` builds its
    /// `SKUniform` list from this, so the two can never drift apart.
    ///
    /// **Scalars are packed into vectors on purpose.** SpriteKit binds each
    /// uniform to its own Metal buffer slot, and Metal allows only 31 — two of
    /// which SpriteKit already spends on `u_time` and `u_path_length`. One
    /// uniform per parameter blew straight past that ceiling and the shader
    /// failed to build. Packing four floats into a `vec4` costs nothing and
    /// buys three slots back each time.
    public static let uniformNames = [
        "u_size",        // vec2  drawable size in points
        "u_now",         // float our own clock, shared with ripple birth times
        "u_flowCenter",  // vec4  swell direction .xy, bowl centre .zw
        "u_state",       // vec4  energy, surge, lightning flash, spare
        "u_wave",        // vec4  choppiness, turbulence, crest sharpness, glitter
        "u_layers",      // vec4  bed detail, shadows, shafts, sky glow
        "u_optics",      // vec4  caustic strength, caustic time scale, foam, glow
        "u_deep", "u_shallow", "u_light", "u_foam", "u_skyA", "u_skyB",
        "u_r0", "u_r1", "u_r2", "u_r3", "u_r4", "u_r5",
    ]

    public static let source = """
    float hash21(vec2 p) {
        return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
    }

    // A wave whose crests can be peaked.
    //
    // `sharp` 0 gives a plain sine swell. Raising it narrows the crests and
    // broadens the troughs, which is the trochoidal shape water actually takes
    // as it steepens toward breaking. Implemented by raising the half-cycle to
    // a power, with the derivative carried through so the normal stays exact.
    // Returns (height, dx, dy).
    vec3 wave(vec2 p, vec2 dir, float freq, float amp, float speed, float t, float sharp) {
        float phase = dot(p, dir) * freq + t * speed;
        float s = sin(phase);
        float c = cos(phase);
        float e = 1.0 + sharp * 2.6;
        float u = 0.5 + 0.5 * s;                 // 0…1 across the cycle
        float shaped = pow(u, e) * 2.0 - 1.0;    // back to -1…1, crest narrowed
        float dShaped = e * pow(u, e - 1.0) * c; // d(shaped)/d(phase)
        return vec3(amp * shaped, dir * (freq * amp * dShaped));
    }

    // An expanding ring. The crest lives at radius = age * speed and is
    // localised by an exponential envelope, so old ripples fade rather than
    // leaving the screen full of standing waves.
    vec3 ripple(vec2 p, vec4 r, float t) {
        float age = t - r.z;
        float alive = step(0.0, age) * step(age, 3.2) * step(0.001, r.w);
        vec2 d = p - r.xy;
        float dist = length(d) + 0.0001;
        float front = dist - age * 0.42;
        float env = exp(-abs(front) * 13.0) * exp(-age * 1.15) * r.w * alive;
        float phase = front * 62.0;
        return vec3(env * 0.05 * sin(phase),
                    (d / dist) * (env * 0.05 * 62.0 * cos(phase)));
    }

    // Light converges along the *zero crossings* of the interference field, not
    // at its peaks. Taking `1 - |field|` and raising it hard puts a thin bright
    // line exactly where the field crosses zero, which is why this reads as a
    // connected web instead of scattered flakes.
    //
    // Three waves rather than two: two make a grid, three make a mesh. Each
    // octave is rotated so nothing lines up with the pixel axes, and the domain
    // is warped so the filaments curve.
    //
    // Freeze the time input and the very same network stops being moving light
    // and becomes a fracture pattern. That is all Under ice is.
    float causticOctave(vec2 p, float t, float scale, float angle) {
        float c = cos(angle);
        float s = sin(angle);
        vec2 q = vec2(p.x * c - p.y * s, p.x * s + p.y * c) * scale;
        q += 0.30 * vec2(sin(q.y * 0.63 + t), cos(q.x * 0.57 - t * 0.82));
        float v = (sin(q.x) + sin(q.y * 1.17) + sin((q.x + q.y) * 0.73)) / 3.0;
        return pow(max(1.0 - abs(v), 0.0), 7.0);
    }

    float caustics(vec2 p, float t) {
        float a = causticOctave(p, t * 0.72, 9.0, 0.0);
        float b = causticOctave(p + vec2(4.1, 2.7), t * 0.91, 15.0, 1.10);
        return a * 0.62 + b * 0.38;
    }

    // Mottling for the whitecaps. Flat white foam looks like paint; foam needs
    // visible grain to read as churned air and water.
    float foamTexture(vec2 p, float t) {
        float n = sin(p.x * 61.0 + t * 2.1) * sin(p.y * 53.0 - t * 1.7)
                + 0.5 * sin(p.x * 97.0 - t * 3.1) * sin(p.y * 89.0 + t * 2.3);
        return clamp(0.45 + 0.55 * n, 0.0, 1.0);
    }

    // Sand ripples with pebbles scattered through them. Sampled through the
    // refraction, so the surface distorts it exactly as real shallow water
    // distorts a visible bottom.
    float bedPattern(vec2 p) {
        // Sand ripples, warped twice so they meander instead of running dead
        // straight across the pool.
        float sand = sin(p.x * 34.0 + sin(p.y * 9.0) * 2.1 + sin(p.x * 3.0) * 1.3);
        sand = sand * 0.5 + 0.5;

        // Pebbles, jittered inside their cells and skipped at random. One
        // pebble at the centre of every cell of a square grid does not read as
        // a stony bottom, it reads as polka dots. The jitter range and radius
        // are chosen so a stone stays inside its own cell, which avoids having
        // to sample the eight neighbours to catch the overlaps.
        vec2 grid = p * 22.0;
        vec2 cell = floor(grid);
        vec2 frac = fract(grid);
        float h1 = hash21(cell);
        float h2 = hash21(cell + vec2(17.3, 5.1));
        float h3 = hash21(cell + vec2(3.7, 29.2));
        vec2 centre = vec2(0.3 + h1 * 0.4, 0.3 + h2 * 0.4);
        float radius = 0.12 + h3 * 0.14;
        float present = step(0.45, h3);
        float pebble = smoothstep(radius, radius * 0.35, length(frac - centre)) * present;

        return sand * 0.45 + pebble * 0.55;
    }

    // Slow silhouettes below the surface. Never lit and never detailed — a fish
    // under water reads as a moving absence of light, and trying to draw scales
    // at this size would only produce mush.
    float shapesBelow(vec2 p, float t) {
        vec2 a = vec2(0.50 + 0.30 * sin(t * 0.21), 0.62 + 0.30 * cos(t * 0.17));
        vec2 b = vec2(0.48 + 0.33 * sin(t * 0.13 + 2.1), 0.55 + 0.32 * cos(t * 0.23 + 1.1));
        vec2 c = vec2(0.52 + 0.35 * sin(t * 0.17 + 4.2), 0.60 + 0.28 * cos(t * 0.11 + 3.3));
        float d = length((p - a) * vec2(1.0, 2.1));
        d = min(d, length((p - b) * vec2(1.9, 1.0)));
        d = min(d, length((p - c) * vec2(1.4, 1.6)));
        return smoothstep(0.15, 0.03, d);
    }

    // Sunlight coming down through the water in columns. Leaned rather than
    // vertical — shafts that run straight down the screen look like a UI
    // gradient, shafts that lean look like light entering at an angle.
    float lightShafts(vec2 uv, float t) {
        float x = uv.x + uv.y * 0.35;
        float a = sin(x * 7.0 + t * 0.19) * 0.5 + 0.5;
        float b = sin(x * 11.0 - t * 0.14 + 1.7) * 0.5 + 0.5;
        // Fades with depth, the way real shafts lose themselves in the water.
        return pow(a * b, 1.7) * clamp(1.0 - uv.y * 0.8, 0.0, 1.0);
    }

    // Curtains of colour, to be reflected in the surface rather than lit by it.
    vec3 skyCurtains(vec2 p, float t, vec3 ca, vec3 cb) {
        float a = sin(p.x * 3.1 + sin(p.y * 1.7 + t * 0.31) * 2.3 + t * 0.19);
        float b = sin(p.x * 5.3 - sin(p.y * 2.3 - t * 0.27) * 1.8 - t * 0.13);
        return ca * pow(max(a, 0.0), 3.0) + cb * pow(max(b, 0.0), 4.0) * 0.75;
    }

    void main() {
        vec2 uv = v_tex_coord;
        float aspect = u_size.y / max(u_size.x, 1.0);
        vec2 p = vec2(uv.x, uv.y * aspect);
        float t = u_now;

        float amp = u_state.x * (1.0 + u_state.y);
        // Movement does not just raise the waves, it disorders them — which is
        // what makes a shaken surface look shaken rather than merely bigger.
        float chaos = u_wave.y * (1.0 + u_state.y * 0.9);

        // Capped well below 1. Peaked crests are what breaking water looks
        // like, but sharpening *every* band drives the whole fan into a regular
        // diamond lattice that reads as lace, not sea.
        float sharp = clamp(u_wave.z * 0.55 + u_state.y * 0.10, 0.0, 0.62);

        // Stir the domain before sampling. Two octaves at unrelated scales,
        // because a single warp just translates the lattice instead of
        // dissolving it. The warp's Jacobian is ignored, so the gradient is
        // approximate here; invisible against the gain.
        vec2 wp = p
            + chaos * 0.055 * vec2(sin(p.y * 5.30 + t * 0.83),
                                   cos(p.x * 4.10 - t * 0.71))
            + chaos * 0.022 * vec2(cos(p.x * 13.7 - t * 1.51),
                                   sin(p.y * 11.3 + t * 1.27));

        // Swell, built from a fan of waves around the flow direction. Spreading
        // them rather than stacking parallel ones is what stops the surface
        // looking like corrugated iron. The low bands carry the rolling motion;
        // the high bands carry the texture that catches light. It stops at 79 —
        // finer aliases against the watch's pixel grid and reads as static.
        //
        // Only the two longest bands are sharpened. Those are the ones that
        // actually peak and break; sharpening the short ones just multiplies
        // the interference into a grid.
        vec2 f = normalize(u_flowCenter.xy + vec2(0.0001, 0.0));
        vec2 fp = vec2(-f.y, f.x);

        vec3 w = vec3(0.0);
        w += wave(wp, f,                              7.0, 0.0190 * amp,            0.42, t, sharp);
        w += wave(wp, normalize(f + 0.45 * fp),      11.0, 0.0140 * amp,            0.61, t, sharp * 0.7);
        w += wave(wp, normalize(f - 0.70 * fp),      17.0, 0.0105 * amp,            0.83, t, 0.0);
        w += wave(wp, normalize(f * 0.35 + fp),      29.0, 0.0072 * amp * u_wave.x, 1.15, t, 0.0);
        w += wave(wp, normalize(f - 1.30 * fp),      47.0, 0.0044 * amp * u_wave.x, 1.55, t, 0.0);
        w += wave(wp, normalize(f * 1.7 + 0.4 * fp), 79.0, 0.0024 * amp * u_wave.x, 2.10, t, 0.0);

        // Cross swell running against the wind. Only present when the water is
        // disordered, and it is most of why a storm looks like it is moving in
        // every direction at once rather than marching one way. Kept modest and
        // unsharpened — a strong symmetric counter-wave is exactly what builds
        // a visible crosshatch.
        w += wave(wp, -fp,                           13.0, 0.0052 * amp * chaos,    0.71, t, 0.0);
        w += wave(wp, normalize(-f + 0.37 * fp),     23.0, 0.0030 * amp * chaos,    1.02, t, 0.0);

        w += ripple(p, u_r0, t);
        w += ripple(p, u_r1, t);
        w += ripple(p, u_r2, t);
        w += ripple(p, u_r3, t);
        w += ripple(p, u_r4, t);
        w += ripple(p, u_r5, t);

        vec3 n = normalize(vec3(-w.y, -w.z, 1.0));
        float steepness = length(w.yz);

        // Looking down, most of what reaches the eye is refracted, not
        // reflected — so the bed is displaced by the surface normal.
        vec2 bed = p + n.xy * 0.055;

        // The bowl. Its centre is not fixed: tilting shifts it, so the water
        // visibly pools toward the low side instead of only changing direction.
        float edge = clamp(length(p - u_flowCenter.zw) * 1.45, 0.0, 1.0);
        float depth = edge * edge;
        vec3 col = mix(u_shallow, u_deep, depth);

        if (u_layers.x > 0.0) {
            col *= 1.0 + (bedPattern(bed) - 0.5) * 0.55 * u_layers.x;
        }

        if (u_layers.y > 0.0) {
            col *= 1.0 - shapesBelow(bed, t) * 0.72 * u_layers.y;
        }

        // Caustics reach the shallows and drown in the deep.
        float caus = caustics(bed, t * u_optics.y) * u_optics.x;
        col += u_light * caus * (1.0 - depth * 0.86) * 0.62;

        if (u_layers.z > 0.0) {
            col += u_light * lightShafts(uv, t) * 1.15 * u_layers.z;
        }

        // Relief: crests catch light, troughs fall away. Cheap, and it is most
        // of what sells the surface as three-dimensional.
        col *= 1.0 + clamp(w.x, -0.09, 0.09) * 3.2;

        // Bioluminescence: light *emitted* by disturbance rather than
        // reflected, so stirring the water makes it glow where you stirred it.
        if (u_optics.w > 0.0) {
            col += u_light * u_optics.w * smoothstep(0.05, 0.55, steepness) * 0.9;
        }

        // Sun glitter. A wide lobe turns into bright flakes sitting on top of
        // the water rather than sparks living on it, so the exponent is
        // deliberately savage and the weight low.
        vec3 L = normalize(vec3(0.34, -0.52, 0.78));
        vec3 H = normalize(L + vec3(0.0, 0.0, 1.0));
        col += u_light * pow(max(dot(n, H), 0.0), 420.0) * u_wave.w * 0.75;

        // A soft sheen where the surface tilts away, which reads as sky.
        float sheen = pow(1.0 - clamp(n.z, 0.0, 1.0), 3.4);
        col += u_light * sheen * 0.16;

        // Reflected sky. Weighted by the same grazing-angle term as the sheen,
        // so the curtains live *in* the surface and ripple with it rather than
        // floating over the top as a decal.
        if (u_layers.w > 0.0) {
            vec2 mirror = p + n.xy * 0.42;
            vec3 curtains = skyCurtains(mirror, t, u_skyA, u_skyB);
            col += curtains * u_layers.w * (0.30 + sheen * 1.8);
        }

        // Whitecaps. Real water goes white where the surface is too steep to
        // hold together, so steepness drives it directly — foam then appears
        // exactly on the breaking crests and on ripple fronts, and spreads on
        // its own when the water is thrown about.
        //
        // The threshold is high on purpose. Foam that starts too early covers
        // the whole surface in white haze, which reads as fog rather than as
        // breaking waves.
        float foam = 0.0;
        if (u_optics.z > 0.0) {
            float breaking = smoothstep(0.62, 1.15, steepness);
            foam = clamp(breaking * u_optics.z * foamTexture(p, t) * 1.4, 0.0, 1.0);
            col = mix(col, u_foam, foam);
        }

        // Lightning. It floods the surface, but it lands hardest on the foam,
        // so a strike shows you the shape of the water rather than washing the
        // screen flat.
        if (u_state.z > 0.0) {
            col += u_light * u_state.z * (0.55 + foam * 2.2 + sheen * 0.8);
        }

        // Settle the rim into darkness so the screen edge feels like depth
        // rather than a crop.
        col *= 1.0 - 0.52 * pow(edge, 2.0);

        gl_FragColor = vec4(col, 1.0);
    }
    """
}
