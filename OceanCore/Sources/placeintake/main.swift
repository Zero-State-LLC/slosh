import Foundation
import OceanCore

private enum IntakeCLIError: Error, CustomStringConvertible {
    case usage
    case missingValue(String)

    var description: String {
        switch self {
        case .usage:
            return "usage: swift run placeintake --input request.json [--output artifact.json]\n       swift run placeintake --example [--output request.json]"
        case let .missingValue(option):
            return "missing value for \(option)"
        }
    }
}

private struct Options {
    var input: String?
    var output: String?
    var example = false
}

private func parseOptions() throws -> Options {
    var options = Options()
    var arguments = Array(CommandLine.arguments.dropFirst())
    while !arguments.isEmpty {
        let argument = arguments.removeFirst()
        switch argument {
        case "--input":
            guard !arguments.isEmpty else { throw IntakeCLIError.missingValue(argument) }
            options.input = arguments.removeFirst()
        case "--output":
            guard !arguments.isEmpty else { throw IntakeCLIError.missingValue(argument) }
            options.output = arguments.removeFirst()
        case "--example":
            options.example = true
        default:
            throw IntakeCLIError.usage
        }
    }
    guard options.example != (options.input != nil) else { throw IntakeCLIError.usage }
    return options
}

private func encoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    return encoder
}

private func decoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
}

private func write(_ data: Data, to output: String?) throws {
    var terminated = data
    terminated.append(0x0A)
    if let output {
        try terminated.write(to: URL(fileURLWithPath: output), options: .atomic)
    } else {
        FileHandle.standardOutput.write(terminated)
    }
}

private func exampleRequest() -> ReviewedPlaceIntakeRequest {
    let coordinate = GeographicCoordinate(latitude: 39.1807175, longitude: -120.1193368)
    let feature = GeographicFeatureIdentity(
        namespace: "gov.usgs.nhdplus.waterbody",
        featureID: "155185252",
        name: "Lake Tahoe",
        kind: .lake,
        representativeCoordinate: coordinate
    )
    let source = ObservationSourceCandidate(
        namespace: "gov.usgs.nwis.iv",
        sourceID: "10337000",
        name: "Lake Tahoe A Tahoe City CA",
        coordinate: coordinate,
        locationKind: .lake,
        capabilities: [.waterLevel],
        distanceMeters: 0
    )
    let candidate = WaterBodyResolutionCandidate(
        feature: feature,
        observationSources: [source],
        evidence: [
            ResolutionEvidence(kind: .selectedPointContainedByFeature, source: "NHDPlus review artifact", note: "Selected point lies within the stable reviewed lake identity."),
            ResolutionEvidence(kind: .sourceContainedByFeature, source: "reviewed overlay", note: "Source coordinate lies within the reviewed feature."),
            ResolutionEvidence(kind: .compatibleWaterBodyClass, source: "reviewed metadata", note: "Source and feature are both lakes."),
            ResolutionEvidence(kind: .productAvailable, source: "USGS product review", note: "Gage height is available."),
        ]
    )
    let decision = WaterBodyResolutionEvaluator().evaluate(candidate)
    let binding = ReviewedSourceBindingDeclaration(
        namespace: source.namespace,
        sourceID: source.sourceID,
        capabilities: source.capabilities,
        parameters: ["waterLevelParameter": "00065"]
    )
    let coverage = HydroCapability.allCases.map { capability in
        HydroCapabilityCoverageDeclaration(
            capability: capability,
            availability: capability == .waterLevel ? .supported : .unavailable,
            sourceIDs: capability == .waterLevel ? [source.sourceID] : [],
            note: capability == .waterLevel ? "Reviewed USGS gage-height coverage." : "No reviewed source supports this signal."
        )
    }
    let promotion = ReviewedWaterBodyPromotionRequest(
        candidate: candidate,
        decision: decision,
        approval: ReviewedResolutionApproval(
            reviewerID: "replace-with-reviewer-id",
            reviewedAt: Date(timeIntervalSince1970: 0),
            approved: true,
            notes: ["Replace this example evidence with a real review record."]
        ),
        id: "lake-tahoe-example",
        region: "California / Nevada, USA",
        reviewedBindings: [binding],
        coverage: coverage
    )
    return ReviewedPlaceIntakeRequest(
        promotion: promotion,
        verificationEvidence: ProductVerificationEvidenceKind.allCases.map { kind in
            ProductVerificationEvidence(
                kind: kind,
                verified: true,
                source: "replace-with-evidence-reference",
                note: "Replace this example with captured product verification evidence."
            )
        }
    )
}

do {
    let options = try parseOptions()
    if options.example {
        try write(encoder().encode(exampleRequest()), to: options.output)
    } else if let input = options.input {
        let request = try decoder().decode(
            ReviewedPlaceIntakeRequest.self,
            from: Data(contentsOf: URL(fileURLWithPath: input))
        )
        let artifact = try ReviewedPlaceIntake().build(request)
        try write(encoder().encode(artifact), to: options.output)
    }
} catch {
    FileHandle.standardError.write(Data("placeintake: \(error)\n".utf8))
    exit(1)
}
