# Decisions

The load-bearing calls, and what they cost. Written so the next person does not
repeat the dead ends — including a full rewrite.

---

## 1. The side-on renderer was built, then thrown away

**Decision:** replace a working, well-tested renderer entirely.

The first version drew a **cross-section**: a wiggling waterline with sky above
and water below, rendered with SwiftUI `Canvas` over a 1-D spring heightfield.
It had 276 passing assertions and behaved correctly.

It was still wrong. It read as a line animation rather than as water. The
premise — a pocket ocean you look *into* — was not served by a side view at any
level of polish, and no amount of tuning was going to fix a framing problem.

**Cost:** the entire simulation, renderer and test suite. **Kept:** the module
boundaries, the motion abstraction, and the discipline of testing the driver.

**Lesson worth generalising:** the side-on version was verified against its spec
and passed. What it was never checked against was whether the spec was the right
one. Put something on screen early and look at it.

---

## 2. SpriteKit `SKShader`, because nothing else exists

**Decision:** render with a GLSL fragment shader through SpriteKit.

Measured, not assumed — compiling against the watchOS SDK shows `Metal` has no
module and SwiftUI's shader effects are marked unavailable. `SKShader` compiles
to Metal internally and works.

**Consequence:** the three-rule contract in
[ARCHITECTURE.md](ARCHITECTURE.md#the-spritekit-shader-contract). Every one of
them fails as a plain white sprite with a single line in the device log, which
is a genuinely bad failure mode — it looks like a layout bug.

---

## 3. One analytic height field, no simulation grid

**Decision:** compute the surface per-pixel from a sum of waves rather than
simulating a grid and sampling it.

A grid would need state between frames, a texture to hold it, and a way to get
that texture into the shader. The analytic approach is stateless, has no
resolution, and — crucially — gives the **exact gradient for free**, because
each wave returns its own derivative alongside its height. The surface normal
drives refraction, caustics, glitter and foam, so getting it exactly and cheaply
is worth more than physical accuracy.

**Trade-off:** waves cannot interact with each other or with geometry. Nothing
in the product needs them to.

---

## 4. Caustics from zero crossings, not peaks

**Decision:** compute caustics as `pow(1 − |field|, k)` rather than
`max(field, 0)`.

Light converges along the **zero crossings** of an interference field. Finding
peaks instead gives scattered flakes; finding zero crossings gives a connected
web. This is the single change that took the render from "fog" to "swimming
pool", and it took three attempts to get there:

1. Two axis-aligned sine waves, sharpened → **city blocks**. A
   `sin(x) · sin(y)` field is a grid, and sharpening a grid makes it obvious.
2. Rotated and domain-warped, still peak-finding → **scattered flakes**. Better,
   but not connected.
3. Three waves, rotated, warped, zero-crossing → **a web**.

Three waves rather than two, because two make a grid and three make a mesh.

---

## 5. Modes are behaviour, not palettes

**Decision:** a mode carries physics as well as colour — turbulence, crest
sharpness, foam, motion gain, rain rate, lightning, and whether it obeys gravity
at all.

The alternative, colour schemes over one water, is much less work and much less
interesting. Switching from Calm ocean to Breaking surf should change the
substance.

This is enforced in the test suite rather than by convention: there are checks
that the restful modes stay restful, that a violent mode answers the wrist
harder than a calm one, and that **every mode actually has the feature it exists
for**. A mode whose defining feature is off is a recolour of another mode.

Every field defaults to off, so adding a mode means declaring only what makes it
different, and expensive layers sit behind uniform branches so a mode that
leaves a feature off does not pay for it.

---

## 6. Uniforms packed into vectors

**Decision:** pack scalars into `vec4`s rather than one uniform per parameter.

Forced, not chosen. SpriteKit binds each uniform to its own Metal buffer slot
and Metal allows 31, two of which SpriteKit already spends. At 31 uniforms every
shader compile failed.

Packing took the count from 31 to 19 and costs nothing at runtime. It does cost
readability — `u_wave.z` is worse than `u_sharpness` — which is why
`WaterShader.uniformNames` documents the layout inline.

---

## 7. The engine is a Swift package, extracted immediately

**Decision:** put physics and modes in `OceanCore` with no UI framework, from
day one, rather than extracting later.

Originally planned as a final step. Pulled forward because the machine had an
unusable Xcode at the time, and a package with no UI imports could still be
built, tested and — via a macOS render harness — *looked at*. That turned a hard
block into an afternoon of progress.

It also makes the iOS port a host change rather than a rewrite, which is the
whole commercial argument in [ECONOMICS.md](ECONOMICS.md).

---

## 8. Tests as an executable, not XCTest

**Decision:** the suite is a plain `swift run oceancheck` executable.

XCTest ships only inside Xcode. A plain executable runs anywhere the Swift
toolchain does — CI images without Xcode, and the machine this started on. The
harness is about eighty lines.

**Trade-off:** no Xcode test navigator integration, no code coverage tooling. For
a suite that is entirely pure-Swift assertions over a driver, that is a fair
trade.

---

## 9. A particle pool, not `SKEmitterNode`

**Decision:** hand-rolled pool of `SKShapeNode`s.

An emitter without a texture draws squares, and creating a texture on watchOS
means going through UIKit image rendering to get a soft dot. A fixed pool is
predictable, hard-capped, and costs nothing when idle.

---

## 10. Simulator input is a first-class feature

**Decision:** `SimulatedMotionProvider` and debug launch flags ship in the debug
build rather than being scratch code.

The watch simulator has **no motion sensors at all** and no way to script a tap.
Without a drag-to-tilt fallback the app is untestable outside a physical device;
without `-startInPicker` the entire theme picker can only be checked by hand.
These are load-bearing, not conveniences.

Compiled out on real hardware so the drag gesture can never shadow a system edge
swipe.
