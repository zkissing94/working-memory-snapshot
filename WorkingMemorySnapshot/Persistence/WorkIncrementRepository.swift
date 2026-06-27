import Foundation
import SQLite3

struct WorkIncrementRepository {
    let database: Database

    func addIncrement(
        blockID: UUID,
        kind: WorkIncrementKind,
        title: String,
        detail: String? = nil
    ) async throws -> WorkIncrement {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            throw WorkIncrementRepositoryError.emptyTitle
        }

        let now = try DateCoding.date(from: DateCoding.string(from: Date()))
        let increment = WorkIncrement(
            id: UUID(),
            blockID: blockID,
            occurredAt: now,
            kind: kind,
            title: trimmedTitle,
            detail: trimmedOptional(detail),
            createdAt: now,
            updatedAt: now
        )

        let changes = try await database.executeReturningChanges("""
        INSERT INTO work_increments(
            id,
            block_id,
            occurred_at,
            kind,
            title,
            detail,
            created_at,
            updated_at
        )
        SELECT ?, ?, ?, ?, ?, ?, ?, ?
        WHERE EXISTS (
            SELECT 1
            FROM pomodoro_blocks
            INNER JOIN sessions ON sessions.id = pomodoro_blocks.session_id
            WHERE pomodoro_blocks.id = ?
              AND pomodoro_blocks.status IN (?, ?)
              AND sessions.status = ?
        )
        """) { statement in
            try bind(increment, to: statement)
            try SQLiteValue.bind(blockID.uuidString, to: statement, at: 9)
            try SQLiteValue.bind(PomodoroBlockStatus.active.rawValue, to: statement, at: 10)
            try SQLiteValue.bind(PomodoroBlockStatus.paused.rawValue, to: statement, at: 11)
            try SQLiteValue.bind(SessionStatus.active.rawValue, to: statement, at: 12)
        }

        guard changes == 1 else {
            throw WorkIncrementRepositoryError.blockNotOpen
        }

        return increment
    }

    func listIncrements(for blockID: UUID) async throws -> [WorkIncrement] {
        try await database.query("""
        SELECT id,
               block_id,
               occurred_at,
               kind,
               title,
               detail,
               created_at,
               updated_at
        FROM work_increments
        WHERE block_id = ?
        ORDER BY occurred_at ASC, created_at ASC
        """, bind: { statement in
            try SQLiteValue.bind(blockID.uuidString, to: statement, at: 1)
        }, map: { statement in
            try mapIncrement(from: statement)
        })
    }

    func listIncrementsForSession(_ sessionID: UUID) async throws -> [WorkIncrement] {
        try await database.query("""
        SELECT work_increments.id,
               work_increments.block_id,
               work_increments.occurred_at,
               work_increments.kind,
               work_increments.title,
               work_increments.detail,
               work_increments.created_at,
               work_increments.updated_at
        FROM work_increments
        INNER JOIN pomodoro_blocks ON pomodoro_blocks.id = work_increments.block_id
        WHERE pomodoro_blocks.session_id = ?
        ORDER BY pomodoro_blocks.block_index ASC,
                 work_increments.occurred_at ASC,
                 work_increments.created_at ASC
        """, bind: { statement in
            try SQLiteValue.bind(sessionID.uuidString, to: statement, at: 1)
        }, map: { statement in
            try mapIncrement(from: statement)
        })
    }

    private func bind(_ increment: WorkIncrement, to statement: OpaquePointer) throws {
        try SQLiteValue.bind(increment.id.uuidString, to: statement, at: 1)
        try SQLiteValue.bind(increment.blockID.uuidString, to: statement, at: 2)
        try SQLiteValue.bind(DateCoding.string(from: increment.occurredAt), to: statement, at: 3)
        try SQLiteValue.bind(increment.kind.rawValue, to: statement, at: 4)
        try SQLiteValue.bind(increment.title, to: statement, at: 5)
        if let detail = increment.detail {
            try SQLiteValue.bind(detail, to: statement, at: 6)
        } else {
            try SQLiteValue.bindNull(to: statement, at: 6)
        }
        try SQLiteValue.bind(DateCoding.string(from: increment.createdAt), to: statement, at: 7)
        try SQLiteValue.bind(DateCoding.string(from: increment.updatedAt), to: statement, at: 8)
    }

    private func mapIncrement(from statement: OpaquePointer) throws -> WorkIncrement {
        let idString = SQLiteValue.text(statement, at: 0)
        let blockIDString = SQLiteValue.text(statement, at: 1)
        let kindString = SQLiteValue.text(statement, at: 3)

        guard let id = UUID(uuidString: idString) else {
            throw WorkIncrementRepositoryError.invalidStoredIncrement("Invalid increment id: \(idString)")
        }
        guard let blockID = UUID(uuidString: blockIDString) else {
            throw WorkIncrementRepositoryError.invalidStoredIncrement("Invalid increment block id: \(blockIDString)")
        }
        guard let kind = WorkIncrementKind(rawValue: kindString) else {
            throw WorkIncrementRepositoryError.invalidStoredIncrement("Invalid increment kind: \(kindString)")
        }

        return WorkIncrement(
            id: id,
            blockID: blockID,
            occurredAt: try DateCoding.date(from: SQLiteValue.text(statement, at: 2)),
            kind: kind,
            title: SQLiteValue.text(statement, at: 4),
            detail: SQLiteValue.optionalText(statement, at: 5),
            createdAt: try DateCoding.date(from: SQLiteValue.text(statement, at: 6)),
            updatedAt: try DateCoding.date(from: SQLiteValue.text(statement, at: 7))
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

enum WorkIncrementRepositoryError: Error, Equatable, LocalizedError {
    case emptyTitle
    case blockNotOpen
    case invalidStoredIncrement(String)

    var errorDescription: String? {
        switch self {
        case .emptyTitle:
            "Enter a capture before saving."
        case .blockNotOpen:
            "Captures can only be saved to an active focus block."
        case .invalidStoredIncrement(let message):
            message
        }
    }
}
