import Foundation
import SQLite3

struct SettingsRepository {
    let database: Database

    func loadLMStudioSettings() async throws -> LMStudioSettings {
        let baseURLString = try await value(for: .lmStudioBaseURL)
            ?? LMStudioSettings.defaultBaseURLString
        let selectedModelID = try await value(for: .lmStudioSynthesizerModel) ?? ""

        return LMStudioSettings(
            baseURLString: baseURLString,
            selectedModelID: selectedModelID
        )
    }

    func saveLMStudioSettings(_ settings: LMStudioSettings) async throws {
        let normalizedSettings = try settings.normalized()
        let updatedAt = try DateCoding.now()

        try await database.withTransaction { database in
            try setValue(
                normalizedSettings.baseURLString,
                for: .lmStudioBaseURL,
                updatedAt: updatedAt,
                using: database
            )
            try setValue(
                normalizedSettings.selectedModelID,
                for: .lmStudioSynthesizerModel,
                updatedAt: updatedAt,
                using: database
            )
        }
    }

    func value(for key: SettingsKey) async throws -> String? {
        try await database.query("""
        SELECT value
        FROM app_settings
        WHERE key = ?
        LIMIT 1
        """, bind: { statement in
            try SQLiteValue.bind(key.rawValue, to: statement, at: 1)
        }, map: { statement in
            SQLiteValue.text(statement, at: 0)
        })
        .first
    }

    func setValue(_ value: String, for key: SettingsKey) async throws {
        let updatedAt = try DateCoding.now()
        try await database.withTransaction { database in
            try setValue(value, for: key, updatedAt: updatedAt, using: database)
        }
    }

    private func setValue(
        _ value: String,
        for key: SettingsKey,
        updatedAt: Date,
        using database: isolated Database
    ) throws {
        try database.execute("""
        INSERT INTO app_settings(key, value, updated_at)
        VALUES(?, ?, ?)
        ON CONFLICT(key) DO UPDATE SET
            value = excluded.value,
            updated_at = excluded.updated_at
        """) { statement in
            try SQLiteValue.bind(key.rawValue, to: statement, at: 1)
            try SQLiteValue.bind(value, to: statement, at: 2)
            try SQLiteValue.bind(DateCoding.string(from: updatedAt), to: statement, at: 3)
        }
    }
}

enum SettingsKey: String, CaseIterable {
    case lmStudioBaseURL = "lmstudio_base_url"
    case lmStudioSynthesizerModel = "lmstudio_synthesizer_model"
}
