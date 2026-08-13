import Foundation
import HydroProviders
import HydroProvidersResearch
import OceanCore
import OceanCoreResearch

private enum Check {
    static var failures = 0
    static var count = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        count += 1
        if condition() { print("  ✓ \(message)") } else { failures += 1; print("  ✗ \(message)") }
    }
}

private struct CoordinateArtifact: Codable, Equatable {
    let latitude: Double
    let longitude: Double
}

private struct FeatureIdentityArtifact: Codable, Equatable {
    let namespace: String
    let id: String
    let name: String
    let kind: WaterBodyKind
}

private struct ObservationCandidateArtifact: Codable, Equatable {
    let namespace: String
    let sourceID: String
    let name: String
    let locationKind: WaterBodyKind?
    let capabilities: [HydroCapability]
    let distanceMeters: Double
}

private struct EvidenceArtifact: Codable, Equatable {
    let kind: ResolutionEvidenceKind
    let strength: ResolutionEvidenceStrength
    let source: String
    let note: String
}

private struct ReviewArtifact: Codable, Equatable {
    let caseID: String
    let input: CoordinateArtifact
    let featureIdentity: FeatureIdentityArtifact?
    let observationCandidate: ObservationCandidateArtifact?
    let evidence: [EvidenceArtifact]
    let hardBlockers: [EvidenceArtifact]
    let decision: ResolutionConfidence
    let decisionReasons: [String]
    let expectedDecision: ResolutionConfidence
    let knownRepresentative: Bool?
}

private struct CalibrationSummary: Codable, Equatable {
    let fixtureCount: Int
    let acceptedCount: Int
    let needsReviewCount: Int
    let rejectedCount: Int
    let notComputableCount: Int
    let falseAutomaticAccepts: Int
    let falseRejectsWhereKnown: Int
    let automaticAcceptancePrecision: Double
}

private struct CalibrationArtifact: Codable, Equatable {
    let summary: CalibrationSummary
    let cases: [ReviewArtifact]
}

private struct Scenario {
    let caseID: String
    let input: GeographicCoordinate
    let candidate: WaterBodyResolutionCandidate
    let expectedDecision: ResolutionConfidence
    /// True/false only where the fixture asserts representative ground truth.
    /// nil means the correct product outcome is review or not-computable, not a
    /// known positive/negative automatic-resolution label.
    let knownRepresentative: Bool?
}

private func fixture(_ name: String) throws -> Data {
    guard let url = Bundle.module.url(forResource: name, withExtension: "json") else { throw CocoaError(.fileNoSuchFile) }
    return try Data(contentsOf: url)
}

private func coord(_ coordinate: GeographicCoordinate) -> CoordinateArtifact {
    CoordinateArtifact(latitude: coordinate.latitude, longitude: coordinate.longitude)
}

private func featureArtifact(_ feature: GeographicFeatureIdentity?) -> FeatureIdentityArtifact? {
    feature.map {
        FeatureIdentityArtifact(namespace: $0.namespace, id: $0.featureID, name: $0.name, kind: $0.kind)
    }
}

private func observationArtifact(_ source: ObservationSourceCandidate?) -> ObservationCandidateArtifact? {
    source.map {
        ObservationCandidateArtifact(
            namespace: $0.namespace,
            sourceID: $0.sourceID,
            name: $0.name,
            locationKind: $0.locationKind,
            capabilities: $0.capabilities.sorted { $0.rawValue < $1.rawValue },
            distanceMeters: $0.distanceMeters
        )
    }
}

private func evidenceArtifact(_ evidence: ResolutionEvidence) -> EvidenceArtifact {
    EvidenceArtifact(kind: evidence.kind, strength: evidence.kind.strength, source: evidence.source, note: evidence.note)
}

private func scenarioArtifact(
    _ scenario: Scenario,
    decision: WaterBodyResolutionDecision,
    evaluation: CandidateEvidenceEvaluation
) -> ReviewArtifact {
    ReviewArtifact(
        caseID: scenario.caseID,
        input: coord(scenario.input),
        featureIdentity: featureArtifact(scenario.candidate.feature),
        observationCandidate: observationArtifact(scenario.candidate.observationSources.first),
        evidence: scenario.candidate.evidence.sorted(by: evidenceOrder).map(evidenceArtifact),
        hardBlockers: evaluation.hardBlockers.map(evidenceArtifact),
        decision: decision.confidence,
        decisionReasons: decision.reasons.sorted(),
        expectedDecision: scenario.expectedDecision,
        knownRepresentative: scenario.knownRepresentative
    )
}

private func evidenceOrder(_ lhs: ResolutionEvidence, _ rhs: ResolutionEvidence) -> Bool {
    if lhs.kind.rawValue != rhs.kind.rawValue { return lhs.kind.rawValue < rhs.kind.rawValue }
    if lhs.source != rhs.source { return lhs.source < rhs.source }
    return lhs.note < rhs.note
}

private func source(
    _ id: String,
    name: String,
    coordinate: GeographicCoordinate,
    kind: WaterBodyKind?,
    capabilities: Set<HydroCapability> = [.waterLevel],
    distance: Double,
    namespace: String = "gov.usgs.waterdata.site"
) -> ObservationSourceCandidate {
    ObservationSourceCandidate(
        namespace: namespace,
        sourceID: id,
        name: name,
        coordinate: coordinate,
        locationKind: kind,
        capabilities: capabilities,
        distanceMeters: distance
    )
}

private func evidence(_ kind: ResolutionEvidenceKind, _ source: String, _ note: String) -> ResolutionEvidence {
    ResolutionEvidence(kind: kind, source: source, note: note)
}

private func candidate(
    feature: GeographicFeatureIdentity?,
    observations: [ObservationSourceCandidate],
    evidence: [ResolutionEvidence]
) -> WaterBodyResolutionCandidate {
    WaterBodyResolutionCandidate(feature: feature, observationSources: observations, evidence: evidence)
}

private func standardFeatureEvidence(_ feature: GeographicFeatureIdentity) -> [ResolutionEvidence] {
    [
        evidence(.selectedPointContainedByFeature, "Authoritative feature fixture", "Selected point is contained by \(feature.name)."),
        evidence(.authoritativeFeatureClass, "Authoritative feature fixture", "Feature class maps to product kind \(feature.kind.rawValue).")
    ]
}

private func makeCalibrationSummary(for decisions: [(Scenario, WaterBodyResolutionDecision)]) -> CalibrationSummary {
    let accepted = decisions.filter { $0.1.confidence == .accepted }
    let falseAccepts = accepted.filter { $0.0.knownRepresentative == false }.count
    let trueAccepts = accepted.filter { $0.0.knownRepresentative == true }.count
    let falseRejects = decisions.filter { $0.1.confidence == .rejected && $0.0.knownRepresentative == true }.count
    let precisionDenominator = trueAccepts + falseAccepts
    return CalibrationSummary(
        fixtureCount: decisions.count,
        acceptedCount: accepted.count,
        needsReviewCount: decisions.filter { $0.1.confidence == .needsReview }.count,
        rejectedCount: decisions.filter { $0.1.confidence == .rejected }.count,
        notComputableCount: decisions.filter { $0.1.confidence == .notComputable }.count,
        falseAutomaticAccepts: falseAccepts,
        falseRejectsWhereKnown: falseRejects,
        automaticAcceptancePrecision: precisionDenominator == 0 ? 1 : Double(trueAccepts) / Double(precisionDenominator)
    )
}

private let selectedLakeTahoe = GeographicCoordinate(latitude: 39.0968, longitude: -120.0324)
private let boundaryLakeTahoe = GeographicCoordinate(latitude: 39.16810, longitude: -120.14228)
private let outsideLakeTahoe = GeographicCoordinate(latitude: 39.40, longitude: -120.40)
private let truckeeRiverPoint = GeographicCoordinate(latitude: 39.327, longitude: -120.205)
private let sanFranciscoBayPoint = GeographicCoordinate(latitude: 37.806305, longitude: -122.46589)
private let offshorePacific = GeographicCoordinate(latitude: 36.70, longitude: -123.80)

let features = try NHDPlusFeatureFixtureAdapter().decode(fixture("nhdplus-inland-features"))
let resolver = DeterministicFeatureIndexResolver(features: features)
let composer = AuthoritativeResolutionComposer()
let evidenceEvaluator = CandidateEvidenceEvaluator()
let policy = ResolutionPolicy()
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

print("RW4G representative-water resolution policy")
Check.expect(features.map(\.identity.featureID) == ["44560536", "NHDHR-16050102-TRUCKEE-RIVER-FIXTURE", "NHDHR-18050004-SAN-FRANCISCO-BAY-AREA-FIXTURE"], "NHDPlus-derived adapter preserves the official Tahoe ID and excludes malformed or unsupported geometry")
Check.expect(features[0].contains(selectedLakeTahoe), "geometry contains an interior selected point")
Check.expect(!features[0].contains(outsideLakeTahoe), "geometry excludes an outside point")
Check.expect(features[0].contains(boundaryLakeTahoe), "geometry treats boundary points as contained for deterministic review")
Check.expect(features.allSatisfy { !$0.identity.featureID.contains("MALFORMED") }, "malformed unclosed polygon fails closed")
Check.expect(features.allSatisfy { !$0.identity.featureID.contains("MULTIPOLYGON") }, "multipolygon input is outside the single-ring prototype constraint")

let tahoeFeature = features[0].identity
let truckeeFeature = features[1].identity
let sfBayFeature = features[2].identity

let tahoeLakeSource = source(
    "10337000", name: "LAKE TAHOE A TAHOE CITY CA",
    coordinate: GeographicCoordinate(latitude: 39.1807, longitude: -120.1194),
    kind: .lake, distance: 12_598
)
let truckeeOutletSource = source(
    "10338000", name: "TRUCKEE R A TAHOE CITY CA",
    coordinate: GeographicCoordinate(latitude: 39.167, longitude: -120.145),
    kind: .river, distance: 900
)
let riverReachSource = source(
    "10338500", name: "TRUCKEE R NR TRUCKEE CA",
    coordinate: truckeeRiverPoint,
    kind: .river, distance: 0
)
let sfReviewedStation = source(
    "9414290", name: "San Francisco",
    coordinate: sanFranciscoBayPoint,
    kind: .estuary,
    capabilities: [.waterLevel, .wind, .airPressure],
    distance: 0,
    namespace: "gov.noaa.coops.station"
)

private let scenarios: [Scenario] = [
    Scenario(
        caseID: "L1-tahoe-correct-station-accepted",
        input: selectedLakeTahoe,
        candidate: candidate(feature: tahoeFeature, observations: [tahoeLakeSource], evidence: standardFeatureEvidence(tahoeFeature) + [
            evidence(.sourceContainedByFeature, "NHDPlus HR fixture overlay", "Reviewed source coordinate is inside the same Lake Tahoe polygon."),
            evidence(.compatibleWaterBodyClass, "USGS site_type", "Monitoring location is classified as lake/reservoir."),
            evidence(.productAvailable, "Reviewed USGS capability input", "Water level product is explicitly reviewed as available."),
            evidence(.sameHydrologicUnit, "USGS hydrologic_unit_code", "HUC matches Lake Tahoe and is supporting evidence only.")
        ]),
        expectedDecision: .accepted,
        knownRepresentative: true
    ),
    Scenario(
        caseID: "L2-tahoe-nearby-truckee-river-rejected",
        input: selectedLakeTahoe,
        candidate: candidate(feature: tahoeFeature, observations: [truckeeOutletSource, tahoeLakeSource], evidence: standardFeatureEvidence(tahoeFeature) + [
            evidence(.proximityOnly, "USGS monitoring-locations", "Truckee River gage is nearer than the lake gage; distance is ranking evidence only."),
            evidence(.conflictingFeature, "NHDPlus HR fixture overlay", "Nearest source belongs to Truckee River, not Lake Tahoe."),
            evidence(.wrongWaterBodyClass, "USGS site_type", "River site class conflicts with selected lake feature."),
            evidence(.productAvailable, "Reviewed USGS capability input", "Water level product exists but cannot override identity conflict.")
        ]),
        expectedDecision: .rejected,
        knownRepresentative: false
    ),
    Scenario(
        caseID: "L3-tahoe-source-just-outside-polygon-needs-review",
        input: selectedLakeTahoe,
        candidate: candidate(feature: tahoeFeature, observations: [source("TAHOE-OUTSIDE", name: "Lake Tahoe Shoreline Sensor", coordinate: GeographicCoordinate(latitude: 39.1683, longitude: -120.1425), kind: .lake, distance: 80)], evidence: standardFeatureEvidence(tahoeFeature) + [
            evidence(.proximityOnly, "fixture geometry", "Source is just outside the Tahoe polygon; proximity cannot establish same-water identity."),
            evidence(.compatibleWaterBodyClass, "site metadata", "Site class is lake/reservoir."),
            evidence(.productAvailable, "fixture product catalog", "Water level product is available."),
            evidence(.nameAgreement, "normalized station name", "Name agreement is supporting evidence only.")
        ]),
        expectedDecision: .needsReview,
        knownRepresentative: nil
    ),
    Scenario(
        caseID: "L4-tahoe-same-feature-wrong-site-class-rejected",
        input: selectedLakeTahoe,
        candidate: candidate(feature: tahoeFeature, observations: [source("TAHOE-RIVER-CLASS", name: "Lake Tahoe Outlet Channel", coordinate: GeographicCoordinate(latitude: 39.1807, longitude: -120.1194), kind: .river, distance: 200)], evidence: standardFeatureEvidence(tahoeFeature) + [
            evidence(.sourceContainedByFeature, "fixture overlay", "Coordinate falls within the broad reviewed feature area."),
            evidence(.wrongWaterBodyClass, "site metadata", "Source is classified as river/stream while the selected feature is a lake."),
            evidence(.productAvailable, "fixture product catalog", "Product exists but wrong class blocks acceptance.")
        ]),
        expectedDecision: .rejected,
        knownRepresentative: false
    ),
    Scenario(
        caseID: "L5-tahoe-same-huc-only-needs-review",
        input: selectedLakeTahoe,
        candidate: candidate(feature: tahoeFeature, observations: [source("TAHOE-HUC-ONLY", name: "Upper Tahoe Basin Stage", coordinate: GeographicCoordinate(latitude: 39.26, longitude: -120.03), kind: .lake, distance: 18_000)], evidence: standardFeatureEvidence(tahoeFeature) + [
            evidence(.sameHydrologicUnit, "USGS hydrologic_unit_code", "Same HUC is basin evidence; it is not source containment or same feature identity."),
            evidence(.productAvailable, "fixture product catalog", "Water level product is available."),
            evidence(.proximityOnly, "distance", "Distance ranks candidates only.")
        ]),
        expectedDecision: .needsReview,
        knownRepresentative: nil
    ),
    Scenario(
        caseID: "R1-same-authoritative-reach-accepted",
        input: truckeeRiverPoint,
        candidate: candidate(feature: truckeeFeature, observations: [riverReachSource], evidence: standardFeatureEvidence(truckeeFeature) + [
            evidence(.sameAuthoritativeReach, "NHDPlus HR flowline topology fixture", "Monitoring location is on the same authoritative Truckee River reach."),
            evidence(.compatibleWaterBodyClass, "USGS site_type", "Monitoring location is stream/river."),
            evidence(.productAvailable, "fixture product catalog", "Water level product is available.")
        ]),
        expectedDecision: .accepted,
        knownRepresentative: true
    ),
    Scenario(
        caseID: "R2-same-watershed-different-tributary-rejected",
        input: truckeeRiverPoint,
        candidate: candidate(feature: truckeeFeature, observations: [source("TRIBUTARY-1", name: "Prosser Creek near confluence", coordinate: GeographicCoordinate(latitude: 39.33, longitude: -120.20), kind: .river, distance: 500)], evidence: standardFeatureEvidence(truckeeFeature) + [
            evidence(.sameHydrologicUnit, "USGS hydrologic_unit_code", "Same HUC does not prove same river reach."),
            evidence(.wrongTributary, "NHDPlus HR topology fixture", "Source is on Prosser Creek tributary, not the selected Truckee River reach."),
            evidence(.productAvailable, "fixture product catalog", "Product exists but wrong tributary blocks acceptance.")
        ]),
        expectedDecision: .rejected,
        knownRepresentative: false
    ),
    Scenario(
        caseID: "R3-upstream-downstream-ambiguity-needs-review",
        input: truckeeRiverPoint,
        candidate: candidate(feature: truckeeFeature, observations: [source("TRUCKEE-UPDOWN", name: "Truckee River Upstream", coordinate: GeographicCoordinate(latitude: 39.34, longitude: -120.22), kind: .river, distance: 1_700)], evidence: standardFeatureEvidence(truckeeFeature) + [
            evidence(.upstreamDownstreamAmbiguous, "topology fixture", "Upstream/downstream relation exists but representativeness for the selected reach is ambiguous."),
            evidence(.sameHydrologicUnit, "USGS hydrologic_unit_code", "Same HUC remains supporting evidence only."),
            evidence(.compatibleWaterBodyClass, "USGS site_type", "Monitoring location is stream/river."),
            evidence(.productAvailable, "fixture product catalog", "Water level product is available.")
        ]),
        expectedDecision: .needsReview,
        knownRepresentative: nil
    ),
    Scenario(
        caseID: "R4-close-parallel-disconnected-channel-rejected",
        input: truckeeRiverPoint,
        candidate: candidate(feature: truckeeFeature, observations: [source("PARALLEL-CHANNEL", name: "Parallel Drainage Canal", coordinate: GeographicCoordinate(latitude: 39.3275, longitude: -120.204), kind: .river, distance: 70)], evidence: standardFeatureEvidence(truckeeFeature) + [
            evidence(.proximityOnly, "distance", "Parallel channel is physically close."),
            evidence(.disconnectedNetwork, "topology fixture", "Parallel channel is disconnected from the selected Truckee River reach."),
            evidence(.productAvailable, "fixture product catalog", "Product exists but disconnected network blocks acceptance.")
        ]),
        expectedDecision: .rejected,
        knownRepresentative: false
    ),
    Scenario(
        caseID: "C1-sf-bay-reviewed-source-relationship-accepted",
        input: sanFranciscoBayPoint,
        candidate: candidate(feature: sfBayFeature, observations: [sfReviewedStation], evidence: standardFeatureEvidence(sfBayFeature) + [
            evidence(.reviewedSourceRelationship, "Curated Slosh source binding", "Existing reviewed San Francisco Bay Place binds NOAA station 9414290 for water level, wind, and pressure."),
            evidence(.compatibleWaterBodyClass, "NOAA station metadata", "Tidal station is compatible with bay/estuary feature."),
            evidence(.productAvailable, "Reviewed NOAA CO-OPS capability input", "Reviewed products are explicitly available.")
        ]),
        expectedDecision: .accepted,
        knownRepresentative: true
    ),
    Scenario(
        caseID: "C2-sf-bay-nearby-unrelated-coastal-station-rejected",
        input: sanFranciscoBayPoint,
        candidate: candidate(feature: sfBayFeature, observations: [source("9419999", name: "Outer Coast Test Station", coordinate: GeographicCoordinate(latitude: 37.81, longitude: -122.51), kind: .ocean, capabilities: [.waterLevel], distance: 3_200, namespace: "gov.noaa.coops.station")], evidence: standardFeatureEvidence(sfBayFeature) + [
            evidence(.proximityOnly, "NOAA CO-OPS MDAPI", "Station is nearby but outside the bay relationship."),
            evidence(.landBarrierOrDistinctBasin, "coastal topology fixture", "Station is separated from the selected bay by a headland/open-coast water mass."),
            evidence(.productAvailable, "fixture product catalog", "Product exists but distinct basin blocks acceptance.")
        ]),
        expectedDecision: .rejected,
        knownRepresentative: false
    ),
    Scenario(
        caseID: "C3-plausible-bay-station-without-association-needs-review",
        input: sanFranciscoBayPoint,
        candidate: candidate(feature: sfBayFeature, observations: [source("9410001", name: "San Francisco Bay North", coordinate: GeographicCoordinate(latitude: 37.90, longitude: -122.42), kind: .estuary, capabilities: [.waterLevel], distance: 11_000, namespace: "gov.noaa.coops.station")], evidence: standardFeatureEvidence(sfBayFeature) + [
            evidence(.proximityOnly, "NOAA CO-OPS MDAPI", "Station is plausible and nearby, but proximity is not identity."),
            evidence(.nameAgreement, "normalized station name", "Bay name overlaps; name agreement is supporting evidence only."),
            evidence(.compatibleWaterBodyClass, "NOAA station metadata", "Tidal station is compatible with bay/estuary feature."),
            evidence(.productAvailable, "fixture product catalog", "Water level product is available.")
        ]),
        expectedDecision: .needsReview,
        knownRepresentative: nil
    ),
    Scenario(
        caseID: "C4-offshore-point-not-computable",
        input: offshorePacific,
        candidate: candidate(feature: nil, observations: [], evidence: [
            evidence(.unsupportedRegion, "Authoritative feature index", "Offshore point lacks a bounded authoritative water feature in the fixture corpus.")
        ]),
        expectedDecision: .notComputable,
        knownRepresentative: nil
    ),
    Scenario(
        caseID: "A1-sensor-across-narrow-peninsula-rejected",
        input: selectedLakeTahoe,
        candidate: candidate(feature: tahoeFeature, observations: [source("PENINSULA-ACROSS", name: "Emerald Bay Across Ridge", coordinate: GeographicCoordinate(latitude: 39.09, longitude: -120.03), kind: .lake, distance: 350)], evidence: standardFeatureEvidence(tahoeFeature) + [
            evidence(.proximityOnly, "distance", "Sensor is close across a narrow peninsula."),
            evidence(.landBarrierOrDistinctBasin, "fixture topology", "Land barrier separates the candidate source from the selected feature."),
            evidence(.productAvailable, "fixture product catalog", "Product exists but land barrier blocks acceptance.")
        ]),
        expectedDecision: .rejected,
        knownRepresentative: false
    ),
    Scenario(
        caseID: "A2-lake-outlet-river-gauge-near-polygon-rejected",
        input: selectedLakeTahoe,
        candidate: candidate(feature: tahoeFeature, observations: [truckeeOutletSource], evidence: standardFeatureEvidence(tahoeFeature) + [
            evidence(.proximityOnly, "distance", "Outlet river gauge is near the lake polygon."),
            evidence(.wrongWaterBodyClass, "USGS site_type", "Outlet gauge is river/stream, not lake/reservoir."),
            evidence(.conflictingFeature, "NHDPlus HR topology fixture", "Outlet gauge belongs to the river network, not the selected lake feature."),
            evidence(.productAvailable, "fixture product catalog", "Product exists but conflict blocks acceptance.")
        ]),
        expectedDecision: .rejected,
        knownRepresentative: false
    ),
    Scenario(
        caseID: "A3-adjacent-lake-nearest-sensor-rejected",
        input: selectedLakeTahoe,
        candidate: candidate(feature: tahoeFeature, observations: [source("ADJACENT-LAKE", name: "Fallen Leaf Lake", coordinate: GeographicCoordinate(latitude: 38.93, longitude: -120.05), kind: .lake, distance: 4_000)], evidence: standardFeatureEvidence(tahoeFeature) + [
            evidence(.nameAgreement, "normalized place name", "Nearby lake name is similar regional evidence only."),
            evidence(.conflictingFeature, "authoritative feature fixture", "Source belongs to an adjacent lake feature."),
            evidence(.productAvailable, "fixture product catalog", "Product exists but adjacent feature blocks acceptance.")
        ]),
        expectedDecision: .rejected,
        knownRepresentative: false
    ),
    Scenario(
        caseID: "A4-tributaries-near-confluence-rejected",
        input: truckeeRiverPoint,
        candidate: candidate(feature: truckeeFeature, observations: [source("CONFLUENCE-TRIBUTARY", name: "Tributary near Truckee confluence", coordinate: GeographicCoordinate(latitude: 39.326, longitude: -120.206), kind: .river, distance: 120)], evidence: standardFeatureEvidence(truckeeFeature) + [
            evidence(.proximityOnly, "distance", "Tributary source is close to confluence."),
            evidence(.wrongTributary, "topology fixture", "Source is on a different tributary just before confluence."),
            evidence(.productAvailable, "fixture product catalog", "Product exists but wrong tributary blocks acceptance.")
        ]),
        expectedDecision: .rejected,
        knownRepresentative: false
    ),
    Scenario(
        caseID: "A5-estuary-versus-open-coast-station-rejected",
        input: sanFranciscoBayPoint,
        candidate: candidate(feature: sfBayFeature, observations: [source("OPEN-COAST", name: "San Francisco Ocean Beach", coordinate: GeographicCoordinate(latitude: 37.76, longitude: -122.51), kind: .ocean, capabilities: [.waterLevel], distance: 6_500, namespace: "gov.noaa.coops.station")], evidence: standardFeatureEvidence(sfBayFeature) + [
            evidence(.proximityOnly, "NOAA CO-OPS MDAPI", "Open-coast station is close to the bay."),
            evidence(.explicitMetadataConflict, "station metadata", "Station metadata identifies open coast rather than the selected bay/estuary."),
            evidence(.productAvailable, "fixture product catalog", "Product exists but metadata conflict blocks acceptance.")
        ]),
        expectedDecision: .rejected,
        knownRepresentative: false
    ),
    Scenario(
        caseID: "A6-similar-name-different-feature-rejected",
        input: sanFranciscoBayPoint,
        candidate: candidate(feature: sfBayFeature, observations: [source("SF-NAME-OTHER", name: "San Francisco Creek", coordinate: GeographicCoordinate(latitude: 37.82, longitude: -122.35), kind: .river, capabilities: [.waterLevel], distance: 8_000)], evidence: standardFeatureEvidence(sfBayFeature) + [
            evidence(.nameAgreement, "normalized station name", "Name contains San Francisco but names are not identity."),
            evidence(.explicitMetadataConflict, "authoritative feature fixture", "Candidate source belongs to a creek feature, not San Francisco Bay."),
            evidence(.productAvailable, "fixture product catalog", "Product exists but feature mismatch blocks acceptance.")
        ]),
        expectedDecision: .rejected,
        knownRepresentative: false
    )
]

private let decisions = scenarios.map { scenario -> (Scenario, WaterBodyResolutionDecision, CandidateEvidenceEvaluation) in
    let evaluation = evidenceEvaluator.evaluate(scenario.candidate)
    let decision = policy.decide(candidate: scenario.candidate, evaluation: evaluation)
    return (scenario, decision, evaluation)
}

for (scenario, decision, _) in decisions.sorted(by: { $0.0.caseID < $1.0.caseID }) {
    Check.expect(decision.confidence == scenario.expectedDecision, "\(scenario.caseID) -> \(scenario.expectedDecision.rawValue)")
}

func decision(for caseID: String) -> WaterBodyResolutionDecision {
    decisions.first { $0.0.caseID == caseID }!.1
}

Check.expect(decision(for: "L1-tahoe-correct-station-accepted").confidence == .accepted, "same polygon + compatible site can accept lake case")
Check.expect(decision(for: "L4-tahoe-same-feature-wrong-site-class-rejected").confidence == .rejected, "wrong site class blocks lake acceptance")
Check.expect(decision(for: "R2-same-watershed-different-tributary-rejected").confidence == .rejected, "wrong tributary blocks river acceptance")
Check.expect(decision(for: "R3-upstream-downstream-ambiguity-needs-review").confidence == .needsReview, "ambiguous river topology becomes needsReview")
Check.expect(decision(for: "C3-plausible-bay-station-without-association-needs-review").confidence == .needsReview, "coastal candidate without authoritative association stays needsReview")
Check.expect(decision(for: "C4-offshore-point-not-computable").confidence == .notComputable, "unsupported coordinate becomes notComputable")

let proximityOnlyLake = candidate(feature: tahoeFeature, observations: [tahoeLakeSource], evidence: standardFeatureEvidence(tahoeFeature) + [
    evidence(.proximityOnly, "distance", "Distance-only source evidence must never accept.")
])
let hucOnlyLake = candidate(feature: tahoeFeature, observations: [tahoeLakeSource], evidence: standardFeatureEvidence(tahoeFeature) + [
    evidence(.sameHydrologicUnit, "HUC", "HUC-only source evidence must never accept.")
])
let nameOnlyLake = candidate(feature: tahoeFeature, observations: [tahoeLakeSource], evidence: standardFeatureEvidence(tahoeFeature) + [
    evidence(.nameAgreement, "name", "Name-only source evidence must never accept.")
])
let hardMismatch = candidate(feature: tahoeFeature, observations: [tahoeLakeSource], evidence: standardFeatureEvidence(tahoeFeature) + [
    evidence(.conflictingFeature, "fixture", "Hard identity mismatch must block acceptance."),
    evidence(.sourceContainedByFeature, "fixture", "Even strong positive evidence cannot override a hard blocker."),
    evidence(.compatibleWaterBodyClass, "fixture", "Compatible class exists."),
    evidence(.productAvailable, "fixture", "Product exists.")
])
Check.expect(policy.decide(candidate: proximityOnlyLake, evaluation: evidenceEvaluator.evaluate(proximityOnlyLake)).confidence != .accepted, "distance alone never accepts")
Check.expect(policy.decide(candidate: hucOnlyLake, evaluation: evidenceEvaluator.evaluate(hucOnlyLake)).confidence != .accepted, "HUC alone never accepts")
Check.expect(policy.decide(candidate: nameOnlyLake, evaluation: evidenceEvaluator.evaluate(nameOnlyLake)).confidence != .accepted, "name alone never accepts")
Check.expect(policy.decide(candidate: hardMismatch, evaluation: evidenceEvaluator.evaluate(hardMismatch)).confidence == .rejected, "hard identity mismatch always blocks acceptance")

let emptyState = HydroState(observedAt: Date(timeIntervalSince1970: 0), retrievedAt: Date(timeIntervalSince1970: 0))
let emptyExperience = HydroInterpreter().interpret(emptyState, referenceDate: Date(timeIntervalSince1970: 0))
Check.expect(
    HydroInterpreter().freshness(of: emptyState, referenceDate: Date(timeIntervalSince1970: 0)) == .unavailable
        && emptyExperience.forcing.waveAmplitude == 0
        && emptyExperience.forcing.windStrength == 0
        && emptyExperience.forcing.flowStrength == 0,
    "missing environmental signals do not get synthesized during resolution or promotion"
)
Check.expect(
    WaterBodies.lakeTahoe.coverage[.waterLevel] == .supported
        && WaterBodies.lakeTahoe.coverage[.wind] == .unavailable
        && WaterBodies.lakeTahoe.coverage[.currentSpeed] == .unavailable,
    "accepted representative source does not imply complete sensor coverage"
)

private let calibrationSummary = makeCalibrationSummary(for: decisions.map { ($0.0, $0.1) })
Check.expect(calibrationSummary.falseAutomaticAccepts == 0, "false automatic accepts = 0 in calibration corpus")
Check.expect(calibrationSummary.automaticAcceptancePrecision == 1, "automatic acceptance precision is 100% for known fixture truth")
Check.expect(Set(decisions.map { $0.1.confidence }) == [.accepted, .needsReview, .rejected, .notComputable], "calibration corpus exercises every decision vocabulary value")

private let artifacts = decisions
    .sorted { $0.0.caseID < $1.0.caseID }
    .map { scenarioArtifact($0.0, decision: $0.1, evaluation: $0.2) }
private let calibrationArtifact = CalibrationArtifact(summary: calibrationSummary, cases: artifacts)
let artifactData = try encoder.encode(calibrationArtifact)
let repeatedArtifactData = try encoder.encode(calibrationArtifact)
Check.expect(artifactData == repeatedArtifactData, "all decisions are deterministic and encode repeatably")
let artifactText = String(decoding: artifactData, as: UTF8.self) + "\n"

let sourceArtifactURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources")
    .appendingPathComponent("resolutioncheck")
    .appendingPathComponent("Artifacts")
    .appendingPathComponent("rw4g-calibration-artifacts.json")
if CommandLine.arguments.contains("--write-artifacts") {
    try FileManager.default.createDirectory(
        at: sourceArtifactURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try artifactText.write(to: sourceArtifactURL, atomically: true, encoding: String.Encoding.utf8)
    print("wrote \(sourceArtifactURL.path)")
}

guard let committedArtifactURL = Bundle.module.url(
    forResource: "rw4g-calibration-artifacts",
    withExtension: "json",
    subdirectory: "Artifacts"
) else { throw CocoaError(.fileNoSuchFile) }
let committedArtifactData = try Data(contentsOf: committedArtifactURL)
Check.expect(committedArtifactData == Data(artifactText.utf8), "generated RW4G artifacts exactly match the committed deterministic review artifact")
private let roundTrip = try JSONDecoder().decode(CalibrationArtifact.self, from: Data(artifactText.utf8))
Check.expect(roundTrip == calibrationArtifact, "expanded JSON review artifacts round-trip")

print("\(calibrationSummary.fixtureCount) scenarios")
print("accepted       \(calibrationSummary.acceptedCount)")
print("needsReview    \(calibrationSummary.needsReviewCount)")
print("rejected       \(calibrationSummary.rejectedCount)")
print("notComputable  \(calibrationSummary.notComputableCount)")
print("false accepts  \(calibrationSummary.falseAutomaticAccepts)")
print(String(format: "precision      %.3f", calibrationSummary.automaticAcceptancePrecision))

if Check.failures == 0 {
    print("resolutioncheck passed (\(Check.count) checks)")
} else {
    print("resolutioncheck failed (\(Check.failures)/\(Check.count) failures)")
    exit(1)
}
