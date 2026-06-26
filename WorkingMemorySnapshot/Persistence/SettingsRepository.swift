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

        try await setValue(
            normalizedSettings.baseURLString,
            for: .lmStudioBaseURL
        )
        try await setValue(
            normalizedSettings.selectedModelID,
            for: .lmStudioSynthesizerModel
        )
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
        try await database.execute("""
        INSERT INTO app_settings(key, value, updated_at)
        VALUES(?, ?, ?)
        ON CONFLICT(key) DO UPDATE SET
            value = excluded.value,
            updated_at = excluded.updated_at
        """) { statement in
            try SQLiteValue.bind(key.rawValue, to: statement, at: 1)
            try SQLiteValue.bind(value, to: statement, at: 2)
            try SQLiteValue.bind(DateCoding.string(from: Date()), to: statement, at: 3)
        }
    }
}

enum SettingsKey: String, CaseIterable {
    case lmStudioBaseURL = "lmstudio_base_url"
    case lmStudioSynthesizerModel = "lmstudio_synthesizer_model"
    case snapshotPromptVersion = "snapshot_prompt_version"
}
