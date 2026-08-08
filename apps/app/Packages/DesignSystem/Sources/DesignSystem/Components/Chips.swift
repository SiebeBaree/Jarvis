import SwiftUI

// MARK: - Priority flag (P1 danger / P2 warning / P3 quiet)

public enum TaskPriorityLevel: Int, CaseIterable, Sendable {
    case p1 = 1
    case p2 = 2
    case p3 = 3

    public var label: String { "P\(rawValue)" }

    public var color: Color {
        switch self {
        case .p1: .danger
        case .p2: .warning
        case .p3: .textTertiary
        }
    }
}

public struct PriorityFlag: View {
    private let priority: TaskPriorityLevel
    private let showsLabel: Bool

    public init(_ priority: TaskPriorityLevel, showsLabel: Bool = false) {
        self.priority = priority
        self.showsLabel = showsLabel
    }

    public var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "flag.fill")
                .font(.system(size: 10, weight: .semibold))
            if showsLabel {
                Text(priority.label).font(.microJ)
            }
        }
        .foregroundStyle(priority.color)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Priority \(priority.rawValue)"))
    }
}

// MARK: - Dot chip
//
// The general-purpose "this belongs to X" marker: a coloured dot plus a name.
// Used for task categories and life areas, so a row shows its grouping without
// a heavy filled pill fighting the row title for attention.

public struct DotChip: View {
    private let title: String
    private let color: Color
    private let filled: Bool

    public init(_ title: String, color: Color = .textTertiary, filled: Bool = false) {
        self.title = title
        self.color = color
        self.filled = filled
    }

    public var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(title)
                .font(.microJ)
                .foregroundStyle(filled ? color : Color.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, filled ? Space.sm : 0)
        .padding(.vertical, filled ? 3 : 0)
        .background {
            if filled {
                Capsule().fill(color.opacity(0.12))
            }
        }
    }
}

// MARK: - Tag chip — neutral metadata (a due time, a repeat rule)

public struct TagChip: View {
    private let title: String
    private let symbol: String?
    private let tint: Color

    public init(_ title: String, symbol: String? = nil, tint: Color = .textSecondary) {
        self.title = title
        self.symbol = symbol
        self.tint = tint
    }

    public var body: some View {
        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 9, weight: .semibold))
            }
            Text(title).font(.microJ).lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, Space.sm)
        .padding(.vertical, 3)
        .background(Color.bgSubtle, in: Capsule())
    }
}

/// Kept for call sites that still label something as a goal.
public struct GoalChip: View {
    private let title: String

    public init(_ title: String) {
        self.title = title
    }

    public var body: some View {
        DotChip(title, color: .accentPrimary, filled: true)
    }
}

#Preview("Chips") {
    VStack(alignment: .leading, spacing: Space.lg) {
        HStack(spacing: Space.md) {
            PriorityFlag(.p1, showsLabel: true)
            PriorityFlag(.p2, showsLabel: true)
            PriorityFlag(.p3)
        }
        HStack(spacing: Space.sm) {
            DotChip("Work", color: ItemColor.blue.color)
            DotChip("Health", color: ItemColor.green.color, filled: true)
            DotChip("Household", color: ItemColor.amber.color, filled: true)
        }
        HStack(spacing: Space.sm) {
            TagChip("18:30", symbol: "clock")
            TagChip("Every Mon", symbol: "repeat")
            TagChip("2/5", symbol: "checklist")
        }
        GoalChip("Ship Jarvis v1")
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding()
    .background(Color.bgCanvas)
}
