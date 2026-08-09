import Foundation
import OceanCore

let dt = 1.0 / 60.0

/// Runs the driver forward with a constant motion sample.
func run(
    _ driver: inout SurfaceDriver, seconds: Double, motion: MotionSample
) {
    var t = 0.0
    while t < seconds {
        driver.advance(dt: dt, motion: motion)
        t += dt
    }
}

Check.suite("Flow direction") {
    // The swell has to travel the way gravity points, or tilting the watch
    // looks like it does nothing.
    Check.test("flow turns toward gravity") {
        var driver = SurfaceDriver()
        // Gravity swung hard to the right.
        run(&driver, seconds: 6, motion: MotionSample(gravityX: 1, gravityY: 0))
        Check.greaterThan(driver.flowX, 0.9, "flow never turned to the right")
        Check.equal(
            (driver.flowX * driver.flowX + driver.flowY * driver.flowY).squareRoot(),
            1.0, accuracy: 1e-6, "flow stopped being a unit vector"
        )
    }

    Check.test("flow reverses when gravity reverses") {
        var driver = SurfaceDriver()
        run(&driver, seconds: 6, motion: MotionSample(gravityX: 1, gravityY: 0))
        run(&driver, seconds: 6, motion: MotionSample(gravityX: -1, gravityY: 0))
        Check.lessThan(driver.flowX, -0.9, "flow never turned back to the left")
    }

    // Flat on a table there is no in-plane gravity at all. The swell should
    // keep its heading rather than snapping to whatever noise says.
    Check.test("a face-up watch keeps its heading") {
        var driver = SurfaceDriver()
        run(&driver, seconds: 4, motion: MotionSample(gravityX: 1, gravityY: 0))
        let heldX = driver.flowX
        let heldY = driver.flowY
        run(&driver, seconds: 4, motion: MotionSample(gravityX: 0, gravityY: 0))
        Check.equal(driver.flowX, heldX, accuracy: 1e-9, "heading drifted when flat")
        Check.equal(driver.flowY, heldY, accuracy: 1e-9, "heading drifted when flat")
    }

    Check.test("flow is smoothed, not snapped") {
        var driver = SurfaceDriver()
        driver.advance(dt: dt, motion: MotionSample(gravityX: 1, gravityY: 0))
        Check.lessThan(
            driver.flowX, 0.5,
            "one frame should not complete the turn — that reads as a jump"
        )
    }

    Check.test("rejects non-finite gravity") {
        var driver = SurfaceDriver()
        driver.advance(dt: dt, motion: MotionSample(gravityX: .nan, gravityY: .nan))
        Check.expect(driver.flowX.isFinite && driver.flowY.isFinite, "flow poisoned by NaN")
    }
}

Check.suite("Surge") {
    Check.test("shaking raises surge, stillness lets it fall") {
        var driver = SurfaceDriver()
        run(&driver, seconds: 1.0, motion: MotionSample(accelerationX: 1.4, rotationZ: 5))
        let excited = driver.surge
        Check.greaterThan(excited, 0.1, "shaking did not stir the water")

        run(&driver, seconds: 3.0, motion: .level)
        Check.lessThan(driver.surge, excited * 0.05, "surge never decayed")
    }

    Check.test("surge is bounded under sustained violence") {
        var driver = SurfaceDriver()
        // The most violent mode, shaken as hard as a wrist can manage.
        driver.motionGain = OceanTheme.breakingSurf.motionGain
        run(
            &driver, seconds: 20,
            motion: MotionSample(accelerationX: 9, accelerationY: 9, rotationZ: 40)
        )
        Check.expect(driver.surge <= 3.0 + 1e-9, "surge ran away to \(driver.surge)")
        Check.expect(driver.surge.isFinite, "surge went non-finite")
    }

    // A violent mode has to answer the same wrist far harder than a restful
    // one, or the modes are only a palette swap.
    Check.test("motion gain separates the violent modes from the calm ones") {
        var wild = SurfaceDriver()
        var mild = SurfaceDriver()
        wild.motionGain = OceanTheme.breakingSurf.motionGain
        mild.motionGain = OceanTheme.rainShower.motionGain
        // Brief and gentle on purpose: a hard shake saturates both against the
        // surge ceiling, which would make them look identical and prove
        // nothing.
        let shake = MotionSample(accelerationX: 0.4, rotationZ: 1.0)
        run(&wild, seconds: 0.25, motion: shake)
        run(&mild, seconds: 0.25, motion: shake)
        Check.lessThan(wild.surge, 3.0, "the test saturated; lighten the shake")
        Check.greaterThan(wild.surge, mild.surge * 3, "the modes react alike")
    }

    Check.test("a still watch never surges") {
        var driver = SurfaceDriver()
        run(&driver, seconds: 4, motion: .level)
        Check.lessThan(driver.surge, 1e-6, "the water stirred itself")
    }
}

Check.suite("Ripples") {
    Check.test("a tap fills the next slot") {
        var driver = SurfaceDriver()
        driver.advance(dt: dt, motion: .level)
        driver.ripple(atX: 0.5, y: 0.6)
        Check.equal(driver.ripples.filter { $0.strength > 0 }.count, 1)
        Check.equal(driver.ripples[0].x, 0.5, accuracy: 1e-9)
    }

    // Six slots, oldest recycled — the shader cannot afford more, and a
    // silently dropped tap would feel broken.
    Check.test("slots recycle rather than overflow") {
        var driver = SurfaceDriver()
        for i in 0..<14 {
            driver.advance(dt: dt, motion: .level)
            driver.ripple(atX: Double(i) / 14, y: 0.5)
        }
        Check.equal(driver.ripples.count, 6, "slot count changed")
        Check.expect(
            driver.ripples.allSatisfy { $0.strength > 0 },
            "a slot was left empty after fourteen taps"
        )
    }

    Check.test("ripple strength follows crown energy") {
        var driver = SurfaceDriver()
        driver.energy = 2.0
        driver.ripple(atX: 0.5, y: 0.5, strength: 1)
        let loud = driver.ripples[0].strength

        var quiet = SurfaceDriver()
        quiet.energy = 0.3
        quiet.ripple(atX: 0.5, y: 0.5, strength: 1)
        Check.greaterThan(loud, quiet.ripples[0].strength * 3, "energy had no effect")
    }

    Check.test("rejects non-finite taps") {
        var driver = SurfaceDriver()
        driver.ripple(atX: .nan, y: .infinity)
        Check.expect(
            driver.ripples.allSatisfy { $0.strength == 0 },
            "a NaN tap was accepted"
        )
    }

    // A sustained shake must not spawn a ripple every frame, or they smear
    // into noise instead of reading as distinct waves.
    Check.test("jolt ripples are rate limited") {
        var driver = SurfaceDriver()
        run(
            &driver, seconds: 1.0,
            motion: MotionSample(accelerationX: 6, accelerationY: 4, rotationZ: 20)
        )
        let born = driver.ripples.filter { $0.birth > 0 }.map(\.birth).sorted()
        for (earlier, later) in zip(born, born.dropFirst()) {
            Check.expect(
                later - earlier > 0.3,
                "two jolt ripples were born \(later - earlier)s apart"
            )
        }
    }

    Check.test("reset clears the surface") {
        var driver = SurfaceDriver()
        run(&driver, seconds: 1, motion: MotionSample(accelerationX: 4, rotationZ: 12))
        driver.ripple(atX: 0.5, y: 0.5)
        driver.reset()
        Check.equal(driver.surge, 0, accuracy: 1e-12)
        Check.expect(driver.ripples.allSatisfy { $0.strength == 0 }, "ripples survived reset")
    }
}

Check.suite("Rain") {
    // Rain is the only mode that keeps moving when the wrist does not, so it
    // has to produce drops from nothing at all.
    Check.test("drops fall with no motion at all") {
        var driver = SurfaceDriver()
        driver.rainRate = OceanTheme.rainShower.rainRate
        run(&driver, seconds: 2.0, motion: .level)
        Check.expect(
            driver.ripples.contains { $0.strength > 0 },
            "a rain shower produced no drops"
        )
    }

    Check.test("drops land at roughly the requested rate") {
        var driver = SurfaceDriver()
        driver.rainRate = 3.0
        // Count births rather than slots, since slots recycle.
        var births = Set<Double>()
        var t = 0.0
        while t < 4.0 {
            driver.advance(dt: dt, motion: .level)
            for r in driver.ripples where r.strength > 0 { births.insert(r.birth) }
            t += dt
        }
        // 3/s for 4s is 12, minus those already recycled out of view.
        Check.greaterThan(Double(births.count), 8, "too few drops: \(births.count)")
    }

    // Fractional drops must carry over, or a slow shower rounds to nothing.
    Check.test("a slow shower still rains") {
        var driver = SurfaceDriver()
        driver.rainRate = 0.4
        run(&driver, seconds: 12, motion: .level)
        Check.expect(
            driver.ripples.contains { $0.strength > 0 },
            "a slow rate rounded away to no drops at all"
        )
    }

    Check.test("modes that declare no rain stay dry") {
        for theme in OceanTheme.all where theme.rainRate == 0 {
            var driver = SurfaceDriver()
            driver.configure(for: theme)
            run(&driver, seconds: 3, motion: .level)
            Check.expect(
                driver.ripples.allSatisfy { $0.strength == 0 },
                "\(theme.name) rained unprompted"
            )
        }
    }
}

Check.suite("Lightning") {
    Check.test("a storm strikes, a calm sea never does") {
        var storm = SurfaceDriver()
        storm.configure(for: .stormAtNight)
        var peak = 0.0
        var t = 0.0
        while t < 40 {
            storm.advance(dt: dt, motion: .level)
            peak = max(peak, storm.flash)
            t += dt
        }
        Check.greaterThan(peak, 0.5, "no lightning in forty seconds of storm")

        var calm = SurfaceDriver()
        calm.configure(for: .calmOcean)
        run(&calm, seconds: 20, motion: .level)
        Check.equal(calm.flash, 0, accuracy: 1e-12, "a calm sea flashed")
    }

    // A strike has to be a strike: bright, then gone. A slow fade reads as a
    // light being turned up, not as lightning.
    Check.test("a strike decays fast") {
        var driver = SurfaceDriver()
        driver.configure(for: .stormAtNight)
        var t = 0.0
        while t < 40, driver.flash < 0.5 {
            driver.advance(dt: dt, motion: .level)
            t += dt
        }
        Check.greaterThan(driver.flash, 0.5, "never caught a strike")
        run(&driver, seconds: 0.5, motion: .level)
        Check.lessThan(driver.flash, 0.05, "the flash lingered like a lamp")
    }

    // Real lightning is not a metronome, and a periodic one would be maddening
    // on something meant to be watched for minutes.
    Check.test("strikes are irregular") {
        var driver = SurfaceDriver()
        driver.configure(for: .stormAtNight)
        var gaps: [Double] = []
        var lastStrike: Double?
        var wasDark = true
        var t = 0.0
        while t < 200 {
            driver.advance(dt: dt, motion: .level)
            if wasDark, driver.flash > 0.5 {
                if let last = lastStrike { gaps.append(driver.time - last) }
                lastStrike = driver.time
            }
            wasDark = driver.flash < 0.1
            t += dt
        }
        Check.greaterThan(Double(gaps.count), 3, "too few strikes to judge")
        let spread = (gaps.max() ?? 0) - (gaps.min() ?? 0)
        Check.greaterThan(spread, 0.5, "strikes were evenly spaced")
    }
}

Check.suite("Zero gravity") {
    // The whole idea of the mode: gravity is ignored and the swell wanders.
    Check.test("heading wanders with no gravity to follow") {
        var driver = SurfaceDriver()
        driver.configure(for: .zeroGravity)
        let start = driver.heading
        run(&driver, seconds: 12, motion: MotionSample(gravityX: 1, gravityY: 0))
        Check.greaterThan(
            abs(driver.heading - start), 0.05, "the swell never wandered"
        )
    }

    // Comparing the two headings directly is a trap: a wandering heading can
    // pass through the gravity direction by coincidence. The real distinction
    // is that water which follows gravity *settles* under a fixed tilt, and
    // water which ignores it never stops moving.
    Check.test("gravity is genuinely ignored") {
        var free = SurfaceDriver()
        var bound = SurfaceDriver()
        free.configure(for: .zeroGravity)
        bound.configure(for: .calmOcean)
        let tilted = MotionSample(gravityX: 1, gravityY: 0)

        run(&free, seconds: 8, motion: tilted)
        run(&bound, seconds: 8, motion: tilted)
        let freeSettled = free.heading
        let boundSettled = bound.heading

        run(&free, seconds: 8, motion: tilted)
        run(&bound, seconds: 8, motion: tilted)

        Check.greaterThan(bound.flowX, 0.9, "gravity-following water did not follow")
        Check.lessThan(
            abs(bound.heading - boundSettled), 0.02,
            "gravity-following water never settled under a fixed tilt"
        )
        Check.greaterThan(
            abs(free.heading - freeSettled), 0.3,
            "free water settled, so it is following something"
        )
    }
}

Check.suite("Bowl centre") {
    // Tilting should move where the water is deepest, not only which way the
    // waves march — otherwise tilt reads as a texture change.
    Check.test("the deep part moves toward the low side") {
        var driver = SurfaceDriver()
        driver.configure(for: .calmOcean)
        let restX = driver.centerX
        run(&driver, seconds: 8, motion: MotionSample(gravityX: 1, gravityY: 0))
        Check.greaterThan(driver.centerX, restX + 0.05, "the bowl never shifted")
    }

    Check.test("the centre stays on screen") {
        var driver = SurfaceDriver()
        driver.configure(for: .zeroGravity)
        var worstX = 0.0
        var t = 0.0
        while t < 60 {
            driver.advance(dt: dt, motion: .level)
            worstX = max(worstX, abs(driver.centerX - 0.5))
            t += dt
        }
        Check.lessThan(worstX, 0.35, "the bowl wandered off the edge")
    }

    Check.test("the centre lags the heading") {
        var driver = SurfaceDriver()
        driver.configure(for: .calmOcean)
        driver.advance(dt: dt, motion: MotionSample(gravityX: 1, gravityY: 0))
        Check.lessThan(
            abs(driver.centerX - 0.5), 0.02,
            "the centre snapped in one frame, which reads as a bug"
        )
    }
}

Check.suite("Clock") {
    Check.test("time advances monotonically and ignores bad steps") {
        var driver = SurfaceDriver()
        run(&driver, seconds: 2, motion: .level)
        let elapsed = driver.time
        Check.equal(elapsed, 2.0, accuracy: 0.05, "clock drifted")

        driver.advance(dt: -1, motion: .level)
        driver.advance(dt: .nan, motion: .level)
        Check.equal(driver.time, elapsed, accuracy: 1e-9, "a bad step moved the clock")
    }
}

Check.suite("Themes") {
    Check.test("catalogue is well formed") {
        Check.equal(
            Set(OceanTheme.all.map(\.id)).count, OceanTheme.all.count, "duplicate theme ids"
        )
        for theme in OceanTheme.all {
            Check.expect(!theme.name.isEmpty, "a theme has no name")
            Check.expect(!theme.blurb.isEmpty, "\(theme.name) has no blurb")
            Check.greaterThan(theme.choppiness, 0, "\(theme.name) has no chop")
            Check.expect(theme.glitter >= 0, "\(theme.name) has negative glitter")
            Check.expect(
                (0...1).contains(theme.crestSharpness),
                "\(theme.name) crest sharpness is out of range"
            )
            Check.expect(theme.turbulence >= 0, "\(theme.name) has negative turbulence")
            Check.expect(theme.foaminess >= 0, "\(theme.name) has negative foam")
            Check.greaterThan(theme.motionGain, 0, "\(theme.name) ignores motion entirely")
        }
    }

    // The modes have to be genuinely different substances, not one water in
    // several colours. Breaking surf is the extreme end of that promise.
    Check.test("breaking surf is the violent one") {
        let surf = OceanTheme.breakingSurf
        for other in OceanTheme.all where other.id != surf.id {
            Check.expect(
                surf.motionGain >= other.motionGain,
                "\(other.name) answers motion harder than breaking surf"
            )
            Check.expect(
                surf.foaminess >= other.foaminess,
                "\(other.name) foams more than breaking surf"
            )
        }
        Check.greaterThan(surf.crestSharpness, 0.5, "surf crests do not peak")
        Check.greaterThan(surf.turbulence, 0.5, "surf is not disordered")
    }

    // Foam is drawn over the water, so it has to be lighter than it.
    Check.test("foam reads lighter than the water it sits on") {
        for theme in OceanTheme.all where theme.foaminess > 0 {
            let foam = theme.foamColor.red + theme.foamColor.green + theme.foamColor.blue
            let water = theme.shallow.red + theme.shallow.green + theme.shallow.blue
            Check.greaterThan(foam, water, "\(theme.name) foam is darker than its water")
        }
    }

    // Every optional shader layer is gated on a uniform being above zero, so a
    // negative value would silently disable a mode's defining feature.
    Check.test("no mode declares a negative layer strength") {
        for theme in OceanTheme.all {
            Check.expect(theme.bedDetail >= 0, "\(theme.name) bed detail")
            Check.expect(theme.shadows >= 0, "\(theme.name) shadows")
            Check.expect(theme.shafts >= 0, "\(theme.name) shafts")
            Check.expect(theme.skyGlow >= 0, "\(theme.name) sky glow")
            Check.expect(theme.causticTimeScale >= 0, "\(theme.name) caustic time")
            Check.expect(theme.lightningInterval >= 0, "\(theme.name) lightning")
        }
    }

    // Each of these modes exists *because* of one feature. If the feature is
    // off the mode is a recolour of something else, so the catalogue is checked
    // against its own premise.
    Check.test("every mode actually has its defining feature") {
        Check.greaterThan(OceanTheme.tidePool.bedDetail, 0.5, "tide pool has no bed")
        Check.greaterThan(OceanTheme.koiPond.shadows, 0.5, "koi pond has nothing below")
        Check.greaterThan(OceanTheme.deepDrift.shafts, 0.5, "deep drift has no shafts")
        Check.equal(OceanTheme.deepDrift.particles, ParticleKind.drift, "no marine snow")
        Check.greaterThan(OceanTheme.aurora.skyGlow, 0.5, "aurora has no sky")
        Check.equal(
            OceanTheme.underIce.causticTimeScale, 0,
            accuracy: 1e-12, "under ice is not frozen"
        )
        Check.greaterThan(
            OceanTheme.stormAtNight.lightningInterval, 0, "night storm has no lightning"
        )
        Check.expect(!OceanTheme.zeroGravity.followsGravity, "zero gravity has gravity")
        Check.equal(OceanTheme.breakingSurf.particles, ParticleKind.spray, "surf has no spray")
    }

    // Only the modes that mean to be lively should be, or the picker's promise
    // that some of these are restful is a lie.
    Check.test("the restful modes stay restful") {
        for theme in [OceanTheme.calmOcean, .rainShower, .underIce, .koiPond] {
            Check.lessThan(theme.motionGain, 1.0, "\(theme.name) is too twitchy")
            Check.lessThan(theme.turbulence, 0.2, "\(theme.name) is too disordered")
            Check.equal(theme.foaminess, 0, accuracy: 1e-12, "\(theme.name) foams")
        }
    }

    // The whole look depends on depth reading darker than the shallows.
    Check.test("deep is darker than shallow in every theme") {
        for theme in OceanTheme.all {
            let deep = theme.deep.red + theme.deep.green + theme.deep.blue
            let shallow = theme.shallow.red + theme.shallow.green + theme.shallow.blue
            Check.lessThan(deep, shallow, "\(theme.name) is inverted")
        }
    }

    Check.test("an unknown id falls back to calm") {
        Check.equal(OceanTheme.theme(id: "nonsense").id, "calm")
    }

    Check.test("hex colour initialiser") {
        let color = RGBA(0x336699)
        Check.equal(color.red, 0x33 / 255.0)
        Check.equal(color.green, 0x66 / 255.0)
        Check.equal(color.blue, 0x99 / 255.0)
        Check.equal(color.alpha, 1)
    }
}

Check.suite("Physical validation metrics") {
    Check.test("60 Hz frames produce a 60 FPS rolling estimate") {
        var monitor = FrameRateMonitor()
        for frame in 0...120 {
            _ = monitor.recordFrame(at: Double(frame) / 60)
        }
        let snapshot = monitor.recordFrame(at: 121.0 / 60.0)!
        Check.equal(snapshot.rollingFPS, 60, accuracy: 0.01, "rolling FPS drifted")
        Check.equal(snapshot.averageFPS, 60, accuracy: 0.01, "average FPS drifted")
        Check.equal(snapshot.slowFrameCount, 0, "normal frames were counted slow")
    }

    Check.test("slow-frame threshold is strict and centralized") {
        var monitor = FrameRateMonitor()
        _ = monitor.recordFrame(at: 0)
        _ = monitor.recordFrame(at: FrameRateMonitor.Thresholds.slowFrameInterval)
        let snapshot = monitor.recordFrame(
            at: FrameRateMonitor.Thresholds.slowFrameInterval * 2 + 0.001
        )!
        Check.equal(snapshot.slowFrameCount, 1, "slow threshold classification changed")
    }

    Check.test("lifecycle boundary excludes a resume gap") {
        var monitor = FrameRateMonitor()
        _ = monitor.recordFrame(at: 0)
        _ = monitor.recordFrame(at: 1.0 / 60.0)
        monitor.resetBoundary()
        _ = monitor.recordFrame(at: 300)
        let snapshot = monitor.recordFrame(at: 300 + 1.0 / 60.0)!
        Check.equal(snapshot.slowFrameCount, 0, "resume gap counted as a slow frame")
    }

    Check.test("validation report round trips through JSON") {
        let report = PhysicalWatchValidationReport(
            device: "Watch",
            watchOS: "26.0",
            configuration: "left-crown-right",
            generatedAt: Date(timeIntervalSince1970: 123),
            tests: [
                .init(
                    id: "PERF-1",
                    startTime: Date(timeIntervalSince1970: 124),
                    durationSeconds: 300,
                    modeOrPlace: "Calm ocean",
                    metrics: ["averageFPS": "60.0"]
                )
            ]
        )
        let data = try! JSONEncoder().encode(report)
        let decoded = try! JSONDecoder().decode(PhysicalWatchValidationReport.self, from: data)
        Check.equal(decoded, report, "validation report did not round trip")
    }
}

Check.suite("iPhone Places selection foundation") {
    Check.test("catalog exposes all three reviewed Places and map coordinates") {
        Check.equal(WaterBodies.all.count, 3, "curated catalog count changed")
        Check.expect(
            Set(WaterBodies.all.map(\.id)) == [
                "san-francisco-bay", "monterey-bay", "lake-tahoe",
            ],
            "curated catalog identity changed"
        )
        for waterBody in WaterBodies.all {
            Check.expect(
                waterBody.latitude.isFinite && waterBody.longitude.isFinite,
                "\(waterBody.name) lost map-ready coordinates"
            )
        }
    }

    Check.test("selection persistence round trips canonical Place identity") {
        let envelope = WaterSelectionEnvelope(
            selection: .place(waterBodyID: WaterBodies.montereyBay.id),
            selectedAt: Date(timeIntervalSince1970: 42),
            origin: .iphone
        )
        let data = try! JSONEncoder().encode(envelope)
        let decoded = try! JSONDecoder().decode(WaterSelectionEnvelope.self, from: data)
        Check.equal(decoded, envelope, "selection did not persist losslessly")
        Check.expect(decoded.selection.isCatalogValid, "canonical Place became invalid")
    }

    Check.test("newest deliberate selection wins independent of device origin") {
        let newer = WaterSelectionEnvelope(
            selection: .place(waterBodyID: WaterBodies.lakeTahoe.id),
            selectedAt: Date(timeIntervalSince1970: 20),
            origin: .watch
        )
        let older = WaterSelectionEnvelope(
            selection: .place(waterBodyID: WaterBodies.sanFranciscoBay.id),
            selectedAt: Date(timeIntervalSince1970: 10),
            origin: .iphone
        )
        Check.equal(older.replacing(newer), newer, "stale message overwrote newer selection")
        Check.equal(newer.replacing(older), newer, "newer selection was rejected")
    }

    Check.test("multi-place loading remains keyed by canonical ID") {
        var store = PlaceObservationStore()
        store.beginLoading(WaterBodies.sanFranciscoBay.id)
        store.accept(.unavailable, for: WaterBodies.lakeTahoe.id)
        Check.equal(
            store.state(for: WaterBodies.sanFranciscoBay.id),
            .loading,
            "Lake Tahoe completion repainted San Francisco"
        )
        Check.equal(
            store.state(for: WaterBodies.lakeTahoe.id),
            .unavailable,
            "Lake Tahoe state was not isolated"
        )
        Check.equal(
            store.state(for: WaterBodies.montereyBay.id),
            .idle,
            "untouched Place did not remain idle"
        )
    }

    Check.test("fake transport records canonical selection deterministically") {
        let transport = RecordingWaterSelectionTransport()
        let envelope = WaterSelectionEnvelope(
            selection: .place(waterBodyID: WaterBodies.sanFranciscoBay.id),
            selectedAt: Date(timeIntervalSince1970: 50),
            origin: .iphone
        )
        let finished = DispatchSemaphore(value: 0)
        Task {
            try! await transport.send(envelope)
            finished.signal()
        }
        finished.wait()
        let sent = transport.sent
        Check.equal(sent, [envelope], "fake transport changed or dropped selection")
        Check.equal(sent.first?.selection.canonicalID, "place:san-francisco-bay")
    }
}

exit(Check.report())
