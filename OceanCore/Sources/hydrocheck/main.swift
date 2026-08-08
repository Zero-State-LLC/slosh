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

func measurement(_ value: Double, _ unit: HydroUnit, id: String = "check") -> HydroMeasurement {
    HydroMeasurement(value: value, unit: unit, origin: .observed, quality: .good, sourceID: id)
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
        currentDirection: currentDirection.map { measurement($0, .degreesTrue) },
        waveHeight: waveHeight.map { measurement($0, .meters) },
        windSpeed: windSpeed.map { measurement($0, .metersPerSecond) }
    )
}

let slowCurrent = interpreter.interpret(state(currentSpeed: 0.2), referenceDate: referenceDate)
let fastCurrent = interpreter.interpret(state(currentSpeed: 1.8), referenceDate: referenceDate)
Check.expect(slowCurrent.forcing.flowStrength < fastCurrent.forcing.flowStrength, "higher current must raise flow strength")

let directed = interpreter.interpret(state(currentDirection: 270), referenceDate: referenceDate)
Check.equal(directed.forcing.flowDirection, 3 * .pi / 2, "current direction must convert degrees true to radians")

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

let repeated = (0..<20).map { _ in interpreter.interpret(HydroFixtures.severe, referenceDate: referenceDate) }
Check.expect(repeated.allSatisfy { $0 == severe }, "fixture output must be deterministic across repeated runs")

print("Hydro fixtures:")
for (name, experience) in [("calm", calm), ("active", active), ("severe", severe)] {
    print("  \(name): energy=\(experience.forcing.energy), chop=\(experience.forcing.chop), turbulence=\(experience.forcing.turbulence)")
}

if Check.failures.isEmpty {
    print("All \(Check.count) hydro checks passed.")
    exit(0)
}

print("\(Check.failures.count) failure(s) out of \(Check.count) hydro checks:")
for failure in Check.failures { print("  • \(failure)") }
exit(1)
