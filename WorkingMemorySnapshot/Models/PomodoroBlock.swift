import Foundation

enum PomodoroBlockStatus: String, Codable, Sendable {
    case active
    case paused
    case completed
    case interrupted
}

struct PomodoroBlock: Identifiable, Equatable, Sendable {
    static let defaultPlannedDurationSeconds = 20 * 60

    let id: UUID
    let sessionID: UUID
    var blockIndex: Int
    var plannedDurationSeconds: Int
    var intention: String?
    var summary: String?
    var status: PomodoroBlockStatus
    var startedAt: Date
    var pausedAt: Date?
    var accumulatedPauseSeconds: Int
    var endedAt: Date?
    var createdAt: Date
    var updatedAt: Date

    var isOpen: Bool {
        status == .active || status == .paused
    }

    func elapsedSeconds(at date: Date = Date()) -> Int {
        let end = endedAt ?? pausedAt ?? date
        let rawElapsed = max(0, Int(end.timeIntervalSince(startedAt)))
        return max(0, rawElapsed - accumulatedPauseSeconds)
    }

    func remainingSeconds(at date: Date = Date()) -> Int {
        max(0, plannedDurationSeconds - elapsedSeconds(at: date))
    }
}
