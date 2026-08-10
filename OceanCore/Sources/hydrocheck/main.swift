import Foundation
import OceanCore

enum Check {
    nonisolated(unsafe) static var failures: [String] = []
    nonisolated(unsafe) static var count = 0

    static func expect(_ condition: Bool, _ message: String) {
        count += 1
        if !condition { failures.append(message) }
    }

    static func equal(_ actual: Double?, _ expected: Double?, accuracy: Double = 1e-9, _ message: String) {
        count += 1
        switch (actual, expected) {
        case let (actual?, expected?) where actual.isFinite && expected.isFinite && abs(actual - expected) <= accuracy:
            return
        case (nil, nil):
            return
        default:
            failures.append("\(message): expected \(String(describing: expected)), got \(String(describing: actual))")
        }
    }
}

let interpreter = HydroInterpreter()
let referenceDate = HydroFixtures.referenceDate
let calm = interpreter.interpret(HydroFixtures.calm, referenceDate: referenceDate)
let active = interpreter.interpret(HydroFixtures.active, referenceDate: referenceDate)
let severe = interpreter.interpret(HydroFixtures.severe, referenceDate: referenceDate)
Check.expect(HydroFixtures.experience(named: "calm") == calm, "calm fixture name must resolve")
Check.expect(HydroFixtures.experience(named: "active") == active, "active fixture name must resolve")
Check.expect(HydroFixtures.experience(named: "severe") == severe, "severe fixture name must resolve")
Check.expect(HydroFixtures.experience(named: "unknown") == nil, "unknown fixture name must remain nil")

Check.expect(
    interpreter.interpret(HydroFixtures.active, referenceDate: referenceDate) == active,
    "equal states must produce equal experiences"
)

for (name, experience) in [("calm", calm), ("active", active), ("severe", severe)] {
    let forcing = experience.forcing
    let modifiers = experience.themeModifiers
    let values = [
        forcing.energy, forcing.chop, forcing.turbulence, forcing.flowStrength,
        forcing.waveAmplitude, forcing.waveRate, forcing.foamPotential, forcing.windStrength,
        modifiers.choppiness, modifiers.turbulence, modifiers.crestSharpness,
        modifiers.foaminess, modifiers.causticStrength, modifiers.glitter,
    ]
    Check.expect(values.allSatisfy { $0.isFinite && (0...1).contains($0) }, "\(name) outputs must be finite and normalized")
}

Check.expect(calm.forcing.energy < active.forcing.energy && active.forcing.energy < severe.forcing.energy, "energy must rise calm < active < severe")
Check.expect(calm.forcing.chop < active.forcing.chop && active.forcing.chop < severe.forcing.chop, "chop must rise calm < active < severe")
Check.expect(calm.forcing.turbulence < active.forcing.turbulence && active.forcing.turbulence < severe.forcing.turbulence, "turbulence must rise calm < active < severe")

func measurement(
    _ value: Double,
    _ unit: HydroUnit,
    quality: HydroQuality = .good,
    convention: HydroDirectionConvention? = nil,
    observedAt: Date? = nil,
    id: String = "check"
) -> HydroMeasurement {
    HydroMeasurement(
        value: value,
        unit: unit,
        origin: .observed,
        quality: quality,
        sourceID: id,
        observedAt: observedAt,
        directionConvention: convention
    )
}

func state(
    currentSpeed: Double? = nil,
    currentDirection: Double? = nil,
    waveHeight: Double? = nil,
    windSpeed: Double? = nil,
    observedAt: Date = referenceDate
) -> HydroState {
    HydroState(
        observedAt: observedAt,
        retrievedAt: referenceDate,
        currentSpeed: currentSpeed.map { measurement($0, .metersPerSecond) },
        currentDirection: currentDirection.map {
            measurement($0, .degreesTrue, convention: .toward)
        },
        waveHeight: waveHeight.map { measurement($0, .meters) },
        windSpeed: windSpeed.map { measurement($0, .metersPerSecond) }
    )
}

let slowCurrent = interpreter.interpret(state(currentSpeed: 0.2), referenceDate: referenceDate)
let fastCurrent = interpreter.interpret(state(currentSpeed: 1.8), referenceDate: referenceDate)
Check.expect(slowCurrent.forcing.flowStrength < fastCurrent.forcing.flowStrength, "higher current must raise flow strength")

let directed = interpreter.interpret(state(currentDirection: 270), referenceDate: referenceDate)
Check.equal(directed.forcing.flowDirection, 3 * .pi / 2, "current direction must convert degrees true to radians")

let fromDirectionState = HydroState(
    observedAt: referenceDate,
    retrievedAt: referenceDate,
    windDirection: measurement(270, .degreesTrue, convention: .from)
)
Check.equal(
    interpreter.interpret(fromDirectionState, referenceDate: referenceDate).forcing.windDirection,
    .pi / 2,
    "270 degrees from must become pi/2 toward"
)
let ambiguousDirectionState = HydroState(
    observedAt: referenceDate,
    retrievedAt: referenceDate,
    currentDirection: measurement(270, .degreesTrue)
)
Check.expect(
    interpreter.interpret(ambiguousDirectionState, referenceDate: referenceDate)
        .forcing.flowDirection == nil,
    "direction without an explicit convention must be ignored"
)

for (degrees, expected) in [(-90.0, 3 * Double.pi / 2), (810.0, Double.pi / 2)] {
    let wrapped = HydroState(
        observedAt: referenceDate,
        retrievedAt: referenceDate,
        currentDirection: measurement(degrees, .degreesTrue, convention: .toward)
    )
    Check.equal(
        interpreter.interpret(wrapped, referenceDate: referenceDate).forcing.flowDirection,
        expected,
        "direction must normalize across complete turns"
    )
}

let lowWind = interpreter.interpret(state(windSpeed: 2), referenceDate: referenceDate)
let highWind = interpreter.interpret(state(windSpeed: 20), referenceDate: referenceDate)
Check.expect(lowWind.forcing.windStrength < highWind.forcing.windStrength, "higher wind must raise wind strength")

let smallWave = interpreter.interpret(state(waveHeight: 0.2), referenceDate: referenceDate)
let largeWave = interpreter.interpret(state(waveHeight: 4), referenceDate: referenceDate)
Check.expect(smallWave.forcing.waveAmplitude < largeWave.forcing.waveAmplitude, "higher waves must raise amplitude")

let bayNoWaveLow = interpreter.interpret(
    state(currentSpeed: 0.4, windSpeed: 4), referenceDate: referenceDate
)
let bayNoWaveHigh = interpreter.interpret(
    state(currentSpeed: 1.6, windSpeed: 18), referenceDate: referenceDate
)
Check.equal(bayNoWaveHigh.forcing.waveAmplitude, 0, "absent waves must not synthesize wave amplitude")
Check.expect(
    bayNoWaveLow.themeModifiers.crestSharpness > 0,
    "wave-absent current and wind must still drive crest sharpness"
)
Check.expect(
    bayNoWaveLow.themeModifiers.foaminess > 0,
    "wave-absent current and wind must still drive foaminess"
)
Check.expect(
    bayNoWaveLow.themeModifiers.crestSharpness < bayNoWaveHigh.themeModifiers.crestSharpness,
    "wave-absent crest sharpness must scale with observed current and wind"
)
Check.expect(
    bayNoWaveLow.themeModifiers.foaminess < bayNoWaveHigh.themeModifiers.foaminess,
    "wave-absent foaminess must scale with observed current and wind"
)
Check.expect(
    bayNoWaveLow.forcing.chop < bayNoWaveHigh.forcing.chop,
    "wave-absent chop must reweight to observed wind"
)

let missing = HydroState(observedAt: referenceDate, retrievedAt: referenceDate)
Check.expect(missing.currentSpeed == nil && missing.waveHeight == nil && missing.windSpeed == nil, "missing measurements must remain nil")
Check.expect(interpreter.interpret(state(currentSpeed: 1), referenceDate: referenceDate).forcing.flowDirection == nil, "missing current direction must stay nil")

var poisoned = HydroFixtures.active
poisoned.waveHeight = measurement(.nan, .meters)
poisoned.windSpeed = measurement(.infinity, .metersPerSecond)
let safe = interpreter.interpret(poisoned, referenceDate: referenceDate)
let safeValues = [safe.forcing.energy, safe.forcing.chop, safe.forcing.turbulence, safe.forcing.waveAmplitude, safe.forcing.windStrength]
Check.expect(safeValues.allSatisfy { $0.isFinite && (0...1).contains($0) }, "non-finite inputs must not poison outputs")

let stale = state(waveHeight: 1, observedAt: referenceDate.addingTimeInterval(-61 * 60))
Check.expect(interpreter.interpret(stale, referenceDate: referenceDate).forcing.freshness == .stale, "observations older than 60 minutes must be stale")
let live = state(waveHeight: 1, observedAt: referenceDate.addingTimeInterval(-15 * 60))
Check.expect(interpreter.interpret(live, referenceDate: referenceDate).forcing.freshness == .live, "observations at 15 minutes must be live")
Check.expect(interpreter.interpret(missing, referenceDate: referenceDate).forcing.freshness == .unavailable, "states without usable measurements must be unavailable")

let fiveMinutesFuture = state(
    waveHeight: 1,
    observedAt: referenceDate.addingTimeInterval(5 * 60)
)
Check.expect(
    interpreter.interpret(fiveMinutesFuture, referenceDate: referenceDate).forcing.freshness == .live,
    "exactly five minutes of future clock skew must remain usable"
)
let sixMinutesFuture = state(
    waveHeight: 1,
    observedAt: referenceDate.addingTimeInterval(6 * 60)
)
Check.expect(
    interpreter.interpret(sixMinutesFuture, referenceDate: referenceDate).forcing.freshness == .unavailable,
    "future observations beyond clock skew must be unavailable"
)
var futureDriver = SurfaceDriver()
futureDriver.environmentalForcing = interpreter.interpret(
    sixMinutesFuture, referenceDate: referenceDate
).forcing
Check.equal(
    futureDriver.resolvedEnergy,
    futureDriver.energy,
    "unavailable future forcing must not affect the driver"
)
let recentBoundary = state(
    waveHeight: 1,
    observedAt: referenceDate.addingTimeInterval(-60 * 60)
)
Check.expect(
    interpreter.interpret(recentBoundary, referenceDate: referenceDate).forcing.freshness == .recent,
    "exactly sixty minutes must remain recent"
)
let staleBoundary = state(
    waveHeight: 1,
    observedAt: referenceDate.addingTimeInterval(-(60 * 60 + 1))
)
Check.expect(
    interpreter.interpret(staleBoundary, referenceDate: referenceDate).forcing.freshness == .stale,
    "past the recent boundary must be stale"
)

print("Per-signal freshness")
let minutes: (Double) -> Date = { referenceDate.addingTimeInterval(-$0 * 60) }
let mixedFresh = HydroState(
    observedAt: minutes(20),
    retrievedAt: referenceDate,
    waterLevel: measurement(1.2, .meters, observedAt: minutes(5)),
    currentSpeed: measurement(1.0, .metersPerSecond, observedAt: minutes(20)),
    currentDirection: measurement(
        240, .degreesTrue, convention: .toward, observedAt: minutes(20)
    ),
    windSpeed: measurement(12, .metersPerSecond, observedAt: minutes(8)),
    windDirection: measurement(
        210, .degreesTrue, convention: .from, observedAt: minutes(8)
    ),
    pressure: measurement(990, .hectopascals, observedAt: minutes(10))
)
let mixedFreshExperience = interpreter.interpret(mixedFresh, referenceDate: referenceDate)
Check.expect(
    mixedFreshExperience.forcing.flowStrength > 0
        && mixedFreshExperience.forcing.flowDirection != nil
        && mixedFreshExperience.forcing.windStrength > 0
        && mixedFreshExperience.forcing.windDirection != nil,
    "mixed fresh fixture keeps every signal usable"
)

let staleCurrent = HydroState(
    observedAt: minutes(90),
    retrievedAt: referenceDate,
    waterLevel: measurement(1.2, .meters, observedAt: minutes(5)),
    currentSpeed: measurement(2.5, .metersPerSecond, observedAt: minutes(90)),
    currentDirection: measurement(
        240, .degreesTrue, convention: .toward, observedAt: minutes(90)
    ),
    waveHeight: measurement(2.5, .meters, observedAt: minutes(6)),
    windSpeed: measurement(10, .metersPerSecond, observedAt: minutes(8))
)
let staleCurrentExperience = interpreter.interpret(staleCurrent, referenceDate: referenceDate)
Check.equal(staleCurrentExperience.forcing.flowStrength, 0, "stale current speed must be ignored")
Check.expect(
    staleCurrentExperience.forcing.flowDirection == nil,
    "stale current direction must be ignored"
)
Check.expect(
    staleCurrentExperience.forcing.waveAmplitude > 0
        && staleCurrentExperience.forcing.windStrength > 0,
    "mixed stale state still uses fresh wave and wind signals"
)
Check.expect(
    staleCurrentExperience.forcing.freshness == .stale,
    "state freshness remains the conservative snapshot status"
)
Check.expect(
    staleCurrent.currentSpeed?.value == 2.5
        && staleCurrent.currentDirection?.value == 240,
    "ignored stale measurements remain preserved in HydroState"
)

let staleWaveWithFreshWind = HydroState(
    observedAt: minutes(90),
    retrievedAt: referenceDate,
    waveHeight: measurement(5, .meters, observedAt: minutes(90)),
    wavePeriod: measurement(2, .seconds, observedAt: minutes(90)),
    windSpeed: measurement(10, .metersPerSecond, observedAt: minutes(8))
)
let staleWaveExperience = interpreter.interpret(
    staleWaveWithFreshWind, referenceDate: referenceDate
)
Check.equal(staleWaveExperience.forcing.waveAmplitude, 0, "stale wave height must be ignored")
Check.equal(staleWaveExperience.forcing.waveRate, 0, "stale wave period must be ignored")
Check.expect(
    staleWaveExperience.forcing.windStrength > 0,
    "fresh wind remains usable beside stale wave measurements"
)

let freshWindOnly = HydroState(
    observedAt: minutes(8),
    retrievedAt: referenceDate,
    windSpeed: measurement(15, .metersPerSecond, observedAt: minutes(8))
)
let freshWindWithStalePressure = HydroState(
    observedAt: minutes(90),
    retrievedAt: referenceDate,
    windSpeed: freshWindOnly.windSpeed,
    pressure: measurement(968, .hectopascals, observedAt: minutes(90))
)
let freshWindOnlyExperience = interpreter.interpret(freshWindOnly, referenceDate: referenceDate)
let stalePressureExperience = interpreter.interpret(
    freshWindWithStalePressure, referenceDate: referenceDate
)
Check.expect(stalePressureExperience.forcing.windStrength > 0, "fresh wind drives turbulence")
Check.equal(
    stalePressureExperience.forcing.turbulence,
    freshWindOnlyExperience.forcing.turbulence,
    "stale pressure does not affect turbulence"
)
Check.equal(
    stalePressureExperience.themeModifiers.causticStrength,
    freshWindOnlyExperience.themeModifiers.causticStrength,
    "stale pressure does not affect the secondary modifier"
)

let staleEverything = HydroState(
    observedAt: minutes(95),
    retrievedAt: referenceDate,
    waterLevel: measurement(3, .meters, observedAt: minutes(95)),
    waterTemperature: measurement(35, .celsius, observedAt: minutes(94)),
    currentSpeed: measurement(2.5, .metersPerSecond, observedAt: minutes(93)),
    currentDirection: measurement(
        90, .degreesTrue, convention: .toward, observedAt: minutes(93)
    ),
    waveHeight: measurement(5, .meters, observedAt: minutes(92)),
    wavePeriod: measurement(2, .seconds, observedAt: minutes(92)),
    windSpeed: measurement(25, .metersPerSecond, observedAt: minutes(91)),
    windDirection: measurement(
        180, .degreesTrue, convention: .from, observedAt: minutes(91)
    ),
    pressure: measurement(968, .hectopascals, observedAt: minutes(90)),
    salinity: measurement(52, .practicalSalinityUnits, observedAt: minutes(90))
)
let staleEverythingExperience = interpreter.interpret(staleEverything, referenceDate: referenceDate)
Check.equal(staleEverythingExperience.forcing.energy, 0.08, "stale everything retains neutral energy baseline")
Check.equal(staleEverythingExperience.forcing.chop, 0, "stale wave height and period must be ignored")
Check.equal(staleEverythingExperience.forcing.turbulence, 0, "stale wind and current must be ignored")
Check.equal(staleEverythingExperience.forcing.flowStrength, 0, "stale current contributes no strength")
Check.equal(staleEverythingExperience.forcing.waveAmplitude, 0, "stale wave height contributes no amplitude")
Check.equal(staleEverythingExperience.forcing.windStrength, 0, "stale wind contributes no strength")
Check.equal(
    staleEverythingExperience.themeModifiers.causticStrength, 0,
    "stale secondary metrics must not affect modifiers"
)

let futurePoisoned = HydroState(
    observedAt: minutes(10),
    retrievedAt: referenceDate,
    waveHeight: measurement(2, .meters, observedAt: minutes(5)),
    windSpeed: measurement(
        25, .metersPerSecond,
        observedAt: referenceDate.addingTimeInterval(6 * 60)
    )
)
let futurePoisonedExperience = interpreter.interpret(futurePoisoned, referenceDate: referenceDate)
Check.expect(futurePoisonedExperience.forcing.waveAmplitude > 0, "fresh peer signal survives future poison")
Check.equal(futurePoisonedExperience.forcing.windStrength, 0, "future-poisoned individual signal is ignored")
Check.expect(
    futurePoisonedExperience.forcing.freshness == .live,
    "one future-poisoned signal does not make a valid state unavailable"
)

let timestampOverride = HydroState(
    observedAt: minutes(90),
    retrievedAt: referenceDate,
    waveHeight: measurement(2, .meters, observedAt: minutes(5))
)
Check.expect(
    interpreter.interpret(timestampOverride, referenceDate: referenceDate).forcing.waveAmplitude > 0,
    "per-measurement timestamp overrides stale state timestamp"
)
let timestampFallback = HydroState(
    observedAt: minutes(61),
    retrievedAt: referenceDate,
    waveHeight: measurement(2, .meters)
)
Check.equal(
    interpreter.interpret(timestampFallback, referenceDate: referenceDate).forcing.waveAmplitude,
    0,
    "missing measurement timestamp falls back to stale state timestamp"
)
Check.expect(
    interpreter.isSignalUsable(
        measurement(1, .meters, quality: .unknown, observedAt: minutes(60)),
        expectedUnit: .meters,
        stateObservedAt: referenceDate,
        referenceDate: referenceDate
    ),
    "unknown quality at exactly sixty minutes remains usable"
)
Check.expect(
    !interpreter.isSignalUsable(
        measurement(1, .seconds, observedAt: minutes(5)),
        expectedUnit: .meters,
        stateObservedAt: referenceDate,
        referenceDate: referenceDate
    ),
    "signal usability requires the expected unit"
)

func qualityState(
    waveHeight: HydroMeasurement? = nil,
    currentSpeed: HydroMeasurement? = nil,
    currentDirection: HydroMeasurement? = nil
) -> HydroState {
    HydroState(
        observedAt: referenceDate,
        retrievedAt: referenceDate,
        currentSpeed: currentSpeed,
        currentDirection: currentDirection,
        waveHeight: waveHeight
    )
}

let suspectWave = interpreter.interpret(
    qualityState(waveHeight: measurement(5, .meters, quality: .suspect)),
    referenceDate: referenceDate
)
Check.equal(suspectWave.forcing.waveAmplitude, 0, "suspect wave height must be ignored")
let suspectCurrent = interpreter.interpret(
    qualityState(currentSpeed: measurement(2.5, .metersPerSecond, quality: .suspect)),
    referenceDate: referenceDate
)
Check.equal(suspectCurrent.forcing.flowStrength, 0, "suspect current speed must be ignored")
let suspectDirection = interpreter.interpret(
    qualityState(
        currentDirection: measurement(
            270, .degreesTrue, quality: .suspect, convention: .toward
        )
    ),
    referenceDate: referenceDate
)
Check.expect(suspectDirection.forcing.flowDirection == nil, "suspect direction must be ignored")
let unknownWave = interpreter.interpret(
    qualityState(waveHeight: measurement(2, .meters, quality: .unknown)),
    referenceDate: referenceDate
)
let goodWave = interpreter.interpret(
    qualityState(waveHeight: measurement(2, .meters, quality: .good)),
    referenceDate: referenceDate
)
Check.expect(unknownWave.forcing.waveAmplitude > 0, "unknown quality must remain usable")
Check.equal(
    goodWave.forcing.waveAmplitude,
    unknownWave.forcing.waveAmplitude,
    "good and unknown quality must use the same physical mapping"
)

let driverDT = 1.0 / 60.0
func advance(_ driver: inout SurfaceDriver, seconds: Double, motion: MotionSample) {
    var elapsed = 0.0
    while elapsed < seconds {
        driver.advance(dt: driverDT, motion: motion)
        elapsed += driverDT
    }
}

func angularDistance(_ a: Double, _ b: Double) -> Double {
    var delta = abs((a - b).truncatingRemainder(dividingBy: 2 * .pi))
    if delta > .pi { delta = 2 * .pi - delta }
    return delta
}

let fixtureExperiences = [calm, active, severe]
let flatMotion = MotionSample(gravityX: 0, gravityY: 0)
var flatDrivers = fixtureExperiences.map { experience -> SurfaceDriver in
    var driver = SurfaceDriver()
    driver.environmentalForcing = experience.forcing
    advance(&driver, seconds: 8, motion: flatMotion)
    return driver
}
for (driver, experience) in zip(flatDrivers, fixtureExperiences) {
    Check.expect(
        angularDistance(driver.heading, experience.forcing.flowDirection!) < 0.02,
        "flat watch must settle toward environmental current"
    )
}
Check.expect(
    flatDrivers[0].resolvedActivity < flatDrivers[1].resolvedActivity
        && flatDrivers[1].resolvedActivity < flatDrivers[2].resolvedActivity,
    "resolved activity must order calm < active < severe"
)

var overrideDriver = SurfaceDriver()
overrideDriver.environmentalForcing = active.forcing
advance(&overrideDriver, seconds: 8, motion: flatMotion)
let ambientDirection = active.forcing.flowDirection!
let settledHeading = overrideDriver.heading
let wristDirection = Double.pi / 2
advance(
    &overrideDriver,
    seconds: 4,
    motion: MotionSample(gravityX: 1, gravityY: 0)
)
let overriddenHeading = overrideDriver.heading
Check.expect(
    angularDistance(overriddenHeading, wristDirection)
        < angularDistance(settledHeading, wristDirection),
    "strong wrist tilt must gain directional authority"
)
Check.expect(
    angularDistance(overriddenHeading, ambientDirection) > 0.2,
    "heading must not remain locked to environmental direction"
)
advance(&overrideDriver, seconds: 5, motion: flatMotion)
Check.expect(
    angularDistance(overrideDriver.heading, ambientDirection)
        < angularDistance(overriddenHeading, ambientDirection),
    "returning flat must settle back toward ambient flow"
)

var surgeDriver = SurfaceDriver()
surgeDriver.environmentalForcing = active.forcing
let persistentBaseline = surgeDriver.resolvedEnergy
advance(
    &surgeDriver,
    seconds: 1,
    motion: MotionSample(accelerationX: 1.4, rotationZ: 5)
)
let raisedSurge = surgeDriver.surge
Check.expect(raisedSurge > 0.1, "shake must still create surge with environmental forcing")
advance(&surgeDriver, seconds: 4, motion: .level)
Check.expect(surgeDriver.surge < raisedSurge * 0.02, "environmental surge must remain transient")
Check.equal(
    surgeDriver.resolvedEnergy,
    persistentBaseline,
    "environmental baseline must remain after surge decays"
)

var originalDriver = SurfaceDriver()
var nilForcingDriver = SurfaceDriver()
nilForcingDriver.environmentalForcing = nil
let compatibilityMotion = MotionSample(
    gravityX: 0.6,
    gravityY: -0.2,
    accelerationX: 0.3,
    rotationZ: 1
)
advance(&originalDriver, seconds: 2, motion: compatibilityMotion)
advance(&nilForcingDriver, seconds: 2, motion: compatibilityMotion)
Check.equal(nilForcingDriver.heading, originalDriver.heading, "nil forcing must preserve heading")
Check.equal(nilForcingDriver.surge, originalDriver.surge, "nil forcing must preserve surge")
Check.equal(
    nilForcingDriver.resolvedEnergy,
    originalDriver.energy,
    "nil forcing must preserve crown energy"
)

var authoredZeroGravity = SurfaceDriver()
authoredZeroGravity.configure(for: .zeroGravity)
authoredZeroGravity.environmentalForcing = severe.forcing
var baselineZeroGravity = SurfaceDriver()
baselineZeroGravity.configure(for: .zeroGravity)
advance(&authoredZeroGravity, seconds: 6, motion: .level)
advance(&baselineZeroGravity, seconds: 6, motion: .level)
Check.equal(
    authoredZeroGravity.heading,
    baselineZeroGravity.heading,
    "environmental heading must not override Zero Gravity"
)

let baseTheme = OceanTheme.calmOcean
let originalTheme = baseTheme
let authoredStyle = ResolvedWaterStyle(base: baseTheme, modifiers: nil)
Check.equal(authoredStyle.choppiness, baseTheme.choppiness, "nil style must preserve choppiness")
Check.equal(authoredStyle.turbulence, baseTheme.turbulence, "nil style must preserve turbulence")
Check.equal(
    authoredStyle.crestSharpness,
    baseTheme.crestSharpness,
    "nil style must preserve crest sharpness"
)
Check.equal(authoredStyle.foaminess, baseTheme.foaminess, "nil style must preserve foaminess")
Check.equal(
    authoredStyle.causticStrength,
    baseTheme.causticStrength,
    "nil style must preserve caustic strength"
)
Check.equal(authoredStyle.glitter, baseTheme.glitter, "nil style must preserve glitter")

let calmStyle = ResolvedWaterStyle(base: baseTheme, modifiers: calm.themeModifiers)
let activeStyle = ResolvedWaterStyle(base: baseTheme, modifiers: active.themeModifiers)
let severeStyle = ResolvedWaterStyle(base: baseTheme, modifiers: severe.themeModifiers)
Check.expect(
    calmStyle.choppiness < activeStyle.choppiness
        && activeStyle.choppiness < severeStyle.choppiness,
    "resolved choppiness must order calm < active < severe"
)
Check.expect(
    calmStyle.turbulence < activeStyle.turbulence
        && activeStyle.turbulence < severeStyle.turbulence,
    "resolved turbulence must order calm < active < severe"
)
Check.expect(
    calmStyle.crestSharpness < activeStyle.crestSharpness
        && activeStyle.crestSharpness < severeStyle.crestSharpness,
    "resolved crest sharpness must order calm < active < severe"
)
Check.expect(
    calmStyle.foaminess < activeStyle.foaminess
        && activeStyle.foaminess < severeStyle.foaminess,
    "resolved foaminess must order calm < active < severe"
)

let resolvedStyle = severeStyle
Check.expect(baseTheme == originalTheme, "resolving style must not mutate OceanTheme")
Check.expect(
    (0...2.5).contains(resolvedStyle.choppiness)
        && (0...1).contains(resolvedStyle.turbulence)
        && (0...1).contains(resolvedStyle.crestSharpness)
        && (0...1).contains(resolvedStyle.foaminess)
        && (0...2).contains(resolvedStyle.causticStrength)
        && (0...3.5).contains(resolvedStyle.glitter),
    "resolved style fields must respect renderer-specific bounds"
)
Check.expect(
    (0..<20).allSatisfy { _ in
        ResolvedWaterStyle(base: baseTheme, modifiers: active.themeModifiers) == activeStyle
    },
    "resolved style must be deterministic"
)
Check.expect(
    severeStyle.choppiness < 1.2
        && severeStyle.turbulence < 0.5
        && severeStyle.crestSharpness < 0.5
        && severeStyle.foaminess < 0.5,
    "severe fixture must remain below visual saturation thresholds"
)

let poisonedModifiers = HydroThemeModifiers(
    choppiness: .nan,
    turbulence: .infinity,
    crestSharpness: -.infinity,
    foaminess: .nan,
    causticStrength: .infinity,
    glitter: .nan
)
let safeStyle = ResolvedWaterStyle(base: baseTheme, modifiers: poisonedModifiers)
Check.expect(
    [
        safeStyle.choppiness, safeStyle.turbulence, safeStyle.crestSharpness,
        safeStyle.foaminess, safeStyle.causticStrength, safeStyle.glitter,
    ].allSatisfy(\.isFinite),
    "non-finite modifiers must not poison resolved style"
)

let repeated = (0..<20).map { _ in interpreter.interpret(HydroFixtures.severe, referenceDate: referenceDate) }
Check.expect(repeated.allSatisfy { $0 == severe }, "fixture output must be deterministic across repeated runs")

print("Place status presentation")
let statusResolver = PlaceHydroStatusResolver()
let statusBody = WaterBodies.sanFranciscoBay
let freshTime = referenceDate.addingTimeInterval(-7 * 60)
let staleTime = referenceDate.addingTimeInterval(-90 * 60)
let statusState = HydroState(
    observedAt: freshTime,
    retrievedAt: referenceDate,
    waterLevel: measurement(1.2, .meters, observedAt: freshTime, id: "noaa.coops.9414290.water_level"),
    currentSpeed: measurement(0.8, .metersPerSecond, observedAt: freshTime, id: "noaa.coops.s09010.currents.speed"),
    windSpeed: measurement(4.2, .metersPerSecond, observedAt: freshTime, id: "noaa.coops.9414290.wind.speed")
)
let presented = statusResolver.resolve(
    waterBody: statusBody,
    state: statusState,
    referenceDate: referenceDate
)
Check.expect(
    presented.signals.count == HydroCapability.allCases.count,
    "every canonical Hydro capability must produce a presentation status"
)
Check.expect(
    presented.signal(.waterLevel)?.observationAvailability == .observed,
    "catalog supported plus current measurement must present observed"
)
Check.expect(
    presented.signal(.waterTemperature)?.observationAvailability == .unavailable,
    "catalog unsupported capability must present unavailable"
)
let noObservation = statusResolver.resolve(
    waterBody: statusBody,
    state: HydroState(observedAt: freshTime, retrievedAt: referenceDate),
    referenceDate: referenceDate
)
Check.expect(
    noObservation.signal(.waterLevel)?.observationAvailability == .missing,
    "supported capability without a measurement must present missing current observation"
)

var staleStatusState = statusState
staleStatusState.currentSpeed?.observedAt = staleTime
let stalePresented = statusResolver.resolve(
    waterBody: statusBody,
    state: staleStatusState,
    referenceDate: referenceDate
)
Check.expect(
    stalePresented.signal(.currentSpeed)?.observationAvailability == .stale,
    "supported stale measurement must present stale"
)
Check.expect(
    stalePresented.signal(.currentSpeed)?.measurements.first?.value == 0.8,
    "stale status must preserve the raw measurement"
)

var suspectStatusState = statusState
suspectStatusState.waterLevel?.quality = .suspect
let suspectPresented = statusResolver.resolve(
    waterBody: statusBody,
    state: suspectStatusState,
    referenceDate: referenceDate
)
Check.expect(
    suspectPresented.signal(.waterLevel)?.observationAvailability == .observed,
    "timely suspect evidence must remain visibly observed"
)
Check.expect(
    suspectPresented.signal(.waterLevel)?.usableForForcing == false,
    "suspect evidence must be marked not used"
)
var unknownStatusState = statusState
unknownStatusState.waterLevel?.quality = .unknown
let unknownPresented = statusResolver.resolve(
    waterBody: statusBody,
    state: unknownStatusState,
    referenceDate: referenceDate
)
Check.expect(
    unknownPresented.signal(.waterLevel)?.usableForForcing == true,
    "unknown-quality evidence must remain usable"
)
var fallbackTimestampState = statusState
fallbackTimestampState.waterLevel?.observedAt = nil
let fallbackTimestampStatus = statusResolver.resolve(
    waterBody: statusBody,
    state: fallbackTimestampState,
    referenceDate: referenceDate
)
Check.expect(
    fallbackTimestampStatus.signal(.waterLevel)?
        .effectiveObservedAtBySourceID["noaa.coops.9414290.water_level"] == freshTime,
    "missing measurement timestamp must present the state observation fallback"
)

let speedOnlyCurrent = presented.displaySignals.first { $0.signal == .current }
Check.expect(
    speedOnlyCurrent?.observationAvailability == .observed
        && speedOnlyCurrent?.measurements.count == 1,
    "current grouping must present speed-only observations without inventing direction"
)
var directionOnlyState = HydroState(observedAt: freshTime, retrievedAt: referenceDate)
directionOnlyState.currentDirection = measurement(
    225, .degreesTrue, convention: .toward, observedAt: freshTime,
    id: "noaa.coops.s09010.currents.direction"
)
let directionOnly = statusResolver.resolve(
    waterBody: statusBody,
    state: directionOnlyState,
    referenceDate: referenceDate
).displaySignals.first { $0.signal == .current }
Check.expect(
    directionOnly?.observationAvailability == .observed
        && directionOnly?.measurements.count == 1,
    "current grouping must present direction-only observations without inventing speed"
)
let windOnly = presented.displaySignals.first { $0.signal == .wind }
Check.expect(
    windOnly?.measurements.count == 1 && windOnly?.usableForForcing == true,
    "wind grouping must preserve partial speed-only fields"
)

let noaaSource = HydroPresentationFormatter.source("noaa.coops.9414290.water_level")
Check.expect(
    noaaSource.providerName == "NOAA CO-OPS"
        && noaaSource.sourceName == "Station 9414290"
        && noaaSource.canonicalSourceID == "noaa.coops.9414290.water_level",
    "NOAA source presentation must be deterministic and retain canonical identity"
)
let usgsSource = HydroPresentationFormatter.source("usgs.nwis.10337000.00065")
Check.expect(
    usgsSource.providerName == "USGS"
        && usgsSource.sourceName == "Site 10337000"
        && usgsSource.canonicalSourceID == "usgs.nwis.10337000.00065",
    "USGS source presentation must be deterministic and retain canonical identity"
)
Check.expect(
    HydroPresentationFormatter.age(
        observedAt: referenceDate.addingTimeInterval(-7 * 60),
        referenceDate: referenceDate
    ) == "Observed 7 min ago",
    "minute freshness formatting must be deterministic"
)
Check.expect(
    HydroPresentationFormatter.age(
        observedAt: referenceDate.addingTimeInterval(-2 * 60 * 60),
        referenceDate: referenceDate
    ) == "Observed 2 hr ago",
    "hour freshness formatting must be deterministic"
)
Check.expect(
    HydroPresentationFormatter.quality(.unknown, used: true) == "Provisional / Unknown",
    "unknown quality wording must not imply invalid data"
)
Check.expect(
    HydroPresentationFormatter.quality(.suspect, used: false) == "Suspect · not used",
    "suspect quality wording must disclose that it does not drive water"
)
Check.expect(
    HydroPresentationFormatter.origin(.forecast) == "Forecast"
        && HydroPresentationFormatter.origin(.predicted) == "Predicted"
        && HydroPresentationFormatter.origin(.derived) == "Derived",
    "origin wording must cover future Real Water products"
)

print("Active Place load-state boundary")
let bodyA = WaterBodies.sanFranciscoBay
let bodyB = WaterBodies.montereyBay
let statusA = statusResolver.resolve(waterBody: bodyA, state: statusState, referenceDate: referenceDate)
let statusB = statusResolver.resolve(waterBody: bodyB, state: nil, referenceDate: referenceDate)
var loadReducer = RealWaterLoadReducer()
let requestA = loadReducer.beginLoading(waterBodyID: bodyA.id)
Check.expect(loadReducer.state == .loading(bodyA.id), "selection must start loading for the selected Place ID")
let requestB = loadReducer.beginLoading(waterBodyID: bodyB.id)
Check.expect(loadReducer.state == .loading(bodyB.id), "switching Place must clear the old status")
Check.expect(
    loadReducer.accept(
        .updated,
        status: statusA,
        waterBodyID: bodyA.id,
        requestGeneration: requestA
    ) == false,
    "late result for an old Place must be rejected"
)
Check.expect(
    loadReducer.state == .loading(bodyB.id),
    "late result for an old Place must not overwrite the new Place loading state"
)
Check.expect(
    loadReducer.accept(
        .updated,
        status: statusB,
        waterBodyID: bodyB.id,
        requestGeneration: requestB
    ),
    "updated active Place result must be accepted"
)
Check.expect(loadReducer.state == .loaded(statusB), "updated active Place must publish loaded status")
let olderSamePlaceRequest = loadReducer.beginLoading(waterBodyID: bodyB.id)
let newerSamePlaceRequest = loadReducer.beginLoading(waterBodyID: bodyB.id)
Check.expect(
    loadReducer.accept(
        .updated,
        status: statusB,
        waterBodyID: bodyB.id,
        requestGeneration: olderSamePlaceRequest
    ) == false && loadReducer.state == .loading(bodyB.id),
    "older generation for the same Place must not overwrite its newer activation"
)
Check.expect(
    loadReducer.accept(
        .updated,
        status: statusB,
        waterBodyID: bodyB.id,
        requestGeneration: newerSamePlaceRequest
    ),
    "newest generation for the active Place must be accepted"
)
let preservedRequest = loadReducer.beginLoading(waterBodyID: bodyB.id)
Check.expect(
    loadReducer.accept(
        .preserved,
        status: statusB,
        waterBodyID: bodyB.id,
        requestGeneration: preservedRequest
    )
        && loadReducer.state == .preserved(statusB),
    "cached failure must publish preserved status"
)
let unavailableRequest = loadReducer.beginLoading(waterBodyID: bodyB.id)
Check.expect(
    loadReducer.accept(
        .unavailable,
        status: nil,
        waterBodyID: bodyB.id,
        requestGeneration: unavailableRequest
    )
        && loadReducer.state == .unavailable(bodyB.id),
    "uncached failure must publish unavailable status"
)

let failedState = RealWaterLoadState.failed(bodyB.id, "Real Water unavailable on watch")
Check.expect(
    failedState == .failed(bodyB.id, "Real Water unavailable on watch")
        && failedState.waterBodyID == bodyB.id
        && failedState.failureReason == "Real Water unavailable on watch",
    "failed watch-state must retain place identity and reason"
)

print("Hydro fixtures:")
for (name, experience, style) in [
    ("calm", calm, calmStyle),
    ("active", active, activeStyle),
    ("severe", severe, severeStyle),
] {
    print("  \(name): energy=\(experience.forcing.energy), chop=\(experience.forcing.chop), turbulence=\(experience.forcing.turbulence)")
    print("    style: chop=\(style.choppiness), turbulence=\(style.turbulence), crest=\(style.crestSharpness), foam=\(style.foaminess), caustics=\(style.causticStrength), glitter=\(style.glitter)")
}

if Check.failures.isEmpty {
    print("All \(Check.count) hydro checks passed.")
    exit(0)
}

print("\(Check.failures.count) failure(s) out of \(Check.count) hydro checks:")
for failure in Check.failures { print("  • \(failure)") }
exit(1)
