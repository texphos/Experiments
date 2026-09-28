import Foundation

/// Learns how fast *this* baker's dough runs compared with the textbook model.
///
/// Only bakes where the baker says the dough was "just right" at shaping are used, so the sample measures
/// time-to-ready rather than when the baker happened to be free.
public struct Calibration: Codable, Hashable, Sendable {
    public struct Sample: Codable, Hashable, Sendable {
        public var date: Date
        public var tempC: Double
        public var inoculationPercent: Double
        /// Bulk hours the uncalibrated model predicted for these conditions.
        public var modelHours: Double
        public var actualHours: Double

        public init(date: Date, tempC: Double, inoculationPercent: Double, modelHours: Double, actualHours: Double) {
            self.date = date
            self.tempC = tempC
            self.inoculationPercent = inoculationPercent
            self.modelHours = modelHours
            self.actualHours = actualHours
        }

        /// > 1 means the dough ran faster than the model.
        public var observedSpeed: Double { modelHours / actualHours }
    }

    public static let defaultUncertainty = 0.2
    public static let minimumUncertainty = 0.1
    public static let maximumUncertainty = 0.3
    /// Pseudo-observations at speed 1.0, so one odd bake cannot swing the model.
    public static let priorWeight = 2.0
    public static let maxSamples = 12
    public static let samplesNeededToNarrow = 3

    public private(set) var samples: [Sample]

    public init(samples: [Sample] = []) {
        self.samples = Array(samples.suffix(Calibration.maxSamples))
    }

    public mutating func record(_ sample: Sample) {
        guard sample.actualHours > 0.5, sample.modelHours > 0.5 else { return }
        samples.append(sample)
        if samples.count > Calibration.maxSamples {
            samples.removeFirst(samples.count - Calibration.maxSamples)
        }
    }

    public var speedFactor: Double {
        guard !samples.isEmpty else { return 1 }
        let logSum = samples.reduce(0) { $0 + log(clampSpeed($1.observedSpeed)) }
        return exp(logSum / (Double(samples.count) + Calibration.priorWeight))
    }

    /// Window half-width. Stays at the default until there is enough evidence, then follows the observed spread;
    /// it can widen as well as narrow.
    public var uncertainty: Double {
        guard samples.count >= Calibration.samplesNeededToNarrow else { return Calibration.defaultUncertainty }
        let k = log(speedFactor)
        let residuals = samples.map { log(clampSpeed($0.observedSpeed)) - k }
        let meanSquare = residuals.reduce(0) { $0 + $1 * $1 } / Double(residuals.count)
        let spread = sqrt(meanSquare)
        return min(max(1.3 * spread + 0.05, Calibration.minimumUncertainty), Calibration.maximumUncertainty)
    }

    public var isPersonalized: Bool { samples.count >= Calibration.samplesNeededToNarrow }

    private func clampSpeed(_ s: Double) -> Double { min(max(s, 0.4), 2.5) }
}
