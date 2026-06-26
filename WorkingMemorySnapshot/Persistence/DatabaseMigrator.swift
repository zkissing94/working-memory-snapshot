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

        let appliedVersions = try await appliedVersions()
        guard !appliedVersions.contains(1) else {
            return
        }

        try await database.execute("BEGIN IMMEDIATE TRANSACTION")
        do {
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

            try await database.execute("""
            INSERT INTO schema_migrations(version, applied_at)
            VALUES(1, ?)
            """) { statement in
                try SQLiteValue.bind(DateCoding.string(from: Date()), to: statement, at: 1)
            }

            try await database.execute("COMMIT")
        } catch {
            try? await database.execute("ROLLBACK")
            throw error
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
