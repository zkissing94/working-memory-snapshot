import Foundation

struct AppEnvironment {
    let databaseMigrator: DatabaseMigrator
    let projectRepository: ProjectRepository
    let sessionRepository: SessionRepository
    let pomodoroBlockRepository: PomodoroBlockRepository
    let workIncrementRepository: WorkIncrementRepository
    let eventRepository: EventRepository
    let snapshotRepository: SnapshotRepository
    let settingsRepository: SettingsRepository
    let tokenStore: any LMStudioTokenStore
    let lmStudioHTTPTransport: any LMStudioHTTPTransport
    let observationCoordinator: ObservationCoordinator
    let snapshotGenerator: any SessionSnapshotGenerating

    @MainActor
    static func live() -> AppEnvironment {
        let database = Database(url: applicationSupportDatabaseURL())
        let pomodoroBlockRepository = PomodoroBlockRepository(database: database)
        let workIncrementRepository = WorkIncrementRepository(database: database)
        let eventRepository = EventRepository(database: database)
        let snapshotRepository = SnapshotRepository(database: database)
        let settingsRepository = SettingsRepository(database: database)
        let tokenStore = KeychainStore()
        let transport = URLSessionLMStudioHTTPTransport()

        return AppEnvironment(
            databaseMigrator: DatabaseMigrator(database: database),
            projectRepository: ProjectRepository(database: database),
            sessionRepository: SessionRepository(database: database),
            pomodoroBlockRepository: pomodoroBlockRepository,
            workIncrementRepository: workIncrementRepository,
            eventRepository: eventRepository,
            snapshotRepository: snapshotRepository,
            settingsRepository: settingsRepository,
            tokenStore: tokenStore,
            lmStudioHTTPTransport: transport,
            observationCoordinator: ObservationCoordinator(eventRepository: eventRepository),
            snapshotGenerator: SnapshotGenerator(
                eventRepository: eventRepository,
                pomodoroBlockRepository: pomodoroBlockRepository,
                workIncrementRepository: workIncrementRepository,
                snapshotRepository: snapshotRepository,
                settingsRepository: settingsRepository,
                tokenStore: tokenStore,
                transport: transport
            )
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
