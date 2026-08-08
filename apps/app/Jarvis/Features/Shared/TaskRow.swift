import DesignSystem
import JarvisAPI
import SwiftUI

extension TaskPriority {
    var flagLevel: TaskPriorityLevel {
        switch self {
        case .high: .p1
        case .medium: .p2
        case .low: .p3
        }
    }

    /// Colour of the row's empty check ring. High and medium earn a tint;
    /// low is the default gray, because if every priority is coloured then
    /// none of them are.
    var ringTint: Color? {
        switch self {
        case .high: .danger
        case .medium: .warning
        case .low: nil
        }
    }
}

/// Shared task row, used on Today and in the Tasks list.
///
/// Priority lives on the check ring rather than as a flag glyph at the far
/// right — the old layout put the one piece of colour in the row as far as
/// possible from the title it described, and left a ragged column of flags
/// down the edge of the screen.
struct TaskRow: View {
    let task: TaskDTO
    var goalTitle: String? = nil
    var category: TaskCategoryDTO? = nil
    var overdueLabel: String? = nil
    /// Hairline under the row, inset to the title. Without it the rows float
    /// in whitespace and a list of four reads as four unrelated objects.
    var showsDivider: Bool = true
    var onToggle: () -> Void
    var onTap: () -> Void

    private var isDone: Bool { task.status == .done }

    private var subtaskFraction: (done: Int, total: Int)? {
        let counted = task.subtasks.filter { $0.status != .cancelled }
        guard !counted.isEmpty else { return nil }
        return (counted.filter { $0.status == .done }.count, counted.count)
    }

    private var hasMeta: Bool {
        overdueLabel != nil || task.dueTime != nil || subtaskFraction != nil
            || category != nil || goalTitle != nil
    }

    var body: some View {
        HStack(spacing: Space.sm) {
            CheckCircle(
                isOn: isDone,
                ringTint: task.priority.ringTint,
                size: 24,
                action: onToggle
            )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(task.title)
                        .font(.headlineJ)
                        .foregroundStyle(isDone ? Color.textTertiary : Color.textPrimary)
                        .strikethrough(isDone, color: .textTertiary)
                        .lineLimit(2)
                    if task.templateId != nil {
                        Image(systemName: "arrow.trianglehead.2.clockwise")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.textTertiary)
                    }
                }
                if hasMeta {
                    metaLine
                }
            }

            Spacer(minLength: Space.xs)
        }
        .padding(.trailing, Space.sm)
        // A one-line row does not need a 56 pt slot; the check circle already
        // reserves a 44 pt target, so this is the floor, not the target.
        .frame(minHeight: 44)
        .overlay(alignment: .bottom) {
            if showsDivider {
                Rectangle()
                    .fill(Color.borderHairline)
                    .frame(height: 0.5)
                    .padding(.leading, 44)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        // The strikethrough and the fade are the completion animation; without
        // this they snap, which makes a tap feel like a page reload.
        .jarvisAnimation(Motion.standard, value: isDone)
    }

    @ViewBuilder
    private var metaLine: some View {
        HStack(spacing: Space.sm) {
            if let overdueLabel {
                Text(overdueLabel)
                    .font(.microJ)
                    .foregroundStyle(Color.danger)
            }
            if let dueTime = task.dueTime {
                HStack(spacing: 3) {
                    Image(systemName: "clock")
                        .font(.system(size: 9, weight: .semibold))
                    Text(String(dueTime.prefix(5)))
                        .font(.microJ)
                }
                .foregroundStyle(Color.textSecondary)
            }
            if let fraction = subtaskFraction {
                Text("\(fraction.done)/\(fraction.total)")
                    .font(.microJ)
                    .monospacedDigit()
                    .foregroundStyle(Color.textSecondary)
            }
            if let category {
                DotChip(category.name, color: Color(hexString: category.colorHex) ?? .textTertiary)
            }
            if let goalTitle {
                DotChip(goalTitle, color: .accentPrimary)
            }
        }
    }
}
