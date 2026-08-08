# Contributing

## Setup

Requires Xcode with the watchOS platform installed:

```bash
xcodebuild -downloadPlatform watchOS
```

Then open `Slosh/Slosh.xcodeproj`, or build from the command line:

```bash
xcodebuild -scheme "Slosh Watch App" \
  -destination "id=$(xcrun simctl list devices available | grep -m1 'Apple Watch' | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')" \
  -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

The engine builds without Xcode at all:

```bash
cd OceanCore && swift build && swift run oceancheck
```

## Before opening a pull request

1. `swift run oceancheck` passes.
2. The app builds for the watch simulator.
3. **You have looked at it.** This is a visual project; a change that compiles
   and passes is not a change that works. Attach a capture for anything that
   alters the render:
   ```bash
   xcrun simctl io <udid> screenshot shot.png
   ```

## Conventions

**Module boundaries are load-bearing.** `OceanCore` imports no UI framework —
not SwiftUI, not SpriteKit, not CoreMotion, not WatchKit. This is what lets the
engine be tested anywhere and ported without a rewrite. A UI import in
`OceanCore` should fail review.

**Comments explain constraints, not mechanics.** Most non-obvious code here is
non-obvious for a reason that is invisible locally — a platform limit, a visual
failure mode, a numerical trap. Write those down. Do not narrate what the next
line does.

Good:
```swift
// Stored as an angle rather than a vector: interpolating a vector and
// renormalising it every step cancels the interpolation, and a 180° reversal
// collapses through zero length.
```

Noise:
```swift
// Convert the heading to a vector
```

**Tests defend the product, not just the code.** Alongside the numerical checks,
the suite asserts that restful modes are restful, that violent modes answer the
wrist harder, and that every mode has the feature it exists for. If you add a
mode, add the check that proves it is not a recolour.

**Shader changes carry extra risk.** A mistake usually shows as a *plain white
screen*, because SpriteKit falls back to the bare sprite when compilation fails.
The reason is always in the device log:

```bash
xcrun simctl spawn <udid> log show --last 2m \
  --predicate 'processImagePath CONTAINS "Slosh"' | grep -A5 "SKShader failed"
```

Read [ARCHITECTURE.md](docs/ARCHITECTURE.md#the-spritekit-shader-contract)
before touching `WaterShader`. The three rules there are not style preferences;
each one is a build failure.

## Commits

Present tense, explaining the why when it is not obvious:

```
Freeze the caustic clock to make Under ice

Zero time-scale turns the same cell network from moving light into a
static fracture pattern, which is the entire mode.
```

## Adding a mode

See [MODES.md](docs/MODES.md#adding-a-mode).
