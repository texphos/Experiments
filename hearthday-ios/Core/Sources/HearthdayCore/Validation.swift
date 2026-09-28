import Foundation

/// Something the baker entered (or a saved file contained) that Hearthday can't plan with.
/// The UI constrains most inputs, but the core re-checks everything so bad data never reaches the model.
public enum InputProblem: Hashable, Sendable {
    case temperatureOutOfRange(Double)
    case riseOutOfRange(Double)
    case readyTimeInPast
    case readyTimeTooFar
    case formulaNameEmpty
    case flourOutOfRange(Double)
    case hydrationOutOfRange(Double)
    case starterOutOfRange(Double)
    case saltOutOfRange(Double)
    case busyLabelEmpty
    case busyNoDays
    case busyTimeInvalid
    case busyZeroLength

    public var code: String {
        switch self {
        case .temperatureOutOfRange: return "temperatureOutOfRange"
        case .riseOutOfRange: return "riseOutOfRange"
        case .readyTimeInPast: return "readyTimeInPast"
        case .readyTimeTooFar: return "readyTimeTooFar"
        case .formulaNameEmpty: return "formulaNameEmpty"
        case .flourOutOfRange: return "flourOutOfRange"
        case .hydrationOutOfRange: return "hydrationOutOfRange"
        case .starterOutOfRange: return "starterOutOfRange"
        case .saltOutOfRange: return "saltOutOfRange"
        case .busyLabelEmpty: return "busyLabelEmpty"
        case .busyNoDays: return "busyNoDays"
        case .busyTimeInvalid: return "busyTimeInvalid"
        case .busyZeroLength: return "busyZeroLength"
        }
    }

    public var message: String {
        switch self {
        case .temperatureOutOfRange:
            return "Enter a dough temperature between \(Int(Limits.tempC.lowerBound)) and \(Int(Limits.tempC.upperBound)) °C. Outside that range Hearthday’s timing model isn’t reliable enough to plan with."
        case .riseOutOfRange:
            return "Enter a rise between 0% and \(Int(Limits.risePercent.upperBound))%."
        case .readyTimeInPast:
            return "Pick a time in the future."
        case .readyTimeTooFar:
            return "Pick a time within the next \(Limits.maxDaysAhead) days."
        case .formulaNameEmpty:
            return "Give the formula a name."
        case .flourOutOfRange:
            return "Flour should be between \(Int(Limits.flourGrams.lowerBound)) and \(Int(Limits.flourGrams.upperBound)) g."
        case .hydrationOutOfRange:
            return "Water should be between \(Int(Limits.hydrationPercent.lowerBound))% and \(Int(Limits.hydrationPercent.upperBound))% of the flour."
        case .starterOutOfRange:
            return "Starter should be between \(Int(Limits.starterPercent.lowerBound))% and \(Int(Limits.starterPercent.upperBound))% of the flour."
        case .saltOutOfRange:
            return "Salt should be between 0% and \(Int(Limits.saltPercent.upperBound))% of the flour."
        case .busyLabelEmpty:
            return "Give this busy time a name."
        case .busyNoDays:
            return "Choose at least one day."
        case .busyTimeInvalid:
            return "Choose a valid start and end time."
        case .busyZeroLength:
            return "Start and end can’t be the same time."
        }
    }
}

public enum Limits {
    public static let tempC: ClosedRange<Double> = 14...32
    public static let risePercent: ClosedRange<Double> = 0...200
    public static let flourGrams: ClosedRange<Double> = 200...2000
    public static let hydrationPercent: ClosedRange<Double> = 55...95
    public static let starterPercent: ClosedRange<Double> = 5...40
    public static let saltPercent: ClosedRange<Double> = 0...3
    public static let maxDaysAhead = 7

    static func contains(_ range: ClosedRange<Double>, _ value: Double) -> Bool {
        value.isFinite && range.contains(value)
    }
}

extension BusyBlock {
    public var problems: [InputProblem] {
        var result: [InputProblem] = []
        if label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { result.append(.busyLabelEmpty) }
        if weekdays.isEmpty || !weekdays.isSubset(of: BusyBlock.everyDay) { result.append(.busyNoDays) }
        if !(0..<1440).contains(startMinute) || !(0..<1440).contains(endMinute) {
            result.append(.busyTimeInvalid)
        } else if startMinute == endMinute {
            result.append(.busyZeroLength)
        }
        return result
    }

    /// Blocks that fail validation are ignored by planning rather than crashing or blocking the whole week.
    public var isValid: Bool {
        (0..<1440).contains(startMinute) && (0..<1440).contains(endMinute) && startMinute != endMinute
            && !weekdays.isEmpty && weekdays.isSubset(of: BusyBlock.everyDay)
    }
}

extension Formula {
    public var problems: [InputProblem] {
        var result: [InputProblem] = []
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { result.append(.formulaNameEmpty) }
        if !Limits.contains(Limits.flourGrams, flourGrams) { result.append(.flourOutOfRange(flourGrams)) }
        if !Limits.contains(Limits.hydrationPercent, hydrationPercent) { result.append(.hydrationOutOfRange(hydrationPercent)) }
        if !Limits.contains(Limits.starterPercent, starterPercent) { result.append(.starterOutOfRange(starterPercent)) }
        if !Limits.contains(Limits.saltPercent, saltPercent) { result.append(.saltOutOfRange(saltPercent)) }
        return result
    }
}

extension PlanRequest {
    public var problems: [InputProblem] {
        var result: [InputProblem] = []
        if !Limits.contains(Limits.tempC, kitchenTempC) { result.append(.temperatureOutOfRange(kitchenTempC)) }
        if readyBy <= now {
            result.append(.readyTimeInPast)
        } else if readyBy.timeIntervalSince(now) > TimeInterval(Limits.maxDaysAhead) * 86_400 + 3600 {
            result.append(.readyTimeTooFar)
        }
        result += formula.problems
        return result
    }
}

public enum CheckInValidation {
    public static func problems(risePercent: Double, tempC: Double) -> [InputProblem] {
        var result: [InputProblem] = []
        if !Limits.contains(Limits.risePercent, risePercent) { result.append(.riseOutOfRange(risePercent)) }
        if !Limits.contains(Limits.tempC, tempC) { result.append(.temperatureOutOfRange(tempC)) }
        return result
    }
}
