import Foundation
import OceanCore

public struct NOAAProductSample: Sendable, Equatable {
    public let observedAt: Date
    public var waterLevel: HydroMeasurement?
    public var waterTemperature: HydroMeasurement?
    public var currentSpeed: HydroMeasurement?
    public var currentDirection: HydroMeasurement?
    public var windSpeed: HydroMeasurement?
    public var windDirection: HydroMeasurement?
    public var pressure: HydroMeasurement?
    public var salinity: HydroMeasurement?

    public init(observedAt: Date) {
        self.observedAt = observedAt
    }

    public var hasMeasurement: Bool {
        waterLevel != nil || waterTemperature != nil || currentSpeed != nil
            || currentDirection != nil || windSpeed != nil || windDirection != nil
            || pressure != nil || salinity != nil
    }
}

public enum NOAAHydroAdapter {
    public static func decode(
        _ data: Data,
        product: NOAAProduct,
        stationID: String
    ) throws -> NOAAProductSample {
        let response: NOAAResponse
        do {
            response = try JSONDecoder().decode(NOAAResponse.self, from: data)
        } catch {
            throw NOAAProviderError.malformedResponse
        }

        if let message = response.error?.message {
            throw NOAAProviderError.providerMessage(message)
        }
        guard let observation = response.data?.first else {
            throw NOAAProviderError.noUsableMeasurements
        }
        guard let observedAt = parseTimestamp(observation.t) else {
            throw NOAAProviderError.malformedTimestamp(observation.t)
        }

        var sample = NOAAProductSample(observedAt: observedAt)
        let quality = mapQuality(flags: observation.f, assurance: observation.q, product: product)
        let sourcePrefix = "noaa.coops.\(stationID).\(product.rawValue)"

        switch product {
        case .waterLevel:
            sample.waterLevel = measurement(
                observation.v, unit: .meters, quality: quality,
                sourceID: sourcePrefix, observedAt: observedAt
            )
        case .waterTemperature:
            sample.waterTemperature = measurement(
                observation.v, unit: .celsius, quality: quality,
                sourceID: sourcePrefix, observedAt: observedAt
            )
        case .wind:
            sample.windSpeed = measurement(
                observation.s, unit: .metersPerSecond, quality: quality,
                sourceID: "\(sourcePrefix).speed", observedAt: observedAt
            )
            sample.windDirection = measurement(
                observation.d, unit: .degreesTrue, quality: quality,
                sourceID: "\(sourcePrefix).direction", observedAt: observedAt,
                directionConvention: .from
            )
        case .airPressure:
            sample.pressure = measurement(
                observation.v, unit: .hectopascals, quality: quality,
                sourceID: sourcePrefix, observedAt: observedAt
            )
        case .salinity:
            sample.salinity = measurement(
                observation.s, unit: .practicalSalinityUnits, quality: quality,
                sourceID: sourcePrefix, observedAt: observedAt
            )
        case .currents:
            // NOAA metric currents are centimeters per second. CO-OPS current
            // bearings use the oceanographic convention: where water flows toward.
            sample.currentSpeed = measurement(
                observation.s, unit: .metersPerSecond, quality: quality,
                sourceID: "\(sourcePrefix).speed", observedAt: observedAt,
                transform: { $0 / 100 }
            )
            sample.currentDirection = measurement(
                observation.d, unit: .degreesTrue, quality: quality,
                sourceID: "\(sourcePrefix).direction", observedAt: observedAt,
                directionConvention: .toward
            )
        }
        return sample
    }

    /// CO-OPS QC flags vary by product and include leading count in water-level.
    public static func mapQuality(
        flags: String?,
        assurance: String?,
        product: NOAAProduct = .waterLevel
    ) -> HydroQuality {
        guard let flags, !flags.isEmpty else { return .unknown }
        let values = Array(flags.split(separator: ",", omittingEmptySubsequences: false))
        let relevantFlags = relevantQualityFlags(for: product, in: values)

        if relevantFlags.contains(where: { $0.trimmingCharacters(in: .whitespaces) != "0" }) {
            return .suspect
        }
        if let assurance, !["p", "v"].contains(assurance.lowercased()) {
            return .unknown
        }
        return .good
    }

    /// Product-specific interpretation of NOAA quality flags:
    /// - waterLevel: first flag is sample-count and must be dropped.
    /// - currents/salinity: CO-OPS payloads do not carry useful QC flags.
    /// - all others: all flags are direct QC booleans.
    private static let qualityFlagPolicy: [NOAAProduct: QualityFlagPolicy] = [
        .waterLevel: .skipLeading(1),
        .currents: .ignore,
        .salinity: .ignore
    ]

    private enum QualityFlagPolicy {
        case useAll
        case skipLeading(Int)
        case ignore
    }

    private static func relevantQualityFlags(
        for product: NOAAProduct,
        in values: [Substring]
    ) -> ArraySlice<Substring> {
        let policy = qualityFlagPolicy[product] ?? .useAll
        switch policy {
        case .useAll:
            return values[...]
        case let .skipLeading(count):
            return values.dropFirst(count)
        case .ignore:
            return []
        }
    }

    public static func parseTimestamp(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.isLenient = false
        return formatter.date(from: value)
    }

    private static func measurement(
        _ rawValue: String?,
        unit: HydroUnit,
        quality: HydroQuality,
        sourceID: String,
        observedAt: Date,
        directionConvention: HydroDirectionConvention? = nil,
        transform: (Double) -> Double = { $0 }
    ) -> HydroMeasurement? {
        guard let rawValue,
              !rawValue.isEmpty,
              rawValue.lowercased() != "null",
              let decoded = Double(rawValue),
              decoded.isFinite else { return nil }
        let value = transform(decoded)
        guard value.isFinite else { return nil }
        return HydroMeasurement(
            value: value,
            unit: unit,
            origin: .observed,
            quality: quality,
            sourceID: sourceID,
            observedAt: observedAt,
            directionConvention: directionConvention
        )
    }
}

private struct NOAAResponse: Decodable {
    let data: [NOAAObservation]?
    let error: NOAAErrorResponse?
}

private struct NOAAObservation: Decodable {
    let t: String
    let v: String?
    let s: String?
    let d: String?
    let f: String?
    let q: String?
}

private struct NOAAErrorResponse: Decodable {
    let message: String
}
