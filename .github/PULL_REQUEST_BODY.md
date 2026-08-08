## What this is

An Apple Watch app that renders live, interactive water: you look straight down
into it, tilt to make the swell roll, shake to stir it and break it into foam,
tap to send a ripple. Fifteen modes, each a different substance rather than a
different palette.

| Calm ocean | Breaking surf | Rain shower |
|---|---|---|
| ![calm](media/calm-ocean.gif) | ![surf](media/breaking-surf.gif) | ![rain](media/rain-shower.gif) |

| Under ice | Aurora | Storm at night |
|---|---|---|
| ![ice](media/under-ice.gif) | ![aurora](media/aurora.gif) | ![storm](media/storm-at-night.gif) |

All captured live from the watchOS simulator.

## The interesting part

**watchOS gives third-party apps almost no way to draw per-pixel.** Measured by
compiling against the SDK rather than assumed:

| | watchOS |
|---|---|
| `Metal` | absent — no module |
| SwiftUI `colorEffect` / `layerEffect` | absent — marked unavailable |
| SpriteKit `SKShader` | **works** — GLSL compiled to Metal internally |
| SwiftUI `Canvas` | works, but draws shapes not pixels |

So the water is a SpriteKit fragment shader. Everything visible comes from **one
analytic height field** — each wave returns its own gradient alongside its
height, so the surface normal is exact and effectively free, and refraction,
caustics, glitter and foam all fall out of it. No simulation grid, no state
between frames.

Three rules govern SpriteKit's GLSL→Metal translation, all learned from compiler
errors and all failing identically as a **plain white screen**: uniforms must not
be declared in the source, `inout` parameters are unsupported, and there is a
hard ceiling of 29 uniforms because each is bound to its own Metal buffer slot.
Documented in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md#the-spritekit-shader-contract).

## Review guide

Start with [`docs/DECISIONS.md`](docs/DECISIONS.md) — it covers the calls worth
arguing with, including a full renderer rewrite. Then:

- `OceanCore/Sources/OceanUI/WaterShader.swift` — the shader; the caustics
  function is the one bit of real cleverness
- `OceanCore/Sources/OceanCore/SurfaceDriver.swift` — motion → water, and the
  only tested logic
- `OceanCore/Sources/oceancheck/main.swift` — 340 assertions

Skim the rest.

## An earlier version was built and thrown away

The first implementation rendered a side-on cross-section — a waterline with sky
above and water below, over a 1-D spring heightfield. It had 276 passing
assertions and behaved exactly as specified. It was still wrong: it read as a
line animation, not as water, and no amount of polish fixes a framing problem.

Kept in [`docs/DECISIONS.md`](docs/DECISIONS.md#1-the-side-on-renderer-was-built-then-thrown-away)
because the reason is more useful than the code was.

## Testing

```bash
cd OceanCore && swift run oceancheck   # 340 assertions, no Xcode needed
```

Written as a plain executable rather than XCTest, which ships only inside Xcode
— this runs anywhere the Swift toolchain does.

Some checks defend the product rather than the code: that restful modes stay
restful, that a violent mode answers the wrist harder than a calm one, and that
**every mode actually has the feature it exists for**. A mode whose defining
feature is off is a recolour of another mode, so the catalogue is tested against
its own premise.

## Status — please read before approving

**This has never run on physical hardware.** It builds, installs and runs on the
watchOS simulator, and every mode renders. Two things need a real watch and
either could force rework:

1. **Tilt axis and sign.** The mapping from gravity to swell direction has never
   met a real wrist. If the water rolls uphill it is a one-line fix —
   `SurfaceDriver`'s `atan2(gx, -gy)` is deliberately the only place it is
   decided — but it must be checked, including for left-crown wearers.
2. **Frame rate and battery.** A per-pixel shader over ~206k pixels is the
   genuine risk here, and the simulator runs on a Mac GPU so it tells us
   nothing. Breaking surf and Storm at night are by far the most expensive.

Both are [ROADMAP.md Phase 0](docs/ROADMAP.md#phase-0--hardware-validation),
which blocks everything else.

## Commercial view

[docs/ECONOMICS.md](docs/ECONOMICS.md) is deliberately unflattering. Short
version: watch-only distribution is structurally poor, the category is crowded
and subscription-led, and a realistic unpromoted launch is tens to low hundreds
of downloads. The recommendation is **iOS-first for discovery, a single $2.99
unlock, a genuinely good free tier, and no expectation that it pays for
itself** — build it because the engineering is the valuable output.

## Not included

App icon, real bundle identifier, accessibility labels, and any monetisation.
All tracked in [ROADMAP.md](docs/ROADMAP.md) Phase 1 onward.
