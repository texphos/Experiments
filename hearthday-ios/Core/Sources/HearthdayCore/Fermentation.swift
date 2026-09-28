import Foundation

/// A bread formula in baker's percentages (relative to flour weight; starter assumed 100% hydration and not
/// counted toward flour or hydration, the most common home-baker convention).
public struct Formula: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var flourGrams: Double
    public var hydrationPercent: Double
    public var starterPercent: Double
    public var saltPercent: Double

    public init(
        id: UUID = UUID(),
        name: String,
        flourGrams: Double,
        hydrationPercent: Double,
        starterPercent: Double,
        saltPercent: Double
    ) {
        self.id = id
        self.name = name
        self.flourGrams = flourGrams
        self.hydrationPercent = hydrationPercent
        self.starterPercent = starterPercent
        self.saltPercent = saltPercent
    }

    public static let countryLoaf = Formula(
        name: "Everyday country loaf",
        flourGrams: 500,
        hydrationPercent: 72,
        starterPercent: 20,
        saltPercent: 2
    )

    public struct Amounts: Hashable, Sendable {
        public var flour: Double
        public var water: Double
        public var starter: Double
        public var salt: Double
        public var total: Double { flour + water + starter + salt }
    }

    public func amounts(starterPercent override: Double? = nil) -> Amounts {
        let starter = override ?? starterPercent
        return Amounts(
            flour: flourGrams,
            water: flourGrams * hydrationPercent / 100,
            starter: flourGrams * starter / 100,
            salt: flourGrams * saltPercent / 100
        )
    }
}

public enum FeedRatio: String, Codable, CaseIterable, Sendable {
    case oneOneOne = "1:1:1"
    case oneTwoTwo = "1:2:2"
    case oneFiveFive = "1:5:5"
    case oneTenTen = "1:10:10"

    /// Hours from feeding to peak at 24 °C. Community rule of thumb, not measured by us; the in-app copy says so.
    var referencePeakHours: Double {
        switch self {
        case .oneOneOne: return 4.5
        case .oneTwoTwo: return 6.5
        case .oneFiveFive: return 9
        case .oneTenTen: return 12
        }
    }

    var index: Int { FeedRatio.allCases.firstIndex(of: self) ?? 0 }
}

/// Deterministic, deliberately simple fermentation-time model.
///
/// Rate scales with temperature by `q10` per 10 °C and with inoculation by `(inoc / ref) ^ exponent`.
/// Defaults sit between published home-baker tables that disagree with each other by up to ~2x
/// (see docs/research.md), which is why every estimate is shown as a window and the live check-in exists.
public struct FermentationModel: Codable, Hashable, Sendable {
    public var referenceTempC: Double = 21
    public var referenceBulkHours: Double = 7
    public var referenceInoculationPercent: Double = 20
    public var q10: Double = 2.6
    public var inoculationExponent: Double = 0.5
    public var referenceRoomProofHours: Double = 2
    public var starterReferenceTempC: Double = 24
    /// Personal speed multiplier learned from logged bakes (1 = textbook).
    public var speedFactor: Double = 1
    /// Half-width of the "likely ready" window as a fraction of the estimate.
    public var uncertainty: Double = 0.2

    public init() {}

    public func temperatureRate(_ tempC: Double, reference: Double) -> Double {
        pow(q10, (tempC - reference) / 10)
    }

    public func bulkHours(tempC: Double, inoculationPercent: Double) -> Double {
        let inoc = max(inoculationPercent, 2)
        let rate = temperatureRate(tempC, reference: referenceTempC)
            * pow(inoc / referenceInoculationPercent, inoculationExponent)
            * speedFactor
        return referenceBulkHours / rate
    }

    public func roomProofHours(tempC: Double) -> Double {
        referenceRoomProofHours / (temperatureRate(tempC, reference: referenceTempC) * speedFactor)
    }

    public func starterPeakHours(ratio: FeedRatio, tempC: Double) -> Double {
        ratio.referencePeakHours / temperatureRate(tempC, reference: starterReferenceTempC)
    }

    /// Target volume rise at the end of bulk for a given average dough temperature, interpolated from
    /// The Sourdough Journey's dough-temping guide (warmer dough → stop at a lower rise).
    public static func targetRisePercent(tempC: Double) -> Double {
        let table: [(Double, Double)] = [(18, 100), (20, 85), (21, 75), (22, 65), (24, 50), (27, 30)]
        if tempC <= table[0].0 { return table[0].1 }
        if tempC >= table[table.count - 1].0 { return table[table.count - 1].1 }
        for i in 0..<(table.count - 1) {
            let (t0, r0) = table[i]
            let (t1, r1) = table[i + 1]
            if tempC >= t0 && tempC <= t1 {
                return r0 + (r1 - r0) * (tempC - t0) / (t1 - t0)
            }
        }
        return 75
    }

    public func applying(_ calibration: Calibration) -> FermentationModel {
        var copy = self
        copy.speedFactor = calibration.speedFactor
        copy.uncertainty = calibration.uncertainty
        return copy
    }
}
