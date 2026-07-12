import Foundation
import JarvisAPI

/// Display helpers for the Chat feature: tool-name labels, ISO date parsing,
/// and relative timestamps.
enum ChatDisplay {
    // MARK: - Tool names

    /// Type-badge label for an action card, e.g. "NEW TASK".
    static func badgeLabel(for toolName: String) -> String {
        switch normalize(toolName) {
        case "create_task": "New task"
        case "update_task", "edit_task": "Edit task"
        case "complete_task": "Complete task"
        case "delete_task": "Delete task"
        case "create_recurring_task", "create_recurrence": "New recurring task"
        case "create_habit": "New habit"
        case "update_habit", "edit_habit": "Edit habit"
        case "archive_habit": "Archive habit"
        case "log_habit": "Log habit"
        case "set_mood": "Set mood"
        case "create_goal": "New goal"
        case "update_goal", "edit_goal": "Edit goal"
        case "update_vision", "edit_vision": "Edit vision"
        default: humanize(toolName)
        }
    }

    /// Transient status line while a tool runs, e.g. "Creating task…".
    static func runningLabel(for toolName: String) -> String {
        switch normalize(toolName) {
        case "create_task": "Creating task…"
        case "update_task", "edit_task": "Updating task…"
        case "complete_task": "Completing task…"
        case "delete_task": "Deleting task…"
        case "create_habit": "Creating habit…"
        case "update_habit", "edit_habit": "Updating habit…"
        case "archive_habit": "Archiving habit…"
        case "log_habit": "Logging habit…"
        case "set_mood": "Setting mood…"
        case "create_goal": "Creating goal…"
        case "update_goal", "edit_goal": "Updating goal…"
        case "update_vision", "edit_vision": "Updating vision…"
        case let name where name.hasPrefix("get_") || name.hasPrefix("read_") || name.hasPrefix("list_"):
            "Reading your data…"
        default: humanize(toolName) + "…"
        }
    }

    /// System line for a completed tool step in a replayed conversation.
    static func doneLabel(for toolName: String) -> String {
        var label = runningLabel(for: toolName)
        if label.hasSuffix("…") { label = String(label.dropLast()) }
        return "Done: " + label.lowercased()
    }

    private static func normalize(_ toolName: String) -> String {
        toolName.lowercased()
    }

    /// "create_task" → "Create task".
    private static func humanize(_ toolName: String) -> String {
        let words = toolName
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }

    // MARK: - Dates

    private static let isoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func date(from isoString: String) -> Date? {
        isoFractional.date(from: isoString) ?? iso.date(from: isoString)
    }

    /// "2 hours ago", "yesterday" — for conversation history rows.
    static func relativeLabel(for isoString: String) -> String {
        guard let date = date(from: isoString) else { return "" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: .now)
    }

    /// "8:04 AM" — for the briefing "Generated <time>" caption.
    static func timeLabel(for isoString: String) -> String {
        guard let date = date(from: isoString) else { return "" }
        return date.formatted(date: .omitted, time: .shortened)
    }

    /// Label for a conversation kind, used as the title fallback.
    static func kindLabel(for conversation: ConversationLike) -> String {
        switch conversation.kind {
        case "weekly_review":
            conversation.weekNumber.map { "Week \($0) review" } ?? "Weekly review"
        case "block_review":
            "Block review"
        case "seeding":
            "Getting to know you"
        default:
            "Conversation"
        }
    }
}

/// Common surface of ConversationSummaryDTO / ConversationDTO the display
/// helpers need.
protocol ConversationLike {
    var kind: String { get }
    var title: String? { get }
    var weekNumber: Int? { get }
}

extension ConversationSummaryDTO: ConversationLike {}
extension ConversationDTO: ConversationLike {}
