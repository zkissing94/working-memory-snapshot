import Foundation
import SQLite3

struct EventRepository {
    let database: Database

    @discardableResult
    func insertEvent(_ event: SessionEvent) async throws -> SessionEvent {
        try await insert(event)
        return event
    }

    func insertEvents(_ events: [SessionEvent]) async throws {
        guard !events.isEmpty else {
            return
        }

        try await database.execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            for event in events {
                try await insert(event)
            }
            try await database.execute("COMMIT")
        } catch {
            try? await database.execute("ROLLBACK")
            throw error
        }
    }

    func listEvents(for sessionID: UUID) async throws -> [SessionEvent] {
        try await database.query("""
        SELECT id,
               session_id,
               occurred_at,
               source,
               kind,
               title,
               body,
               payload_json,
               created_at
        FROM events
        WHERE session_id = ?
        ORDER BY occurred_at ASC, created_at ASC
        """, bind: { statement in
            try SQLiteValue.bind(sessionID.uuidString, to: statement, at: 1)
        }, map: { statement in
            try mapEvent(from: statement)
        })
    }

    func countEvents(
        for sessionID: UUID,
        source: EventSource? = nil,
        kind: String? = nil
    ) async throws -> Int {
        var conditions = ["session_id = ?"]
        if source != nil {
            conditions.append("source = ?")
        }
        if kind != nil {
            conditions.append("kind = ?")
        }

        let sql = """
        SELECT COUNT(*)
        FROM events
        WHERE \(conditions.joined(separator: " AND "))
        """

        return try await database.query(sql, bind: { statement in
            try SQLiteValue.bind(sessionID.uuidString, to: statement, at: 1)
            var index: Int32 = 2
            if let source {
                try SQLiteValue.bind(source.rawValue, to: statement, at: index)
                index += 1
            }
            if let kind {
                try SQLiteValue.bind(kind, to: statement, at: index)
            }
        }, map: { statement in
            SQLiteValue.integer(statement, at: 0)
        })
        .first ?? 0
    }

    func listDistinctActiveApps(for sessionID: UUID) async throws -> [String] {
        try await database.query("""
        SELECT title
        FROM events
        WHERE session_id = ? AND source = ? AND kind = ?
        ORDER BY occurred_at ASC, created_at ASC
        """, bind: { statement in
            try SQLiteValue.bind(sessionID.uuidString, to: statement, at: 1)
            try SQLiteValue.bind(EventSource.activeApp.rawValue, to: statement, at: 2)
            try SQLiteValue.bind(SessionEventKind.appActivated, to: statement, at: 3)
        }, map: { statement in
            SQLiteValue.text(statement, at: 0)
        })
        .orderedUnique()
    }

    func listChangedFilePaths(for sessionID: UUID) async throws -> [String] {
        try await database.query("""
        SELECT title
        FROM events
        WHERE session_id = ? AND source = ? AND kind = ?
        ORDER BY occurred_at ASC, created_at ASC
        """, bind: { statement in
            try SQLiteValue.bind(sessionID.uuidString, to: statement, at: 1)
            try SQLiteValue.bind(EventSource.file.rawValue, to: statement, at: 2)
            try SQLiteValue.bind(SessionEventKind.fileChanged, to: statement, at: 3)
        }, map: { statement in
            SQLiteValue.text(statement, at: 0)
        })
        .orderedUnique()
    }

    private func insert(_ event: SessionEvent) async throws {
        let changes = try await database.executeReturningChanges("""
        INSERT INTO events(
            id,
            session_id,
            occurred_at,
            source,
            kind,
            title,
            body,
            payload_json,
            created_at
        )
        SELECT ?, ?, ?, ?, ?, ?, ?, ?, ?
        WHERE EXISTS (
            SELECT 1
            FROM sessions
            WHERE id = ? AND status = ?
        )
        """) { statement in
            try SQLiteValue.bind(event.id.uuidString, to: statement, at: 1)
            try SQLiteValue.bind(event.sessionID.uuidString, to: statement, at: 2)
            try SQLiteValue.bind(DateCoding.string(from: event.occurredAt), to: statement, at: 3)
            try SQLiteValue.bind(event.source.rawValue, to: statement, at: 4)
            try SQLiteValue.bind(event.kind, to: statement, at: 5)
            try SQLiteValue.bind(event.title, to: statement, at: 6)
            if let body = event.body {
                try SQLiteValue.bind(body, to: statement, at: 7)
            } else {
                try SQLiteValue.bindNull(to: statement, at: 7)
            }
            if let payloadJSON = event.payloadJSON {
                try SQLiteValue.bind(payloadJSON, to: statement, at: 8)
            } else {
                try SQLiteValue.bindNull(to: statement, at: 8)
            }
            try SQLiteValue.bind(DateCoding.string(from: event.createdAt), to: statement, at: 9)
            try SQLiteValue.bind(event.sessionID.uuidString, to: statement, at: 10)
            try SQLiteValue.bind(SessionStatus.active.rawValue, to: statement, at: 11)
        }

        guard changes == 1 else {
            throw EventRepositoryError.sessionNotActive
        }
    }

    private func mapEvent(from statement: OpaquePointer) throws -> SessionEvent {
        let idString = SQLiteValue.text(statement, at: 0)
        let sessionIDString = SQLiteValue.text(statement, at: 1)
        let sourceString = SQLiteValue.text(statement, at: 3)

        guard let id = UUID(uuidString: idString) else {
            throw EventRepositoryError.invalidStoredEvent("Invalid event id: \(idString)")
        }
        guard let sessionID = UUID(uuidString: sessionIDString) else {
            throw EventRepositoryError.invalidStoredEvent("Invalid event session id: \(sessionIDString)")
        }
        guard let source = EventSource(rawValue: sourceString) else {
            throw EventRepositoryError.invalidStoredEvent("Invalid event source: \(sourceString)")
        }

        return SessionEvent(
            id: id,
            sessionID: sessionID,
            occurredAt: try DateCoding.date(from: SQLiteValue.text(statement, at: 2)),
            source: source,
            kind: SQLiteValue.text(statement, at: 4),
            title: SQLiteValue.text(statement, at: 5),
            body: SQLiteValue.optionalText(statement, at: 6),
            payloadJSON: SQLiteValue.optionalText(statement, at: 7),
            createdAt: try DateCoding.date(from: SQLiteValue.text(statement, at: 8))
        )
    }
}

enum EventRepositoryError: Error, Equatable, LocalizedError {
    case sessionNotActive
    case invalidStoredEvent(String)

    var errorDescription: String? {
        switch self {
        case .sessionNotActive:
            "Events can only be recorded for an active session."
        case .invalidStoredEvent(let message):
            message
        }
    }
}

private extension Array where Element == String {
    func orderedUnique() -> [String] {
        var seen = Set<String>()
        var values: [String] = []
        for value in self where !seen.contains(value) {
            seen.insert(value)
            values.append(value)
        }
        return values
    }
}
