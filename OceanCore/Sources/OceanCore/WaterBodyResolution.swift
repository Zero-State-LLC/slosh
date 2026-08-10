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
    case reviewedSourceRelationship
    case sameAuthoritativeReach
    case upstreamDownstreamRelationship
    case upstreamDownstreamAmbiguous
    case tributaryIdentity
    case hydrologicallyConnected
    case sameHydrologicUnit
    case compatibleWaterBodyClass
    case productAvailable
    case nameAgreement
    case proximityOnly
    case geometryDatasetVersion
    case authoritativeFeatureClass
    case authoritativeFeatureName
    case authoritativeHydrologicID
    case providerSourceVersion
    case conflictingFeature
    case wrongWaterBodyClass
    case landBarrierOrDistinctBasin
    case disconnectedNetwork
    case wrongTributary
    case sourceLacksRequiredProduct
    case explicitMetadataConflict
    case unsupportedRegion
    case malformedEvidenceSource
    case sourceCoordinateUnavailable
}

public enum ResolutionEvidenceStrength: String, Sendable, Equatable, Codable {
    case required
    case identity
    case strong
    case supporting
    case weakRankingOnly
    case hardBlocker
    case notComputable
}

extension ResolutionEvidenceKind {
    public var strength: ResolutionEvidenceStrength {
        switch self {
        case .productAvailable:
            return .required
        case .sourceContainedByFeature, .sourceExplicitlyReferencesFeature,
             .reviewedSourceRelationship, .sameAuthoritativeReach:
            return .identity
        case .selectedPointContainedByFeature, .compatibleWaterBodyClass,
             .upstreamDownstreamRelationship, .tributaryIdentity:
            return .strong
        case .hydrologicallyConnected, .sameHydrologicUnit, .upstreamDownstreamAmbiguous,
             .geometryDatasetVersion, .authoritativeFeatureClass,
             .authoritativeFeatureName, .authoritativeHydrologicID,
             .providerSourceVersion:
            return .supporting
        case .nameAgreement:
            return .supporting
        case .proximityOnly:
            return .weakRankingOnly
        case .conflictingFeature, .wrongWaterBodyClass, .landBarrierOrDistinctBasin,
             .disconnectedNetwork, .wrongTributary, .sourceLacksRequiredProduct,
             .explicitMetadataConflict:
            return .hardBlocker
        case .unsupportedRegion, .malformedEvidenceSource, .sourceCoordinateUnavailable:
            return .notComputable
        }
    }
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

public enum ResolutionPolicyClass: String, Sendable, Equatable, Codable {
    case lakeReservoir
    case riverStream
    case bayEstuaryCoastal
    case unsupportedUnknown
}

public struct CandidateEvidenceEvaluation: Sendable, Equatable, Codable {
    public let policyClass: ResolutionPolicyClass
    public let evidenceKinds: Set<ResolutionEvidenceKind>
    public let hardBlockers: [ResolutionEvidence]
    public let notComputableEvidence: [ResolutionEvidence]

    public init(
        policyClass: ResolutionPolicyClass,
        evidenceKinds: Set<ResolutionEvidenceKind>,
        hardBlockers: [ResolutionEvidence],
        notComputableEvidence: [ResolutionEvidence]
    ) {
        self.policyClass = policyClass
        self.evidenceKinds = evidenceKinds
        self.hardBlockers = hardBlockers
        self.notComputableEvidence = notComputableEvidence
    }

    public func contains(_ kind: ResolutionEvidenceKind) -> Bool {
        evidenceKinds.contains(kind)
    }
}

/// Normalizes collected evidence without applying acceptance thresholds. This
/// keeps provider/feature facts separate from the deterministic product policy.
public struct CandidateEvidenceEvaluator: Sendable {
    public init() {}

    public func evaluate(_ candidate: WaterBodyResolutionCandidate) -> CandidateEvidenceEvaluation {
        let kinds = Set(candidate.evidence.map(\.kind))
        return CandidateEvidenceEvaluation(
            policyClass: Self.policyClass(for: candidate.feature),
            evidenceKinds: kinds,
            hardBlockers: candidate.evidence
                .filter { $0.kind.strength == .hardBlocker }
                .sorted(by: evidenceOrder),
            notComputableEvidence: candidate.evidence
                .filter { $0.kind.strength == .notComputable }
                .sorted(by: evidenceOrder)
        )
    }

    private static func policyClass(for feature: GeographicFeatureIdentity?) -> ResolutionPolicyClass {
        guard let feature else { return .unsupportedUnknown }
        switch feature.kind {
        case .lake:
            return .lakeReservoir
        case .river:
            return .riverStream
        case .bay, .estuary, .ocean, .sound, .gulf:
            return .bayEstuaryCoastal
        }
    }

    private func evidenceOrder(_ lhs: ResolutionEvidence, _ rhs: ResolutionEvidence) -> Bool {
        if lhs.kind.rawValue != rhs.kind.rawValue { return lhs.kind.rawValue < rhs.kind.rawValue }
        if lhs.source != rhs.source { return lhs.source < rhs.source }
        return lhs.note < rhs.note
    }
}

/// Pure class-specific resolution policy. It consumes normalized evidence and
/// returns the existing decision vocabulary; weak evidence such as distance, name,
/// or HUC can never accumulate into automatic acceptance.
public struct ResolutionPolicy: Sendable {
    public init() {}

    public func decide(
        candidate: WaterBodyResolutionCandidate,
        evaluation: CandidateEvidenceEvaluation
    ) -> WaterBodyResolutionDecision {
        if !evaluation.notComputableEvidence.isEmpty {
            return .init(
                confidence: .notComputable,
                reasons: evaluation.notComputableEvidence.map(\.note).sorted()
            )
        }
        guard candidate.feature != nil else {
            return .init(confidence: .notComputable, reasons: ["No authoritative geographic feature resolved"])
        }
        guard !candidate.observationSources.isEmpty else {
            return .init(confidence: .notComputable, reasons: ["No observation source candidates found"])
        }
        if !evaluation.hardBlockers.isEmpty {
            return .init(
                confidence: .rejected,
                reasons: evaluation.hardBlockers.map(\.note).sorted()
            )
        }

        switch evaluation.policyClass {
        case .lakeReservoir:
            return lakeReservoirDecision(evaluation)
        case .riverStream:
            return riverStreamDecision(evaluation)
        case .bayEstuaryCoastal:
            return bayEstuaryCoastalDecision(evaluation)
        case .unsupportedUnknown:
            return .init(confidence: .notComputable, reasons: ["Unsupported or unknown water-body class"])
        }
    }

    private func lakeReservoirDecision(_ evaluation: CandidateEvidenceEvaluation) -> WaterBodyResolutionDecision {
        if evaluation.contains(.selectedPointContainedByFeature)
            && evaluation.contains(.compatibleWaterBodyClass)
            && evaluation.contains(.productAvailable)
            && hasFeatureIdentityLink(evaluation) {
            return .init(
                confidence: .accepted,
                reasons: ["Lake/reservoir policy accepted: selected point, source identity, class, and product evidence all agree"]
            )
        }
        return .init(
            confidence: .needsReview,
            reasons: ["Lake/reservoir evidence exists, but automatic same-feature acceptance is not proven"]
        )
    }

    private func riverStreamDecision(_ evaluation: CandidateEvidenceEvaluation) -> WaterBodyResolutionDecision {
        if evaluation.contains(.sameAuthoritativeReach)
            && evaluation.contains(.compatibleWaterBodyClass)
            && evaluation.contains(.productAvailable) {
            return .init(
                confidence: .accepted,
                reasons: ["River/stream policy accepted: same authoritative reach, compatible source class, and product evidence agree"]
            )
        }
        if evaluation.contains(.upstreamDownstreamAmbiguous) {
            return .init(
                confidence: .needsReview,
                reasons: ["River/stream topology is ambiguous; same HUC or proximity cannot prove same reach"]
            )
        }
        return .init(
            confidence: .needsReview,
            reasons: ["River/stream evidence exists, but topology does not prove source representativeness"]
        )
    }

    private func bayEstuaryCoastalDecision(_ evaluation: CandidateEvidenceEvaluation) -> WaterBodyResolutionDecision {
        if evaluation.contains(.reviewedSourceRelationship)
            && evaluation.contains(.productAvailable)
            && evaluation.contains(.compatibleWaterBodyClass) {
            return .init(
                confidence: .accepted,
                reasons: ["Coastal policy accepted only because a reviewed maintained source relationship exists"]
            )
        }
        return .init(
            confidence: .needsReview,
            reasons: ["Coastal/bay evidence remains conservative without an authoritative basin or reviewed station relationship"]
        )
    }

    private func hasFeatureIdentityLink(_ evaluation: CandidateEvidenceEvaluation) -> Bool {
        evaluation.contains(.sourceContainedByFeature)
            || evaluation.contains(.sourceExplicitlyReferencesFeature)
            || evaluation.contains(.reviewedSourceRelationship)
    }
}

/// Deterministic evidence policy. Distance may order otherwise-valid candidates,
/// but proximity never establishes water-body identity.
public struct WaterBodyResolutionEvaluator: Sendable {
    public init() {}

    public func evaluate(_ candidate: WaterBodyResolutionCandidate) -> WaterBodyResolutionDecision {
        let evaluation = CandidateEvidenceEvaluator().evaluate(candidate)
        return ResolutionPolicy().decide(candidate: candidate, evaluation: evaluation)
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
    case candidateNotApproved
    case incompleteCoverageDeclaration
    case supportedCoverageMissingReviewedBinding(HydroCapability)
}

public struct ReviewedSourceBindingDeclaration: Sendable, Equatable, Codable {
    public let namespace: String
    public let sourceID: String
    public let capabilities: Set<HydroCapability>
    public let parameters: [String: String]

    public init(
        namespace: String,
        sourceID: String,
        capabilities: Set<HydroCapability>,
        parameters: [String: String] = [:]
    ) {
        self.namespace = namespace
        self.sourceID = sourceID
        self.capabilities = capabilities
        self.parameters = parameters
    }

    public var binding: HydroSourceBinding {
        HydroSourceBinding(
            namespace: namespace,
            sourceID: sourceID,
            capabilities: capabilities,
            parameters: parameters
        )
    }
}

public struct HydroCapabilityCoverageDeclaration: Sendable, Equatable, Codable {
    public let capability: HydroCapability
    public let availability: HydroCoverageAvailability
    public let sourceIDs: [String]
    public let note: String

    public init(
        capability: HydroCapability,
        availability: HydroCoverageAvailability,
        sourceIDs: [String],
        note: String
    ) {
        self.capability = capability
        self.availability = availability
        self.sourceIDs = sourceIDs.sorted()
        self.note = note
    }
}

public struct ReviewedResolutionApproval: Sendable, Equatable, Codable {
    public let reviewerID: String
    public let reviewedAt: Date
    public let approved: Bool
    public let notes: [String]

    public init(
        reviewerID: String,
        reviewedAt: Date,
        approved: Bool,
        notes: [String]
    ) {
        self.reviewerID = reviewerID
        self.reviewedAt = reviewedAt
        self.approved = approved
        self.notes = notes.sorted()
    }
}

public struct ReviewedWaterBodyPromotionRequest: Sendable, Equatable, Codable {
    public let candidate: WaterBodyResolutionCandidate
    public let decision: WaterBodyResolutionDecision
    public let approval: ReviewedResolutionApproval
    public let id: WaterBody.ID
    public let region: String
    public let reviewedBindings: [ReviewedSourceBindingDeclaration]
    public let coverage: [HydroCapabilityCoverageDeclaration]

    public init(
        candidate: WaterBodyResolutionCandidate,
        decision: WaterBodyResolutionDecision,
        approval: ReviewedResolutionApproval,
        id: WaterBody.ID,
        region: String,
        reviewedBindings: [ReviewedSourceBindingDeclaration],
        coverage: [HydroCapabilityCoverageDeclaration]
    ) {
        self.candidate = candidate
        self.decision = decision
        self.approval = approval
        self.id = id
        self.region = region
        self.reviewedBindings = reviewedBindings.sorted {
            if $0.namespace != $1.namespace { return $0.namespace < $1.namespace }
            return $0.sourceID < $1.sourceID
        }
        self.coverage = coverage.sorted { $0.capability.rawValue < $1.capability.rawValue }
    }
}

/// Promotion is deliberately explicit. Candidate discovery cannot manufacture a
/// product Place without an accepted decision and separately reviewed bindings.
public struct ReviewedWaterBodyPromotion: Sendable {
    public init() {}

    public func promote(_ request: ReviewedWaterBodyPromotionRequest) throws -> WaterBody {
        guard request.approval.approved else {
            throw ReviewedWaterBodyPromotionError.candidateNotApproved
        }
        try validateCompleteCoverage(
            request.coverage,
            reviewedBindings: request.reviewedBindings
        )
        return try promote(
            request.candidate,
            decision: request.decision,
            id: request.id,
            region: request.region,
            reviewedBindings: request.reviewedBindings.map(\.binding)
        )
    }

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

    private func validateCompleteCoverage(
        _ coverage: [HydroCapabilityCoverageDeclaration],
        reviewedBindings: [ReviewedSourceBindingDeclaration]
    ) throws {
        let declared = Set(coverage.map(\.capability))
        guard declared == Set(HydroCapability.allCases), coverage.count == HydroCapability.allCases.count else {
            throw ReviewedWaterBodyPromotionError.incompleteCoverageDeclaration
        }
        for declaration in coverage where declaration.availability == .supported {
            let sourceIDs = Set(declaration.sourceIDs)
            let backed = reviewedBindings.contains { binding in
                sourceIDs.contains(binding.sourceID)
                    && binding.capabilities.contains(declaration.capability)
            }
            guard backed else {
                throw ReviewedWaterBodyPromotionError.supportedCoverageMissingReviewedBinding(
                    declaration.capability
                )
            }
        }
    }
}
