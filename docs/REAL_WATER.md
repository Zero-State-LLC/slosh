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

## Interaction rule

**Environmental data is persistent forcing. Wrist movement is transient
forcing.**

The future `SurfaceDriver` integration must blend the two. Environmental flow
should persist while the watch is still, wrist tilt should temporarily bias the
water, and a shake should add a surge that decays back toward the environmental
state. Real Water must not eliminate wrist interaction.

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
