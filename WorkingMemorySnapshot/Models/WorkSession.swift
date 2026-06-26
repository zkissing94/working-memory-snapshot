import Foundation

enum SessionStatus: String, Codable, Sendable {
    case active
    case completed
    case cancelled
}

struct WorkSession: Identifiable, Equatable, Sendable {
    let id: UUID
    let projectID: UUID
    var mission: String
    var brainDump: String?
    var startedAt: Date
    var endedAt: Date?
    var status: SessionStatus
    var createdAt: Date
    var updatedAt: Date
}
