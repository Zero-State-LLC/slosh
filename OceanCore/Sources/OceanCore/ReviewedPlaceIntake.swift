import Foundation

public enum ProductVerificationEvidenceKind: String, Sendable, Equatable, CaseIterable, Codable {
    case featureIdentity
    case sourceBinding
    case capabilityCoverage
    case productPresentation
}

public struct ProductVerificationEvidence: Sendable, Equatable, Codable {
    public let kind: ProductVerificationEvidenceKind
    public let verified: Bool
    public let source: String
    public let note: String

    public init(kind: ProductVerificationEvidenceKind, verified: Bool, source: String, note: String) {
        self.kind = kind
        self.verified = verified
        self.source = source
        self.note = note
    }
}

public struct ReviewedPlaceIntakeRequest: Sendable, Equatable, Codable {
    public let schemaVersion: Int
    public let promotion: ReviewedWaterBodyPromotionRequest
    public let verificationEvidence: [ProductVerificationEvidence]

    public init(
        schemaVersion: Int = 1,
        promotion: ReviewedWaterBodyPromotionRequest,
        verificationEvidence: [ProductVerificationEvidence]
    ) {
        self.schemaVersion = schemaVersion
        self.promotion = promotion
        self.verificationEvidence = verificationEvidence.sorted {
            if $0.kind.rawValue != $1.kind.rawValue { return $0.kind.rawValue < $1.kind.rawValue }
            if $0.source != $1.source { return $0.source < $1.source }
            return $0.note < $1.note
        }
    }
}

public struct ReviewedPlaceArtifact: Sendable, Equatable, Codable {
    public let id: String
    public let name: String
    public let region: String
    public let latitude: Double
    public let longitude: Double
    public let kind: WaterBodyKind
    public let reviewedBindings: [ReviewedSourceBindingDeclaration]
    public let coverage: [HydroCapabilityCoverageDeclaration]

    public init(waterBody: WaterBody, request: ReviewedWaterBodyPromotionRequest) {
        id = waterBody.id
        name = waterBody.name
        region = waterBody.region
        latitude = waterBody.latitude
        longitude = waterBody.longitude
        kind = waterBody.kind
        reviewedBindings = request.reviewedBindings
        coverage = request.coverage
    }
}

public struct ReviewedPlaceIntakeArtifact: Sendable, Equatable, Codable {
    public let schemaVersion: Int
    public let reviewerID: String
    public let reviewedAt: Date
    public let decision: WaterBodyResolutionDecision
    public let verificationEvidence: [ProductVerificationEvidence]
    public let place: ReviewedPlaceArtifact
}

public enum ReviewedPlaceIntakeError: Error, Sendable, Equatable {
    case unsupportedSchemaVersion(Int)
    case incompleteVerificationEvidence
    case failedVerification(ProductVerificationEvidenceKind)
}

/// Converts an approved RW4H request into a deterministic, reviewable intake
/// artifact. It does not mutate the shipping catalog or create product UI.
public struct ReviewedPlaceIntake: Sendable {
    public init() {}

    public func build(_ request: ReviewedPlaceIntakeRequest) throws -> ReviewedPlaceIntakeArtifact {
        guard request.schemaVersion == 1 else {
            throw ReviewedPlaceIntakeError.unsupportedSchemaVersion(request.schemaVersion)
        }

        let evidenceByKind = Dictionary(grouping: request.verificationEvidence, by: \.kind)
        guard Set(evidenceByKind.keys) == Set(ProductVerificationEvidenceKind.allCases) else {
            throw ReviewedPlaceIntakeError.incompleteVerificationEvidence
        }
        for kind in ProductVerificationEvidenceKind.allCases {
            guard evidenceByKind[kind]?.allSatisfy(\.verified) == true else {
                throw ReviewedPlaceIntakeError.failedVerification(kind)
            }
        }

        let waterBody = try ReviewedWaterBodyPromotion().promote(request.promotion)
        return ReviewedPlaceIntakeArtifact(
            schemaVersion: request.schemaVersion,
            reviewerID: request.promotion.approval.reviewerID,
            reviewedAt: request.promotion.approval.reviewedAt,
            decision: request.promotion.decision,
            verificationEvidence: request.verificationEvidence,
            place: ReviewedPlaceArtifact(waterBody: waterBody, request: request.promotion)
        )
    }
}
