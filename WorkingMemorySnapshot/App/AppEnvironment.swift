import Foundation

struct AppEnvironment {
    let databaseMigrator: DatabaseMigrator
    let projectRepository: ProjectRepository
    let sessionRepository: SessionRepository
    let snapshotRepository: SnapshotRepository
    let settingsRepository: SettingsRepository
    let tokenStore: any LMStudioTokenStore
    let lmStudioHTTPTransport: any LMStudioHTTPTransport

    static func live() -> AppEnvironment {
        let database = Database(url: applicationSupportDatabaseURL())

        return AppEnvironment(
            databaseMigrator: DatabaseMigrator(database: database),
            projectRepository: ProjectRepository(database: database),
            sessionRepository: SessionRepository(database: database),
            snapshotRepository: SnapshotRepository(database: database),
            settingsRepository: SettingsRepository(database: database),
            tokenStore: KeychainStore(),
            lmStudioHTTPTransport: URLSessionLMStudioHTTPTransport()
        )
    }

    private static func applicationSupportDatabaseURL() -> URL {
        let baseURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser

        return baseURL
            .appendingPathComponent("WorkingMemorySnapshot", isDirectory: true)
            .appendingPathComponent("working-memory.sqlite3", isDirectory: false)
    }
}
