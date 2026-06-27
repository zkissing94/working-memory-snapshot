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

        if !appliedVersions.contains(4) {
            try await applyMigration(version: 4) {
                try await database.execute("""
                CREATE TABLE IF NOT EXISTS snapshots (
                    id TEXT PRIMARY KEY NOT NULL,
                    session_id TEXT NOT NULL,
                    what_changed TEXT NOT NULL,
                    decisions_json TEXT NOT NULL,
                    open_loops_json TEXT NOT NULL,
                    next_action TEXT NOT NULL,
                    resume_brief TEXT NOT NULL,
                    generator_model TEXT,
                    prompt_version TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    FOREIGN KEY(session_id) REFERENCES sessions(id) ON DELETE CASCADE
                )
                """)

                try await database.execute("""
                CREATE UNIQUE INDEX IF NOT EXISTS snapshots_session_unique
                ON snapshots(session_id)
                """)
            }
        }

        if !appliedVersions.contains(5) {
            try await applyMigration(version: 5) {
                try await database.execute("""
                CREATE TABLE IF NOT EXISTS events (
                    id TEXT PRIMARY KEY NOT NULL,
                    session_id TEXT NOT NULL,
                    occurred_at TEXT NOT NULL,
                    source TEXT NOT NULL CHECK (
                        source IN ('system', 'user', 'file', 'git', 'active_app')
                    ),
                    kind TEXT NOT NULL,
                    title TEXT NOT NULL,
                    body TEXT,
                    payload_json TEXT,
                    created_at TEXT NOT NULL,
                    FOREIGN KEY(session_id) REFERENCES sessions(id) ON DELETE CASCADE
                )
                """)

                try await database.execute("""
                CREATE INDEX IF NOT EXISTS events_session_time_index
                ON events(session_id, occurred_at ASC)
                """)

                try await database.execute("""
                CREATE INDEX IF NOT EXISTS events_session_source_kind_index
                ON events(session_id, source, kind)
                """)
            }
        }

        if !appliedVersions.contains(6) {
            try await applyMigration(version: 6) {
                try await database.execute("""
                CREATE TABLE IF NOT EXISTS pomodoro_blocks (
                    id TEXT PRIMARY KEY NOT NULL,
                    session_id TEXT NOT NULL,
                    block_index INTEGER NOT NULL,
                    planned_duration_seconds INTEGER NOT NULL,
                    intention TEXT,
                    summary TEXT,
                    status TEXT NOT NULL CHECK (
                        status IN ('active', 'paused', 'completed', 'interrupted')
                    ),
                    started_at TEXT NOT NULL,
                    paused_at TEXT,
                    accumulated_pause_seconds INTEGER NOT NULL,
                    ended_at TEXT,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    FOREIGN KEY(session_id) REFERENCES sessions(id) ON DELETE CASCADE
                )
                """)

                try await database.execute("""
                CREATE UNIQUE INDEX IF NOT EXISTS pomodoro_blocks_session_index_unique
                ON pomodoro_blocks(session_id, block_index)
                """)

                try await database.execute("""
                CREATE UNIQUE INDEX IF NOT EXISTS pomodoro_blocks_one_open_per_session
                ON pomodoro_blocks(session_id)
                WHERE status IN ('active', 'paused')
                """)

                try await database.execute("""
                CREATE INDEX IF NOT EXISTS pomodoro_blocks_session_started_index
                ON pomodoro_blocks(session_id, started_at ASC)
                """)

                try await database.execute("""
                CREATE TABLE IF NOT EXISTS work_increments (
                    id TEXT PRIMARY KEY NOT NULL,
                    block_id TEXT NOT NULL,
                    occurred_at TEXT NOT NULL,
                    kind TEXT NOT NULL CHECK (
                        kind IN ('note', 'decision', 'blocker')
                    ),
                    title TEXT NOT NULL,
                    detail TEXT,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    FOREIGN KEY(block_id) REFERENCES pomodoro_blocks(id) ON DELETE CASCADE
                )
                """)

                try await database.execute("""
                CREATE INDEX IF NOT EXISTS work_increments_block_time_index
                ON work_increments(block_id, occurred_at ASC)
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
