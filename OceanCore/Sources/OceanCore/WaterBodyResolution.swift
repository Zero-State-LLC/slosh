import Foundation

public struct GeographicCoordinate: Sendable, Equatable, Hashable, Codable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    public var isValid: Bool {
        latitude.isFinite && longitude.isFinite
            && (-90 ... 90).contains(latitude)
            && (-180 ... 180).contains(longitude)
    }
}

public struct GeographicFeatureIdentity: Sendable, Equatable, Codable {
    public let namespace: String
    public let featureID: String
    public let name: String
    public let kind: WaterBodyKind
    public let representativeCoordinate: GeographicCoordinate

    public init(
        namespace: String,
        featureID: String,
        name: String,
        kind: WaterBodyKind,
        representativeCoordinate: GeographicCoordinate
    ) {
        self.namespace = namespace
        self.featureID = featureID
        self.name = name
        self.kind = kind
        self.representativeCoordinate = representativeCoordinate
    }
}

public struct ObservationSourceCandidate: Sendable, Equatable, Codable {
    public let namespace: String
    public let sourceID: String
    public let name: String
    public let coordinate: GeographicCoordinate
    public let locationKind: WaterBodyKind?
    public let capabilities: Set<HydroCapability>
    public let distanceMeters: Double

    public init(
        namespace: String,
        sourceID: String,
        name: String,
        coordinate: GeographicCoordinate,
        locationKind: WaterBodyKind?,
        capabilities: Set<HydroCapability>,
        distanceMeters: Double
    ) {
        self.namespace = namespace
        self.sourceID = sourceID
        self.name = name
        self.coordinate = coordinate
        self.locationKind = locationKind
        self.capabilities = capabilities
        self.distanceMeters = distanceMeters
    }
}

public enum ResolutionEvidenceKind: String, Sendable, Equatable, Codable {
    case selectedPointContainedByFeature
    case sourceContainedByFeature
    case sourceExplicitlyReferencesFeature
    case hydrologicallyConnected
    case compatibleWaterBodyClass
    case productAvailable
    case nameAgreement
    case proximityOnly
    case conflictingFeature
    case unsupportedRegion
}

public struct ResolutionEvidence: Sendable, Equatable, Codable {
    public let kind: ResolutionEvidenceKind
    public let source: String
    public let note: String

    public init(kind: ResolutionEvidenceKind, source: String, note: String) {
        self.kind = kind
        self.source = source
        self.note = note
    }
}

public enum ResolutionConfidence: String, Sendable, Equatable, Codable {
    case accepted
    case needsReview
    case rejected
    case notComputable
}

public struct WaterBodyResolutionCandidate: Sendable, Equatable, Codable {
    public let feature: GeographicFeatureIdentity?
    public let observationSources: [ObservationSourceCandidate]
    public let evidence: [ResolutionEvidence]

    public init(
        feature: GeographicFeatureIdentity?,
        observationSources: [ObservationSourceCandidate],
        evidence: [ResolutionEvidence]
    ) {
        self.feature = feature
        self.observationSources = observationSources
        self.evidence = evidence
    }
}

public struct WaterBodyResolutionDecision: Sendable, Equatable, Codable {
    public let confidence: ResolutionConfidence
    public let reasons: [String]

    public init(confidence: ResolutionConfidence, reasons: [String]) {
        self.confidence = confidence
        self.reasons = reasons
    }
}

/// Deterministic evidence policy. Distance may order otherwise-valid candidates,
/// but proximity never establishes water-body identity.
public struct WaterBodyResolutionEvaluator: Sendable {
    public init() {}

    public func evaluate(_ candidate: WaterBodyResolutionCandidate) -> WaterBodyResolutionDecision {
        let kinds = Set(candidate.evidence.map(\.kind))
        if kinds.contains(.unsupportedRegion) {
            return .init(confidence: .notComputable, reasons: ["No supported authoritative feature/provider coverage"])
        }
        if kinds.contains(.conflictingFeature) {
            return .init(confidence: .rejected, reasons: ["Candidate source belongs to a conflicting geographic feature"])
        }
        guard candidate.feature != nil else {
            return .init(confidence: .notComputable, reasons: ["No authoritative geographic feature resolved"])
        }
        guard !candidate.observationSources.isEmpty else {
            return .init(confidence: .notComputable, reasons: ["No observation source candidates found"])
        }

        let hasFeatureContainment = kinds.contains(.selectedPointContainedByFeature)
        let hasCompatibleClass = kinds.contains(.compatibleWaterBodyClass)
        let hasProduct = kinds.contains(.productAvailable)
        let hasIdentityLink = kinds.contains(.sourceContainedByFeature)
            || kinds.contains(.sourceExplicitlyReferencesFeature)
        if hasFeatureContainment && hasCompatibleClass && hasProduct && hasIdentityLink {
            return .init(
                confidence: .accepted,
                reasons: ["Authoritative feature and observation source identity evidence agree"]
            )
        }

        return .init(
            confidence: .needsReview,
            reasons: ["Candidates exist, but same-water-body identity is not proven"]
        )
    }
}

public protocol WaterBodyResolutionCandidateProvider: Sendable {
    func candidates(at coordinate: GeographicCoordinate) async -> [WaterBodyResolutionCandidate]
}

/// Deterministic research-only provider. It performs no network or geographic
/// inference and is suitable for proving resolution policy in command-line tests.
public struct FixtureWaterBodyResolutionCandidateProvider: WaterBodyResolutionCandidateProvider {
    public let fixtures: [GeographicCoordinate: [WaterBodyResolutionCandidate]]

    public init(fixtures: [GeographicCoordinate: [WaterBodyResolutionCandidate]]) {
        self.fixtures = fixtures
    }

    public func candidates(at coordinate: GeographicCoordinate) async -> [WaterBodyResolutionCandidate] {
        fixtures[coordinate] ?? []
    }
}

public enum ReviewedWaterBodyPromotionError: Error, Sendable, Equatable {
    case candidateNotAccepted
    case missingFeature
    case missingReviewedBindings
}

/// Promotion is deliberately explicit. Candidate discovery cannot manufacture a
/// product Place without an accepted decision and separately reviewed bindings.
public struct ReviewedWaterBodyPromotion: Sendable {
    public init() {}

    public func promote(
        _ candidate: WaterBodyResolutionCandidate,
        decision: WaterBodyResolutionDecision,
        id: WaterBody.ID,
        region: String,
        reviewedBindings: [HydroSourceBinding]
    ) throws -> WaterBody {
        guard decision.confidence == .accepted else {
            throw ReviewedWaterBodyPromotionError.candidateNotAccepted
        }
        guard let feature = candidate.feature else {
            throw ReviewedWaterBodyPromotionError.missingFeature
        }
        guard !reviewedBindings.isEmpty else {
            throw ReviewedWaterBodyPromotionError.missingReviewedBindings
        }
        return WaterBody(
            id: id,
            name: feature.name,
            region: region,
            latitude: feature.representativeCoordinate.latitude,
            longitude: feature.representativeCoordinate.longitude,
            kind: feature.kind,
            sourceBindings: reviewedBindings
        )
    }
}
