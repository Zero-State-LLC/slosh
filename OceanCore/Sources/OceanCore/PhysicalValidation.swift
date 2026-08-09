import Foundation

/// Pure rolling frame/update metrics shared by device diagnostics and command-line
/// checks. The renderer supplies timestamps; this type never owns a timer.
public struct FrameRateMonitor: Sendable {
    public enum Thresholds {
        public static let requestedFramesPerSecond = 60.0
        public static let slowFrameTolerance = 1.5
        public static let rollingWindowDuration = 2.0
        public static let reportingInterval = 5.0
        public static var targetInterval: TimeInterval {
            1.0 / requestedFramesPerSecond
        }
        public static var slowFrameInterval: TimeInterval {
            targetInterval * slowFrameTolerance
        }
    }

    public struct Snapshot: Sendable, Equatable {
        public let duration: TimeInterval
        public let instantaneousFPS: Double
        public let rollingFPS: Double
        public let averageFPS: Double
        public let minimumRollingFPS: Double
        public let slowFrameCount: Int
        public let observedFrameCount: Int
    }

    private var lastTime: TimeInterval?
    private var rollingFrames: [(time: TimeInterval, interval: TimeInterval)] = []
    private var totalInterval: TimeInterval = 0
    private var observedFrameCount = 0
    private var slowFrameCount = 0
    private var minimumRollingFPS = Double.infinity

    public init() {}

    /// Lifecycle boundaries call `resetBoundary` so a background/resume gap is not
    /// counted as a slow frame or allowed to distort the measured platform ceiling.
    public mutating func resetBoundary(at time: TimeInterval? = nil) {
        lastTime = time
        rollingFrames.removeAll(keepingCapacity: true)
    }

    @discardableResult
    public mutating func recordFrame(at time: TimeInterval) -> Snapshot? {
        guard time.isFinite else { return nil }
        guard let previous = lastTime else {
            lastTime = time
            return nil
        }
        lastTime = time

        let interval = time - previous
        guard interval > 0, interval.isFinite else { return nil }
        observedFrameCount += 1
        totalInterval += interval
        if interval > Thresholds.slowFrameInterval { slowFrameCount += 1 }

        rollingFrames.append((time, interval))
        let cutoff = time - Thresholds.rollingWindowDuration
        rollingFrames.removeAll { $0.time < cutoff }
        let rollingDuration = rollingFrames.reduce(0) { $0 + $1.interval }
        let rollingFPS = rollingDuration > 0
            ? Double(rollingFrames.count) / rollingDuration
            : 0
        if rollingFrames.count >= 2 {
            minimumRollingFPS = min(minimumRollingFPS, rollingFPS)
        }

        // `totalInterval` excludes lifecycle boundaries, so duration and average
        // FPS describe active rendering rather than wall-clock time in background.
        let duration = totalInterval
        return Snapshot(
            duration: duration,
            instantaneousFPS: 1 / interval,
            rollingFPS: rollingFPS,
            averageFPS: totalInterval > 0 ? Double(observedFrameCount) / totalInterval : 0,
            minimumRollingFPS: minimumRollingFPS.isFinite ? minimumRollingFPS : rollingFPS,
            slowFrameCount: slowFrameCount,
            observedFrameCount: observedFrameCount
        )
    }
}

/// Provider-independent, file-sized result format for one physical validation run.
public struct PhysicalWatchValidationReport: Codable, Sendable, Equatable {
    public struct TestResult: Codable, Sendable, Equatable {
        public var id: String
        public var startTime: Date
        public var durationSeconds: Double
        public var modeOrPlace: String
        public var observations: [String]
        public var metrics: [String: String]
        public var result: String
        public var notes: String

        public init(
            id: String,
            startTime: Date,
            durationSeconds: Double,
            modeOrPlace: String,
            observations: [String] = [],
            metrics: [String: String] = [:],
            result: String = "NOT_RUN",
            notes: String = ""
        ) {
            self.id = id
            self.startTime = startTime
            self.durationSeconds = durationSeconds
            self.modeOrPlace = modeOrPlace
            self.observations = observations
            self.metrics = metrics
            self.result = result
            self.notes = notes
        }
    }

    public var device: String
    public var watchOS: String
    public var configuration: String
    public var generatedAt: Date
    public var tests: [TestResult]

    public init(
        device: String,
        watchOS: String,
        configuration: String,
        generatedAt: Date = Date(),
        tests: [TestResult] = []
    ) {
        self.device = device
        self.watchOS = watchOS
        self.configuration = configuration
        self.generatedAt = generatedAt
        self.tests = tests
    }
}
