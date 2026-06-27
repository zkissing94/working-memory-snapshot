import Foundation

enum WorkIncrementKind: String, Codable, CaseIterable, Sendable {
    case note
    case decision
    case blocker

    var displayName: String {
        switch self {
        case .note:
            "Note"
        case .decision:
            "Decision"
        case .blocker:
            "Blocker"
        }
    }
}

struct WorkIncrement: Identifiable, Equatable, Sendable {
    let id: UUID
    let blockID: UUID
    var occurredAt: Date
    var kind: WorkIncrementKind
    var title: String
    var detail: String?
    var createdAt: Date
    var updatedAt: Date
}
