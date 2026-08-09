import Foundation
import HydroProviders
import OceanCore

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

private struct FeatureCandidateArtifact: Codable, Equatable {
    let authority: String
    let namespace: String
    let id: String
    let name: String
    let featureClass: GeographicFeatureKind
    let productKind: WaterBodyKind
    let containedSelectedPoint: Bool
    let sourceDataset: String
    let datasetVersion: String
    let collectionName: String
    let serviceReference: String
    let geometryReference: String
    let hydrologicUnitID: String?
}

private struct ObservationCandidateArtifact: Codable, Equatable {
    let provider: String
    let id: String
    let name: String
    let classHint: WaterBodyKind?
    let distanceMeters: Double
    let hucEvidence: String?
    let productEvidence: [HydroCapability]
}

private struct DecisionArtifact: Codable, Equatable {
    let confidence: ResolutionConfidence
    let reasons: [String]
}

private struct Artifact: Codable, Equatable {
    let caseID: String
    let inputCoordinate: CoordinateArtifact
    let featureCandidates: [FeatureCandidateArtifact]
    let observationCandidates: [ObservationCandidateArtifact]
    let evidenceKinds: [ResolutionEvidenceKind]
    let decision: DecisionArtifact
    let explicitReasons: [String]
}

private func fixture(_ name: String) throws -> Data {
    guard let url = Bundle.module.url(forResource: name, withExtension: "json") else { throw CocoaError(.fileNoSuchFile) }
    return try Data(contentsOf: url)
}

private func coord(_ coordinate: GeographicCoordinate) -> CoordinateArtifact {
    CoordinateArtifact(latitude: coordinate.latitude, longitude: coordinate.longitude)
}

private func featureArtifacts(_ features: [AuthoritativeGeographicFeature], selected: GeographicCoordinate) -> [FeatureCandidateArtifact] {
    features.map { feature in
        FeatureCandidateArtifact(
            authority: feature.provenance.authorityName,
            namespace: feature.identity.namespace,
            id: feature.identity.featureID,
            name: feature.identity.name,
            featureClass: feature.featureKind,
            productKind: feature.identity.kind,
            containedSelectedPoint: feature.contains(selected),
            sourceDataset: feature.provenance.datasetName,
            datasetVersion: feature.provenance.datasetVersion,
            collectionName: feature.provenance.collectionName,
            serviceReference: feature.provenance.serviceReference,
            geometryReference: feature.provenance.geometryReference,
            hydrologicUnitID: feature.hydrologicUnitID
        )
    }
}

private func observationArtifacts(_ observations: [ObservationSourceCandidate], hucEvidence: [String: String?] = [:]) -> [ObservationCandidateArtifact] {
    observations.map { source in
        ObservationCandidateArtifact(
            provider: source.namespace,
            id: source.sourceID,
            name: source.name,
            classHint: source.locationKind,
            distanceMeters: source.distanceMeters,
            hucEvidence: hucEvidence[source.sourceID] ?? nil,
            productEvidence: source.capabilities.sorted { $0.rawValue < $1.rawValue }
        )
    }
}

private func artifact(
    caseID: String,
    input: GeographicCoordinate,
    allFeatures: [AuthoritativeGeographicFeature],
    observations: [ObservationSourceCandidate],
    candidate: WaterBodyResolutionCandidate,
    decision: WaterBodyResolutionDecision,
    hucEvidence: [String: String?] = [:],
    explicitReasons: [String]
) -> Artifact {
    Artifact(
        caseID: caseID,
        inputCoordinate: coord(input),
        featureCandidates: featureArtifacts(allFeatures, selected: input),
        observationCandidates: observationArtifacts(observations, hucEvidence: hucEvidence),
        evidenceKinds: candidate.evidence.map(\.kind),
        decision: DecisionArtifact(confidence: decision.confidence, reasons: decision.reasons),
        explicitReasons: explicitReasons
    )
}

private let selectedLakeTahoe = GeographicCoordinate(latitude: 39.0968, longitude: -120.0324)
private let boundaryLakeTahoe = GeographicCoordinate(latitude: 39.16810, longitude: -120.14228)
private let outsideLakeTahoe = GeographicCoordinate(latitude: 39.40, longitude: -120.40)
private let truckeeRiverPoint = GeographicCoordinate(latitude: 39.327, longitude: -120.205)
private let sanFranciscoBay = GeographicCoordinate(latitude: 37.806305, longitude: -122.46589)
private let offshorePacific = GeographicCoordinate(latitude: 36.70, longitude: -123.80)

private let lakeTahoeSource = ObservationSourceCandidate(
    namespace: "gov.usgs.waterdata.site",
    sourceID: "10337000",
    name: "LAKE TAHOE A TAHOE CITY CA",
    coordinate: GeographicCoordinate(latitude: 39.1807, longitude: -120.1194),
    locationKind: .lake,
    capabilities: [.waterLevel],
    distanceMeters: 12_598
)

private let nearbyTruckeeRiverSource = ObservationSourceCandidate(
    namespace: "gov.usgs.waterdata.site",
    sourceID: "10338000",
    name: "TRUCKEE R A TAHOE CITY CA",
    coordinate: GeographicCoordinate(latitude: 39.167, longitude: -120.145),
    locationKind: .river,
    capabilities: [.waterLevel],
    distanceMeters: 900
)

private let riverSource = ObservationSourceCandidate(
    namespace: "gov.usgs.waterdata.site",
    sourceID: "10338500",
    name: "TRUCKEE R NR TRUCKEE CA",
    coordinate: GeographicCoordinate(latitude: 39.327, longitude: -120.205),
    locationKind: .river,
    capabilities: [],
    distanceMeters: 0
)

private let coastalSource = ObservationSourceCandidate(
    namespace: "gov.noaa.coops.station",
    sourceID: "9414290",
    name: "San Francisco",
    coordinate: GeographicCoordinate(latitude: 37.8063, longitude: -122.4659),
    locationKind: .estuary,
    capabilities: [.waterLevel, .wind, .airPressure],
    distanceMeters: 0
)

let features = try NHDPlusFeatureFixtureAdapter().decode(fixture("nhdplus-inland-features"))
let resolver = DeterministicFeatureIndexResolver(features: features)
let composer = AuthoritativeResolutionComposer()
let evaluator = WaterBodyResolutionEvaluator()
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

print("RW4F authoritative geographic feature resolver")
Check.expect(features.map(\.identity.featureID) == ["44560536", "NHDHR-16050102-TRUCKEE-RIVER-FIXTURE", "NHDHR-18050004-SAN-FRANCISCO-BAY-AREA-FIXTURE"], "NHDPlus-derived adapter preserves the official Tahoe ID and excludes malformed or unsupported geometry")
Check.expect(features[0].contains(selectedLakeTahoe), "geometry contains an interior selected point")
Check.expect(!features[0].contains(outsideLakeTahoe), "geometry excludes an outside point")
Check.expect(features[0].contains(boundaryLakeTahoe), "geometry treats boundary points as contained for deterministic review")
Check.expect(features.allSatisfy { !$0.identity.featureID.contains("MALFORMED") }, "malformed unclosed polygon fails closed")
Check.expect(features.allSatisfy { !$0.identity.featureID.contains("MULTIPOLYGON") }, "multipolygon input is outside the single-ring prototype constraint")

let acceptedCandidate = await composer.compose(
    featureResolution: resolver.resolveFeature(containing: selectedLakeTahoe),
    providerCandidates: [lakeTahoeSource],
    providerEvidence: [
        .init(kind: .sourceContainedByFeature, source: "NHDPlus HR fixture overlay", note: "Reviewed source coordinate is inside the same Lake Tahoe feature polygon."),
        .init(kind: .productAvailable, source: "Reviewed USGS capability input", note: "Water level is supplied as reviewed product evidence, not inferred from metadata."),
        .init(kind: .providerSourceVersion, source: "USGS Water Data monitoring-locations fixture", note: "Observation source identity is fixture-pinned for deterministic review.")
    ]
)
let acceptedDecision = evaluator.evaluate(acceptedCandidate)
Check.expect(acceptedDecision.confidence == .accepted, "accepted inland case requires containment, source identity evidence, class, and reviewed product evidence")

let mismatchCandidate = await composer.compose(
    featureResolution: resolver.resolveFeature(containing: selectedLakeTahoe),
    providerCandidates: [nearbyTruckeeRiverSource, lakeTahoeSource],
    providerEvidence: [
        .init(kind: .proximityOnly, source: "USGS monitoring-locations", note: "Truckee River site is nearer than the accepted lake gage, but distance does not prove water-body identity."),
        .init(kind: .conflictingFeature, source: "NHDPlus HR fixture overlay", note: "Nearest candidate is an explicit Truckee River observation source, not Lake Tahoe."),
        .init(kind: .authoritativeHydrologicID, source: "USGS monitoring-locations huc", note: "Truckee River source HUC 160501020101 differs from Lake Tahoe HUC 160501010101.")
    ]
)
let mismatchDecision = evaluator.evaluate(mismatchCandidate)
Check.expect(mismatchDecision.confidence == .rejected, "explicit nearby Truckee River source is rejected for feature mismatch")
Check.expect(mismatchCandidate.observationSources.first?.sourceID == "10338000", "distance sorts the Truckee source first")
Check.expect(mismatchDecision.confidence == .rejected, "distance cannot override authoritative feature mismatch")

let riverCandidate = await composer.compose(
    featureResolution: resolver.resolveFeature(containing: truckeeRiverPoint),
    providerCandidates: [riverSource],
    providerEvidence: [
        .init(kind: .proximityOnly, source: "USGS monitoring-locations", note: "River source is colocated, but source-to-flowline identity is not independently proven."),
        .init(kind: .hydrologicallyConnected, source: "USGS hydrologic_unit_code", note: "HUC 160501020101 agrees with the Truckee River fixture as basin evidence.")
    ]
)
let riverDecision = evaluator.evaluate(riverCandidate)
Check.expect(riverCandidate.feature?.kind == .river, "bounded river/flowline fixture produces river identity")
Check.expect(riverDecision.confidence == .needsReview, "river/stream identity remains needsReview without source-contained or product evidence")

let coastalCandidate = await composer.compose(
    featureResolution: resolver.resolveFeature(containing: sanFranciscoBay),
    providerCandidates: [coastalSource],
    providerEvidence: [
        .init(kind: .proximityOnly, source: "NOAA CO-OPS MDAPI", note: "Station proximity is evidence only and does not establish same-feature bay representativeness."),
        .init(kind: .productAvailable, source: "Reviewed NOAA CO-OPS capability input", note: "Products are available at the station, but product evidence is not a same-feature identity link.")
    ]
)
let coastalDecision = evaluator.evaluate(coastalCandidate)
Check.expect(coastalCandidate.feature?.featureID == "NHDHR-18050004-SAN-FRANCISCO-BAY-AREA-FIXTURE", "San Francisco Bay uses a conservative NHDPlus-schema scenario feature for coastal policy evaluation")
Check.expect(coastalDecision.confidence == .needsReview, "San Francisco Bay remains needsReview without same-feature NOAA station identity evidence")

let offshoreCandidate = await composer.compose(
    featureResolution: resolver.resolveFeature(containing: offshorePacific),
    providerCandidates: [],
    providerEvidence: []
)
let offshoreDecision = evaluator.evaluate(offshoreCandidate)
Check.expect(offshoreDecision.confidence == .notComputable, "offshore coordinate returns notComputable")

private let artifacts = [
    artifact(caseID: "accepted-inland-lake", input: selectedLakeTahoe, allFeatures: features, observations: [lakeTahoeSource], candidate: acceptedCandidate, decision: acceptedDecision, hucEvidence: ["10337000": "160501010101"], explicitReasons: ["Selected point is inside Lake Tahoe authoritative feature.", "Observation source identity evidence links the source to the same feature.", "Reviewed product evidence is explicit."]),
    artifact(caseID: "truckee-river-nearer-rejected", input: selectedLakeTahoe, allFeatures: features, observations: [nearbyTruckeeRiverSource, lakeTahoeSource], candidate: mismatchCandidate, decision: mismatchDecision, hucEvidence: ["10338000": "160501020101", "10337000": "160501010101"], explicitReasons: ["Truckee River observation is nearer but is a different authoritative feature.", "Distance cannot override feature mismatch."]),
    artifact(caseID: "river-flowline-needs-review", input: truckeeRiverPoint, allFeatures: features, observations: [riverSource], candidate: riverCandidate, decision: riverDecision, hucEvidence: ["10338500": "160501020101"], explicitReasons: ["Bounded flowline fixture resolves river identity.", "Source-to-feature identity and reviewed products remain insufficient for acceptance."]),
    artifact(caseID: "coastal-bay-needs-review", input: sanFranciscoBay, allFeatures: features, observations: [coastalSource], candidate: coastalCandidate, decision: coastalDecision, hucEvidence: ["9414290": "180500040000"], explicitReasons: ["San Francisco Bay has a conservative NHDPlus-schema scenario feature containing the point; it is not asserted as an authoritative extract.", "NOAA station proximity and product evidence do not prove same-feature identity.", "Coastal automatic acceptance remains prohibited."]),
    artifact(caseID: "offshore-not-computable", input: offshorePacific, allFeatures: features, observations: [], candidate: offshoreCandidate, decision: offshoreDecision, explicitReasons: ["Offshore coordinate is outside bounded inland authoritative fixture coverage."])
]

let artifactData = try encoder.encode(artifacts)
let repeatedArtifactData = try encoder.encode(artifacts)
Check.expect(artifactData == repeatedArtifactData, "repeated fixture runs encode identical deterministic artifacts")
let artifactText = String(decoding: artifactData, as: UTF8.self) + "\n"
guard let committedArtifactURL = Bundle.module.url(
    forResource: "rw4f-resolution-artifacts",
    withExtension: "json",
    subdirectory: "Artifacts"
) else { throw CocoaError(.fileNoSuchFile) }
let committedArtifactData = try Data(contentsOf: committedArtifactURL)
Check.expect(committedArtifactData == Data(artifactText.utf8), "generated artifacts exactly match the committed deterministic review artifact")
private let roundTrip = try JSONDecoder().decode([Artifact].self, from: Data(artifactText.utf8))
Check.expect(roundTrip == artifacts, "expanded JSON review artifacts round-trip")

if Check.failures == 0 {
    print("resolutioncheck passed (\(Check.count) checks)")
} else {
    print("resolutioncheck failed (\(Check.failures)/\(Check.count) failures)")
    exit(1)
}
