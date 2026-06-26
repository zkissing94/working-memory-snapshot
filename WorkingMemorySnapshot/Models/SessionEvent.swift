import Foundation

enum EventSource: String, Codable, Sendable {
    case system
    case user
    case file
    case git
    case activeApp = "active_app"
}

enum SessionEventKind {
    static let sessionStarted = "session_started"
    static let sessionEnded = "session_ended"
    static let sessionCancelled = "session_cancelled"
    static let brainDump = "brain_dump"
    static let fileChanged = "file_changed"
    static let gitInitialState = "git_initial_state"
    static let gitFinalSummary = "git_final_summary"
    static let appActivated = "app_activated"
    static let observationIssue = "observation_issue"
}

struct SessionEvent: Identifiable, Equatable, Sendable {
    let id: UUID
    let sessionID: UUID
    let occurredAt: Date
    let source: EventSource
    let kind: String
    let title: String
    let body: String?
    let payloadJSON: String?
    let createdAt: Date

    init(
        id: UUID = UUID(),
        sessionID: UUID,
        occurredAt: Date = Date(),
        source: EventSource,
        kind: String,
        title: String,
        body: String? = nil,
        payloadJSON: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sessionID = sessionID
        self.occurredAt = occurredAt
        self.source = source
        self.kind = kind
        self.title = title
        self.body = body
        self.payloadJSON = payloadJSON
        self.createdAt = createdAt
    }
}
