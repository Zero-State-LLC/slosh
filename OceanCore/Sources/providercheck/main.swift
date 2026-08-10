import Foundation
import HydroProviders
import OceanCore

private enum Check {
    static var failures = 0
    static var count = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        count += 1
        if condition() {
            print("  ✓ \(message)")
        } else {
            failures += 1
            print("  ✗ \(message)")
        }
    }

    static func equal(_ actual: Double?, _ expected: Double, _ message: String, tolerance: Double = 1e-9) {
        expect(actual.map { abs($0 - expected) <= tolerance } == true, message)
    }
}

private func fixture(_ name: String) throws -> Data {
    guard let url = Bundle.module.url(forResource: name, withExtension: "json") else {
        throw CocoaError(.fileNoSuchFile)
    }
    return try Data(contentsOf: url)
}

/// Fails a chosen site while others succeed, and records how concurrently the
/// requests actually ran.
private actor PartialUSGSTransport: USGSDataTransport {
    private let payload: Data
    private let failingSiteFragment: String
    private var inFlight = 0
    private(set) var peakInFlight = 0
    private(set) var attempts = 0

    init(payload: Data, failingSiteFragment: String) {
        self.payload = payload
        self.failingSiteFragment = failingSiteFragment
    }

    func data(from url: URL) async throws -> Data {
        attempts += 1
        inFlight += 1
        peakInFlight = max(peakInFlight, inFlight)
        defer { inFlight -= 1 }
        // Long enough that a serial loop cannot overlap two requests.
        try await Task.sleep(nanoseconds: 60_000_000)
        if url.absoluteString.contains(failingSiteFragment) {
            throw USGSIVError.httpStatus(503)
        }
        return payload
    }

    func stats() -> (attempts: Int, peak: Int) { (attempts, peakInFlight) }
}

/// Cancels the way the network does, from beneath the USGS provider.
private actor URLCancellingUSGSTransport: USGSDataTransport {
    private(set) var attempts = 0

    func data(from url: URL) async throws -> Data {
        attempts += 1
        throw URLError(.cancelled)
    }

    func count() -> Int { attempts }
}

private struct FixtureUSGSTransport: USGSDataTransport {
    let payload: Data
    func data(from url: URL) async throws -> Data { payload }
}

private actor URLCancelledNOAATransport: NOAADataTransport {
    private let payloads: [String: Data]
    private(set) var requestedProducts: [String] = []

    init(payloads: [String: Data]) {
        self.payloads = payloads
    }

    func data(from url: URL) async throws -> Data {
        let product = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "product" })?
            .value ?? ""
        requestedProducts.append(product)
        if product == "wind" { throw URLError(.cancelled) }
        guard let payload = payloads[product] else { throw NOAAProviderError.noUsableMeasurements }
        return payload
    }

    func products() -> [String] { requestedProducts }
}

actor ProductPayloadNOAATransport: NOAADataTransport {
    private let payloads: [String: Data]
    private let productWithFailure: String?
    private let failure: Error
    private(set) var requestedProducts: [String] = []

    init(payloads: [String: Data], productWithFailure: String? = nil, failure: Error = NOAAProviderError.noUsableMeasurements) {
        self.payloads = payloads
        self.productWithFailure = productWithFailure
        self.failure = failure
    }

    func data(from url: URL) async throws -> Data {
        let product = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "product" })?
            .value ?? ""
        requestedProducts.append(product)
        if product == productWithFailure { throw failure }
        guard let payload = payloads[product] else {
            throw NOAAProviderError.noUsableMeasurements
        }
        return payload
    }

    func products() -> [String] { requestedProducts }
}

actor PerProductNOAATransport: NOAADataTransport {
    private let payloads: [String: Data]
    private let failures: [String: Error]
    private(set) var requestedProducts: [String] = []

    init(payloads: [String: Data], failures: [String: Error]) {
        self.payloads = payloads
        self.failures = failures
    }

    func data(from url: URL) async throws -> Data {
        let product = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "product" })?
            .value ?? ""
        requestedProducts.append(product)
        if let failure = failures[product] { throw failure }
        guard let payload = payloads[product] else {
            throw NOAAProviderError.noUsableMeasurements
        }
        return payload
    }

    func products() -> [String] { requestedProducts }
}

private actor ConcurrentNOAATransport: NOAADataTransport {
    private let payloads: [String: Data]
    private var activeRequests = 0
    private(set) var maxActiveRequests = 0

    init(payloads: [String: Data]) {
        self.payloads = payloads
    }

    func data(from url: URL) async throws -> Data {
        let product = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "product" })?
            .value ?? ""
        activeRequests += 1
        maxActiveRequests = max(maxActiveRequests, activeRequests)
        try await Task.sleep(nanoseconds: 50_000_000)
        activeRequests -= 1
        guard let payload = payloads[product] else { throw NOAAProviderError.noUsableMeasurements }
        return payload
    }

    func maximumActiveRequests() -> Int { maxActiveRequests }
}

private actor SequencedProvider: HydroStateProvider {
    enum Result: Sendable {
        case success(HydroState)
        case failure
    }

    private var results: [Result]
    private(set) var fetchCount = 0
    private(set) var fetchedWaterBodyIDs: [WaterBody.ID] = []

    init(_ results: [Result]) {
        self.results = results
    }

    func fetch(_ waterBody: WaterBody) async throws -> HydroState {
        fetchCount += 1
        fetchedWaterBodyIDs.append(waterBody.id)
        guard !results.isEmpty else { throw NOAAProviderError.noUsableMeasurements }
        switch results.removeFirst() {
        case let .success(state): return state
        case .failure: throw NOAAProviderError.noUsableMeasurements
        }
    }

    func count() -> Int { fetchCount }
    func fetchedIDs() -> [WaterBody.ID] { fetchedWaterBodyIDs }
}

private actor FixedProvider: HydroStateProvider {
    enum Outcome: Sendable {
        case success(HydroState)
        case failure
    }

    let outcome: Outcome
    private(set) var fetchCount = 0

    init(_ outcome: Outcome) { self.outcome = outcome }

    func fetch(_ waterBody: WaterBody) async throws -> HydroState {
        fetchCount += 1
        switch outcome {
        case let .success(state): return state
        case .failure: throw RoutedHydroProviderError.noUsableMeasurements
        }
    }

    func count() -> Int { fetchCount }
}

/// Blocks until released, so a second caller genuinely overlaps the first.
private actor GatedProvider: HydroStateProvider {
    private let state: HydroState
    private var released = false
    private(set) var fetchCount = 0

    init(state: HydroState) {
        self.state = state
    }

    func release() { released = true }

    func fetch(_ waterBody: WaterBody) async throws -> HydroState {
        fetchCount += 1
        while !released {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        return state
    }

    func count() -> Int { fetchCount }
}

/// Always cancels the way the network does, and counts how often it is asked.
private actor AlwaysCancellingProvider: HydroStateProvider {
    private(set) var fetchCount = 0

    func fetch(_ waterBody: WaterBody) async throws -> HydroState {
        fetchCount += 1
        throw URLError(.cancelled)
    }

    func count() -> Int { fetchCount }
}

private actor URLCancelledThenSuccessProvider: HydroStateProvider {
    private let state: HydroState
    private var canceledOnce = false
    private(set) var fetchCount = 0

    init(state: HydroState) {
        self.state = state
    }

    func fetch(_ waterBody: WaterBody) async throws -> HydroState {
        fetchCount += 1
        if !canceledOnce {
            canceledOnce = true
            throw URLError(.cancelled)
        }
        return state
    }

    func count() -> Int { fetchCount }
}

actor CancellationThenSuccessProvider: HydroStateProvider {
    private let canceledWaterBodyID: WaterBody.ID
    private let states: [WaterBody.ID: HydroState]
    private(set) var fetchCount = 0
    private var canceledOnce = false
    private(set) var fetchedWaterBodyIDs: [WaterBody.ID] = []

    init(canceledWaterBodyID: WaterBody.ID, states: [WaterBody.ID: HydroState]) {
        self.canceledWaterBodyID = canceledWaterBodyID
        self.states = states
    }

    func fetch(_ waterBody: WaterBody) async throws -> HydroState {
        fetchCount += 1
        fetchedWaterBodyIDs.append(waterBody.id)
        if waterBody.id == canceledWaterBodyID, !canceledOnce {
            canceledOnce = true
            try await Task.sleep(nanoseconds: 10_000_000_000)
        }
        guard let state = states[waterBody.id] else {
            throw NOAAProviderError.noUsableMeasurements
        }
        return state
    }

    func count() -> Int { fetchCount }
    func fetchedIDs() -> [WaterBody.ID] { fetchedWaterBodyIDs }
}

private func syntheticWaterBody(id: String) -> WaterBody {
    WaterBody(
        id: id,
        name: id,
        region: "Deterministic test",
        latitude: 0,
        longitude: 0,
        kind: .bay,
        sourceBindings: []
    )
}

print("WaterBody and request contract")
let bay = WaterBodies.sanFranciscoBay
Check.expect(bay.id == "san-francisco-bay", "San Francisco Bay has a stable product id")
Check.expect(bay.kind == .bay, "San Francisco Bay is classified as a bay")
Check.expect(bay.sourceBindings.count == 2, "San Francisco Bay uses separate met and current bindings")
Check.expect(
    bay.sourceBindings.allSatisfy { !$0.namespace.isEmpty && !$0.sourceID.isEmpty },
    "source bindings use provider-independent opaque identifiers"
)
Check.expect(
    bay.capabilities == [.waterLevel, .wind, .airPressure, .currentSpeed, .currentDirection],
    "coverage exposes only reviewed live capabilities"
)
Check.expect(WaterBodies.all.map(\.id) == ["san-francisco-bay", "monterey-bay", "lake-tahoe"], "catalog order is curated and deterministic")
Check.expect(Set(WaterBodies.all.map(\.id)).count == WaterBodies.all.count, "catalog ids are unique")
Check.expect(WaterBodies.body(id: "monterey-bay") == WaterBodies.montereyBay, "Monterey resolves by canonical id")
Check.expect(WaterBodies.body(id: "lake-tahoe") == WaterBodies.lakeTahoe, "Lake Tahoe resolves by canonical id")
Check.expect(WaterBodies.montereyBay.capabilities == [.waterLevel, .waterTemperature, .airPressure], "Monterey publishes reviewed partial NOAA coverage")
Check.expect(WaterBodies.montereyBay.coverage[.wind] == .unavailable, "Monterey does not promise unavailable wind")
Check.expect(WaterBodies.lakeTahoe.coverage[.waterLevel] == .supported, "Lake Tahoe publishes supported inland water level")
Check.expect(WaterBodies.lakeTahoe.coverage[.wind] == .unavailable, "Lake Tahoe exposes explicit unavailable capabilities")
Check.expect(WaterBodies.all.allSatisfy { $0.coverage.count == HydroCapability.allCases.count }, "every place publishes complete capability coverage")

let requestProvider = NOAACOOPSProvider(transport: URLSessionNOAATransport())
let requests = requestProvider.requests(for: bay)
Check.expect(requests.map(\.product) == [.waterLevel, .wind, .airPressure, .currents], "request order is deterministic")
let waterURL = requests[0].url?.absoluteString ?? ""
Check.expect(waterURL.contains("date=latest"), "requests use NOAA latest observations")
Check.expect(waterURL.contains("time_zone=gmt"), "requests require GMT")
Check.expect(waterURL.contains("units=metric"), "requests require metric units")
Check.expect(waterURL.contains("format=json"), "requests require JSON")
Check.expect(waterURL.contains("datum=MLLW"), "water levels explicitly use MLLW")
Check.expect(requests[3].url?.absoluteString.contains("bin=2") == true, "currents request uses reviewed real-time bin 2")

let unrelatedBinding = HydroSourceBinding(
    namespace: "example.other-provider",
    sourceID: "opaque-source",
    capabilities: [.waterLevel]
)
let unrelatedBody = WaterBody(
    id: "unrelated",
    name: "Unrelated",
    region: "Test",
    latitude: 0,
    longitude: 0,
    kind: .lake,
    sourceBindings: [unrelatedBinding]
)
Check.expect(
    requestProvider.requests(for: unrelatedBody).isEmpty,
    "NOAA provider ignores bindings owned by other providers"
)

let montereyRequests = requestProvider.requests(for: WaterBodies.montereyBay)
Check.expect(montereyRequests.map(\.product) == [.waterLevel, .waterTemperature, .airPressure], "Monterey requests only reviewed products")
let defaultNOAASession = URLSessionNOAATransport.makeDefaultSession()
Check.expect(defaultNOAASession.configuration.timeoutIntervalForRequest == 10, "NOAA live transport uses a watch-bounded request timeout")
Check.expect(defaultNOAASession.configuration.timeoutIntervalForResource == 20, "NOAA live transport uses a watch-bounded resource timeout")
Check.expect(defaultNOAASession.configuration.requestCachePolicy == .reloadIgnoringLocalCacheData, "NOAA live transport bypasses cached provider bodies")
Check.expect(defaultNOAASession.configuration.allowsExpensiveNetworkAccess == false, "NOAA live transport avoids expensive network access")
Check.expect(defaultNOAASession.configuration.waitsForConnectivity == false, "NOAA live transport fails fast instead of waiting for connectivity")

let noaaPayloads = [
    "water_level": try fixture("valid-water-level"),
    "wind": try fixture("valid-wind"),
    "air_pressure": try fixture("valid-pressure"),
    "currents": try fixture("valid-currents"),
]
private let cancelledNOAATransport = URLCancelledNOAATransport(payloads: noaaPayloads)
private let cancelledNOAAProvider = NOAACOOPSProvider(transport: cancelledNOAATransport)
do {
    _ = try await cancelledNOAAProvider.fetch(bay)
    Check.expect(false, "NOAA provider treats URLSession canceled requests as cancellation")
} catch is CancellationError {
    Check.expect(true, "NOAA provider treats URLSession canceled requests as cancellation")
} catch {
    Check.expect(false, "NOAA provider treats URLSession canceled requests as cancellation: \(error)")
}

private let concurrentNOAATransport = ConcurrentNOAATransport(payloads: noaaPayloads)
private let concurrentNOAAProvider = NOAACOOPSProvider(transport: concurrentNOAATransport)
let concurrentNOAAState = try await concurrentNOAAProvider.fetch(bay)
Check.expect(concurrentNOAAState.waterLevel != nil && concurrentNOAAState.windSpeed != nil, "concurrent NOAA fetch still aggregates usable products")
let maxNOAAConcurrency = await concurrentNOAATransport.maximumActiveRequests()
Check.expect(maxNOAAConcurrency > 1, "NOAA provider fetches products concurrently")
private let usgsProvider = USGSIVProvider(transport: FixtureUSGSTransport(payload: try fixture("valid-usgs-lake-level")))
let tahoeRequests = usgsProvider.requests(for: WaterBodies.lakeTahoe)
Check.expect(tahoeRequests.count == 1 && tahoeRequests[0].siteID == "10337000", "Lake Tahoe resolves to reviewed USGS site")
Check.expect(tahoeRequests[0].parameterCodes == ["00065"], "Lake Tahoe requests only gage height")
let tahoeURL = tahoeRequests[0].url?.absoluteString ?? ""
Check.expect(tahoeURL.contains("format=json") && tahoeURL.contains("siteStatus=all"), "USGS request is deterministic JSON instantaneous values")
Check.expect(usgsProvider.requests(for: bay).isEmpty, "USGS provider ignores NOAA-owned bindings")

print("\nUSGS adapter")
let usgsMeasurements = try USGSIVAdapter.decode(try fixture("valid-usgs-lake-level"), siteID: "10337000")
Check.expect(usgsMeasurements.count == 1, "USGS fixture decodes one reviewed measurement")
Check.equal(usgsMeasurements.first?.measurement.value, 7.94 * 0.3048, "USGS feet convert explicitly to meters")
Check.expect(usgsMeasurements.first?.measurement.unit == .meters, "USGS water level carries canonical units")
Check.expect(usgsMeasurements.first?.measurement.quality == .unknown, "USGS provisional data remains usable unknown quality")
Check.expect(usgsMeasurements.first?.measurement.sourceID == "usgs.nwis.10337000.00065", "USGS source identity is preserved")
Check.expect(USGSIVAdapter.mapQuality(["A"]) == .good, "USGS approved data maps to good")
Check.expect(USGSIVAdapter.mapQuality(["P"]) == .unknown, "USGS provisional data maps to unknown")
Check.expect(USGSIVAdapter.mapQuality(["Ice"]) == .suspect, "unrecognized USGS qualifiers fail closed")
Check.expect(USGSIVAdapter.parseTimestamp("not-a-time") == nil, "malformed USGS timestamps fail closed")
let tahoeState = try await usgsProvider.fetch(WaterBodies.lakeTahoe)
Check.expect(tahoeState.waterLevel == usgsMeasurements.first?.measurement, "USGS provider assembles Lake Tahoe HydroState")
Check.expect(tahoeState.waterTemperature == nil && tahoeState.windSpeed == nil, "USGS provider never fabricates uncovered fields")

// The USGS path was serial and all-or-nothing while NOAA was concurrent and
// partial-tolerant. These assert the two now behave the same way, using a
// multi-site body since every curated place currently has exactly one binding.
private let multiSiteTahoe = WaterBody(
    id: "multi-site-tahoe",
    name: "Multi-site fixture",
    region: "Deterministic test",
    latitude: WaterBodies.lakeTahoe.latitude,
    longitude: WaterBodies.lakeTahoe.longitude,
    kind: .lake,
    sourceBindings: (0..<4).map { index in
        HydroSourceBinding(
            namespace: USGSIVProvider<URLSessionUSGSTransport>.namespace,
            sourceID: "1033700\(index)",
            capabilities: [.waterLevel]
        )
    }
)

private let partialTransport = PartialUSGSTransport(
    payload: try fixture("valid-usgs-lake-level"),
    failingSiteFragment: "10337002"
)
private let partialProvider = USGSIVProvider(transport: partialTransport)
let usgsPartialState = try await partialProvider.fetch(multiSiteTahoe)
Check.expect(
    usgsPartialState.waterLevel != nil,
    "one failing USGS site does not discard the sites that succeeded"
)
let usgsStats = await partialTransport.stats()
Check.expect(usgsStats.attempts == 4, "every USGS site is attempted")
Check.expect(
    usgsStats.peak > 1,
    "USGS sites are fetched concurrently (peak in flight was \(usgsStats.peak))"
)

private let cancellingUSGS = URLCancellingUSGSTransport()
private let cancellingUSGSProvider = USGSIVProvider(transport: cancellingUSGS)
do {
    _ = try await cancellingUSGSProvider.fetch(multiSiteTahoe)
    Check.expect(false, "a cancelled USGS transport must not yield a state")
} catch {
    Check.expect(
        error is CancellationError,
        "USGS reports URLError(.cancelled) as cancellation rather than an outage"
    )
}

// A leaked URLSession per transport is invisible until it is measured, so
// assert identity rather than trusting the comment.
Check.expect(
    URLSessionUSGSTransport.makeDefaultSession() !== URLSessionUSGSTransport.makeDefaultSession(),
    "makeDefaultSession builds a distinct session when explicitly asked"
)

print("\nProvider routing and aggregation")
let routeReference = USGSIVAdapter.parseTimestamp("2026-08-09T04:00:00Z")!
let noaaRouteState = HydroState(
    observedAt: routeReference.addingTimeInterval(-120),
    retrievedAt: routeReference,
    windSpeed: HydroMeasurement(
        value: 8,
        unit: .metersPerSecond,
        origin: .observed,
        quality: .good,
        sourceID: "route.noaa.wind",
        observedAt: routeReference.addingTimeInterval(-120)
    )
)
let usgsRouteState = HydroState(
    observedAt: routeReference.addingTimeInterval(-300),
    retrievedAt: routeReference.addingTimeInterval(30),
    waterLevel: HydroMeasurement(
        value: 2.4,
        unit: .meters,
        origin: .observed,
        quality: .unknown,
        sourceID: "route.usgs.level",
        observedAt: routeReference.addingTimeInterval(-300)
    )
)
let mixedBody = WaterBody(
    id: "mixed-route",
    name: "Mixed Route",
    region: "Test",
    latitude: 0,
    longitude: 0,
    kind: .lake,
    sourceBindings: [
        HydroSourceBinding(namespace: "test.noaa", sourceID: "n", capabilities: [.wind]),
        HydroSourceBinding(namespace: "test.usgs", sourceID: "u", capabilities: [.waterLevel]),
    ]
)
private let fixedNOAA = FixedProvider(.success(noaaRouteState))
private let fixedUSGS = FixedProvider(.success(usgsRouteState))
let routed = RoutedHydroProvider(routes: [
    HydroProviderRoute(namespaces: ["test.noaa"], provider: fixedNOAA),
    HydroProviderRoute(namespaces: ["test.usgs"], provider: fixedUSGS),
])
let routedState = try await routed.fetch(mixedBody)
Check.expect(routedState.windSpeed == noaaRouteState.windSpeed && routedState.waterLevel == usgsRouteState.waterLevel, "matching providers merge complementary signals")
Check.expect(routedState.observedAt == usgsRouteState.observedAt, "routed aggregate uses oldest observation timestamp")
Check.expect(routedState.retrievedAt == usgsRouteState.retrievedAt, "routed aggregate uses latest retrieval timestamp")
let fixedNOAACount = await fixedNOAA.count()
let fixedUSGSCount = await fixedUSGS.count()
Check.expect(fixedNOAACount == 1 && fixedUSGSCount == 1, "each matching provider is fetched exactly once")

private let failedRoute = FixedProvider(.failure)
let partialRouted = RoutedHydroProvider(routes: [
    HydroProviderRoute(namespaces: ["test.noaa"], provider: fixedNOAA),
    HydroProviderRoute(namespaces: ["test.usgs"], provider: failedRoute),
])
let partialState = try await partialRouted.fetch(mixedBody)
Check.expect(partialState.windSpeed == noaaRouteState.windSpeed && partialState.waterLevel == nil, "one provider failure preserves another provider's usable state")

let collisionFirst = HydroState(
    observedAt: routeReference,
    retrievedAt: routeReference,
    waterLevel: HydroMeasurement(value: 1, unit: .meters, origin: .observed, quality: .good, sourceID: "first")
)
let collisionSecond = HydroState(
    observedAt: routeReference,
    retrievedAt: routeReference,
    waterLevel: HydroMeasurement(value: 2, unit: .meters, origin: .observed, quality: .good, sourceID: "second")
)
let collisionMerged = try HydroStateMerger.merge([collisionFirst, collisionSecond])
Check.expect(collisionMerged.waterLevel?.sourceID == "first", "declared route order resolves signal collisions deterministically")
do {
    _ = try HydroStateMerger.merge([])
    Check.expect(false, "empty aggregation fails safely")
} catch let error as RoutedHydroProviderError {
    Check.expect(error == .noUsableMeasurements, "empty aggregation fails safely")
}

do {
    _ = try await RoutedHydroProvider(routes: []).fetch(mixedBody)
    Check.expect(false, "missing route fails explicitly")
} catch let error as RoutedHydroProviderError {
    Check.expect(error == .noMatchingProvider, "missing route fails explicitly")
}
do {
    let allFailed = RoutedHydroProvider(routes: [
        HydroProviderRoute(namespaces: ["test.noaa", "test.usgs"], provider: failedRoute),
    ])
    _ = try await allFailed.fetch(mixedBody)
    Check.expect(false, "all matching provider failures remain unavailable")
} catch let error as RoutedHydroProviderError {
    Check.expect(error == .noUsableMeasurements, "all matching provider failures remain unavailable")
}

print("\nNOAA adapter")
let level = try NOAAHydroAdapter.decode(
    fixture("valid-water-level"), product: .waterLevel, stationID: "9414290"
)
Check.equal(level.waterLevel?.value, 1.234, "water level decodes in meters")
Check.expect(level.waterLevel?.unit == .meters, "water level carries an explicit unit")
Check.expect(level.waterLevel?.quality == .good, "verified zero-flag water level maps to good")
Check.expect(level.waterLevel?.origin == .observed, "NOAA observations retain observed provenance")
Check.expect(level.waterLevel?.observedAt == level.observedAt, "measurement retains its own observation timestamp")

let expectedLevelDate = NOAAHydroAdapter.parseTimestamp("2025-01-15 12:00")
Check.expect(level.observedAt == expectedLevelDate, "GMT timestamp parses exactly")
Check.expect(NOAAHydroAdapter.parseTimestamp("2025-02-30 25:99") == nil, "invalid timestamp fails closed")

let wind = try NOAAHydroAdapter.decode(fixture("valid-wind"), product: .wind, stationID: "9414290")
Check.equal(wind.windSpeed?.value, 4.5, "metric wind speed remains meters per second")
Check.equal(wind.windDirection?.value, 270, "wind direction decodes in degrees true")
Check.expect(wind.windDirection?.directionConvention == .from, "NOAA wind uses meteorological from convention")
Check.expect(wind.windSpeed?.quality == .good, "normal wind flags map to good")

let currents = try NOAAHydroAdapter.decode(
    fixture("valid-currents"), product: .currents, stationID: "s09010"
)
Check.equal(currents.currentSpeed?.value, 0.228, "metric current cm/s converts explicitly to m/s")
Check.expect(currents.currentSpeed?.unit == .metersPerSecond, "current speed carries canonical units")
Check.equal(currents.currentDirection?.value, 212, "current direction decodes in degrees true")
Check.expect(currents.currentDirection?.directionConvention == .toward, "NOAA currents use flow-toward convention")
Check.expect(currents.currentSpeed?.quality == .unknown, "currents without quality flags remain unknown")

let partial = try NOAAHydroAdapter.decode(fixture("partial-wind"), product: .wind, stationID: "9414290")
Check.equal(partial.windSpeed?.value, 3.2, "partial wind retains its valid speed")
Check.expect(partial.windDirection == nil, "empty direction remains nil")

let malformed = try NOAAHydroAdapter.decode(
    fixture("malformed-pressure"), product: .airPressure, stationID: "9414290"
)
Check.expect(malformed.pressure == nil, "malformed numeric value remains nil")
Check.expect(!malformed.hasMeasurement, "malformed-only product is unusable rather than zero")

let suspect = try NOAAHydroAdapter.decode(
    fixture("suspect-water-level"), product: .waterLevel, stationID: "9414290"
)
Check.expect(suspect.waterLevel?.quality == .suspect, "nonzero NOAA QC flag maps to suspect")

let counted = try NOAAHydroAdapter.decode(
    fixture("count-noaa-water-level"), product: .waterLevel, stationID: "9414290"
)
Check.expect(counted.waterLevel?.quality == .good, "water-level count flag does not trigger suspect")
let suspectState = try NOAAHydroAggregator.state(
    samples: [suspect], retrievedAt: suspect.observedAt
)
Check.expect(
    HydroInterpreter().interpret(
        suspectState,
        referenceDate: suspect.observedAt
    ).forcing.freshness == .unavailable,
    "suspect-only state cannot create usable forcing"
)

var providerErrorWasTyped = false
do {
    _ = try NOAAHydroAdapter.decode(fixture("provider-error"), product: .salinity, stationID: "9414290")
} catch let error as NOAAProviderError {
    if case .providerMessage = error { providerErrorWasTyped = true }
}
Check.expect(providerErrorWasTyped, "provider error JSON becomes a typed error")

let partialNoaaTransport = ProductPayloadNOAATransport(
    payloads: [
        "wind": try fixture("valid-wind"),
        "currents": try fixture("provider-error"),
    ],
    productWithFailure: "currents",
    failure: NOAAProviderError.providerMessage("No data was found. This product may not be offered at this station at the requested time.")
)
let partialNoaaBody = WaterBody(
    id: "partial-noaa",
    name: "Partial NOAA",
    region: "Deterministic test",
    latitude: WaterBodies.sanFranciscoBay.latitude,
    longitude: WaterBodies.sanFranciscoBay.longitude,
    kind: .bay,
    sourceBindings: [
        HydroSourceBinding(
            namespace: NOAACOOPSProvider<URLSessionNOAATransport>.stationNamespace,
            sourceID: "9414290",
            capabilities: [.wind]
        ),
        HydroSourceBinding(
            namespace: NOAACOOPSProvider<URLSessionNOAATransport>.currentStationNamespace,
            sourceID: "s09010",
            capabilities: [.currentSpeed, .currentDirection],
            parameters: ["bin": "2"]
        ),
    ]
)
let partialNoaaProvider = NOAACOOPSProvider(transport: partialNoaaTransport)
let partialNoaa = try await partialNoaaProvider.fetch(partialNoaaBody)
Check.expect(partialNoaa.windSpeed != nil, "NOAA provider exposes partial product when another product returns provider message")
Check.expect(partialNoaa.currentSpeed == nil && partialNoaa.currentDirection == nil, "Noaa current returns absent from provider-message failures")

let terminalNoaaTransport = ProductPayloadNOAATransport(
    payloads: [
        "currents": try fixture("provider-error")
    ],
    productWithFailure: "currents",
    failure: NOAAProviderError.providerMessage("No data was found. This product may not be offered at this station at the requested time.")
)
let terminalNoaaBody = WaterBody(
    id: "terminal-noaa",
    name: "Terminal NOAA",
    region: "Deterministic test",
    latitude: WaterBodies.sanFranciscoBay.latitude,
    longitude: WaterBodies.sanFranciscoBay.longitude,
    kind: .bay,
    sourceBindings: [
        HydroSourceBinding(
            namespace: NOAACOOPSProvider<URLSessionNOAATransport>.currentStationNamespace,
            sourceID: "s09010",
            capabilities: [.currentSpeed, .currentDirection],
            parameters: ["bin": "2"]
        )
    ]
)
let terminalNoaaProvider = NOAACOOPSProvider(transport: terminalNoaaTransport)
var terminalNoaaError = false
do {
    _ = try await terminalNoaaProvider.fetch(terminalNoaaBody)
} catch let error as NOAAProviderError {
    if case .providerMessage = error { terminalNoaaError = true }
}
Check.expect(terminalNoaaError, "all NOAA failures for one body surface provider-message as a terminal error")

let mixedFailureTransport = PerProductNOAATransport(
    payloads: noaaPayloads,
    failures: [
        "wind": NOAAProviderError.providerMessage("No data was found. This product may not be offered at this station at the requested time."),
        "currents": CancellationError()
    ]
)
let mixedFailureNoaaBody = WaterBody(
    id: "mixed-failure-noaa",
    name: "Mixed Failure NOAA",
    region: "Deterministic test",
    latitude: WaterBodies.sanFranciscoBay.latitude,
    longitude: WaterBodies.sanFranciscoBay.longitude,
    kind: .bay,
    sourceBindings: [
        HydroSourceBinding(
            namespace: NOAACOOPSProvider<URLSessionNOAATransport>.stationNamespace,
            sourceID: "9414290",
            capabilities: [.waterLevel, .wind]
        ),
        HydroSourceBinding(
            namespace: NOAACOOPSProvider<URLSessionNOAATransport>.currentStationNamespace,
            sourceID: "s10010",
            capabilities: [.currentSpeed, .currentDirection],
            parameters: ["bin": "2"]
        ),
    ]
)
let mixedFailureNoaaProvider = NOAACOOPSProvider(transport: mixedFailureTransport)
do {
    _ = try await mixedFailureNoaaProvider.fetch(mixedFailureNoaaBody)
    Check.expect(false, "mixed NOAA failures prefer cancellation over provider-message")
} catch is CancellationError {
    Check.expect(true, "mixed NOAA failures prefer cancellation over provider-message")
} catch {
    Check.expect(false, "mixed NOAA failures prefer cancellation over provider-message: \(error)")
}

var timestampWasRejected = false
do {
    _ = try NOAAHydroAdapter.decode(fixture("timestamp-edge"), product: .waterLevel, stationID: "9414290")
} catch let error as NOAAProviderError {
    if case .malformedTimestamp = error { timestampWasRejected = true }
}
Check.expect(timestampWasRejected, "malformed product timestamp rejects the sample")

print("\nAggregation and fallback")
let pressure = try NOAAHydroAdapter.decode(
    fixture("valid-pressure"), product: .airPressure, stationID: "9414290"
)
let retrievedAt = NOAAHydroAdapter.parseTimestamp("2025-01-15 12:08")!
let state = try NOAAHydroAggregator.state(
    samples: [wind, currents, pressure, level, malformed], retrievedAt: retrievedAt
)
Check.expect(state.observedAt == level.observedAt, "state timestamp conservatively uses oldest valid product")
Check.expect(state.retrievedAt == retrievedAt, "aggregation retains retrieval time")
Check.expect(state.waterLevel != nil && state.windSpeed != nil && state.pressure != nil, "multiple products aggregate")
Check.expect(state.currentSpeed != nil && state.currentDirection != nil, "separate currents binding aggregates")
Check.expect(state.waterTemperature == nil && state.salinity == nil, "unavailable station products remain nil")
Check.expect(state.waveHeight == nil && state.wavePeriod == nil, "unsupported waves remain nil")
let repeatedState = try NOAAHydroAggregator.state(
    samples: [wind, currents, pressure, level], retrievedAt: retrievedAt
)
Check.expect(
    repeatedState == state,
    "aggregation is deterministic"
)
let experience = HydroInterpreter().interpret(state, referenceDate: retrievedAt)
Check.expect(experience.forcing.flowDirection != nil, "aggregated current reaches interpreted flow direction")
Check.expect(experience.forcing.windDirection != nil, "aggregated wind reaches interpreted wind direction")

let bayA = syntheticWaterBody(id: "test-bay-a")
let bayB = syntheticWaterBody(id: "test-bay-b")
var stateA = state
stateA.waterLevel?.sourceID = "test-bay-a.level"
var stateB = state
stateB.waterLevel?.sourceID = "test-bay-b.level"

private let provenanceProvider = SequencedProvider([
    .success(stateA),
    .failure,
    .success(stateB),
    .failure,
])
let coordinator = LiveHydroCoordinator(provider: provenanceProvider)
let firstA = await coordinator.refresh(waterBody: bayA, referenceDate: retrievedAt)
if case let .updated(updatedState, _) = firstA {
    Check.expect(updatedState == stateA, "fetch A updates A")
} else { Check.expect(false, "fetch A updates A") }

let throttledA = await coordinator.refresh(
    waterBody: bayA,
    referenceDate: retrievedAt.addingTimeInterval(2 * 60)
)
if case let .preserved(preservedState, _) = throttledA {
    Check.expect(preservedState == stateA, "fetch A inside interval preserves A")
} else { Check.expect(false, "fetch A inside interval preserves A") }

let failedB = await coordinator.refresh(
    waterBody: bayB,
    referenceDate: retrievedAt.addingTimeInterval(2 * 60)
)
if case let .failed(message) = failedB {
    Check.expect(message == "Live data unavailable", "B failure without B cache reports a reason")
} else { Check.expect(false, "B failure without B cache reports a reason") }
let provenanceFetchedIDs = await provenanceProvider.fetchedIDs()
Check.expect(
    provenanceFetchedIDs == [bayA.id, bayB.id],
    "A throttle never suppresses B provider fetch"
)
let cachedAAfterBFailure = await coordinator.cachedState(for: bayA)
Check.expect(
    cachedAAfterBFailure == stateA,
    "A cache remains intact after B failure"
)
let cachedBAfterFailure = await coordinator.cachedState(for: bayB.id)
Check.expect(
    cachedBAfterFailure == nil,
    "B cannot reuse A cached state"
)

let successfulB = await coordinator.refresh(
    waterBody: bayB,
    referenceDate: retrievedAt.addingTimeInterval(12 * 60)
)
if case let .updated(updatedState, _) = successfulB {
    Check.expect(updatedState == stateB, "B later succeeds into an independent cache")
} else { Check.expect(false, "B later succeeds into an independent cache") }

let failedALater = await coordinator.refresh(
    waterBody: bayA,
    referenceDate: retrievedAt.addingTimeInterval(12 * 60)
)
if case let .preserved(preservedState, _) = failedALater {
    Check.expect(preservedState == stateA, "A failure preserves A rather than B")
} else { Check.expect(false, "A failure preserves A rather than B") }
let finalCachedA = await coordinator.cachedState(for: bayA)
let finalCachedB = await coordinator.cachedState(for: bayB)
Check.expect(
    finalCachedA == stateA && finalCachedB == stateB,
    "A and B caches remain independently inspectable"
)

let emptyCoordinator = LiveHydroCoordinator(provider: SequencedProvider([.failure]))
let unavailable = await emptyCoordinator.refresh(waterBody: bayA, referenceDate: retrievedAt)
if case let .failed(message) = unavailable {
    Check.expect(message == "Live data unavailable", "first network failure reports a reason")
} else { Check.expect(false, "first network failure reports a reason") }

let cancellationProvider = CancellationThenSuccessProvider(
    canceledWaterBodyID: bayA.id,
    states: [bayA.id: stateA, bayB.id: stateB]
)
let cancellationCoordinator = LiveHydroCoordinator(provider: cancellationProvider)
let seededB = await cancellationCoordinator.refresh(waterBody: bayB, referenceDate: retrievedAt)
if case .updated = seededB { Check.expect(true, "B cache seeds before A cancellation") }
else { Check.expect(false, "B cache seeds before A cancellation") }
let canceledTask = Task {
    await cancellationCoordinator.refresh(waterBody: bayA, referenceDate: retrievedAt)
}
try await Task.sleep(nanoseconds: 10_000_000)
canceledTask.cancel()
_ = await canceledTask.value
let retryAfterCancellation = await cancellationCoordinator.refresh(
    waterBody: bayA,
    referenceDate: retrievedAt.addingTimeInterval(1)
)
if case .updated = retryAfterCancellation {
    Check.expect(true, "canceled refresh does not throttle next activation")
} else {
    Check.expect(false, "canceled refresh does not throttle next activation")
}
let cancellationFetchCount = await cancellationProvider.count()
Check.expect(cancellationFetchCount == 3, "next A activation reaches provider after cancellation")
let bAfterACancellation = await cancellationCoordinator.refresh(
    waterBody: bayB,
    referenceDate: retrievedAt.addingTimeInterval(2)
)
if case let .preserved(preservedState, _) = bAfterACancellation {
    Check.expect(preservedState == stateB, "canceling A does not mutate B refresh record")
} else { Check.expect(false, "canceling A does not mutate B refresh record") }
let cancellationFetchedIDs = await cancellationProvider.fetchedIDs()
Check.expect(
    cancellationFetchedIDs == [bayB.id, bayA.id, bayA.id],
    "B remains throttled while canceled A retries independently"
)

private let urlCancelledProvider = URLCancelledThenSuccessProvider(state: stateA)
let urlCancelledCoordinator = LiveHydroCoordinator(provider: urlCancelledProvider)
let urlCancelledFirst = await urlCancelledCoordinator.refresh(waterBody: bayA, referenceDate: retrievedAt)
if case let .failed(message) = urlCancelledFirst {
    Check.expect(message == "Live data unavailable", "URLSession cancellation leaves uncached water with an explicit reason")
} else { Check.expect(false, "URLSession cancellation leaves uncached water with an explicit reason") }
let urlCancelledRetry = await urlCancelledCoordinator.refresh(
    waterBody: bayA,
    referenceDate: retrievedAt.addingTimeInterval(1)
)
if case let .updated(updatedState, _) = urlCancelledRetry {
    Check.expect(updatedState == stateA, "URLSession cancellation resets throttle for immediate retry")
} else {
    Check.expect(false, "URLSession cancellation resets throttle for immediate retry")
}
let urlCancelledFetchCount = await urlCancelledProvider.count()
Check.expect(urlCancelledFetchCount == 2, "URLSession cancellation does not suppress the next coordinator fetch")

print("\nProvider metadata candidate adapters")
let tahoeCoordinate = GeographicCoordinate(
    latitude: WaterBodies.lakeTahoe.latitude,
    longitude: WaterBodies.lakeTahoe.longitude
)
let noaaMetadataRequest = NOAACOOPSMetadataRequest(stationID: "9414290")
Check.expect(
    noaaMetadataRequest.url?.absoluteString == "https://api.tidesandcurrents.noaa.gov/mdapi/prod/webapi/stations/9414290.json",
    "NOAA metadata request uses the public station endpoint"
)
let noaaCandidates = try NOAACOOPSMetadataCandidateAdapter.decode(
    fixture("noaa-stations-metadata"),
    selectedCoordinate: GeographicCoordinate(latitude: 37.806305, longitude: -122.46589)
)
Check.expect(noaaCandidates.map(\.source.sourceID) == ["9414290", "9413450"], "NOAA metadata candidates sort deterministically by distance")
Check.expect(noaaCandidates[0].source.capabilities.isEmpty, "NOAA station metadata does not invent product capabilities")
Check.expect(noaaCandidates[0].evidence.map(\.kind) == [.proximityOnly], "NOAA station metadata supplies proximity evidence only")
let reviewedNOAACandidates = try NOAACOOPSMetadataCandidateAdapter.decode(
    fixture("noaa-stations-metadata"),
    selectedCoordinate: GeographicCoordinate(latitude: 37.806305, longitude: -122.46589),
    reviewedCapabilities: ["9414290": [.waterLevel, .wind]]
)
Check.expect(reviewedNOAACandidates[0].source.capabilities == [.waterLevel, .wind], "separately reviewed NOAA capabilities remain explicit")
Check.expect(reviewedNOAACandidates[0].evidence.contains { $0.kind == .productAvailable }, "reviewed NOAA product availability is recorded as separate evidence")

let usgsRequest = USGSMonitoringLocationsRequest(center: tahoeCoordinate, radiusDegrees: 0.25, limit: 25)
let usgsURL = usgsRequest.url?.absoluteString ?? ""
Check.expect(usgsURL.contains("monitoring-locations/items"), "USGS metadata request uses the public OGC collection")
Check.expect(usgsURL.contains("bbox="), "USGS metadata request is geographically bounded")
Check.expect(USGSMonitoringLocationsRequest(center: tahoeCoordinate, radiusDegrees: -1).url == nil, "USGS metadata request rejects invalid radius")
let usgsCandidates = try USGSMonitoringLocationCandidateAdapter.decode(
    fixture("usgs-monitoring-locations"),
    selectedCoordinate: tahoeCoordinate
)
Check.expect(usgsCandidates.map(\.source.sourceID) == ["10337000", "10336635"], "USGS candidates sort by distance rather than response order")
Check.expect(usgsCandidates[0].source.locationKind == .lake, "USGS lake site class maps to provider-independent lake kind")
Check.expect(usgsCandidates[1].source.locationKind == .river, "USGS stream site class maps to provider-independent river kind")
Check.expect(usgsCandidates.allSatisfy { $0.source.capabilities.isEmpty }, "USGS location metadata does not imply observation products")
Check.expect(usgsCandidates[0].evidence.contains { $0.kind == .hydrologicallyConnected }, "USGS HUC is preserved as hydrologic evidence")
Check.expect(usgsCandidates[1].evidence.contains { $0.kind == .proximityOnly }, "nearby tributary remains proximity evidence, not lake identity")
let metadataOnlyDecision = WaterBodyResolutionEvaluator().evaluate(.init(
    feature: GeographicFeatureIdentity(
        namespace: "fixture.feature",
        featureID: "lake-tahoe",
        name: "Lake Tahoe",
        kind: .lake,
        representativeCoordinate: tahoeCoordinate
    ),
    observationSources: usgsCandidates.map(\.source),
    evidence: usgsCandidates.flatMap(\.evidence)
))
Check.expect(metadataOnlyDecision.confidence == .needsReview, "provider metadata alone cannot accept a WaterBody resolution")
let encodedMetadataCandidates = try JSONEncoder().encode(usgsCandidates)
Check.expect(
    !encodedMetadataCandidates.isEmpty,
    "provider metadata candidates encode as portable research artifacts"
)

do {
    _ = try NOAACOOPSMetadataCandidateAdapter.decode(Data("{}".utf8), selectedCoordinate: tahoeCoordinate)
    Check.expect(false, "malformed NOAA metadata fails closed")
} catch {
    Check.expect(true, "malformed NOAA metadata fails closed")
}

if CommandLine.arguments.contains("--live") {
    print("\nLive NOAA smoke test")
    let liveProvider = LiveNOAACOOPSProvider()
    for request in liveProvider.requests(for: bay) {
        print("  request: \(request.url?.absoluteString ?? "invalid")")
    }
    do {
        let liveState = try await liveProvider.fetch(bay)
        let referenceDate = Date()
        let liveExperience = HydroInterpreter().interpret(liveState, referenceDate: referenceDate)
        let fields = [
            liveState.waterLevel.map { "waterLevel=\($0.value) m" },
            liveState.waterTemperature.map { "waterTemperature=\($0.value) C" },
            liveState.currentSpeed.map { "currentSpeed=\($0.value) m/s" },
            liveState.currentDirection.map { "currentDirection=\($0.value) deg" },
            liveState.windSpeed.map { "windSpeed=\($0.value) m/s" },
            liveState.windDirection.map { "windDirection=\($0.value) deg" },
            liveState.pressure.map { "pressure=\($0.value) hPa" },
            liveState.salinity.map { "salinity=\($0.value) PSU" },
        ].compactMap { $0 }
        print("  observedAt: \(liveState.observedAt)")
        print("  retrievedAt: \(liveState.retrievedAt)")
        print("  fields: \(fields.joined(separator: ", "))")
        print("  freshness: \(liveExperience.forcing.freshness.rawValue)")
        print("  forcing: \(liveExperience.forcing)")
        print("  modifiers: \(liveExperience.themeModifiers)")
        Check.expect(!fields.isEmpty, "live NOAA response produces real Hydro fields")
        Check.expect(liveExperience.forcing.freshness != .unavailable, "live NOAA state is usable")
    } catch {
        Check.expect(false, "live NOAA smoke test succeeded: \(error)")
    }

    print("\nLive USGS smoke test")
    do {
        let liveUSGS = LiveUSGSIVProvider(transport: URLSessionUSGSTransport())
        let liveTahoe = try await liveUSGS.fetch(WaterBodies.lakeTahoe)
        print("  waterLevel: \(liveTahoe.waterLevel?.value ?? .nan) m")
        print("  observedAt: \(liveTahoe.observedAt)")
        Check.expect(liveTahoe.waterLevel != nil, "live USGS response produces Lake Tahoe water level")
        Check.expect(liveTahoe.waterLevel?.sourceID == "usgs.nwis.10337000.00065", "live USGS response preserves source identity")
    } catch {
        Check.expect(false, "live USGS smoke test succeeded: \(error)")
    }

    print("\nLive provider metadata smoke test")
    do {
        let noaaMetadataURL = NOAACOOPSMetadataRequest(stationID: "9414290").url!
        let noaaMetadataData = try await URLSessionNOAATransport().data(from: noaaMetadataURL)
        let liveNOAACandidates = try NOAACOOPSMetadataCandidateAdapter.decode(
            noaaMetadataData,
            selectedCoordinate: GeographicCoordinate(latitude: bay.latitude, longitude: bay.longitude)
        )
        Check.expect(liveNOAACandidates.first?.source.sourceID == "9414290", "live NOAA metadata produces the requested station candidate")

        let usgsMetadataURL = USGSMonitoringLocationsRequest(
            center: tahoeCoordinate,
            radiusDegrees: 0.2,
            limit: 25
        ).url!
        let usgsMetadataData = try await URLSessionUSGSTransport().data(from: usgsMetadataURL)
        let liveUSGSCandidates = try USGSMonitoringLocationCandidateAdapter.decode(
            usgsMetadataData,
            selectedCoordinate: tahoeCoordinate
        )
        Check.expect(!liveUSGSCandidates.isEmpty, "live USGS metadata produces bounded monitoring-location candidates")
        Check.expect(liveUSGSCandidates.allSatisfy { $0.source.capabilities.isEmpty }, "live USGS metadata remains capability-conservative")
    } catch {
        Check.expect(false, "live provider metadata smoke test succeeded: \(error)")
    }
}

print("\nRefresh coalescing and retry floor")

// Two callers arriving together — the view's .task and a complication refresh —
// must not have one of them told "unavailable" by the throttle the other just
// armed. Previously the loser got .unavailable on a cold cache.
private let gated = GatedProvider(state: stateA)
private let gatedCoordinator = LiveHydroCoordinator(provider: gated)
private let firstCaller = Task {
    await gatedCoordinator.refresh(waterBody: bayA, referenceDate: retrievedAt)
}
try await Task.sleep(nanoseconds: 30_000_000)
private let secondCaller = Task {
    await gatedCoordinator.refresh(
        waterBody: bayA, referenceDate: retrievedAt.addingTimeInterval(0.2)
    )
}
try await Task.sleep(nanoseconds: 30_000_000)
await gated.release()
private let firstOutcome = await firstCaller.value
private let secondOutcome = await secondCaller.value

if case .updated = firstOutcome { Check.expect(true, "the originating caller is updated") }
else { Check.expect(false, "the originating caller is updated") }
if case .updated = secondOutcome {
    Check.expect(true, "a concurrent caller joins the fetch instead of being told unavailable")
} else {
    Check.expect(false, "a concurrent caller joins the fetch instead of being told unavailable")
}
private let gatedFetches = await gated.count()
Check.expect(gatedFetches == 1, "two concurrent callers produce one provider fetch, not two")

// Clearing the throttle on cancellation was correct in intent but had no floor,
// so a wrist raise-and-lower cycle could drive an unbounded request rate.
private let hammered = AlwaysCancellingProvider()
private let hammeredCoordinator = LiveHydroCoordinator(provider: hammered)
for tick in 0..<50 {
    _ = await hammeredCoordinator.refresh(
        waterBody: bayA,
        referenceDate: retrievedAt.addingTimeInterval(Double(tick) * 0.2)
    )
}
private let hammeredFetches = await hammered.count()
Check.expect(
    hammeredFetches <= 4,
    "50 refreshes across 10 seconds of cancellations back off to a handful, not 50 (got \(hammeredFetches))"
)
Check.expect(
    hammeredFetches >= 2,
    "the first cancellation still retries immediately (got \(hammeredFetches))"
)

// The floor must expire, or a cancelled attempt would be as punishing as a
// successful one.
_ = await hammeredCoordinator.refresh(
    waterBody: bayA,
    // The loop above already advanced to +9.8s, so clear both it and the floor.
    referenceDate: retrievedAt.addingTimeInterval(20)
)
private let afterFloor = await hammered.count()
Check.expect(
    afterFloor > hammeredFetches,
    "a repeatedly cancelled place retries again once the backoff passes"
)
Check.expect(
    LiveHydroCoordinator.minimumRetryInterval < LiveHydroCoordinator.minimumRefreshInterval,
    "the cancellation floor is shorter than the ordinary refresh window"
)

print("\n────────────────────────────────────────────────────")
if Check.failures == 0 {
    print("All \(Check.count) provider checks passed.")
} else {
    print("\(Check.failures) of \(Check.count) provider checks failed.")
    exit(1)
}
