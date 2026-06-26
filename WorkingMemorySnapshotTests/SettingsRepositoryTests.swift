import XCTest
@testable import WorkingMemorySnapshot

final class SettingsRepositoryTests: XCTestCase {
    private var temporaryURLs: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryURLs {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryURLs.removeAll()
    }

    func testMigrationCreatesDefaultSettings() async throws {
        let harness = try makeHarness()

        try await harness.migrator.migrate()

        let settings = try await harness.repository.loadLMStudioSettings()
        let promptVersion = try await harness.repository.value(for: .snapshotPromptVersion)

        XCTAssertEqual(settings, .defaults)
        XCTAssertEqual(promptVersion, "v1")
    }

    func testSettingsPersistAcrossRepositoryReload() async throws {
        let rootDirectory = try makeTemporaryDirectory(named: "DatabaseRoot")
        let databaseURL = rootDirectory.appendingPathComponent("working-memory.sqlite3")

        let firstDatabase = Database(url: databaseURL)
        let firstMigrator = DatabaseMigrator(database: firstDatabase)
        let firstRepository = SettingsRepository(database: firstDatabase)
        try await firstMigrator.migrate()
        try await firstRepository.saveLMStudioSettings(
            LMStudioSettings(
                baseURLString: "http://localhost:1234/v1///",
                selectedModelID: "local-model"
            )
        )

        let secondDatabase = Database(url: databaseURL)
        let secondMigrator = DatabaseMigrator(database: secondDatabase)
        let secondRepository = SettingsRepository(database: secondDatabase)
        try await secondMigrator.migrate()

        let settings = try await secondRepository.loadLMStudioSettings()
        XCTAssertEqual(settings.baseURLString, "http://localhost:1234/v1")
        XCTAssertEqual(settings.selectedModelID, "local-model")
    }

    private func makeHarness() throws -> (database: Database, migrator: DatabaseMigrator, repository: SettingsRepository) {
        let rootDirectory = try makeTemporaryDirectory(named: "DatabaseRoot")
        let database = Database(url: rootDirectory.appendingPathComponent("working-memory.sqlite3"))
        let migrator = DatabaseMigrator(database: database)
        let repository = SettingsRepository(database: database)

        return (database, migrator, repository)
    }

    private func makeTemporaryDirectory(named name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkingMemorySnapshotTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)

        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        temporaryURLs.append(url.deletingLastPathComponent())
        return url
    }
}
