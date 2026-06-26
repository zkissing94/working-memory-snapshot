import Foundation
import SQLite3

struct DatabaseMigrator {
    let database: Database

    func migrate() async throws {
        try await database.execute("""
        CREATE TABLE IF NOT EXISTS schema_migrations (
            version INTEGER PRIMARY KEY,
            applied_at TEXT NOT NULL
        )
        """)

        let appliedVersions = Set(try await appliedVersions())
        if !appliedVersions.contains(1) {
            try await applyMigration(version: 1) {
                try await database.execute("""
                CREATE TABLE IF NOT EXISTS projects (
                    id TEXT PRIMARY KEY NOT NULL,
                    name TEXT NOT NULL,
                    root_path TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                )
                """)

                try await database.execute("""
                CREATE UNIQUE INDEX IF NOT EXISTS projects_root_path_unique
                ON projects(root_path)
                """)
            }
        }

        if !appliedVersions.contains(2) {
            try await applyMigration(version: 2) {
                try await database.execute("""
                CREATE TABLE IF NOT EXISTS app_settings (
                    key TEXT PRIMARY KEY NOT NULL,
                    value TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                )
                """)

                let now = DateCoding.string(from: Date())
                try await insertDefaultSetting(
                    key: SettingsKey.lmStudioBaseURL.rawValue,
                    value: LMStudioSettings.defaultBaseURLString,
                    appliedAt: now
                )
                try await insertDefaultSetting(
                    key: SettingsKey.lmStudioSynthesizerModel.rawValue,
                    value: "",
                    appliedAt: now
                )
                try await insertDefaultSetting(
                    key: SettingsKey.snapshotPromptVersion.rawValue,
                    value: "v1",
                    appliedAt: now
                )
            }
        }

        if !appliedVersions.contains(3) {
            try await applyMigration(version: 3) {
                try await database.execute("""
                CREATE TABLE IF NOT EXISTS sessions (
                    id TEXT PRIMARY KEY NOT NULL,
                    project_id TEXT NOT NULL,
                    mission TEXT NOT NULL,
                    brain_dump TEXT,
                    started_at TEXT NOT NULL,
                    ended_at TEXT,
                    status TEXT NOT NULL CHECK (
                        status IN ('active', 'completed', 'cancelled')
                    ),
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    FOREIGN KEY(project_id) REFERENCES projects(id) ON DELETE CASCADE
                )
                """)

                try await database.execute("""
                CREATE INDEX IF NOT EXISTS sessions_project_started_index
                ON sessions(project_id, started_at DESC)
                """)

                try await database.execute("""
                CREATE UNIQUE INDEX IF NOT EXISTS sessions_single_active_index
                ON sessions(status)
                WHERE status = 'active'
                """)
            }
        }
    }

    private func applyMigration(version: Int, body: () async throws -> Void) async throws {
        try await database.execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            try await body()

            try await database.execute("""
            INSERT INTO schema_migrations(version, applied_at)
            VALUES(?, ?)
            """) { statement in
                guard sqlite3_bind_int64(statement, 1, Int64(version)) == SQLITE_OK else {
                    throw SQLiteError(code: SQLITE_MISUSE, message: "Could not bind migration version.")
                }
                try SQLiteValue.bind(DateCoding.string(from: Date()), to: statement, at: 2)
            }

            try await database.execute("COMMIT")
        } catch {
            try? await database.execute("ROLLBACK")
            throw error
        }
    }

    private func insertDefaultSetting(key: String, value: String, appliedAt: String) async throws {
        try await database.execute("""
        INSERT OR IGNORE INTO app_settings(key, value, updated_at)
        VALUES(?, ?, ?)
        """) { statement in
            try SQLiteValue.bind(key, to: statement, at: 1)
            try SQLiteValue.bind(value, to: statement, at: 2)
            try SQLiteValue.bind(appliedAt, to: statement, at: 3)
        }
    }

    func appliedVersions() async throws -> [Int] {
        try await database.query("""
        SELECT version
        FROM schema_migrations
        ORDER BY version ASC
        """) { statement in
            SQLiteValue.integer(statement, at: 0)
        }
    }
}
