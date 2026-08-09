# RW4C — Geographic Discovery Feasibility and Dataset Resolution

## Decision

Arbitrary geographic selection is **not safe to ship as automatic nearest-sensor
matching**.

A selected coordinate identifies a point, not a named water body, hydrologic
feature, observation product, or representative station. Distance alone cannot
establish that a station measures the same bay, lake, river reach, estuary, or
coastal water mass. Slosh should use a staged resolution pipeline that separates:

1. geographic feature identification;
2. observation candidate discovery;
3. same-water-body evidence;
4. product and freshness validation;
5. explicit confidence and review.

The recommended next implementation is a **candidate discovery prototype**, not
dynamic `WaterBody` creation in production.

## Research questions

1. Can a map coordinate resolve to an authoritative water feature?
2. Can NOAA or USGS discover observation locations near that feature?
3. What evidence proves a candidate belongs to the same water body?
4. Can coverage be derived without probing every product repeatedly?
5. Which cases can be accepted automatically, and which require review?
6. Where should geographic and provider-specific logic live?

## Existing Slosh constraints

The current architecture remains correct:

```text
WaterBody
  canonical product identity
  representative coordinate
  reviewed coverage
  opaque source bindings

HydroProviders
  provider discovery and transport
  provider DTOs
  product availability

OceanCore
  no MapKit
  no NOAA/USGS DTOs
  no nearest-station policy
```

RW4C does not change the three reviewed Places or create runtime Places.

## Official-source findings

### NOAA CO-OPS

The production CO-OPS Metadata API can return individual or multiple station
records and supports station collections by type, including water levels,
meteorological sensors, water temperature, conductivity, and active currents.
Station records include stable station IDs and coordinates. Separate resources
expose installed sensors, current-meter bins, deployments, notices, and other
metadata.

This is sufficient for **candidate station generation and product capability
inspection**. It is not, by itself, proof that the geographically closest station
represents the selected water body. NOAA station identity is instrumentation
identity. Slosh product identity remains a `WaterBody`.

Sources:

- [CO-OPS Metadata API](https://api.tidesandcurrents.noaa.gov/mdapi/prod/)
- [CO-OPS Data Retrieval API](https://api.tidesandcurrents.noaa.gov/api/prod/)
- [CO-OPS GIS Data Portal](https://tidesandcurrents.noaa.gov/gis-data-portal/)

### USGS Water Data APIs

The USGS OGC APIs expose monitoring locations as geographic features. Their
metadata includes location name and identifier, responsible agency, location
type such as stream or lake, coordinates, and hydrologic unit code. The API
supports machine-readable GeoJSON and standardized collection/query metadata.

This is sufficient for **bounded monitoring-location discovery** and for using
location type and HUC as evidence. HUC agreement is useful but not conclusive:
large hydrologic units contain many distinct water bodies and river reaches.
Station name similarity also remains evidence, not identity.

Sources:

- [USGS Water Data APIs](https://api.waterdata.usgs.gov/)
- [Monitoring locations collection](https://api.waterdata.usgs.gov/ogcapi/v0/collections/monitoring-locations)
- [API documentation](https://api.waterdata.usgs.gov/docs/)

### National hydrography

NHDPlus High Resolution combines National Hydrography Dataset features,
catchments, terrain, and Watershed Boundary Dataset information. It includes
waterbody, area, and flowline feature classes and connects stream-network
features to their drainage landscape.

This provides a stronger inland geographic fabric than a radius query. A point
can potentially be associated with an NHD waterbody polygon, area, or flowline,
and a monitoring location can be compared against that same feature or connected
network. However, NHDPlus HR is distributed as large geospatial products, has
regional/version limitations, and USGS is transitioning national hydrography
work toward 3DHP. A mobile client should not download or spatially process the
national dataset directly.

Coastal bays and open-water selections remain harder. Shoreline geometry,
estuary boundaries, tidal connectivity, and station representativeness are not
reliably reduced to one nearest NHD feature.

Sources:

- [NHDPlus High Resolution](https://www.usgs.gov/national-hydrography/nhdplus-high-resolution)
- [National Hydrography Dataset](https://www.usgs.gov/national-hydrography/national-hydrography-dataset)
- [Watershed Boundary Dataset](https://www.usgs.gov/national-hydrography/watershed-boundary-dataset)

### NOAA ERDDAP

ERDDAP exposes searchable catalogs and consistent REST access to gridded and
tabular scientific datasets. Its `allDatasets`/info/search services can discover
datasets and their metadata, while `griddap` and `tabledap` retrieve subsets.

ERDDAP is a **dataset catalog and access protocol**, not a water-body identity
resolver. Search results can contain satellites, buoys, models, surveys, and
products with different spatial/temporal semantics. An ERDDAP result must be
reviewed for observation versus model/forecast origin, variable meaning,
resolution, update frequency, quality flags, and geographic representativeness
before it can become a source binding.

Source:

- [NOAA ERDDAP REST services](https://coastwatch.pfeg.noaa.gov/erddap/rest.html)

## Feasibility by water-body class

| Class | Feature identification | Candidate observations | Automatic confidence |
|---|---|---|---|
| Named inland lake/reservoir | Often strong with authoritative polygon/name | USGS location type, HUC, site metadata | Medium only when feature and station evidence agree |
| River/stream reach | Stronger with flowline/network position | USGS stream sites and time-series metadata | Medium; upstream/downstream position matters |
| Estuary/bay | Boundary and tidal connectivity are ambiguous | NOAA CO-OPS station metadata and products | Low without curated basin/station association |
| Open coast/ocean | Point is not a bounded product Place | NOAA stations, buoys, ERDDAP datasets | Low; nearest is rarely equivalent to representative |
| Cross-border/non-US water | National datasets incomplete or absent | Provider availability varies | Not computable with current provider set |

## Proposed resolution pipeline

```text
user coordinate
    ↓
GeographicFeatureResolver
    → zero or more authoritative feature candidates
    → feature ID, name, class, geometry reference, evidence source
    ↓
ObservationCandidateProvider(s)
    → NOAA/USGS/other candidate locations and datasets
    → provider-local DTOs remain outside OceanCore
    ↓
CandidateEvidenceEvaluator
    → containment / same feature ID
    → hydrologic connectivity
    → normalized name agreement
    → compatible location/water-body class
    → product availability
    → distance as a weak secondary signal only
    ↓
ResolutionDecision
    → accepted
    → needsReview
    → rejected
    → notComputable
```

### Required evidence model

A future provider-independent research model may contain:

```swift
struct WaterBodyResolutionCandidate {
    let featureIdentity: GeographicFeatureIdentity
    let proposedName: String
    let kind: WaterBodyKind
    let representativeCoordinate: Coordinate
    let sourceCandidates: [ObservationSourceCandidate]
    let evidence: [ResolutionEvidence]
    let confidence: ResolutionConfidence
}
```

This is not yet a `WaterBody`. Promotion requires reviewed source bindings and an
explicit complete capability coverage model.

### Confidence rules

`accepted` must require positive same-water-body evidence. Example inland rule:

```text
selected point contained by named lake polygon
AND monitoring location classified as lake/reservoir
AND station coordinate contained by the same polygon or explicitly references it
AND requested time series/product is currently available
```

Distance can rank candidates that already pass identity evidence. It cannot turn
a failing candidate into an accepted one.

Coastal selections should initially return `needsReview` unless an authoritative
basin/estuary association or maintained Slosh binding proves the relationship.

## Architecture recommendation

### Keep in application/provider infrastructure

- MapKit coordinate capture;
- calls to geographic feature services;
- NOAA/USGS catalog and station discovery;
- provider DTOs and capability probing;
- caching, rate limits, and network policy.

### Keep provider-independent

- candidate/evidence/confidence vocabulary;
- deterministic evidence evaluation;
- distinction between `needsReview`, `rejected`, and `notComputable`;
- promotion contract from a reviewed candidate to `WaterBody`.

### Do not do on-device at national scale

- bundle or download full NHDPlus products;
- scan entire NOAA/USGS station catalogs per map gesture;
- probe every possible provider product;
- infer water identity from reverse-geocoded labels;
- persist unreviewed dynamic Places as if curated.

A small backend or precomputed geographic index may eventually be justified for
feature containment, provider candidate joins, cache control, and dataset-version
management. That is an architecture conclusion, not approval to add a backend in
RW4C.

## Prototype plan

The next engineering slice should be **RW4D — Resolution Candidate Prototype**:

1. define provider-independent candidate/evidence/confidence types;
2. create fixture-based resolvers for one inland lake, one river reach, and one
   coastal bay;
3. implement a provider protocol returning candidates, not `WaterBody`;
4. prove nearest-station rejection with adversarial fixtures;
5. query NOAA and USGS metadata only behind DEBUG/research tooling;
6. output a review artifact containing all evidence and rejection reasons;
7. do not expose arbitrary selection in normal product UI.

**Implementation status:** complete. RW4D added the provider-independent
candidate/evidence/confidence model, deterministic evaluator, fixture provider,
explicit reviewed-promotion gate, JSON artifact encoding, and adversarial tests.
It intentionally added no live metadata adapters or product UI.

**RW4E implementation status:** complete. `HydroProviders` now contains bounded
NOAA CO-OPS MDAPI and USGS Water Data OGC request builders plus pure metadata
adapters. Fixtures prove deterministic distance ordering, conservative site-class
mapping, HUC preservation, explicit reviewed NOAA product input, malformed-data
rejection, and the central rule that provider metadata alone remains
`needsReview`. The adapters are not connected to normal iPhone or Watch UI and do
not promote candidates into `WaterBody` values.

**RW4F implementation status:** complete. `OceanCore` now has provider-independent
authoritative feature resolver contracts, explicit `GeographicFeatureKind`,
feature/source provenance fields for authority, dataset version, collection,
service, geometry reference, deterministic bounding-box and polygon containment,
and composition of authoritative feature evidence with RW4E-style observation
candidates. `HydroProviders` owns the NHDPlus High Resolution-shaped fixture DTO
adapter so NHD-specific JSON never enters `OceanCore`. `resolutioncheck` uses a
captured, generalized official NHDPlus HR `NHDWaterbody` polygon and stable ID for
Lake Tahoe. Separately labeled synthetic NHDPlus-schema scenario geometry covers
the river-policy and coastal-conservatism cases without claiming authoritative
feature extraction. The check writes deterministic JSON review artifacts,
and proves accepted inland identity, explicit nearby Truckee River rejection,
bounded river/flowline `needsReview`, conservative San Francisco
Bay `needsReview`, offshore
`notComputable`, inside/outside/boundary geometry semantics, malformed-polygon
fail-closed behavior, the single-ring/no-MultiPolygon prototype constraint, and
repeatable artifact encoding. It adds no product UI, no live NHD download, and no
catalog entry.

Suggested acceptance cases:

- Lake Tahoe point resolves to the Tahoe feature and reviewed USGS site candidate;
- a nearby Truckee River site is rejected as not the same water body;
- San Francisco Bay uses a conservative NHDPlus-schema scenario feature and
  remains `needsReview` without station-to-feature identity evidence; the scenario
  geometry is not presented as an authoritative extract;
- offshore or unsupported coordinates return `notComputable`, not a fabricated
  Place.

## Product conclusion

RW4B's curated map remains the correct shipping product. RW4C finds no defensible
basis for a general “tap water, use nearest sensor” feature. Trustworthy discovery
is feasible only as evidence-backed candidate resolution with class-specific
rules, explicit uncertainty, and likely precomputed geospatial support.

Phase 0 remains **OPEN / NOT_RUN**. This research provides no physical Watch
evidence.

The exact recommended next slice is **RW4G — Feature + Observation Candidate
Composition & Confidence Calibration**. It should broaden deterministic fixture
coverage and calibrate when explicit identity, class, hydrologic, and product
evidence support `accepted` versus `needsReview`, without exposing arbitrary map
selection in product UI.
