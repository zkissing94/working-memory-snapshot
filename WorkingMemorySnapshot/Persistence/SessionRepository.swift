import Foundation
import SQLite3

struct SessionRepository {
    let database: Database

    func createActiveSession(projectID: UUID, mission: String) async throws -> WorkSession {
        let trimmedMission = mission.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMission.isEmpty else {
            throw SessionRepositoryError.emptyMission
        }

        let now = try DateCoding.now()
        let session = WorkSession(
            id: UUID(),
            projectID: projectID,
            mission: trimmedMission,
            brainDump: nil,
            startedAt: now,
            endedAt: nil,
            status: .active,
            createdAt: now,
            updatedAt: now
        )

        do {
            try await database.execute("""
            INSERT INTO sessions(
                id,
                project_id,
                mission,
                brain_dump,
                started_at,
                ended_at,
                status,
                created_at,
                updated_at
            )
            VALUES(?, ?, ?, NULL, ?, NULL, ?, ?, ?)
            """) { statement in
                try SQLiteValue.bind(session.id.uuidString, to: statement, at: 1)
                try SQLiteValue.bind(session.projectID.uuidString, to: statement, at: 2)
                try SQLiteValue.bind(session.mission, to: statement, at: 3)
                try SQLiteValue.bind(DateCoding.string(from: session.startedAt), to: statement, at: 4)
                try SQLiteValue.bind(session.status.rawValue, to: statement, at: 5)
                try SQLiteValue.bind(DateCoding.string(from: session.createdAt), to: statement, at: 6)
                try SQLiteValue.bind(DateCoding.string(from: session.updatedAt), to: statement, at: 7)
            }
        } catch let error as SQLiteError where error.code == SQLITE_CONSTRAINT {
            if try await activeSession() != nil {
                throw SessionRepositoryError.activeSessionAlreadyExists
            }
            throw error
        }

        return session
    }

    func activeSession() async throws -> WorkSession? {
        try await database.query("""
        SELECT id, project_id, mission, brain_dump, started_at, ended_at, status, created_at, updated_at
        FROM sessions
        WHERE status = ?
        ORDER BY started_at DESC
        LIMIT 1
        """, bind: { statement in
            try SQLiteValue.bind(SessionStatus.active.rawValue, to: statement, at: 1)
        }, map: { statement in
            try mapSession(from: statement)
        })
        .first
    }

    func session(for id: UUID) async throws -> WorkSession? {
        try await database.query("""
        SELECT id, project_id, mission, brain_dump, started_at, ended_at, status, created_at, updated_at
        FROM sessions
        WHERE id = ?
        LIMIT 1
        """, bind: { statement in
            try SQLiteValue.bind(id.uuidString, to: statement, at: 1)
        }, map: { statement in
            try mapSession(from: statement)
        })
        .first
    }

    func listSessions(for projectID: UUID) async throws -> [WorkSession] {
        try await database.query("""
        SELECT id, project_id, mission, brain_dump, started_at, ended_at, status, created_at, updated_at
        FROM sessions
        WHERE project_id = ?
        ORDER BY started_at DESC
        """, bind: { statement in
            try SQLiteValue.bind(projectID.uuidString, to: statement, at: 1)
        }, map: { statement in
            try mapSession(from: statement)
        })
    }

    func latestCompletedSession(for projectID: UUID) async throws -> WorkSession? {
        try await database.query("""
        SELECT id, project_id, mission, brain_dump, started_at, ended_at, status, created_at, updated_at
        FROM sessions
        WHERE project_id = ? AND status = ?
        ORDER BY ended_at DESC, started_at DESC
        LIMIT 1
        """, bind: { statement in
            try SQLiteValue.bind(projectID.uuidString, to: statement, at: 1)
            try SQLiteValue.bind(SessionStatus.completed.rawValue, to: statement, at: 2)
        }, map: { statement in
            try mapSession(from: statement)
        })
        .first
    }

    func completedSessionCount(for projectID: UUID) async throws -> Int {
        try await database.query("""
        SELECT COUNT(*)
        FROM sessions
        WHERE project_id = ? AND status = ?
        """, bind: { statement in
            try SQLiteValue.bind(projectID.uuidString, to: statement, at: 1)
            try SQLiteValue.bind(SessionStatus.completed.rawValue, to: statement, at: 2)
        }, map: { statement in
            Int(sqlite3_column_int64(statement, 0))
        })
        .first ?? 0
    }

    func completeSession(id: UUID, brainDump: String) async throws -> WorkSession {
        let now = try DateCoding.now()
        return try await database.withTransaction { database in
            let changes = try database.executeReturningChanges("""
            UPDATE sessions
            SET brain_dump = ?,
                ended_at = ?,
                status = ?,
                updated_at = ?
            WHERE id = ? AND status = ?
            """) { statement in
                try SQLiteValue.bind(brainDump, to: statement, at: 1)
                try SQLiteValue.bind(DateCoding.string(from: now), to: statement, at: 2)
                try SQLiteValue.bind(SessionStatus.completed.rawValue, to: statement, at: 3)
                try SQLiteValue.bind(DateCoding.string(from: now), to: statement, at: 4)
                try SQLiteValue.bind(id.uuidString, to: statement, at: 5)
                try SQLiteValue.bind(SessionStatus.active.rawValue, to: statement, at: 6)
            }

            guard changes == 1, let session = try session(for: id, using: database) else {
                throw SessionRepositoryError.sessionNotActive
            }

            return session
        }
    }

    func cancelSession(id: UUID) async throws -> WorkSession {
        let now = try DateCoding.now()
        return try await database.withTransaction { database in
            let changes = try database.executeReturningChanges("""
            UPDATE sessions
            SET ended_at = ?,
                status = ?,
                updated_at = ?
            WHERE id = ? AND status = ?
            """) { statement in
                try SQLiteValue.bind(DateCoding.string(from: now), to: statement, at: 1)
                try SQLiteValue.bind(SessionStatus.cancelled.rawValue, to: statement, at: 2)
                try SQLiteValue.bind(DateCoding.string(from: now), to: statement, at: 3)
                try SQLiteValue.bind(id.uuidString, to: statement, at: 4)
                try SQLiteValue.bind(SessionStatus.active.rawValue, to: statement, at: 5)
            }

            guard changes == 1, let session = try session(for: id, using: database) else {
                throw SessionRepositoryError.sessionNotActive
            }

            return session
        }
    }

    private func session(for id: UUID, using database: isolated Database) throws -> WorkSession? {
        try database.query("""
        SELECT id, project_id, mission, brain_dump, started_at, ended_at, status, created_at, updated_at
        FROM sessions
        WHERE id = ?
        LIMIT 1
        """, bind: { statement in
            try SQLiteValue.bind(id.uuidString, to: statement, at: 1)
        }, map: { statement in
            try mapSession(from: statement)
        })
        .first
    }

    private func mapSession(from statement: OpaquePointer) throws -> WorkSession {
        let idString = SQLiteValue.text(statement, at: 0)
        let projectIDString = SQLiteValue.text(statement, at: 1)
        let statusString = SQLiteValue.text(statement, at: 6)

        guard let id = UUID(uuidString: idString) else {
            throw SessionRepositoryError.invalidStoredSession("Invalid session id: \(idString)")
        }
        guard let projectID = UUID(uuidString: projectIDString) else {
            throw SessionRepositoryError.invalidStoredSession("Invalid session project id: \(projectIDString)")
        }
        guard let status = SessionStatus(rawValue: statusString) else {
            throw SessionRepositoryError.invalidStoredSession("Invalid session status: \(statusString)")
        }

        return WorkSession(
            id: id,
            projectID: projectID,
            mission: SQLiteValue.text(statement, at: 2),
            brainDump: SQLiteValue.optionalText(statement, at: 3),
            startedAt: try DateCoding.date(from: SQLiteValue.text(statement, at: 4)),
            endedAt: try SQLiteValue.optionalText(statement, at: 5).map(DateCoding.date(from:)),
            status: status,
            createdAt: try DateCoding.date(from: SQLiteValue.text(statement, at: 7)),
            updatedAt: try DateCoding.date(from: SQLiteValue.text(statement, at: 8))
        )
    }
}

enum SessionRepositoryError: Error, Equatable, LocalizedError {
    case emptyMission
    case activeSessionAlreadyExists
    case sessionNotActive
    case invalidStoredSession(String)

    var errorDescription: String? {
        switch self {
        case .emptyMission:
            "Enter a mission before starting a session."
        case .activeSessionAlreadyExists:
            "A session is already active."
        case .sessionNotActive:
            "That session is no longer active."
        case .invalidStoredSession(let message):
            message
        }
    }
}
