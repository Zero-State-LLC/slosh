# Physical Apple Watch Validation

This document is the Phase 0 execution contract. Physical evidence is the gate.
Simulator motion, simulator FPS, and successful compilation are readiness evidence
only. They cannot pass a physical test.

## Current execution status

```text
physical execution: NOT_RUN
reason: no accessible paired physical Apple Watch available to this validation session
```

Run evidence belongs under `out/physical-watch-validation/`, which is ignored.
Canonical criteria stay in this document. Do not commit volatile logs unless a
review explicitly requests a stable evidence snapshot.

## Acceptance rule

A test passes only when its stated observation and metrics are recorded on a
physical Watch. Visual direction and haptic comfort require human inspection.
Use `NOT_COMPUTABLE` when a public API does not expose a value. Never substitute a
simulator or an invented proxy.

## Supported configurations and expected low side

watchOS reports wrist and crown settings through `WKInterfaceDevice`. The app
re-reads crown orientation while motion runs. Crown-left applies the existing
single 180-degree axis correction in `WatchMotionProvider`; `SurfaceDriver`
remains the only gravity-to-heading mapping.

| Configuration | Screen-right low | Screen-left low | Screen-top low | Screen-bottom low |
|---|---|---|---|---|
| Left wrist, crown right | water moves right | water moves left | water moves top | water moves bottom |
| Left wrist, crown left | water moves right | water moves left | water moves top | water moves bottom |
| Right wrist, crown right | water moves right | water moves left | water moves top | water moves bottom |
| Right wrist, crown left | water moves right | water moves left | water moves top | water moves bottom |

The expected behavior is physical screen direction, not a particular raw gravity
sign. Record signs, then judge the rendered low-side response.

## DEBUG validation mode

The diagnostics route is compiled only with `DEBUG`. It does not alter physics,
shader parameters, Hydro interpretation, provider bindings, or Release behavior.
It is enabled with:

```text
-physicalValidation YES
-validationRoute <route>
```

Routes are deterministic:

| Route | Product state | Purpose |
|---|---|---|
| `calm` | Calm ocean | low-cost baseline |
| `breaking-surf` | Breaking surf | high interaction and particles |
| `storm-at-night` | Storm at night | worst authored shader cost |
| `san-francisco-bay` | live San Francisco Bay on Calm ocean | network + Hydro + dynamic forcing |

San Francisco Bay uses the existing `RoutedHydroProvider.liveCurated()` path.
The route is not a fixture. Debug fixture/failure machinery remains simulator-only.
Normal persisted Place selection can already use live providers on device.

## Instrumentation contract

`WaterScene.update(_:)` feeds a pure `FrameRateMonitor` using SpriteKit update
timestamps. When validation mode is active, one aggregate OSLog line is emitted
at most every five seconds. No frame is logged individually.

Each line includes:

- raw CoreMotion gravity X/Y before crown correction;
- corrected gravity X/Y consumed by `SurfaceDriver`;
- in-plane magnitude `sqrt(gx² + gy²)`;
- `SurfaceDriver.heading`;
- resulting `flowX = sin(heading)` and `flowY = cos(heading)`;
- reported crown orientation and wrist location;
- instantaneous, two-second rolling, average, and minimum rolling FPS;
- slow-frame count, observed frame count, and measured duration;
- public thermal state;
- battery percentage when watchOS reports it.

Lifecycle and haptic events are separate OSLog records. Haptic records distinguish
played, disabled, absent, and rate-limited attempts. Human comfort remains a
manual observation.

### FPS calculation

For positive consecutive update timestamp differences `dt`:

```text
instantaneous FPS = 1 / dt
rolling FPS       = rolling frame count / sum(dt in last 2 seconds)
average FPS       = all observed frame count / sum(all observed dt)
minimum FPS       = minimum valid rolling FPS observed
```

The requested target remains 60 FPS. Report these four fields after physical use:

| Requested target | Actual platform ceiling | Measured result | Recommended acceptance threshold |
|---|---|---|---|
| 60 FPS | NOT_MEASURED | NOT_RUN | Keep 60 until device evidence supports a change |

Do not change `docs/ROADMAP.md` merely because a Watch schedules below 60 FPS.
First record repeatable platform evidence, device model, watchOS, and scenario.

### Slow-frame rule

The centralized rule is:

```text
target interval = 1 / 60 seconds
slow frame      = observed dt > target interval × 1.5
                = observed dt > 25 milliseconds
```

The comparison is strict. Resume/background gaps are excluded by resetting the
measurement boundary when `WaterScene.resume()` resets its render timestamp.
A single transition frame is not interpreted as renderer failure.

## Preparation and exact commands

From the repository root:

```bash
./scripts/prepare-watch-validation.sh
```

This verifies tools, lists devices, creates timestamped JSON/Markdown templates,
and performs an unsigned generic Debug watchOS build. It does not claim to move a
wrist or configure signing.

Software validation:

```bash
cd OceanCore
swift run oceancheck
swift run hydrocheck
swift run providercheck
swift run providercheck --live
swift build
cd ..

xcodebuild -project Slosh/Slosh.xcodeproj \
  -scheme "Slosh Watch App" \
  -configuration Debug \
  -destination "generic/platform=watchOS Simulator" \
  CODE_SIGNING_ALLOWED=NO build

xcodebuild -project Slosh/Slosh.xcodeproj \
  -scheme "Slosh Watch App" \
  -configuration Release \
  -destination "generic/platform=watchOS Simulator" \
  CODE_SIGNING_ALLOWED=NO build
```

List physical destinations:

```bash
xcrun xctrace list devices
xcodebuild -project Slosh/Slosh.xcodeproj \
  -scheme "Slosh Watch App" -showdestinations
```

The current scheme is `Slosh Watch App`; the current bundle identifier is the
placeholder `com.example.Slosh.watchkitapp`. For a real run, open
`Slosh/Slosh.xcodeproj`, select the paired physical Watch destination, select the
Debug configuration, and use the developer team already authorized for that
machine. Do not make unrelated team, certificate, or bundle-ID changes as part of
measurement readiness.

In **Product > Scheme > Edit Scheme > Run > Arguments**, add:

```text
-physicalValidation YES
-validationRoute calm
```

Replace the route for each scenario. Xcode passes these argument pairs into
`UserDefaults`, matching the repository's existing debug launch convention.
Build/run from Xcode so signing and Watch installation use the selected account.

### Capture logs

On the paired Mac, open Console, select the Watch, start streaming, and filter:

```text
subsystem: com.example.Slosh.watchkitapp
category: PhysicalValidation
```

Save the stream in the run directory. Also retain the existing `RealWater`
category for provider lifecycle evidence. Record screenshots or video with
Xcode's device controls or QuickTime/paired-device tooling available on the test
machine. Record the exact capture method in notes.

## Test matrix

### DIR-1 through DIR-4: rendered direction

Repeat for all four wrist/crown configurations. In Calm, hold each physical tilt
long enough for the deliberately smoothed heading to settle.

| Configuration | Physical tilt | Raw gravity X/Y | Corrected X/Y | Computed heading | Observed water direction | Result |
|---|---|---|---|---|---|---|
| Left/crown right | right, left, top, bottom | | | | HUMAN REVIEW | NOT_RUN |
| Left/crown left | right, left, top, bottom | | | | HUMAN REVIEW | NOT_RUN |
| Right/crown right | right, left, top, bottom | | | | HUMAN REVIEW | NOT_RUN |
| Right/crown left | right, left, top, bottom | | | | HUMAN REVIEW | NOT_RUN |

Pass only if rendered water and pooling follow the physical low side in every
case. If correction is needed, keep it in the current centralized axis/mapping
boundary and add a reproducible test. Do not scatter signs through UI or shader.

### Performance scenarios

Use bright foreground state, fixed crown energy, no deliberate interaction after
the initial setup, and five uninterrupted minutes per scenario.

| ID | Route | Duration | Record | Result |
|---|---|---:|---|---|
| PERF-1 | `calm` | 5 min | avg/min rolling FPS, slow frames, thermal, battery delta | NOT_RUN |
| PERF-2 | `breaking-surf` | 5 min | same | NOT_RUN |
| PERF-3 | `storm-at-night` | 5 min | same; critical worst case | NOT_RUN |
| PERF-4 | `san-francisco-bay` | 5 min | same plus fetch outcome; compare PERF-1 | NOT_RUN |

Record any Instruments configuration separately. Simulator FPS is never entered
in these rows.

### Battery protocol

Battery percentage is coarse. Record exactly what watchOS shows and do not infer
fractional precision. Prefer identical starting charge bands, brightness, Always-
On state, and ambient conditions. Repeat sessions if a 10-minute run shows no
resolvable percentage change.

| ID | Route | Duration | Battery before | Start | Screen state | Battery after | Result |
|---|---|---:|---:|---|---|---:|---|
| BAT-1 | `calm` | 10 min | | | bright foreground | | NOT_RUN |
| BAT-2 | `storm-at-night` | 10 min | | | bright foreground | | NOT_RUN |
| BAT-3 | `san-francisco-bay` | 10 min | | | bright foreground | | NOT_RUN |

Report thermal state transitions as `nominal`, `fair`, `serious`, or `critical`.
If the public API returns no usable value, record `NOT_COMPUTABLE`.

### LIFE-1: lifecycle and Always-On

Execute and correlate visual behavior with lifecycle log records:

1. Foreground + bright: rendering and motion active; Real Water may fetch.
2. Luminance reduced/Always-On: expensive work stops exactly as current code
   intends; static frame remains intentional.
3. Background: rendering paused, motion stopped, active provider task cancelled.
4. Foreground again: motion/rendering restart, provider can retry, no giant-dt
   lurch, and no false ten-minute throttle caused by cancellation.
5. During a Real Water fetch, repeat background, dim, and resume transitions.

Pass only with clean visual resume and matching logs. Existing `WaterScene.resume`
resets frame timing, and `RealWaterAppCoordinator.deactivate` cancels its task.
Do not redesign those paths without contrary device evidence.

### HAPTIC-1

Test Calm ocean, Breaking surf, Storm at night, and one additional mode with a
distinct `HapticKind`. Tap/trigger comparable events.

| Mode | OBSERVED event/triggers/rate | Fires as expected? | HUMAN REVIEW comfort/annoyance | Missed/repetitive events | Result |
|---|---|---|---|---|---|
| Calm ocean | | | | | NOT_RUN |
| Breaking surf | | | | | NOT_RUN |
| Storm at night | | | | | NOT_RUN |
| Additional distinct mode | | | | | NOT_RUN |

Do not turn comfort into a fabricated numeric score.

## Report schema

`PhysicalWatchValidationReport` provides the reusable Codable form. The preparation
script creates an operational template with the same core fields:

```json
{
  "device": "Apple Watch model",
  "watchOS": "version",
  "configuration": "left-wrist-crown-right",
  "generatedAt": "RFC3339 timestamp",
  "tests": [{
    "id": "PERF-1",
    "startTime": "RFC3339 timestamp",
    "durationSeconds": 300,
    "modeOrPlace": "Calm ocean",
    "observations": [],
    "metrics": {},
    "result": "PASS | FAIL | NOT_RUN | NOT_COMPUTABLE",
    "notes": ""
  }]
}
```

## Completion decision

P0A readiness is complete when instrumentation, runbook, report format, privacy
audit, pure tests, and Debug/Release builds pass. Phase 0 itself remains open until
physical results exist.

- Physical Watch available and passes: next slice is **P0B, evidence-backed device
  fixes only, then close Phase 0**.
- No accessible physical Watch: next software slice may be **RW4A, iPhone curated
  Places browser foundation**, but Phase 0 stays explicitly unresolved.
