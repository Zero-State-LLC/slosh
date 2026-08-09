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
    id: String = "check"
) -> HydroMeasurement {
    HydroMeasurement(
        value: value,
        unit: unit,
        origin: .observed,
        quality: quality,
        sourceID: id,
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
