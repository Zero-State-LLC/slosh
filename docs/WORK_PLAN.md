# Work plan

Three people are working this repo in parallel and have already collided once —
eight issues were filed and independently fixed at the same time, and a whole
pull request had to be closed as duplicate. This document exists to stop that
happening again.

The split is by **kind of work**, not by module, because module boundaries move
and the kinds of work do not.

| Lane | Owner | Owns |
|---|---|---|
| **A — Hardware and product** | @prabu-openclaw | Anything needing a physical watch, and every product-scope decision |
| **B — Data domain** | @scrimshawlife-ctrl | Real Water semantics, provider domain knowledge, the geographic track |
| **C — Hardening and verification** | Claude | Correctness in shared infrastructure, review, reproducible builds |

**The rule that prevents collisions:** Lane B owns work that moves the product
*forward*. Lane C owns work that makes what exists *correct and verifiable*.
When they touch the same file, the semantic decision belongs to B and the
mechanical fix belongs to C. Anything requiring judgement about what the product
*is* belongs to A.

---

## Lane A — @prabu-openclaw

Nobody else can do any of this.

### A1. Phase 0 hardware validation — **blocks everything**

Never run on a wrist. Roughly 5,000 lines of feature work now sit on top of two
unverified assumptions, and either can invalidate work built above it.

- **Tilt axis and sign.** Does the swell roll toward the low side? Check all four
  orientations, and with the crown on both sides. If it is wrong the fix is one
  line — `SurfaceDriver`'s `atan2(gx, -gy)` is deliberately the only place the
  mapping is decided.
- **Frame rate.** Profile Breaking surf and Storm at night, the two most
  expensive modes, on the oldest device you intend to support. The simulator
  runs on a Mac GPU and has told us nothing.
- **Battery.** Ten minutes foreground. Confirm sensors and rendering actually
  stop when backgrounded and when the screen dims.

Needs: any watchOS 10+ Apple Watch, paired. A free Apple developer account is
enough for a seven-day sideload — the $99 program is not required yet.
`docs/PHYSICAL_WATCH_VALIDATION.md` and `scripts/prepare-watch-validation.sh`
are already written and waiting.

### A2. Decide what the product is

Slosh began as *a beautiful ocean on your wrist, fifteen modes, opens
instantly*. Four research slices later it is substantially a hydrological data
platform. Both are legitimate; they are not the same product, and they have
different demos, different store listings, and very different remaining scope.

Right now the code is being built as the second while `ROADMAP.md` and
`ECONOMICS.md` describe the first. Until this is decided, prioritisation in
lanes B and C is guesswork.

### A3. Freeze or continue

Given A1 is open, decide whether feature work pauses until it runs. The cost of
continuing is that the contingent pile grows; the cost of freezing is idle time
if hardware is far off. This is a judgement call, not a technical one.

---

## Lane B — @scrimshawlife-ctrl

Domain semantics and forward feature work. Lane C will not touch these files
without saying so first.

### B1. #18 — NOAA QC flag is a count, not a boolean **(P0)**

57.1% of live water-level readings at the flagship station are being discarded,
measured against the live API. Needs per-product flag semantics, which is a
domain judgement rather than a mechanical fix — hence lane B.

### B2. #21 — SF Bay currents binding is dead ~45% of the time

Station selection and what `coverage` should honestly promise. Also domain
judgement.

### B3. #16 — finish the geographic resolver PR

Reviewed; the containment maths is correct. One concrete fix: the research
resolver ships in the **iPhone** Release binary. The PR's own assertion covers
watchOS only.

### B4. RW4G and beyond

Whatever the next research slice is — subject to A3.

---

## Lane C — Claude

Cross-cutting correctness in shared infrastructure, plus verification. Chosen so
it does not collide with B: transport and coordinator mechanics rather than data
semantics.

### C1. #19 — USGS transport has no watch-appropriate session

60s request and 7-day resource timeouts against NOAA's 10s/20s, on the same
device. Plus a `URLSession` leak per `liveCurated()` call.

### C2. #20 — coordinator coalescing and throttle floor

A concurrent caller currently gets `.unavailable` even when the other caller
succeeded, and cancellation resets the throttle with no floor — measured at 50
provider fetches in 10 seconds. One fix addresses both: coalesce in-flight work
per water body instead of tracking a timestamp.

### C3. #17 — reproducible build for all four targets

The three SPM suites cover the packages only; nothing compiles the Watch or
iPhone app targets in a form a second contributor can run. A short script, so
"it builds" stops depending on who last built it locally.

### C4. `RoutedHydroProvider` cancellation gap

A child cancelled without the parent being cancelled is merged around as an
ordinary outage, and the partial gets stored as last-known-good. Small.

### C5. Standing: review every PR before merge

Four substantial PRs have merged with zero reviews. The audits found a P0 and
several correctness bugs, so review is demonstrably paying for itself here.

---

## Working agreement

1. **Claim before you start.** Assign yourself the issue. An unassigned issue is
   unclaimed; an assigned one is off limits without a comment.
2. **No direct pushes to `main`.** Six commits went straight to `main` during
   this period, which is what made a rebase necessary and a PR unmergeable.
3. **One PR per concern.** The eight-issue omnibus was hard to review and hard
   to attribute.
4. **State what you verified, and how.** "Tests pass" is weaker than "reverting
   the fix fails these four checks" — and the difference caught a false-confidence
   test where the fake exercised a path the real code could never take.
5. **Fixtures come from live responses.** #18 existed because the suspect-flag
   fixture used the one arrangement that genuinely is suspect, while the common
   real shape was never exercised.
