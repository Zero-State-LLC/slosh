import Foundation
import OceanCore

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum NOAAProduct: String, Sendable, CaseIterable {
    case waterLevel = "water_level"
    case waterTemperature = "water_temperature"
    case wind
    case airPressure = "air_pressure"
    case salinity
    case currents
}

public enum NOAAProviderError: Error, Sendable, Equatable, CustomStringConvertible {
    case invalidRequest
    case httpStatus(Int)
    case providerMessage(String)
    case malformedResponse
    case malformedTimestamp(String)
    case unsupportedUnit(String)
    case noUsableMeasurements

    public var description: String {
        switch self {
        case .invalidRequest: return "Invalid NOAA request"
        case let .httpStatus(code): return "NOAA HTTP status \(code)"
        case let .providerMessage(message): return "NOAA error: \(message)"
        case .malformedResponse: return "Malformed NOAA response"
        case let .malformedTimestamp(value): return "Malformed NOAA GMT timestamp: \(value)"
        case let .unsupportedUnit(unit): return "Unsupported NOAA unit: \(unit)"
        case .noUsableMeasurements: return "NOAA returned no usable measurements"
        }
    }
}

public struct NOAARequest: Sendable, Equatable {
    public static let baseURL = URL(string: "https://api.tidesandcurrents.noaa.gov/api/prod/datagetter")!
    public static let application = "Slosh"
    public static let waterLevelDatum = "MLLW"

    public let stationID: String
    public let product: NOAAProduct
    public let bin: Int?

    public init(stationID: String, product: NOAAProduct, bin: Int? = nil) {
        self.stationID = stationID
        self.product = product
        self.bin = bin
    }

    public var url: URL? {
        var components = URLComponents(url: Self.baseURL, resolvingAgainstBaseURL: false)
        var items = [
            URLQueryItem(name: "date", value: "latest"),
            URLQueryItem(name: "station", value: stationID),
            URLQueryItem(name: "product", value: product.rawValue),
            URLQueryItem(name: "time_zone", value: "gmt"),
            URLQueryItem(name: "units", value: "metric"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "application", value: Self.application),
        ]
        if product == .waterLevel {
            items.append(URLQueryItem(name: "datum", value: Self.waterLevelDatum))
        }
        if let bin {
            items.append(URLQueryItem(name: "bin", value: String(bin)))
        }
        components?.queryItems = items
        return components?.url
    }
}
