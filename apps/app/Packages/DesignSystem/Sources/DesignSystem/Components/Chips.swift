import SwiftUI

// MARK: - Priority flag (P1 danger / P2 warning / P3 gray)

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

    public init(_ priority: TaskPriorityLevel, showsLabel: Bool = true) {
        self.priority = priority
        self.showsLabel = showsLabel
    }

    public var body: some View {
        HStack(spacing: Space.xs) {
            Image(systemName: "flag.fill")
                .font(.system(size: 9))
            if showsLabel {
                Text(priority.label)
                    .font(.captionJ)
            }
        }
        .foregroundStyle(priority.color)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Priority \(priority.rawValue)"))
    }
}

// MARK: - Goal chip (accent-subtle background)

public struct GoalChip: View {
    private let title: String

    public init(_ title: String) {
        self.title = title
    }

    public var body: some View {
        Text(title)
            .font(.captionJ)
            .foregroundStyle(Color.accentPrimary)
            .lineLimit(1)
            .padding(.horizontal, Space.sm)
            .padding(.vertical, 2)
            .background(Color.accentSubtle, in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
    }
}

// MARK: - Generic tag chip

public struct TagChip: View {
    private let title: String

    public init(_ title: String) {
        self.title = title
    }

    public var body: some View {
        Text(title)
            .font(.captionJ)
            .foregroundStyle(Color.textSecondary)
            .lineLimit(1)
            .padding(.horizontal, Space.sm)
            .padding(.vertical, 2)
            .background(Color.bgSubtle, in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                    .strokeBorder(Color.borderHairline, lineWidth: 0.5)
            )
    }
}

#Preview("Chips") {
    VStack(alignment: .leading, spacing: Space.lg) {
        HStack(spacing: Space.md) {
            PriorityFlag(.p1)
            PriorityFlag(.p2)
            PriorityFlag(.p3)
            PriorityFlag(.p1, showsLabel: false)
        }
        HStack(spacing: Space.sm) {
            GoalChip("Ship Jarvis v1")
            GoalChip("Run a half marathon")
        }
        HStack(spacing: Space.sm) {
            TagChip("Health")
            TagChip("Deep work")
        }
    }
    .padding()
    .background(Color.bgCanvas)
}
