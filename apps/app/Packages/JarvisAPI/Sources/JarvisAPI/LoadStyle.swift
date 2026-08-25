import Foundation

/// How an exercise's weight goes up, which is a property of the equipment and
/// not of the lifter.
///
/// A single 2.5 kg step is wrong almost everywhere: dumbbells go up 1 kg to
/// 10 and 2 kg after that, and a cable stack is a column of 5 lb plates whose
/// printed kilogram labels are 2.3, 4.5, 6.8, 9. Stepping a cable machine by
/// 2.5 produces numbers the machine cannot make.
///
/// Every ladder is a whole number of steps from zero, so the maths is one
/// index mapping in each direction rather than a table of allowed weights.
public enum LoadStyle: String, Codable, Sendable, CaseIterable {
    /// Barbells, plate-loaded machines, a dip belt. 2.5 kg.
    case plates
    /// 1 kg apart up to 10, then 2 kg apart.
    case dumbbell
    /// A pin stack of 5 lb plates, as printed on the machine.
    case cable
    /// A pin stack in whole kilograms.
    case machine
    /// Anything else. Half kilograms, so nothing is unreachable.
    case free

    public var label: String {
        switch self {
        case .plates: "Plates"
        case .dumbbell: "Dumbbells"
        case .cable: "Cable stack"
        case .machine: "Machine"
        case .free: "Free"
        }
    }

    /// The step size, said the way the gym says it.
    public var detail: String {
        switch self {
        case .plates: "2.5 kg"
        case .dumbbell: "1 kg, then 2"
        case .cable: "5 lb plates"
        case .machine: "5 kg"
        case .free: "0.5 kg"
        }
    }

    /// Short enough for the chip under the number in the logger.
    public var shortLabel: String {
        switch self {
        case .plates: "Plates"
        case .dumbbell: "DB"
        case .cable: "Cable"
        case .machine: "Machine"
        case .free: "Free"
        }
    }

    // MARK: - The ladder

    /// The weight `steps` rungs from zero.
    public func weight(atStep step: Int) -> Double {
        let step = max(0, step)
        let raw: Double = switch self {
        case .plates: Double(step) * 2.5
        case .machine: Double(step) * 5
        case .free: Double(step) * 0.5
        case .cable: Double(step) * 2.25 // 5 lb
        case .dumbbell: step <= 10 ? Double(step) : 10 + Double(step - 10) * 2
        }
        return (raw * 10).rounded() / 10
    }

    /// Where a weight sits on the ladder, fractionally. Legacy values that
    /// were typed before the ladder existed land between two rungs, which is
    /// exactly what lets stepping snap them onto it.
    private func step(forWeight weight: Double) -> Double {
        let weight = max(0, weight)
        return switch self {
        case .plates: weight / 2.5
        case .machine: weight / 5
        case .free: weight / 0.5
        case .cable: weight / 2.25
        case .dumbbell: weight <= 10 ? weight : 10 + (weight - 10) / 2
        }
    }

    /// A cable rung is stored as its printed label (33.8, not 33.75), so a
    /// value sitting on the ladder can be up to 0.05 kg off its true position.
    /// The tolerance covers that without ever reaching half a step.
    private static let tolerance = 0.03

    /// The next rung up from `weight`, or the next one down for `direction`
    /// of -1. Never returns the value it was given, so holding the button
    /// always moves.
    public func stepped(_ weight: Double, direction: Int) -> Double {
        let position = step(forWeight: weight)
        if direction >= 0 {
            return self.weight(atStep: Int((position + Self.tolerance).rounded(.down)) + 1)
        }
        return self.weight(atStep: Int((position - Self.tolerance).rounded(.up)) - 1)
    }

    // MARK: - Guessing

    /// The ladder implied by a movement's name. Mirrors the SQL backfill in
    /// `drizzle/0009_glorious_squadron_sinister.sql`, so an exercise created
    /// in the app and one created before the column existed agree.
    ///
    /// It is a guess, and the logger lets you change it in one tap.
    public static func guessed(fromName name: String) -> LoadStyle {
        let lowered = name.lowercased()
        func mentions(_ words: [String]) -> Bool { words.contains { lowered.contains($0) } }

        if mentions(["cable", "pulldown", "pushdown", "pulley", "crossover", "rope"]) { return .cable }
        if mentions(["dumbbell", "dumbell", "db "]) { return .dumbbell }
        if mentions([
            "machine", "leg press", "leg curl", "leg extension", "calf", "calve",
            "seated row", "back row", "pec deck", "hack squat", "smith",
        ]) { return .machine }
        return .plates
    }
}
