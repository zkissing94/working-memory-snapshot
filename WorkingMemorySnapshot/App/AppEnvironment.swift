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
    let dailyRollupRepository: DailyRollupRepository
    let dailyRollupSourceLoader: DailyRollupSourceLoader
    let dailyRollupGenerator: any DailyRollupGenerating
    let tokenStore: any LMStudioTokenStore
    let lmStudioHTTPTransport: any LMStudioHTTPTransport
    let observationCoordinator: ObservationCoordinator
    let snapshotGenerator: any SessionSnapshotGenerating
    let focusBlockDeadlineAlertService: any FocusBlockDeadlineAlerting

    @MainActor
    static func live() -> AppEnvironment {
        let database = Database(url: applicationSupportDatabaseURL())
        let pomodoroBlockRepository = PomodoroBlockRepository(database: database)
        let workIncrementRepository = WorkIncrementRepository(database: database)
        let eventRepository = EventRepository(database: database)
        let snapshotRepository = SnapshotRepository(database: database)
        let settingsRepository = SettingsRepository(database: database)
        let projectRepository = ProjectRepository(database: database)
        let sessionRepository = SessionRepository(database: database)
        let dailyRollupRepository = DailyRollupRepository(database: database)
        let tokenStore = KeychainStore()
        let transport = URLSessionLMStudioHTTPTransport()

        return AppEnvironment(
            databaseMigrator: DatabaseMigrator(database: database),
            projectRepository: projectRepository,
            sessionRepository: sessionRepository,
            pomodoroBlockRepository: pomodoroBlockRepository,
            workIncrementRepository: workIncrementRepository,
            eventRepository: eventRepository,
            snapshotRepository: snapshotRepository,
            settingsRepository: settingsRepository,
            dailyRollupRepository: dailyRollupRepository,
            dailyRollupSourceLoader: DailyRollupSourceLoader(
                projectRepository: projectRepository,
                sessionRepository: sessionRepository,
                snapshotRepository: snapshotRepository,
                pomodoroBlockRepository: pomodoroBlockRepository,
                workIncrementRepository: workIncrementRepository
            ),
            dailyRollupGenerator: DailyRollupGenerator(
                repository: dailyRollupRepository,
                settingsRepository: settingsRepository,
                tokenStore: tokenStore,
                transport: transport
            ),
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
            ),
            focusBlockDeadlineAlertService: FocusBlockDeadlineAlertService()
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
