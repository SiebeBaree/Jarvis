import Foundation

// AI long-term memory: one durable fact per row, user-editable.

public struct MemoryDTO: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let category: String // identity|work|health|appearance|preferences|relationships|context
    public let content: String
    public let source: String // chat | seeding | manual
    public let createdAt: String
    public let updatedAt: String
}

public struct MemoryListResponse: Codable, Sendable {
    public let memories: [MemoryDTO]
}

/// Display metadata for the fixed memory categories.
public enum MemoryCategory: String, CaseIterable, Sendable {
    case identity
    case work
    case health
    case appearance
    case preferences
    case relationships
    case context

    public var title: String {
        switch self {
        case .identity: "Identity"
        case .work: "Work"
        case .health: "Health"
        case .appearance: "Appearance"
        case .preferences: "Preferences"
        case .relationships: "Relationships"
        case .context: "Context"
        }
    }

    public var icon: String {
        switch self {
        case .identity: "person"
        case .work: "briefcase"
        case .health: "heart"
        case .appearance: "tshirt"
        case .preferences: "slider.horizontal.3"
        case .relationships: "person.2"
        case .context: "text.alignleft"
        }
    }
}
