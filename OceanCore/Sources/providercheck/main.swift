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

private struct FixtureUSGSTransport: USGSDataTransport {
    let payload: Data
    func data(from url: URL) async throws -> Data { payload }
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
Check.expect(WaterBodies.lakeTahoe.coverage[.waterLevel] == .observed, "Lake Tahoe publishes observed inland water level")
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
Check.expect(failedB == .unavailable, "B failure without B cache is unavailable")
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
Check.expect(unavailable == .unavailable, "first network failure leaves that place unavailable")

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
}

print("\n────────────────────────────────────────────────────")
if Check.failures == 0 {
    print("All \(Check.count) provider checks passed.")
} else {
    print("\(Check.failures) of \(Check.count) provider checks failed.")
    exit(1)
}
