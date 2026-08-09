# Real Water

> **Slosh lets you wear the state of a real body of water.**

Real Water is a planned product domain. It extends Slosh without replacing the
authored experiences that already define the app.

## Device roles

```text
iPhone → browse Places, inspect coverage and provenance, choose water
Watch  → experience and wear the selected water
```

RW4A adds a native iPhone catalog browser for San Francisco Bay, Monterey Bay,
and Lake Tahoe. Catalog identity, reviewed coverage, and coordinates are local
and remain available offline. Live status loads asynchronously per Place through
the existing routed provider and coordinator architecture, so browsing never
waits for networking and one Place cannot inherit another Place's result.

The detail screen presents provider-independent freshness, all six display
signal groups, observed/missing/stale/unsupported distinctions, values,
observation age, quality, origin, provider/station names, and canonical source
IDs. A failed fetch shows cached coordinator state as preserved when available;
otherwise it truthfully reports current observations unavailable.

Selection uses a shared `SelectedWater` value wrapped with timestamp and device
origin. It persists locally and crosses a protocol-abstracted WatchConnectivity
boundary. The most recent deliberate selection wins after reconnection. RW4A
does not add a map, remote Place search, station discovery, polling, or a new
renderer.

### Curated geographic map

RW4B presents the same reviewed catalog through a MapKit map and the existing
list. Every annotation is derived from a canonical `WaterBody.id`, latitude, and
longitude. A pin represents San Francisco Bay, Monterey Bay, or Lake Tahoe as a
product Place. It never represents NOAA station `9414290`, current station
`s09010`, USGS site `10337000`, or any other sensor.

The map consumes the same keyed observation store and provider-independent Place
status used by the list. It remains complete offline and shows loading,
freshness, preserved, or unavailable state without removing Places. Tapping a
pin is transient browsing and opens the existing `PlaceDetailView`; it does not
change the worn water. Only **Wear this water** persists a canonical selection
and sends it through the existing Watch transport boundary.

The default camera fits all reviewed Places when no Place is selected and centers
reasonably around the current selected Place otherwise. Search remains local to
the curated catalog. MapKit search, geocoding, station discovery, nearest-sensor
matching, and dynamic WaterBody creation do not exist.

RW4C evaluates what would be required to move beyond that curated catalog. Its
decision is documented in
[RW4C_GEOGRAPHIC_DISCOVERY_RESEARCH.md](RW4C_GEOGRAPHIC_DISCOVERY_RESEARCH.md):
nearest-sensor matching is not a trustworthy water-body resolver. Future work
must first identify an authoritative geographic feature, gather provider
candidates, evaluate same-water-body evidence, and preserve explicit
`needsReview` and `notComputable` outcomes.

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

The synthetic visual path is:

```text
HydroThemeModifiers → ResolvedWaterStyle → existing WaterScene uniforms
```

`ResolvedWaterStyle` combines an immutable authored `OceanTheme` with bounded
Hydro modifiers. `WaterScene` sends resolved choppiness, turbulence, crest
sharpness, and glitter through the existing packed `u_wave` value, and resolved
caustic strength and foaminess through `u_optics`. No shader uniform was added or
renamed. Removing Hydro modifiers restores the authored values exactly.

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

Quality and freshness compose in one signal-usability rule. A measurement can
affect forcing only when its unit matches the requested signal, its value is
finite, its quality is not `suspect`, directional values declare a convention,
and its effective observation timestamp is within the freshness and clock-skew
bounds. `good` and `unknown` quality remain usable.

## State freshness and signal freshness

`HydroFreshness` remains the conservative status of the assembled snapshot.
Signal usability is separate: it decides whether each individual measurement is
allowed to affect `EnvironmentalForcing` and `HydroThemeModifiers`.

```text
measurement age <= 60 minutes  → usable
measurement age > 60 minutes   → retained as evidence, ignored by HydroInterpreter
measurement > 5 minutes future → ignored
missing measurement timestamp  → use HydroState.observedAt
```

The thresholds are centralized in `HydroInterpreter.FreshnessThresholds`.
Ignoring a signal never deletes or mutates it in `HydroState`. A state can
therefore have a stale conservative summary while fresh component measurements
still drive water, or contain one stale current that is ignored while fresh wind
and waves remain active.

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

## Deterministic simulator fixtures

Debug simulator builds accept `-hydroFixture calm`, `active`, or `severe`.
Each launch interprets the synthetic state with `HydroFixtures.referenceDate`
and applies both its forcing and theme modifiers to the same **Calm ocean** base
theme. Release and physical-watch builds compile the fixture path to `nil`.

Using the repository's current bundle identifier:

```bash
xcrun simctl launch <watch-udid> com.example.Slosh.watchkitapp \
  -hydroFixture calm
xcrun simctl launch <watch-udid> com.example.Slosh.watchkitapp \
  -hydroFixture active
xcrun simctl launch <watch-udid> com.example.Slosh.watchkitapp \
  -hydroFixture severe
```

These are synthetic visual-QA inputs only. They are never presented as
observations of a geographic place.

![Calm, active, and severe synthetic fixture comparison](../media/real-water/rw2a5-fixture-comparison.png)

## First live provider vertical slice

RW2B implements an experimental **DEBUG watch-simulator** path for San
Francisco Bay. It proves the provider boundary without adding a general Places
interface:

```text
NOAA CO-OPS JSON
→ provider-local DTO
→ NOAAHydroAdapter
→ HydroState
→ HydroInterpreter
→ HydroExperience
→ OceanModel / WaterScene
```

`HydroProviders` is a separate Swift package target. It owns `URLSession`, NOAA
URLs, NOAA response DTOs, NOAA flags, parsing, aggregation, refresh policy, and
the in-memory place-scoped last-known valid states. `OceanCore` remains
network-free and owns
only provider-independent water-body and Hydro contracts. Source bindings use
opaque namespaces, identifiers, capabilities, and string parameters; provider
targets resolve only the namespaces they own and ignore all others.

### San Francisco Bay bindings

The curated `WaterBodies.sanFranciscoBay` entry uses two reviewed NOAA CO-OPS
bindings:

| Binding | Why it exists | Products used |
|---|---|---|
| San Francisco `9414290` | Active water-level and meteorological station near the Golden Gate | `water_level`, `wind`, `air_pressure` |
| Oakland Outer Harbor LB3 `s09010`, bin `2` | Active San Francisco Bay PORTS current station; NOAA identifies bin 2 as its real-time bin | `currents` |

Coverage is intentionally not uniform:

| Hydro capability | RW2B coverage |
|---|---|
| Water level | Available from `9414290` |
| Wind speed and direction | Available from `9414290` |
| Air pressure | Available from `9414290` |
| Current speed and direction | Available from separate station `s09010`, bin 2 |
| Water temperature | Unavailable: the `9414290` sensor is inactive and NOAA reports no current data |
| Salinity | Unavailable at the selected station |
| Wave height and period | Unsupported in this slice; remain `nil` |

Every request explicitly uses `date=latest`, `format=json`, `units=metric`, and
`time_zone=gmt`. Water level also uses the explicit **MLLW** (Mean Lower Low
Water) datum. NOAA metric currents are centimeters per second, so the adapter
divides by 100 before creating a `.metersPerSecond` measurement. Other selected
metric products already match the canonical Hydro units.

NOAA wind follows the meteorological **from** convention. NOAA observed currents
report where water flows **toward**. The adapter records those conventions on the
source measurements; `HydroInterpreter` still performs the one canonical
conversion into direction-toward radians.

Quality mapping is fail-closed and preserves provenance:

```text
any documented nonzero NOAA data flag → suspect
all documented flags zero            → good
missing flags or undocumented QA      → unknown
```

Preliminary (`p`) and verified (`v`) water levels are both usable when their
flags are normal. `suspect` measurements remain in `HydroState` but are ignored
by the interpreter. Missing, empty, `null`, malformed, NaN, and infinite values
remain `nil`; provider error JSON becomes a typed error and never creates fake
Hydro data.

NOAA products can have different observation times. Each provider-created
`HydroMeasurement` therefore records its own optional `observedAt`. The
aggregate state's `observedAt` is the **oldest valid product timestamp**, a
conservative freshness summary that does not claim the whole state is newer than
its least-recent component.

### Multi-place isolation

`LiveHydroCoordinator` keys every refresh record by canonical `WaterBody.id`.
Each body has an independent:

- refresh throttle;
- last valid state;
- failure fallback state.

No cached state can cross body IDs, and a recent attempt for one body cannot
suppress a provider fetch for another. Cancellation clears only the affected
body's attempt timestamp, so that body can retry immediately without altering
another body's throttle or cache. Cache inspection is place-scoped through
`cachedState(for:)`; there is no ambiguous global last-state API.

### Curated Places catalog and coverage

RW3 keeps the catalog deliberately small and reviewed:

| Place | Provider source | Reviewed observed coverage |
|---|---|---|
| San Francisco Bay | NOAA CO-OPS `9414290`; currents `s09010` bin 2 | water level, wind, pressure, current speed and direction |
| Monterey Bay | NOAA CO-OPS `9413450` | water level, water temperature, pressure |
| Lake Tahoe | USGS NWIS instantaneous values `10337000` | gage height as water level |

Every `WaterBody` exposes a complete map over `HydroCapability`: each capability
is either `supported` or `unavailable`. This prevents a partial station from being
presented as uniformly instrumented. Monterey wind is unavailable in the
reviewed latest-observation product and is not requested. Lake Tahoe does not
claim wind, current, wave, pressure, salinity, or temperature coverage.

USGS parameter `00065` reports gage height in feet. `USGSIVAdapter` converts it
to canonical meters, preserves `usgs.nwis.<site>.00065` source identity and the
source timestamp, maps approved values to `good`, provisional values to usable
`unknown`, and unrecognized qualifiers to `suspect`. No USGS DTO enters
`OceanCore`. Gage height is station-datum-relative stage, not elevation and not
directly comparable to NOAA MLLW water level; the source identity must remain
visible wherever these values are presented or interpreted.

### Live debug launch and lifecycle

```bash
xcrun simctl launch <watch-udid> com.example.Slosh.watchkitapp \
  -realWater san-francisco-bay
```

The authored Calm ocean starts and renders before networking begins. A fetch is
attempted on activation and no more often than every **10 minutes**. In-flight
work is cancelled when the app backgrounds or the display enters reduced
luminance; no render-rate timer exists. Caching is in-memory only.

The live provider path is not simulator-only. In DEBUG physical-validation mode,
`-physicalValidation YES -validationRoute san-francisco-bay` selects the same
curated San Francisco Bay body and `RoutedHydroProvider.liveCurated()` used by
normal Place selection. Synthetic fixture and forced-offline arguments remain
simulator-only.

Failure behavior is explicit:

```text
success                         → cache and apply the new HydroExperience
failure with prior valid state  → preserve and reapply the prior state
failure without prior state     → preserve authored Calm ocean
```

For simulator QA, `-realWaterOffline YES` forces the unavailable path. Synthetic
`-hydroFixture` arguments take precedence over `-realWater` when both are
present, preserving deterministic fixture testing.

### Network privacy audit

Real Water makes direct HTTPS requests to the configured NOAA CO-OPS and USGS
NWIS public environmental-data services. This is the current factual boundary:

| Exposure | Current behavior |
|---|---|
| Public IP | Naturally visible to NOAA/USGS and their transport infrastructure as part of an HTTP request |
| Application identifier/query | NOAA requests send `application=Slosh`; provider query parameters identify the requested product |
| Station/product | The reviewed station/site, product, datum, units, time zone, and related provider parameters are transmitted |
| Device location | Not transmitted; Places are selected from a curated catalog and no location API feeds provider requests |
| User identity | No account, name, email, advertising identifier, or user profile is sent |
| Analytics identifiers | No analytics SDK or behavioral-tracking identifier exists in the repository |

Server-side retention, CDN behavior, and final App Store transport/privacy
disclosures are outside the repository's direct proof and must be verified at
submission time against the then-current provider endpoints and policies. The
accurate product promise is: no analytics SDK, user account, behavioral tracking,
or user-profile backend; Real Water contacts configured public environmental-data
providers.

![Authored failure fallback and live San Francisco Bay NOAA water](../media/real-water/rw2b-live-fallback-comparison.png)

Implemented in RW2B: the San Francisco Bay debug vertical slice. Not implemented:
a general Places UX, automatic station discovery, historical playback, forecast
mode, persistent caching, or arbitrary geographic search.

RW2C completed multi-place provenance and per-signal freshness hardening. RW3
adds the reviewed three-place catalog and explicit coverage model without adding
a Places UI.

### Multi-provider application composition and Places selection

RW3A adds `RoutedHydroProvider`, whose routes own sets of opaque source-binding
namespaces. Only matching routes fetch a selected place. Successful provider
states merge deterministically; the oldest observation timestamp remains the
conservative summary, the latest retrieval timestamp records completion, and
earlier declared routes win only if providers collide on one canonical signal.
One provider failure does not erase another provider's usable state. If every
matching route fails, the place remains unavailable and authored Calm ocean is
preserved.

The watch picker now presents authored Experiences and the three curated Places.
Place selection persists by canonical `WaterBody.id`. Switching place first
clears the previously applied Hydro experience, preventing cross-place forcing
from appearing during the next fetch. Lifecycle cancellation, ten-minute
per-place throttling, and per-place fallback continue to be owned by
`LiveHydroCoordinator`.

### Place status, freshness, and provenance presentation

RW3B keeps reviewed catalog capability separate from the latest observation
result. `WaterBody.coverage` answers whether a reviewed source binding exists;
`PlaceHydroStatus` answers what the most recent assembled snapshot contains:

```text
observed    → timely measurement evidence is present
stale       → measurement evidence remains, but its timestamp cannot drive water
missing     → the catalog supports the signal, but the latest state has no sample
unavailable → the catalog has no reviewed source for the signal
```

`PlaceHydroStatusResolver` is pure and receives `WaterBody`, optional
`HydroState`, and an explicit reference date. It delegates signal usability to
`HydroInterpreter`; the UI owns no duplicate age or future-skew threshold.
Canonical capabilities remain independently represented, while compact watch
rows group wind speed/direction and current speed/direction without inventing a
missing component. Wave measurements remain part of `HydroState` and the
interpreter, but are not catalog capability claims until a reviewed source exists.

The watch picker derives its capability summary from the catalog. The selected
Place can open a compact status-and-sources surface showing current values,
freshness, age, unavailable versus missing signals, and measurement provenance.
The main water view remains free of telemetry.

Friendly source presentation is deterministic and retains the canonical ID:

```text
noaa.coops.9414290.water_level → NOAA CO-OPS · Station 9414290
usgs.nwis.10337000.00065       → USGS · Site 10337000
```

Each measurement detail also shows origin and quality:

```text
good    → Good
unknown → Provisional / Unknown (still usable)
suspect → Suspect · not used

observed  → Observed
forecast  → Forecast
predicted → Predicted
derived   → Derived
```

The application load state is always scoped to one canonical `WaterBody.id`:

```text
inactive
loading(placeID)
loaded(PlaceHydroStatus)
preserved(PlaceHydroStatus)
unavailable(placeID)
```

Switching Places immediately publishes loading for the new ID and clears the
old Place's forcing. Cancellation remains the first defense against obsolete
work; the application coordinator also compares both the captured request
generation and Place ID before applying either water or presentation state. A
late completion for Place A therefore cannot overwrite Place B, and an older
request cannot overwrite a newer activation of the same Place. Preserved cache is labeled
"Using last observation"; an uncached failure is labeled "Live data
unavailable" and never exposes a raw provider error to normal UI.

Debug simulator launch arguments accept every curated ID:

```bash
-realWater san-francisco-bay
-realWater monterey-bay
-realWater lake-tahoe
```

Catalog growth stops here until the Phase 0 physical-watch gate produces evidence.
If a physical Watch passes, the next slice is **P0B — apply only evidence-backed
device fixes, then close Phase 0**. If no physical Watch is accessible after P0A
readiness, the next software slice may be **RW4A — iPhone curated Places browser
foundation**, while Phase 0 remains explicitly open. USGS Water Data and NOAA
ERDDAP remain options only where they contribute a distinct, reviewed measurement.

## Explicit non-goals of the current Real Water slices

- arbitrary geographic search;
- automatic station discovery;
- forecasting;
- persistent caching or databases;
- historical playback;
- map UI or automatic geographic discovery;
- server infrastructure;
- CFD simulation.

The interpreter is a deterministic perceptual translation into Slosh's existing
water vocabulary. It is not presented as literal hydrodynamics.
