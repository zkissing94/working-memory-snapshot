import Foundation

struct DailyProjectThread: Codable, Equatable, Sendable, Identifiable {
    var projectID: UUID
    var projectName: String
    var summary: String

    var id: UUID { projectID }

    enum CodingKeys: String, CodingKey {
        case projectID = "project_id"
        case projectName = "project_name"
        case summary
    }
}

struct DailyCarryForward: Codable, Equatable, Sendable, Identifiable {
    var projectID: UUID
    var projectName: String
    var text: String

    var id: String { "\(projectID.uuidString):\(text)" }

    enum CodingKeys: String, CodingKey {
        case projectID = "project_id"
        case projectName = "project_name"
        case text
    }
}

struct DailyRollup: Identifiable, Equatable, Sendable {
    let id: UUID
    var rollupDate: String
    var timezoneIdentifier: String
    var daySummary: String
    var projectThreads: [DailyProjectThread]
    var carryForwards: [DailyCarryForward]
    var closureNote: String
    var generatorModel: String?
    var promptVersion: String
    var sourceFingerprint: String
    var generatedAt: Date
    var updatedAt: Date
}

struct DailyRollupSource: Identifiable, Equatable, Sendable {
    var rollupID: UUID
    var sessionID: UUID
    var projectID: UUID
    var projectName: String
    var mission: String
    var endedAt: Date
    var isAvailable: Bool

    var id: UUID { sessionID }
}

struct DailyRollupDraft: Equatable, Sendable {
    var rollupDate: String
    var timezoneIdentifier: String
    var daySummary: String
    var projectThreads: [DailyProjectThread]
    var carryForwards: [DailyCarryForward]
    var closureNote: String
    var generatorModel: String?
    var promptVersion: String
    var sourceFingerprint: String
    var sources: [DailyRollupSource]
}

struct DailyRollupEligibility: Equatable, Sendable {
    var rollupDate: String
    var timezoneIdentifier: String
    var dayStart: Date
    var dayEnd: Date
    var projects: [Project]
    var sessions: [DailyRollupSessionEvidence]
    var sourceFingerprint: String
    var hasActiveSession: Bool

    var completedSessionCount: Int { sessions.count }
    var participatingProjectCount: Int { projects.count }
    var canGenerate: Bool { !sessions.isEmpty && !hasActiveSession }
}

struct DailyRollupSessionEvidence: Equatable, Sendable {
    var project: Project
    var session: WorkSession
    var snapshot: Snapshot?
    var fallbackCapture: String
}

enum DailyRollupDay {
    static func bounds(
        containing date: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> (start: Date, end: Date) {
        let start = calendar.startOfDay(for: date)
        return (start, calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400))
    }

    static func key(
        for date: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
