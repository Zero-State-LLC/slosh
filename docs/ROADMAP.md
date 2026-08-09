# Roadmap

From "runs on a simulator" to "on the App Store". Phases are ordered by risk:
each one can invalidate the ones after it, so they should not be reordered for
convenience.

Nothing here is scheduled. Effort estimates assume one person working part-time.

---

## Phase 0 — Hardware validation

**Blocks everything. Nothing else should start until this is done.**

The app has never run on a physical watch. Two unknowns could each force
significant rework, and no amount of simulator work reduces either.

### 0.1 Tilt axis and sign

The relationship between CoreMotion's gravity vector and the direction the swell
should travel has never been checked against a real wrist. If the water rolls
uphill, the fix is one line — `SurfaceDriver`'s `atan2(gx, -gy)` is deliberately
the only place the mapping is decided — but it must be *checked*, and checked in
all four watch orientations.

Left-crown wearers are handled separately in `WatchMotionProvider`, since that
rotates the screen 180°. Also untested.

**Done when:** the swell rolls toward the low side, on both wrists, with the
crown on either side.

### 0.2 Frame rate and battery

A per-pixel fragment shader over ~206k pixels is the genuine technical risk on
this platform. The simulator says nothing useful about it — it runs on a Mac GPU.

Profile in Instruments on the **oldest device you intend to support**, in
Breaking surf and Storm at night, which are by a wide margin the most expensive
modes.

If it needs to come down, in increasing order of visual damage: drop the highest
wave band, drop the second caustic octave, reduce ripple slots from six to four,
then render at reduced scale.

Separately, measure battery over a ten-minute session. Sensors and rendering
already stop when the app is not frontmost and when the screen dims, but that
has never been confirmed against a real battery.

**Done when:** a sustained 60 fps in the worst mode on the oldest target, and a
ten-minute session with no alarming drain.

### 0.3 Haptics

Unverifiable off-device by definition. Confirm the per-mode haptics fire on
breaking water and are not annoying at the rate limit.

---

## Phase 1 — Make it a product

Everything here is invisible in the simulator but required for a real app.

- **App icon.** Currently an empty asset catalogue. A watch icon is a single
  1024×1024 image, but it has to read at ~30px.
- **Bundle identifier and team.** `com.example.Slosh.watchkitapp` is a
  placeholder and must change before anything can be signed.
- **Onboarding, or a deliberate absence of it.** Launching straight into water
  is correct; the water-drop toolbar button is the only affordance and may not
  be discoverable. Consider a one-time hint on first launch.
- **Accessibility.** The picker needs VoiceOver labels; the ocean itself needs a
  meaningful accessibility description. Also check the modes against Reduce
  Motion — a mode that ignores it is a rejection risk as well as a bad
  experience.
- **Always-On behaviour.** A static frame is drawn when the screen dims. Confirm
  it looks intentional rather than broken.
- **Persistence check.** `@AppStorage` round-trips have only been verified in a
  simulator that was never power-cycled.

---

## Phase 2 — iPhone and iPad

**Where the actual audience is.** See
[ECONOMICS.md](ECONOMICS.md#1-ship-iphone-and-ipad-not-just-the-watch) — watch-only
distribution is the central commercial problem, and this is the fix.

`OceanCore` and `OceanUI` port unchanged. The work is:

- An iOS app target and a host view.
- Raise the ripple slots — a phone screen invites multi-touch, and six is thin
  for it. Watch the uniform ceiling (see
  [ARCHITECTURE.md](ARCHITECTURE.md#the-spritekit-shader-contract)); pack rather
  than cut.
- **Optionally, a much better renderer.** iOS has real Metal *and* SwiftUI
  shader effects, both absent on watchOS. Depth of field, proper foam, real sky
  reflection and screen-space refraction all become available. The watch version
  stays as-is.
- iPhone StandBy landscape mode — a phone on a charger showing this is a strong
  use case and needs almost no new work.
- Universal purchase so one unlock covers every device.

---

## Phase 3 — Monetisation

Only after Phase 2, because monetising watch-only traffic is not worth the
implementation cost.

- StoreKit 2, a single non-consumable unlock.
- Free/paid split as proposed in
  [ECONOMICS.md](ECONOMICS.md#3-give-away-a-genuinely-good-free-tier).
- **Restore purchases** — required by App Review, and the most common rejection
  reason for a first IAP submission.
- Test with StoreKit configuration files locally, then sandbox accounts.

---

## Phase 4 — Submission

- **Guideline 4.2 (minimum functionality) is the real risk.** An ambient app
  with no obvious utility can be read as "not enough". Mitigate by shipping
  iOS + watchOS together, listing the modes explicitly in the description, and
  making the screenshots do the arguing.
- Privacy submission position: no analytics SDK, user account, behavioral
  tracking, user-profile backend, or analytics identifier exists. Real Water
  performs requests to configured public environmental-data providers. The
  final nutrition label and transport disclosures must be verified against the
  shipping provider set at submission time; do not claim "no network calls."
- Motion sensor usage needs no permission string — device motion is not gated
  the way the activity and pedometer APIs are — but confirm this at submission
  time rather than trusting it.
- Screenshots and an App Preview video for every required size. The preview
  video matters more than the screenshots here; still images undersell moving
  water badly.
- Support URL and a marketing page. A single static page is enough.

---

## Phase 5 — After launch

Only worth doing if Phase 4 shows any traction.

- **More modes.** The mode system is designed so a new one declares only what
  makes it different; see [MODES.md](MODES.md#adding-a-mode). Unbuilt ideas are
  listed there.
- **Complications** to launch the app from a watch face. Cannot render water —
  complications are static — but a good entry point.
- **Sunrise mode**, one palette that tracks real time of day.
- **Rain on glass**, the one idea the height-field approach cannot already
  express and which would need a genuinely different simulation.

---

## Future track — Real Water

This track does not weaken **Phase 0**. Physical-watch validation remains the
blocking platform-risk gate, and no network-backed product work should be used
to defer it. The phases below are planned, not shipped, and begin only after the
relevant product foundation is sound.

### RW1 — Hydro foundation

- Establish provider-independent `HydroState`, normalized environmental forcing,
  provenance, freshness, deterministic fixtures, and a perceptual interpreter.
- Keep provider DTOs, networking, UI frameworks, and shader changes outside the
  portable translation contract.

### RW2 — San Francisco Bay vertical slice

- **RW2A foundation complete:** normalized environmental forcing integrates into
  `SurfaceDriver` as a bounded persistent baseline; wrist gravity temporarily
  owns direction, shake remains transient, direction conventions are canonical,
  suspect measurements are ignored, and future clock skew is bounded.
- **RW2A.5 visual wiring complete:** synthetic Hydro theme modifiers resolve
  against an immutable authored theme and reach the existing packed shader
  uniforms. Debug simulator fixtures provide calm/active/severe comparison on
  one Calm ocean base without adding shader uniforms.
- **RW2B live debug vertical slice complete:** the curated San Francisco Bay
  entry combines NOAA CO-OPS water level, wind, and air pressure from `9414290`
  with observed currents from `s09010` bin 2. Provider networking and DTOs stay
  in `HydroProviders`; partial data and network failure preserve authored water.
- **RW2C provenance and freshness hardening complete:** refresh throttles,
  last-valid states, and failure fallbacks are isolated by canonical
  `WaterBody.id`. Per-measurement timestamps gate every interpreted signal at a
  60-minute age limit and five-minute future-skew limit while stale raw evidence
  remains preserved in `HydroState`.
- **Next:** RW3 — Curated Places Catalog + Coverage Model. General Places UX and
  automatic discovery do not exist yet.
- Add USGS Water Data only where it contributes a distinct measurement. Use NOAA
  ERDDAP only as needed.
- Prove the complete observation-to-render path before generalizing discovery.

### RW3 — Curated Places catalog

- **RW3 complete:** San Francisco Bay, Monterey Bay, and Lake Tahoe form a
  deliberately small reviewed catalog spanning NOAA CO-OPS coastal observations
  and USGS NWIS inland gage height.
- Every place publishes explicit `supported` or `unavailable` status for every
  Hydro capability instead of promising uniform coverage.
- **RW3A complete:** provider routes compose by opaque namespace, tolerate
  partial failure, and merge successful states deterministically. The watch
  picker persists deliberate selection of any curated Place and clears prior
  forcing before switching.
- **RW3B complete:** provider-independent Place status now distinguishes reviewed
  capability from observed, stale, missing, and unavailable current state. The
  watch exposes compact freshness, age, quality, origin, and exact source
  provenance without covering the water, identifies preserved versus unavailable
  fetch outcomes, and rejects late async results from a previously selected
  Place.
- **Next:** complete the Phase 0 physical-watch gate. If physical hardware passes,
  apply only evidence-backed P0B fixes and close Phase 0. If hardware remains
  unavailable after P0A readiness, proceed to RW4A's curated iPhone browser while
  keeping Phase 0 explicitly unresolved. Do not expand the catalog to defer the
  hardware gate. The current three-Place product is sufficient for validation and RW4's
  iPhone geographic-discovery foundation.

### RW4 — iPhone geographic discovery

- Add geographic browsing and selection on iPhone after the curated catalog has
  established the data and product model.
- Keep map and station-discovery concerns out of `OceanCore`.

### RW5 — Historical playback

- Replay retained observations through the same interpreter contract.
- Keep playback time separate from render and simulation clocks.

### RW6 — Forecast mode

- Add forecast data only when it can be labeled and sourced distinctly from
  observed, predicted, and derived values.
- Never silently substitute forecast values for missing observations.

## Explicitly not planned

- **A watch face.** Third-party apps cannot be watch faces. This comes up every
  time someone sees it; the answer is no, and it is Apple's decision, not a
  missing feature.
- **Audio.** Ambient sound would double the appeal and also the scope, the
  battery cost and the review surface. Not before Phase 4 tells us anyone cares.
- **Analytics.** Collecting nothing is a feature worth keeping.
