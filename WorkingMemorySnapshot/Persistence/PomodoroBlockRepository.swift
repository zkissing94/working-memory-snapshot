import Foundation
import SQLite3

struct PomodoroBlockRepository {
    let database: Database

    func createNextBlock(
        sessionID: UUID,
        intention: String? = nil,
        plannedDurationSeconds: Int = PomodoroBlock.defaultPlannedDurationSeconds
    ) async throws -> PomodoroBlock {
        try await database.withTransaction { database in
            try createNextBlock(
                sessionID: sessionID,
                intention: intention,
                plannedDurationSeconds: plannedDurationSeconds,
                using: database
            )
        }
    }

    func ensureFirstBlock(for sessionID: UUID) async throws -> PomodoroBlock? {
        try await database.withTransaction { database in
            let blocks = try listBlocks(for: sessionID, using: database)
            if let openBlock = blocks.first(where: \.isOpen) {
                return openBlock
            }
            guard blocks.isEmpty else {
                return nil
            }
            return try createNextBlock(sessionID: sessionID, using: database)
        }
    }

    func block(for id: UUID) async throws -> PomodoroBlock? {
        try await database.query("""
        SELECT id,
               session_id,
               block_index,
               planned_duration_seconds,
               intention,
               summary,
               status,
               started_at,
               paused_at,
               accumulated_pause_seconds,
               ended_at,
               created_at,
               updated_at
        FROM pomodoro_blocks
        WHERE id = ?
        LIMIT 1
        """, bind: { statement in
            try SQLiteValue.bind(id.uuidString, to: statement, at: 1)
        }, map: { statement in
            try mapBlock(from: statement)
        })
        .first
    }

    func listBlocks(for sessionID: UUID) async throws -> [PomodoroBlock] {
        try await database.query("""
        SELECT id,
               session_id,
               block_index,
               planned_duration_seconds,
               intention,
               summary,
               status,
               started_at,
               paused_at,
               accumulated_pause_seconds,
               ended_at,
               created_at,
               updated_at
        FROM pomodoro_blocks
        WHERE session_id = ?
        ORDER BY block_index ASC
        """, bind: { statement in
            try SQLiteValue.bind(sessionID.uuidString, to: statement, at: 1)
        }, map: { statement in
            try mapBlock(from: statement)
        })
    }

    func completedBlockCount(for projectID: UUID) async throws -> Int {
        try await database.query("""
        SELECT COUNT(*)
        FROM pomodoro_blocks
        INNER JOIN sessions ON sessions.id = pomodoro_blocks.session_id
        WHERE sessions.project_id = ? AND pomodoro_blocks.status = ?
        """, bind: { statement in
            try SQLiteValue.bind(projectID.uuidString, to: statement, at: 1)
            try SQLiteValue.bind(PomodoroBlockStatus.completed.rawValue, to: statement, at: 2)
        }, map: { statement in
            Int(sqlite3_column_int64(statement, 0))
        })
        .first ?? 0
    }

    func openBlock(for sessionID: UUID) async throws -> PomodoroBlock? {
        try await database.query("""
        SELECT id,
               session_id,
               block_index,
               planned_duration_seconds,
               intention,
               summary,
               status,
               started_at,
               paused_at,
               accumulated_pause_seconds,
               ended_at,
               created_at,
               updated_at
        FROM pomodoro_blocks
        WHERE session_id = ? AND status IN (?, ?)
        ORDER BY block_index DESC
        LIMIT 1
        """, bind: { statement in
            try SQLiteValue.bind(sessionID.uuidString, to: statement, at: 1)
            try SQLiteValue.bind(PomodoroBlockStatus.active.rawValue, to: statement, at: 2)
            try SQLiteValue.bind(PomodoroBlockStatus.paused.rawValue, to: statement, at: 3)
        }, map: { statement in
            try mapBlock(from: statement)
        })
        .first
    }

    func pauseBlock(id: UUID) async throws -> PomodoroBlock {
        let now = try DateCoding.now()
        return try await database.withTransaction { database in
            let changes = try database.executeReturningChanges("""
            UPDATE pomodoro_blocks
            SET status = ?,
                paused_at = ?,
                updated_at = ?
            WHERE id = ? AND status = ?
            """) { statement in
                try SQLiteValue.bind(PomodoroBlockStatus.paused.rawValue, to: statement, at: 1)
                try SQLiteValue.bind(DateCoding.string(from: now), to: statement, at: 2)
                try SQLiteValue.bind(DateCoding.string(from: now), to: statement, at: 3)
                try SQLiteValue.bind(id.uuidString, to: statement, at: 4)
                try SQLiteValue.bind(PomodoroBlockStatus.active.rawValue, to: statement, at: 5)
            }

            guard changes == 1, let block = try block(for: id, using: database) else {
                throw PomodoroBlockRepositoryError.blockNotOpen
            }
            return block
        }
    }

    func resumeBlock(id: UUID) async throws -> PomodoroBlock {
        try await database.withTransaction { database in
            guard let current = try block(for: id, using: database),
                  current.status == .paused,
                  let pausedAt = current.pausedAt
            else {
                throw PomodoroBlockRepositoryError.blockNotPaused
            }

            let now = try DateCoding.now()
            let pauseSeconds = max(0, Int(now.timeIntervalSince(pausedAt)))
            let changes = try database.executeReturningChanges("""
            UPDATE pomodoro_blocks
            SET status = ?,
                paused_at = NULL,
                accumulated_pause_seconds = ?,
                updated_at = ?
            WHERE id = ? AND status = ?
            """) { statement in
                try SQLiteValue.bind(PomodoroBlockStatus.active.rawValue, to: statement, at: 1)
                try SQLiteValue.bind(current.accumulatedPauseSeconds + pauseSeconds, to: statement, at: 2)
                try SQLiteValue.bind(DateCoding.string(from: now), to: statement, at: 3)
                try SQLiteValue.bind(id.uuidString, to: statement, at: 4)
                try SQLiteValue.bind(PomodoroBlockStatus.paused.rawValue, to: statement, at: 5)
            }

            guard changes == 1, let block = try block(for: id, using: database) else {
                throw PomodoroBlockRepositoryError.blockNotPaused
            }
            return block
        }
    }

    func completeBlock(id: UUID, summary: String?) async throws -> PomodoroBlock {
        try await database.withTransaction { database in
            try closeBlock(id: id, status: .completed, summary: summary, using: database)
        }
    }

    func interruptOpenBlock(for sessionID: UUID) async throws -> PomodoroBlock? {
        try await database.withTransaction { database in
            guard let openBlock = try openBlock(for: sessionID, using: database) else {
                return nil
            }
            return try closeBlock(id: openBlock.id, status: .interrupted, summary: openBlock.summary, using: database)
        }
    }

    private func createNextBlock(
        sessionID: UUID,
        intention: String? = nil,
        plannedDurationSeconds: Int = PomodoroBlock.defaultPlannedDurationSeconds,
        using database: isolated Database
    ) throws -> PomodoroBlock {
        guard plannedDurationSeconds > 0 else {
            throw PomodoroBlockRepositoryError.invalidPlannedDuration
        }

        if try openBlock(for: sessionID, using: database) != nil {
            throw PomodoroBlockRepositoryError.openBlockAlreadyExists
        }

        let nextIndex = try nextBlockIndex(for: sessionID, using: database)
        let now = try DateCoding.now()
        let newBlock = PomodoroBlock(
            id: UUID(),
            sessionID: sessionID,
            blockIndex: nextIndex,
            plannedDurationSeconds: plannedDurationSeconds,
            intention: trimmedOptional(intention),
            summary: nil,
            status: .active,
            startedAt: now,
            pausedAt: nil,
            accumulatedPauseSeconds: 0,
            endedAt: nil,
            createdAt: now,
            updatedAt: now
        )

        do {
            let changes = try database.executeReturningChanges("""
            INSERT INTO pomodoro_blocks(
                id,
                session_id,
                block_index,
                planned_duration_seconds,
                intention,
                summary,
                status,
                started_at,
                paused_at,
                accumulated_pause_seconds,
                ended_at,
                created_at,
                updated_at
            )
            SELECT ?, ?, ?, ?, ?, NULL, ?, ?, NULL, ?, NULL, ?, ?
            WHERE EXISTS (
                SELECT 1
                FROM sessions
                WHERE id = ? AND status = ?
            )
            """) { statement in
                try bind(newBlock, to: statement)
                try SQLiteValue.bind(newBlock.sessionID.uuidString, to: statement, at: 11)
                try SQLiteValue.bind(SessionStatus.active.rawValue, to: statement, at: 12)
            }
            guard changes == 1 else {
                throw PomodoroBlockRepositoryError.sessionNotActive
            }
        } catch let error as SQLiteError where error.code == SQLITE_CONSTRAINT {
            if try openBlock(for: sessionID, using: database) != nil {
                throw PomodoroBlockRepositoryError.openBlockAlreadyExists
            }
            throw error
        }

        guard let stored = try block(for: newBlock.id, using: database) else {
            throw PomodoroBlockRepositoryError.sessionNotActive
        }
        return stored
    }

    private func block(for id: UUID, using database: isolated Database) throws -> PomodoroBlock? {
        try database.query("""
        SELECT id,
               session_id,
               block_index,
               planned_duration_seconds,
               intention,
               summary,
               status,
               started_at,
               paused_at,
               accumulated_pause_seconds,
               ended_at,
               created_at,
               updated_at
        FROM pomodoro_blocks
        WHERE id = ?
        LIMIT 1
        """, bind: { statement in
            try SQLiteValue.bind(id.uuidString, to: statement, at: 1)
        }, map: { statement in
            try mapBlock(from: statement)
        })
        .first
    }

    private func listBlocks(for sessionID: UUID, using database: isolated Database) throws -> [PomodoroBlock] {
        try database.query("""
        SELECT id,
               session_id,
               block_index,
               planned_duration_seconds,
               intention,
               summary,
               status,
               started_at,
               paused_at,
               accumulated_pause_seconds,
               ended_at,
               created_at,
               updated_at
        FROM pomodoro_blocks
        WHERE session_id = ?
        ORDER BY block_index ASC
        """, bind: { statement in
            try SQLiteValue.bind(sessionID.uuidString, to: statement, at: 1)
        }, map: { statement in
            try mapBlock(from: statement)
        })
    }

    private func openBlock(for sessionID: UUID, using database: isolated Database) throws -> PomodoroBlock? {
        try database.query("""
        SELECT id,
               session_id,
               block_index,
               planned_duration_seconds,
               intention,
               summary,
               status,
               started_at,
               paused_at,
               accumulated_pause_seconds,
               ended_at,
               created_at,
               updated_at
        FROM pomodoro_blocks
        WHERE session_id = ? AND status IN (?, ?)
        ORDER BY block_index DESC
        LIMIT 1
        """, bind: { statement in
            try SQLiteValue.bind(sessionID.uuidString, to: statement, at: 1)
            try SQLiteValue.bind(PomodoroBlockStatus.active.rawValue, to: statement, at: 2)
            try SQLiteValue.bind(PomodoroBlockStatus.paused.rawValue, to: statement, at: 3)
        }, map: { statement in
            try mapBlock(from: statement)
        })
        .first
    }

    private func closeBlock(
        id: UUID,
        status: PomodoroBlockStatus,
        summary: String?,
        using database: isolated Database
    ) throws -> PomodoroBlock {
        guard var current = try block(for: id, using: database), current.isOpen else {
            throw PomodoroBlockRepositoryError.blockNotOpen
        }

        let now = try DateCoding.now()
        if current.status == .paused, let pausedAt = current.pausedAt {
            current.accumulatedPauseSeconds += max(0, Int(now.timeIntervalSince(pausedAt)))
        }

        let changes = try database.executeReturningChanges("""
        UPDATE pomodoro_blocks
        SET status = ?,
            summary = ?,
            paused_at = NULL,
            accumulated_pause_seconds = ?,
            ended_at = ?,
            updated_at = ?
        WHERE id = ? AND status IN (?, ?)
        """) { statement in
            try SQLiteValue.bind(status.rawValue, to: statement, at: 1)
            if let summary = trimmedOptional(summary) {
                try SQLiteValue.bind(summary, to: statement, at: 2)
            } else {
                try SQLiteValue.bindNull(to: statement, at: 2)
            }
            try SQLiteValue.bind(current.accumulatedPauseSeconds, to: statement, at: 3)
            try SQLiteValue.bind(DateCoding.string(from: now), to: statement, at: 4)
            try SQLiteValue.bind(DateCoding.string(from: now), to: statement, at: 5)
            try SQLiteValue.bind(id.uuidString, to: statement, at: 6)
            try SQLiteValue.bind(PomodoroBlockStatus.active.rawValue, to: statement, at: 7)
            try SQLiteValue.bind(PomodoroBlockStatus.paused.rawValue, to: statement, at: 8)
        }

        guard changes == 1, let block = try block(for: id, using: database) else {
            throw PomodoroBlockRepositoryError.blockNotOpen
        }
        return block
    }

    private func nextBlockIndex(for sessionID: UUID, using database: isolated Database) throws -> Int {
        let maxIndex = try database.query("""
        SELECT COALESCE(MAX(block_index), 0)
        FROM pomodoro_blocks
        WHERE session_id = ?
        """, bind: { statement in
            try SQLiteValue.bind(sessionID.uuidString, to: statement, at: 1)
        }, map: { statement in
            SQLiteValue.integer(statement, at: 0)
        })
        .first ?? 0

        return maxIndex + 1
    }

    private func bind(_ block: PomodoroBlock, to statement: OpaquePointer) throws {
        try SQLiteValue.bind(block.id.uuidString, to: statement, at: 1)
        try SQLiteValue.bind(block.sessionID.uuidString, to: statement, at: 2)
        try SQLiteValue.bind(block.blockIndex, to: statement, at: 3)
        try SQLiteValue.bind(block.plannedDurationSeconds, to: statement, at: 4)
        if let intention = block.intention {
            try SQLiteValue.bind(intention, to: statement, at: 5)
        } else {
            try SQLiteValue.bindNull(to: statement, at: 5)
        }
        try SQLiteValue.bind(block.status.rawValue, to: statement, at: 6)
        try SQLiteValue.bind(DateCoding.string(from: block.startedAt), to: statement, at: 7)
        try SQLiteValue.bind(block.accumulatedPauseSeconds, to: statement, at: 8)
        try SQLiteValue.bind(DateCoding.string(from: block.createdAt), to: statement, at: 9)
        try SQLiteValue.bind(DateCoding.string(from: block.updatedAt), to: statement, at: 10)
    }

    private func mapBlock(from statement: OpaquePointer) throws -> PomodoroBlock {
        let idString = SQLiteValue.text(statement, at: 0)
        let sessionIDString = SQLiteValue.text(statement, at: 1)
        let statusString = SQLiteValue.text(statement, at: 6)

        guard let id = UUID(uuidString: idString) else {
            throw PomodoroBlockRepositoryError.invalidStoredBlock("Invalid block id: \(idString)")
        }
        guard let sessionID = UUID(uuidString: sessionIDString) else {
            throw PomodoroBlockRepositoryError.invalidStoredBlock("Invalid block session id: \(sessionIDString)")
        }
        guard let status = PomodoroBlockStatus(rawValue: statusString) else {
            throw PomodoroBlockRepositoryError.invalidStoredBlock("Invalid block status: \(statusString)")
        }

        return PomodoroBlock(
            id: id,
            sessionID: sessionID,
            blockIndex: SQLiteValue.integer(statement, at: 2),
            plannedDurationSeconds: SQLiteValue.integer(statement, at: 3),
            intention: SQLiteValue.optionalText(statement, at: 4),
            summary: SQLiteValue.optionalText(statement, at: 5),
            status: status,
            startedAt: try DateCoding.date(from: SQLiteValue.text(statement, at: 7)),
            pausedAt: try SQLiteValue.optionalText(statement, at: 8).map(DateCoding.date(from:)),
            accumulatedPauseSeconds: SQLiteValue.integer(statement, at: 9),
            endedAt: try SQLiteValue.optionalText(statement, at: 10).map(DateCoding.date(from:)),
            createdAt: try DateCoding.date(from: SQLiteValue.text(statement, at: 11)),
            updatedAt: try DateCoding.date(from: SQLiteValue.text(statement, at: 12))
        )
    }

    private func trimmedOptional(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum PomodoroBlockRepositoryError: Error, Equatable, LocalizedError {
    case invalidPlannedDuration
    case sessionNotActive
    case openBlockAlreadyExists
    case blockNotOpen
    case blockNotPaused
    case invalidStoredBlock(String)

    var errorDescription: String? {
        switch self {
        case .invalidPlannedDuration:
            "A focus block must have a positive duration."
        case .sessionNotActive:
            "Focus blocks can only be created for an active session."
        case .openBlockAlreadyExists:
            "Complete or pause the current focus block before starting another."
        case .blockNotOpen:
            "That focus block is no longer active."
        case .blockNotPaused:
            "That focus block is not paused."
        case .invalidStoredBlock(let message):
            message
        }
    }
}
