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
}

/// Shared task row used on Today and in the Tasks list.
/// Checkbox toggles completion; the rest of the row is the tap target for detail.
struct TaskRow: View {
    let task: TaskDTO
    var goalTitle: String? = nil
    var overdueLabel: String? = nil
    var onToggle: () -> Void
    var onTap: () -> Void

    private var isDone: Bool { task.status == .done }

    private var subtaskFraction: (done: Int, total: Int)? {
        let counted = task.subtasks.filter { $0.status != .cancelled }
        guard !counted.isEmpty else { return nil }
        return (counted.filter { $0.status == .done }.count, counted.count)
    }

    var body: some View {
        HStack(spacing: Space.md) {
            Button(action: onToggle) {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(isDone ? Color.success : Color.textTertiary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Space.sm) {
                    Text(task.title)
                        .font(.headlineJ)
                        .foregroundStyle(isDone ? Color.textTertiary : Color.textPrimary)
                        .strikethrough(isDone, color: .textTertiary)
                        .lineLimit(2)
                    if task.templateId != nil {
                        Image(systemName: "arrow.trianglehead.2.clockwise")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.textTertiary)
                    }
                }
                metaLine
            }

            Spacer(minLength: Space.sm)

            PriorityFlag(task.priority.flagLevel, showsLabel: false)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .frame(minHeight: RowHeight.standard)
    }

    @ViewBuilder
    private var metaLine: some View {
        HStack(spacing: Space.sm) {
            if let overdueLabel {
                Text(overdueLabel)
                    .font(.subheadJ)
                    .foregroundStyle(Color.danger)
            }
            if let dueTime = task.dueTime {
                Text(String(dueTime.prefix(5)))
                    .font(.subheadJ)
                    .foregroundStyle(Color.textSecondary)
            }
            if let fraction = subtaskFraction {
                Text("\(fraction.done)/\(fraction.total)")
                    .font(.monoJ)
                    .foregroundStyle(Color.textSecondary)
            }
            if let goalTitle {
                GoalChip(goalTitle)
            }
        }
    }
}
