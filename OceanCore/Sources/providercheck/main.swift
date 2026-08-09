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

/// A transport that fails the way `URLSession` actually fails when its task is
/// cancelled: `URLError(.cancelled)`, **not** `CancellationError`.
///
/// This distinction is the whole point of the fake. A provider fake that cancels
/// via `Task.sleep` throws `CancellationError` and so exercises a path the live
/// transport can never take, which is how the original cancellation bug passed a
/// green suite.
private actor URLCancellingTransport: NOAADataTransport {
    private var calls = 0
    private let succeedFirst: Int
    private let payload: Data

    init(succeedFirst: Int, payload: Data) {
        self.succeedFirst = succeedFirst
        self.payload = payload
    }

    func data(from url: URL) async throws -> Data {
        calls += 1
        if calls > succeedFirst { throw URLError(.cancelled) }
        return payload
    }

    func count() -> Int { calls }
}

/// Cancels the first fetch the way the network does, then succeeds.
private actor URLCancelThenSucceedProvider: HydroStateProvider {
    private let state: HydroState
    private(set) var fetchCount = 0

    init(state: HydroState) {
        self.state = state
    }

    func fetch(_ waterBody: WaterBody) async throws -> HydroState {
        fetchCount += 1
        if fetchCount == 1 { throw URLError(.cancelled) }
        return state
    }

    func count() -> Int { fetchCount }
}

private actor SequencedProvider: HydroStateProvider {
    enum Result: Sendable {
        case success(HydroState)
        case failure
    }

    private var results: [Result]
    private(set) var fetchCount = 0

    init(_ results: [Result]) {
        self.results = results
    }

    func fetch(_ waterBody: WaterBody) async throws -> HydroState {
        fetchCount += 1
        guard !results.isEmpty else { throw NOAAProviderError.noUsableMeasurements }
        switch results.removeFirst() {
        case let .success(state): return state
        case .failure: throw NOAAProviderError.noUsableMeasurements
        }
    }

    func count() -> Int { fetchCount }
}

actor CancellationThenSuccessProvider: HydroStateProvider {
    private let state: HydroState
    private(set) var fetchCount = 0

    init(state: HydroState) {
        self.state = state
    }

    func fetch(_ waterBody: WaterBody) async throws -> HydroState {
        fetchCount += 1
        if fetchCount == 1 {
            try await Task.sleep(nanoseconds: 10_000_000_000)
        }
        return state
    }

    func count() -> Int { fetchCount }
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

private let successProvider = SequencedProvider([.success(state), .failure])
let coordinator = LiveHydroCoordinator(provider: successProvider)
let first = await coordinator.refresh(waterBody: bay, referenceDate: retrievedAt)
if case .updated = first { Check.expect(true, "successful refresh updates live state") }
else { Check.expect(false, "successful refresh updates live state") }
let throttled = await coordinator.refresh(waterBody: bay, referenceDate: retrievedAt.addingTimeInterval(60))
if case .preserved = throttled { Check.expect(true, "refresh inside ten minutes preserves cached state") }
else { Check.expect(false, "refresh inside ten minutes preserves cached state") }
let fetchCount = await successProvider.count()
Check.expect(fetchCount == 1, "refresh policy does not poll inside ten minutes")
let failedAfterWindow = await coordinator.refresh(
    waterBody: bay,
    referenceDate: retrievedAt.addingTimeInterval(LiveHydroCoordinator.minimumRefreshInterval)
)
if case .preserved = failedAfterWindow { Check.expect(true, "network failure preserves last valid state") }
else { Check.expect(false, "network failure preserves last valid state") }

let emptyCoordinator = LiveHydroCoordinator(provider: SequencedProvider([.failure]))
let unavailable = await emptyCoordinator.refresh(waterBody: bay, referenceDate: retrievedAt)
Check.expect(unavailable == .unavailable, "first network failure leaves Real Water unavailable")

let cancellationProvider = CancellationThenSuccessProvider(state: state)
let cancellationCoordinator = LiveHydroCoordinator(provider: cancellationProvider)
let canceledTask = Task {
    await cancellationCoordinator.refresh(waterBody: bay, referenceDate: retrievedAt)
}
try await Task.sleep(nanoseconds: 10_000_000)
canceledTask.cancel()
_ = await canceledTask.value
let retryAfterCancellation = await cancellationCoordinator.refresh(
    waterBody: bay,
    referenceDate: retrievedAt.addingTimeInterval(1)
)
if case .updated = retryAfterCancellation {
    Check.expect(true, "canceled refresh does not throttle next activation")
} else {
    Check.expect(false, "canceled refresh does not throttle next activation")
}
let cancellationFetchCount = await cancellationProvider.count()
Check.expect(cancellationFetchCount == 2, "next activation reaches provider after cancellation")

// Cancellation as the network reports it — URLError(.cancelled) rather than
// CancellationError. Everything above this point cancels via Task.sleep, which
// cannot reach the live transport's failure mode.
print("\nCancellation via URLError")

let bayRequestCount = LiveNOAACOOPSProvider().requests(for: bay).count
Check.expect(bayRequestCount > 1, "San Francisco Bay issues more than one request")

private let cancellingTransport = URLCancellingTransport(
    succeedFirst: 1, payload: try fixture("valid-water-level")
)
private let cancellingProvider = NOAACOOPSProvider(transport: cancellingTransport)
do {
    _ = try await cancellingProvider.fetch(bay)
    Check.expect(false, "a cancelled transport must not yield a state")
} catch {
    Check.expect(
        error is CancellationError,
        "URLError(.cancelled) is reported as cancellation, not as a partial result"
    )
}
let attemptedRequests = await cancellingTransport.count()
Check.expect(
    attemptedRequests == 2,
    "cancellation stops the request loop (attempted \(attemptedRequests) of \(bayRequestCount))"
)

private let urlCancelProvider = URLCancelThenSucceedProvider(state: state)
let urlCancelCoordinator = LiveHydroCoordinator(provider: urlCancelProvider)
let firstOutcome = await urlCancelCoordinator.refresh(
    waterBody: bay, referenceDate: retrievedAt
)
Check.expect(
    firstOutcome == .unavailable,
    "a cancelled refresh with nothing cached stays unavailable"
)
let retryAfterURLCancel = await urlCancelCoordinator.refresh(
    waterBody: bay,
    referenceDate: retrievedAt.addingTimeInterval(1)
)
if case .updated = retryAfterURLCancel {
    Check.expect(true, "URLError cancellation does not throttle the next activation")
} else {
    Check.expect(false, "URLError cancellation does not throttle the next activation")
}
let urlCancelFetchCount = await urlCancelProvider.count()
Check.expect(
    urlCancelFetchCount == 2,
    "next activation reaches the provider after a URLError cancellation"
)

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
}

print("\n────────────────────────────────────────────────────")
if Check.failures == 0 {
    print("All \(Check.count) provider checks passed.")
} else {
    print("\(Check.failures) of \(Check.count) provider checks failed.")
    exit(1)
}
