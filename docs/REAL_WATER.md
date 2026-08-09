# Real Water

> **Slosh lets you wear the state of a real body of water.**

Real Water is a planned product domain. It extends Slosh without replacing the
authored experiences that already define the app.

## Two domains

- **Experiences** are the existing authored `OceanTheme` modes. They define a
  deliberate visual and behavioral character.
- **Places** are real geographic bodies of water whose accessible environmental
  measurements can persistently influence that character.

## Data boundary

Provider-specific data stops before the portable engine:

```text
Provider DTO → HydroState → HydroInterpreter → HydroExperience
```

`HydroState` retains measurement units, origin, quality, and source identity.
`HydroInterpreter` deterministically translates valid measurements into
normalized `EnvironmentalForcing` and renderer-vocabulary-only
`HydroThemeModifiers`. Provider DTOs never enter `OceanCore`.

## Interaction and composition rule

**Environmental data is persistent forcing. Wrist movement is transient
forcing.**

`SurfaceDriver` now composes the three influences as:

- **environmental forcing = persistent baseline**;
- **wrist gravity = temporary directional authority**;
- **shake = transient surge**.

Environmental energy does not overwrite crown energy. The implemented bounded
composition is:

```text
resolvedEnergy = min(
  crownEnergy
  + 0.65 × environmentalEnergy
  + 0.15 × environmentalTurbulence
  + 0.10 × currentStrength
  + 0.10 × windStrength,
  3.0
)
```

With no environmental forcing, `resolvedEnergy` is exactly the existing crown
energy and authored behavior is unchanged. Shake surge remains separate and
decays without erasing the environmental baseline.

For direction, in-plane gravity is mapped from a dead zone of `0.12` to full
wrist authority at `0.75`. A flat watch targets the environmental current
direction. Increasing tilt blends along the shortest angular path toward the
wrist direction, and returning flat smoothly targets the environmental
direction again. Authored modes that do not follow gravity, especially Zero
Gravity, retain their authored heading behavior.

## Direction convention

Hydro directional measurements carry an explicit convention: **toward** or
**from**. `HydroInterpreter` converts both into one canonical contract:

> All `EnvironmentalForcing` directions mean the direction the force moves
> toward, in radians normalized to one full turn.

A direction without an explicit convention is unusable rather than guessed.

## Quality handling

Measurement quality affects interpretation while the source measurement remains
unchanged in `HydroState`:

```text
good    → used
unknown → used
suspect → ignored by HydroInterpreter
```

## Provenance rule

Never fabricate an unavailable measurement. Missing values remain absent rather
than becoming zero or a plausible-looking default. Product UI and future data
plumbing must clearly distinguish:

- **observed** measurements reported for a place;
- **forecast** values describing a future state;
- **predicted** values produced by an established prediction product;
- **derived** values calculated from identified inputs and a documented rule;
- **stale** state whose observation age exceeds the freshness threshold;
- **unavailable** state with no usable observation.

Freshness permits at most five minutes of future clock skew. An observation
exactly five minutes ahead is evaluated normally; one farther in the future is
`unavailable`. `SurfaceDriver` does not apply unavailable forcing. Freshness
remains deterministic because interpretation always receives a reference date.

## Observation rate is not render rate

Observation rate != simulation rate != render rate.

Environmental observations may update only every several minutes. Slosh still
simulates interaction and renders continuously between those updates. Provider
polling must never be coupled to the display loop.

## First vertical slice

The planned first place is **San Francisco Bay**. It is deliberately not
implemented in the Hydro foundation change.

The intended provider sequence is:

1. NOAA CO-OPS
2. USGS Water Data
3. NOAA ERDDAP as needed

## Explicit non-goals of the Hydro foundation

- arbitrary geographic search;
- API integration or networking;
- station discovery;
- forecasting;
- caching;
- historical playback;
- map UI;
- server infrastructure;
- CFD simulation.

The interpreter is a deterministic perceptual translation into Slosh's existing
water vocabulary. It is not presented as literal hydrodynamics.
