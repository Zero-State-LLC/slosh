# Product Doctrine

Slosh's product and engineering doctrine is:

> **Slosh renders an expressive representation of real water from trustworthy environmental evidence. It must never gain apparent coverage by weakening source identity, fabricating missing data, or pretending a perceptual visualization is an exact physical simulation.**

This doctrine is load-bearing. It constrains architecture, data selection, product copy, UX, provider integrations, and future geographic discovery.

## Core promise

Slosh renders a stylized but evidence-grounded representation of a selected real body of water's current environmental state.

## Explicit non-claim

Slosh is not CFD, a navigation tool, a marine safety instrument, or an exact local hydrodynamic simulation. The renderer is expressive and perceptual, not a scientific hydrodynamic model.

## Source rule

A data source may drive Slosh only when there is sufficient evidence that it represents the selected body of water.

## Proximity rule

Geographic proximity alone is never sufficient evidence. Distance may rank candidates after same-water-body evidence exists, but it cannot establish identity.

## Missing-data rule

Missing signals remain missing. Slosh does not fabricate absent measurements, infer unavailable coverage from nearby products, or turn absent observations into plausible-looking defaults.

## Uncertainty rule

Uncertain source relationships remain `needsReview` or `notComputable`. These outcomes are first-class product safety states, not failures to hide.

## Visual freedom

Once trustworthy inputs are established, Slosh may translate them perceptually and artistically through the existing Hydro pipeline:

```text
trustworthy environmental evidence
→ provider-independent HydroState
→ perceptual HydroInterpreter
→ expressive stylized water
```

The doctrine is not "scientific-looking rendering only." It is truthful inputs followed by expressive visual translation.

## Hybrid product thesis

Slosh is one coherent water experience with two input modes:

```text
SLOSH
├── EXPERIENCES  authored expressive water states
└── PLACES       evidence-grounded representations of real waters
```

Experiences and Places are not competing products. Experiences are authored states. Places are real environmental states that may influence the same visual medium only after source representativeness and signal coverage are explicit.

## Two separate confidence dimensions

Source confidence and signal coverage are different dimensions:

- **Source confidence:** are these observations representative of the selected water body?
- **Coverage:** which environmental variables are actually observed?

An accepted representative source may support only water level. Acceptance never implies complete Hydro coverage.

## Future rendering semantics

A Place visual can later communicate representation strength subtly if desired, but confidence calibration does not alter water rendering. Only accepted or reviewed trusted sources reach normal Hydro rendering.
