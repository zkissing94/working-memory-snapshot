import Foundation
import SQLite3

struct SnapshotRepository {
    let database: Database

    func saveOrReplaceSnapshot(_ draft: SnapshotDraft, for sessionID: UUID) async throws -> Snapshot {
        let now = try DateCoding.date(from: DateCoding.string(from: Date()))
        let existingSnapshot = try await snapshot(for: sessionID)
        let snapshot = Snapshot(
            id: existingSnapshot?.id ?? UUID(),
            sessionID: sessionID,
            whatChanged: draft.whatChanged,
            decisions: draft.decisions,
            openLoops: draft.openLoops,
            nextAction: draft.nextAction,
            resumeBrief: draft.resumeBrief,
            generatorModel: draft.generatorModel,
            promptVersion: draft.promptVersion,
            createdAt: existingSnapshot?.createdAt ?? now,
            updatedAt: now
        )

        let decisionsJSON = try encodeStringArray(snapshot.decisions)
        let openLoopsJSON = try encodeStringArray(snapshot.openLoops)

        try await database.execute("""
        INSERT INTO snapshots(
            id,
            session_id,
            what_changed,
            decisions_json,
            open_loops_json,
            next_action,
            resume_brief,
            generator_model,
            prompt_version,
            created_at,
            updated_at
        )
        VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(session_id) DO UPDATE SET
            what_changed = excluded.what_changed,
            decisions_json = excluded.decisions_json,
            open_loops_json = excluded.open_loops_json,
            next_action = excluded.next_action,
            resume_brief = excluded.resume_brief,
            generator_model = excluded.generator_model,
            prompt_version = excluded.prompt_version,
            updated_at = excluded.updated_at
        """) { statement in
            try bind(snapshot, decisionsJSON: decisionsJSON, openLoopsJSON: openLoopsJSON, to: statement)
        }

        return snapshot
    }

    func snapshot(for sessionID: UUID) async throws -> Snapshot? {
        try await database.query("""
        SELECT id,
               session_id,
               what_changed,
               decisions_json,
               open_loops_json,
               next_action,
               resume_brief,
               generator_model,
               prompt_version,
               created_at,
               updated_at
        FROM snapshots
        WHERE session_id = ?
        LIMIT 1
        """, bind: { statement in
            try SQLiteValue.bind(sessionID.uuidString, to: statement, at: 1)
        }, map: { statement in
            try mapSnapshot(from: statement)
        })
        .first
    }

    func latestSnapshot(for projectID: UUID) async throws -> Snapshot? {
        try await database.query("""
        SELECT snapshots.id,
               snapshots.session_id,
               snapshots.what_changed,
               snapshots.decisions_json,
               snapshots.open_loops_json,
               snapshots.next_action,
               snapshots.resume_brief,
               snapshots.generator_model,
               snapshots.prompt_version,
               snapshots.created_at,
               snapshots.updated_at
        FROM snapshots
        INNER JOIN sessions ON sessions.id = snapshots.session_id
        WHERE sessions.project_id = ? AND sessions.status = ?
        ORDER BY sessions.ended_at DESC, snapshots.created_at DESC
        LIMIT 1
        """, bind: { statement in
            try SQLiteValue.bind(projectID.uuidString, to: statement, at: 1)
            try SQLiteValue.bind(SessionStatus.completed.rawValue, to: statement, at: 2)
        }, map: { statement in
            try mapSnapshot(from: statement)
        })
        .first
    }

    func listSnapshots(for projectID: UUID) async throws -> [Snapshot] {
        try await database.query("""
        SELECT snapshots.id,
               snapshots.session_id,
               snapshots.what_changed,
               snapshots.decisions_json,
               snapshots.open_loops_json,
               snapshots.next_action,
               snapshots.resume_brief,
               snapshots.generator_model,
               snapshots.prompt_version,
               snapshots.created_at,
               snapshots.updated_at
        FROM snapshots
        INNER JOIN sessions ON sessions.id = snapshots.session_id
        WHERE sessions.project_id = ? AND sessions.status = ?
        ORDER BY sessions.ended_at DESC, snapshots.created_at DESC
        """, bind: { statement in
            try SQLiteValue.bind(projectID.uuidString, to: statement, at: 1)
            try SQLiteValue.bind(SessionStatus.completed.rawValue, to: statement, at: 2)
        }, map: { statement in
            try mapSnapshot(from: statement)
        })
    }

    private func bind(
        _ snapshot: Snapshot,
        decisionsJSON: String,
        openLoopsJSON: String,
        to statement: OpaquePointer
    ) throws {
        try SQLiteValue.bind(snapshot.id.uuidString, to: statement, at: 1)
        try SQLiteValue.bind(snapshot.sessionID.uuidString, to: statement, at: 2)
        try SQLiteValue.bind(snapshot.whatChanged, to: statement, at: 3)
        try SQLiteValue.bind(decisionsJSON, to: statement, at: 4)
        try SQLiteValue.bind(openLoopsJSON, to: statement, at: 5)
        try SQLiteValue.bind(snapshot.nextAction, to: statement, at: 6)
        try SQLiteValue.bind(snapshot.resumeBrief, to: statement, at: 7)
        if let generatorModel = snapshot.generatorModel {
            try SQLiteValue.bind(generatorModel, to: statement, at: 8)
        } else {
            try SQLiteValue.bindNull(to: statement, at: 8)
        }
        try SQLiteValue.bind(snapshot.promptVersion, to: statement, at: 9)
        try SQLiteValue.bind(DateCoding.string(from: snapshot.createdAt), to: statement, at: 10)
        try SQLiteValue.bind(DateCoding.string(from: snapshot.updatedAt), to: statement, at: 11)
    }

    private func mapSnapshot(from statement: OpaquePointer) throws -> Snapshot {
        let idString = SQLiteValue.text(statement, at: 0)
        let sessionIDString = SQLiteValue.text(statement, at: 1)

        guard let id = UUID(uuidString: idString) else {
            throw SnapshotRepositoryError.invalidStoredSnapshot("Invalid snapshot id: \(idString)")
        }
        guard let sessionID = UUID(uuidString: sessionIDString) else {
            throw SnapshotRepositoryError.invalidStoredSnapshot("Invalid snapshot session id: \(sessionIDString)")
        }

        return Snapshot(
            id: id,
            sessionID: sessionID,
            whatChanged: SQLiteValue.text(statement, at: 2),
            decisions: try decodeStringArray(SQLiteValue.text(statement, at: 3), fieldName: "decisions_json"),
            openLoops: try decodeStringArray(SQLiteValue.text(statement, at: 4), fieldName: "open_loops_json"),
            nextAction: SQLiteValue.text(statement, at: 5),
            resumeBrief: SQLiteValue.text(statement, at: 6),
            generatorModel: SQLiteValue.optionalText(statement, at: 7),
            promptVersion: SQLiteValue.text(statement, at: 8),
            createdAt: try DateCoding.date(from: SQLiteValue.text(statement, at: 9)),
            updatedAt: try DateCoding.date(from: SQLiteValue.text(statement, at: 10))
        )
    }

    private func encodeStringArray(_ array: [String]) throws -> String {
        let data = try JSONEncoder().encode(array)
        guard let json = String(data: data, encoding: .utf8) else {
            throw SnapshotRepositoryError.invalidStringArray
        }
        return json
    }

    private func decodeStringArray(_ json: String, fieldName: String) throws -> [String] {
        guard let data = json.data(using: .utf8) else {
            throw SnapshotRepositoryError.invalidStoredSnapshot("Invalid UTF-8 in \(fieldName).")
        }

        do {
            return try JSONDecoder().decode([String].self, from: data)
        } catch {
            throw SnapshotRepositoryError.invalidStoredSnapshot("Invalid JSON in \(fieldName).")
        }
    }
}

enum SnapshotRepositoryError: Error, Equatable, LocalizedError {
    case invalidStringArray
    case invalidStoredSnapshot(String)

    var errorDescription: String? {
        switch self {
        case .invalidStringArray:
            "The snapshot arrays could not be encoded."
        case .invalidStoredSnapshot(let message):
            message
        }
    }
}
