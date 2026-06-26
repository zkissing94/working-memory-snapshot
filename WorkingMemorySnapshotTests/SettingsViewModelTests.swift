import XCTest
@testable import WorkingMemorySnapshot

@MainActor
final class SettingsViewModelTests: XCTestCase {
    private var temporaryURLs: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryURLs {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryURLs.removeAll()
    }

    func testSavePersistsSettingsButNotTokenInSQLite() async throws {
        let harness = try makeHarness()
        try await harness.migrator.migrate()
        let tokenStore = InMemoryLMStudioTokenStore()
        let viewModel = SettingsViewModel(
            repository: harness.settingsRepository,
            tokenStore: tokenStore,
            transport: MockLMStudioHTTPTransport.success(body: #"{"data":[{"id":"model-a"}]}"#)
        )
        let token = "test-token-\(UUID().uuidString)"

        viewModel.baseURLString = "http://localhost:1234/v1/"
        viewModel.selectedModelID = "model-a"
        viewModel.apiToken = token
        await viewModel.saveSettings()

        let values = try await harness.database.query("""
        SELECT key || '=' || value
        FROM app_settings
        ORDER BY key ASC
        """) { statement in
            SQLiteValue.text(statement, at: 0)
        }

        let savedToken = try await tokenStore.loadToken()
        XCTAssertEqual(savedToken, token)
        XCTAssertFalse(values.joined(separator: "\n").contains(token))
        XCTAssertEqual(viewModel.connectionState, .saved)
    }

    func testConnectionStateErrorsAreDistinct() async throws {
        let cases: [(MockLMStudioHTTPTransport, LMStudioConnectionState)] = [
            (
                MockLMStudioHTTPTransport.failure(URLError(.cannotConnectToHost)),
                .serverUnreachable
            ),
            (
                MockLMStudioHTTPTransport.response(statusCode: 401, body: "{}"),
                .unauthorized
            ),
            (
                MockLMStudioHTTPTransport.success(body: #"{"data":[]}"#),
                .noModels
            ),
            (
                MockLMStudioHTTPTransport.success(body: #"{"unexpected":true}"#),
                .invalidResponse
            )
        ]

        for (transport, expectedState) in cases {
            let harness = try makeHarness()
            try await harness.migrator.migrate()
            let viewModel = SettingsViewModel(
                repository: harness.settingsRepository,
                tokenStore: InMemoryLMStudioTokenStore(),
                transport: transport
            )

            await viewModel.testConnection()

            XCTAssertEqual(viewModel.connectionState, expectedState)
        }
    }

    private func makeHarness() throws -> (
        database: Database,
        migrator: DatabaseMigrator,
        settingsRepository: SettingsRepository
    ) {
        let rootDirectory = try makeTemporaryDirectory(named: "DatabaseRoot")
        let database = Database(url: rootDirectory.appendingPathComponent("working-memory.sqlite3"))
        let migrator = DatabaseMigrator(database: database)
        let settingsRepository = SettingsRepository(database: database)

        return (database, migrator, settingsRepository)
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

actor InMemoryLMStudioTokenStore: LMStudioTokenStore {
    private var token: String?

    func loadToken() async throws -> String? {
        token
    }

    func saveToken(_ token: String?) async throws {
        let trimmedToken = token?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.token = trimmedToken.isEmpty ? nil : trimmedToken
    }

    func deleteToken() async throws {
        token = nil
    }
}
