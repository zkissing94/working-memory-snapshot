import Foundation
import SQLite3

protocol DailyRollupPersisting: Sendable {
    func saveRevision(_ draft: DailyRollupDraft) async throws -> DailyRollup
    func rollup(for rollupDate: String) async throws -> DailyRollup?
    func listRollups() async throws -> [DailyRollup]
    func sources(for rollupID: UUID) async throws -> [DailyRollupSource]
}

struct DailyRollupRepository: DailyRollupPersisting {
    let database: Database

    func saveRevision(_ draft: DailyRollupDraft) async throws -> DailyRollup {
        let now = try DateCoding.now()
        return try await database.withTransaction { database in
            let rollup = DailyRollup(
                id: UUID(),
                rollupDate: draft.rollupDate,
                timezoneIdentifier: draft.timezoneIdentifier,
                daySummary: draft.daySummary,
                projectThreads: draft.projectThreads,
                carryForwards: draft.carryForwards,
                closureNote: draft.closureNote,
                generatorModel: draft.generatorModel,
                promptVersion: draft.promptVersion,
                sourceFingerprint: draft.sourceFingerprint,
                generatedAt: now,
                updatedAt: now
            )

            let threadsJSON = try encode(rollup.projectThreads)
            let carryForwardsJSON = try encode(rollup.carryForwards)
            try database.execute("""
            INSERT INTO daily_rollups(
                id, rollup_date, timezone_identifier, day_summary,
                project_threads_json, carry_forwards_json, closure_note,
                generator_model, prompt_version, source_fingerprint,
                generated_at, updated_at
            )
            VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """) { statement in
                try bind(rollup, threadsJSON: threadsJSON, carryForwardsJSON: carryForwardsJSON, to: statement)
            }

            for source in draft.sources {
                try database.execute("""
                INSERT INTO daily_rollup_sources(
                    rollup_id, session_id, project_id, project_name,
                    session_mission, session_ended_at
                ) VALUES(?, ?, ?, ?, ?, ?)
                """) { statement in
                    try SQLiteValue.bind(rollup.id.uuidString, to: statement, at: 1)
                    try SQLiteValue.bind(source.sessionID.uuidString, to: statement, at: 2)
                    try SQLiteValue.bind(source.projectID.uuidString, to: statement, at: 3)
                    try SQLiteValue.bind(source.projectName, to: statement, at: 4)
                    try SQLiteValue.bind(source.mission, to: statement, at: 5)
                    try SQLiteValue.bind(DateCoding.string(from: source.endedAt), to: statement, at: 6)
                }
            }

            return rollup
        }
    }

    func rollup(for rollupDate: String) async throws -> DailyRollup? {
        try await database.query(selectSQL + " WHERE rollup_date = ? ORDER BY generated_at DESC, rowid DESC LIMIT 1", bind: { statement in
            try SQLiteValue.bind(rollupDate, to: statement, at: 1)
        }, map: mapRollup(from:))
        .first
    }

    func listRollups() async throws -> [DailyRollup] {
        try await database.query(
            selectSQL + " ORDER BY rollup_date DESC, generated_at DESC, rowid DESC",
            map: mapRollup(from:)
        )
    }

    func sources(for rollupID: UUID) async throws -> [DailyRollupSource] {
        try await database.query("""
        SELECT daily_rollup_sources.rollup_id,
               daily_rollup_sources.session_id,
               daily_rollup_sources.project_id,
               daily_rollup_sources.project_name,
               daily_rollup_sources.session_mission,
               daily_rollup_sources.session_ended_at,
               CASE WHEN sessions.id IS NULL THEN 0 ELSE 1 END
        FROM daily_rollup_sources
        LEFT JOIN sessions ON sessions.id = daily_rollup_sources.session_id
        WHERE daily_rollup_sources.rollup_id = ?
        ORDER BY daily_rollup_sources.session_ended_at ASC
        """, bind: { statement in
            try SQLiteValue.bind(rollupID.uuidString, to: statement, at: 1)
        }, map: { statement in
            guard let rollupID = UUID(uuidString: SQLiteValue.text(statement, at: 0)),
                  let sessionID = UUID(uuidString: SQLiteValue.text(statement, at: 1)),
                  let projectID = UUID(uuidString: SQLiteValue.text(statement, at: 2))
            else {
                throw DailyRollupRepositoryError.invalidStoredRollup("Invalid source identifier.")
            }
            return DailyRollupSource(
                rollupID: rollupID,
                sessionID: sessionID,
                projectID: projectID,
                projectName: SQLiteValue.text(statement, at: 3),
                mission: SQLiteValue.text(statement, at: 4),
                endedAt: try DateCoding.date(from: SQLiteValue.text(statement, at: 5)),
                isAvailable: sqlite3_column_int(statement, 6) == 1
            )
        })
    }

    private var selectSQL: String {
        """
        SELECT id, rollup_date, timezone_identifier, day_summary,
               project_threads_json, carry_forwards_json, closure_note,
               generator_model, prompt_version, source_fingerprint,
               generated_at, updated_at
        FROM daily_rollups
        """
    }

    private func bind(
        _ rollup: DailyRollup,
        threadsJSON: String,
        carryForwardsJSON: String,
        to statement: OpaquePointer
    ) throws {
        try SQLiteValue.bind(rollup.id.uuidString, to: statement, at: 1)
        try SQLiteValue.bind(rollup.rollupDate, to: statement, at: 2)
        try SQLiteValue.bind(rollup.timezoneIdentifier, to: statement, at: 3)
        try SQLiteValue.bind(rollup.daySummary, to: statement, at: 4)
        try SQLiteValue.bind(threadsJSON, to: statement, at: 5)
        try SQLiteValue.bind(carryForwardsJSON, to: statement, at: 6)
        try SQLiteValue.bind(rollup.closureNote, to: statement, at: 7)
        if let model = rollup.generatorModel {
            try SQLiteValue.bind(model, to: statement, at: 8)
        } else {
            try SQLiteValue.bindNull(to: statement, at: 8)
        }
        try SQLiteValue.bind(rollup.promptVersion, to: statement, at: 9)
        try SQLiteValue.bind(rollup.sourceFingerprint, to: statement, at: 10)
        try SQLiteValue.bind(DateCoding.string(from: rollup.generatedAt), to: statement, at: 11)
        try SQLiteValue.bind(DateCoding.string(from: rollup.updatedAt), to: statement, at: 12)
    }

    private func mapRollup(from statement: OpaquePointer) throws -> DailyRollup {
        guard let id = UUID(uuidString: SQLiteValue.text(statement, at: 0)) else {
            throw DailyRollupRepositoryError.invalidStoredRollup("Invalid rollup id.")
        }
        return DailyRollup(
            id: id,
            rollupDate: SQLiteValue.text(statement, at: 1),
            timezoneIdentifier: SQLiteValue.text(statement, at: 2),
            daySummary: SQLiteValue.text(statement, at: 3),
            projectThreads: try decode(SQLiteValue.text(statement, at: 4), as: [DailyProjectThread].self),
            carryForwards: try decode(SQLiteValue.text(statement, at: 5), as: [DailyCarryForward].self),
            closureNote: SQLiteValue.text(statement, at: 6),
            generatorModel: SQLiteValue.optionalText(statement, at: 7),
            promptVersion: SQLiteValue.text(statement, at: 8),
            sourceFingerprint: SQLiteValue.text(statement, at: 9),
            generatedAt: try DateCoding.date(from: SQLiteValue.text(statement, at: 10)),
            updatedAt: try DateCoding.date(from: SQLiteValue.text(statement, at: 11))
        )
    }

    private func encode<Value: Encodable>(_ value: Value) throws -> String {
        let data = try JSONEncoder().encode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            throw DailyRollupRepositoryError.invalidJSON
        }
        return string
    }

    private func decode<Value: Decodable>(_ string: String, as type: Value.Type) throws -> Value {
        guard let data = string.data(using: .utf8) else {
            throw DailyRollupRepositoryError.invalidJSON
        }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw DailyRollupRepositoryError.invalidStoredRollup("Invalid rollup JSON.")
        }
    }
}

enum DailyRollupRepositoryError: Error, Equatable, LocalizedError {
    case invalidJSON
    case invalidStoredRollup(String)

    var errorDescription: String? {
        switch self {
        case .invalidJSON:
            "The daily rollup could not be encoded."
        case .invalidStoredRollup(let message):
            message
        }
    }
}
