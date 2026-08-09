# Architecture

How Slosh renders and drives water on a device that offers almost no way to
draw per-pixel.

## The platform constraint

Everything about this project follows from one measurement. Compiling trivial
sources against the watchOS SDK establishes what is actually available:

| Approach | watchOS |
|---|---|
| `Metal` framework | **Absent** — the module does not exist |
| SwiftUI `colorEffect` / `layerEffect` / `ShaderLibrary` | **Absent** — marked unavailable |
| SpriteKit `SKShader` (GLSL source) | **Works** — compiled to Metal internally |
| SwiftUI `Canvas` | Works, but draws *shapes*, not pixels |

So the water is a **SpriteKit fragment shader**. Nothing else on the platform
can produce refraction, caustics or specular glitter.

### The SpriteKit shader contract

SpriteKit translates GLSL ES to Metal. Three rules come out of that translation,
all learned from compiler errors rather than documentation. Each one fails the
same way — a plain white sprite and a single line in the device log — so they
are worth knowing before you spend an afternoon on it.

1. **Never declare uniforms in the shader source.** SpriteKit generates the
   declarations from `shader.uniforms`. Declaring them again collides with
   Metal's own `uniform<T>` template and the whole shader fails to build.

2. **No `inout` parameters.** Wave functions return a `vec3` instead: `.x` is
   the height contribution, `.yz` the gradient.

3. **At most 29 uniforms.** SpriteKit binds each uniform to its own Metal buffer
   slot; Metal allows 31, and SpriteKit already spends two on `u_time` and
   `u_path_length`. Exceeding it gives
   `'buffer' attribute parameter is out of bounds`. Scalars are therefore packed
   into vectors — `u_wave`, `u_layers`, `u_optics`, `u_state`, `u_flowCenter` —
   which took the count from 31 to 19. **Budget roughly ten more slots before
   this bites again, and pack rather than cut.**

Two more platform quirks: `SKView` does not exist on watchOS, so `didMove(to:)`
is unavailable and scene setup belongs in `didChangeSize(_:)`. And
`sceneDidLoad()` fires while the scene is still zero-sized, so anything sized
from the scene must not be built there.

## Real Water provider boundary

`OceanCore` owns geographic product identity, opaque source bindings, the
complete capability coverage model, and provider-independent Hydro values.
`HydroProviders` owns NOAA CO-OPS and USGS NWIS URLs, transports, response DTOs,
quality mapping, timestamp parsing, and unit conversion. Adding a provider does
not add its DTOs or request vocabulary to the portable engine.

The curated catalog deliberately publishes unavailable capabilities. A missing
capability is not inferred from a failed request and is never replaced with a
plausible default. Provider implementations resolve only bindings whose opaque
namespace they own.

`RoutedHydroProvider` is the application composition boundary. It selects only
routes matching a place's opaque binding namespaces, fetches matching providers
independently, tolerates partial provider failure, and merges successful states
in declared route order. The merged summary uses the oldest observation and
latest retrieval timestamps. `LiveHydroCoordinator` then applies its existing
per-place throttle and cache policy to that composed provider.

`PlaceHydroStatusResolver` is the presentation boundary. It combines catalog
coverage with an optional provider-independent `HydroState` at an explicit
reference date. SwiftUI consumes only that status, never NOAA or USGS DTOs.
Signal freshness delegates to `HydroInterpreter`'s authoritative predicate.
The watch coordinator scopes load state and result application by canonical
`WaterBody.id` and request generation, so cancellation races cannot display one
Place's status or forcing after another Place becomes active, or let an older
activation overwrite a newer request for the same Place.

## Rendering

### Physical validation instrumentation

`FrameRateMonitor` is pure `OceanCore` logic. `WaterScene` supplies SpriteKit
update timestamps and exposes an optional aggregate diagnostic callback; it does
not own a timer or log per frame. The callback is nil in normal operation.

The watch target installs `PhysicalValidationDiagnostics` only in `DEBUG` when
`-physicalValidation YES` is present. It combines the renderer aggregate with
raw/crown-corrected motion, public wrist/crown settings, battery, thermal,
lifecycle, and haptic events in OSLog. Deterministic routes select Calm ocean,
Breaking surf, Storm at night, or the existing live San Francisco Bay provider
path. None of these routes changes `SurfaceDriver`, shader parameters, or Hydro
interpretation, and the diagnostics activation code is absent from Release.

Lifecycle resume resets both the renderer's existing `lastUpdate` boundary and
the frame monitor boundary. Background time therefore cannot become a fake slow
frame or giant simulation step. The canonical execution contract and artifact
format live in [PHYSICAL_WATCH_VALIDATION.md](PHYSICAL_WATCH_VALIDATION.md).

Everything visible derives from **one analytic height field**, evaluated per
pixel. There is no simulation grid and no state between frames.

The field is a fan of six directional waves spread around the current flow
direction, two cross-swell waves that appear only when the water is disordered,
and up to six expanding ripples. Each wave returns its height **and its analytic
gradient** from the same call, so the surface normal is exact and essentially
free — no neighbour sampling, no finite differences.

Spreading the waves around the flow direction rather than stacking them parallel
is what stops the surface looking like corrugated iron. Low bands carry the
rolling motion you read as movement; high bands carry the texture that catches
light. The series stops at frequency 79 — finer aliases against the watch's
pixel grid and reads as static.

From the normal, in order:

1. **Refraction** — the bed is sampled at a position displaced by the normal.
2. **Bed texture** *(optional)* — sand ripples and pebbles, seen through that
   refraction.
3. **Shadows** *(optional)* — silhouettes moving below.
4. **Caustics** — the light web on the bed. Light converges along the **zero
   crossings** of an interference field, not at its peaks, so the shader takes
   `1 − |field|` and raises it hard. That single choice is the difference
   between a connected web and scattered flakes. Three sine waves rather than
   two (two make a grid, three make a mesh), each octave rotated so nothing
   aligns with the pixel axes and domain-warped so the filaments curve.
5. **Light shafts** *(optional)* — leaned, not vertical; vertical shafts read as
   a UI gradient.
6. **Depth** — a bowl, shallow at its centre and dark at the rim. The centre
   moves with tilt, so water visibly pools toward the low side.
7. **Relief** — crests brightened and troughs darkened straight from the height.
   Cheap, and most of what sells the surface as three-dimensional.
8. **Glow** *(optional)* — light *emitted* by disturbance. Bioluminescence.
9. **Glitter** — a specular lobe with a deliberately savage exponent. A wide
   lobe produces bright flakes sitting *on top of* the water rather than sparks
   living *on* it.
10. **Sheen**, then **reflected sky** *(optional)* — the sky is weighted by the
    same grazing-angle term as the sheen, so curtains live *in* the surface and
    ripple with it instead of floating over the top as a decal.
11. **Foam** *(optional)* — keyed off surface steepness, so whitecaps land
    exactly where the surface is too steep to hold together.
12. **Lightning** *(optional)* — lands hardest on the foam, so a strike reveals
    the shape of the water rather than washing the screen flat.
13. **Vignette**.

Optional layers sit behind `if` tests on uniforms. Uniform branches are coherent
across the whole draw, so a mode that leaves a feature off does not pay for it.

## Motion

`SurfaceDriver` is plain Swift with no platform imports, which is why it can be
tested. It turns device motion into what the shader consumes:

- **Flow direction** — where the swell travels. Chases gravity, low-passed so it
  feels like water finding its level rather than a compass needle. Stored as an
  **angle, not a vector**: interpolating a vector and renormalising it each step
  cancels the interpolation, and a 180° reversal collapses through zero length.
  An angle sweeps around the short way.
- **Surge** — extra amplitude *and disorder* from recent movement, decaying
  back down. Movement does not simply raise the waves; it disorders them, which
  is what makes a shaken surface look shaken rather than merely bigger.
- **Bowl centre** — deliberately lagging the heading. A centre of mass that
  snaps in one frame reads as a bug.
- **Ripples** — six slots, oldest recycled. Taps spawn one where you touched; a
  hard jolt spawns one just off the edge the motion came from so the wave washes
  *across* the screen; rain spawns them from nothing. Jolt ripples are
  rate-limited or a sustained shake smears them into noise.
- **Lightning** — irregular by design. A metronome is maddening over minutes.

With the watch flat there is no in-plane gravity at all, so the swell holds its
last heading rather than snapping to whatever the noise says.

## Particles

`ParticleField` is a fixed pool of `SKShapeNode`s, not `SKEmitterNode`. An
emitter without a texture draws squares, and building a texture on watchOS means
going through UIKit image rendering for no benefit. A pool is predictable,
capped, and free when idle.

Two behaviours: **spray** bursts outward from a break and slows (seen from
above, thrown water does not arc), and **drift** sinks slowly from top to bottom
as marine snow, fading in and out at both ends so it never pops into existence
mid-screen.

## Module boundaries

```
OceanCore   motion, modes, driver     no UI framework — runs anywhere Swift does
OceanUI     shader, scene, particles  SpriteKit + SwiftUI, shared across platforms
Slosh       the watchOS app           CoreMotion, WatchKit, app lifecycle
```

The split is what allowed the engine to be developed and verified before the
build toolchain was usable, and it is what makes an iOS port a host change
rather than a rewrite. Nothing in `OceanCore` imports SwiftUI, SpriteKit,
CoreMotion or WatchKit.

## Performance

Untested on hardware — see [ROADMAP.md](ROADMAP.md#phase-0--hardware-validation).

Cost is dominated by the fragment shader over roughly 206k pixels. Breaking surf
and Storm at night are by a wide margin the most expensive modes: eight wave
bands, two domain-warp octaves, foam texturing, six ripples, and particles.

If frame rate needs to come down, in increasing order of visual damage:

1. Drop the highest wave band (frequency 79).
2. Drop the second caustic octave.
3. Reduce ripple slots from six to four (costs rain its density).
4. Render at reduced scale and let it upsample — water hides softness well.
