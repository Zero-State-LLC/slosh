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

## Verifying everything

```bash
./scripts/verify.sh            # four suites + all three app targets
./scripts/verify.sh --suites   # suites only, no Xcode required
```

The package suites cover `OceanCore` and `HydroProviders` but never compile a
line of the Watch or iPhone apps, so "the tests pass" and "the app builds" are
genuinely different claims. The script makes the second one reproducible instead
of depending on who last built locally — one machine had no iOS platform
installed at all while the iPhone target sat on `main`. A missing platform is
reported with the exact `xcodebuild -downloadPlatform` command rather than a
raw destination error.

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


## Licensing and contributions

This repository uses the Zero State Proprietary License v1.0 (ZSPL-1.0) for original Zero State materials. See [`LICENSE`](LICENSE) and [`LICENSE_POLICY.md`](LICENSE_POLICY.md).

Contributions are limited to authorized Zero State contributors and agents unless a separate written agreement is approved. Zero State may require a contributor license agreement, intellectual-property assignment, work-for-hire agreement, or other written agreement before accepting an external contribution. Do not add third-party code or assets without documenting their license and preserving required notices.
