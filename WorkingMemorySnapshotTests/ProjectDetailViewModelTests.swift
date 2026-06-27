import XCTest
@testable import WorkingMemorySnapshot

@MainActor
final class ProjectDetailViewModelTests: XCTestCase {
    private var temporaryURLs: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryURLs {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryURLs.removeAll()
    }

    func testCheckProjectAccessReportsAccessibleAndMissingFolders() async throws {
        let harness = try makeHarness()
        try await harness.migrator.migrate()
        let projectFolder = try makeTemporaryDirectory(named: "AccessProject")
        let project = try await harness.projectRepository.createProject(at: projectFolder)
        let viewModel = ProjectDetailViewModel(
            snapshotRepository: harness.snapshotRepository,
            sessionRepository: harness.sessionRepository,
            pomodoroBlockRepository: harness.pomodoroBlockRepository,
            workIncrementRepository: harness.workIncrementRepository,
            eventRepository: harness.eventRepository
        )

        await viewModel.checkProjectAccess(for: project)
        XCTAssertEqual(viewModel.projectAccessState, .accessible)

        try FileManager.default.removeItem(at: projectFolder)
        await viewModel.checkProjectAccess(for: project)
        XCTAssertEqual(viewModel.projectAccessState, .inaccessible)
    }

    private func makeHarness() throws -> (
        database: Database,
        migrator: DatabaseMigrator,
        projectRepository: ProjectRepository,
        sessionRepository: SessionRepository,
        pomodoroBlockRepository: PomodoroBlockRepository,
        workIncrementRepository: WorkIncrementRepository,
        eventRepository: EventRepository,
        snapshotRepository: SnapshotRepository
    ) {
        let rootDirectory = try makeTemporaryDirectory(named: "DatabaseRoot")
        let database = Database(url: rootDirectory.appendingPathComponent("working-memory.sqlite3"))
        let migrator = DatabaseMigrator(database: database)
        let projectRepository = ProjectRepository(database: database)
        let sessionRepository = SessionRepository(database: database)
        let pomodoroBlockRepository = PomodoroBlockRepository(database: database)
        let workIncrementRepository = WorkIncrementRepository(database: database)
        let eventRepository = EventRepository(database: database)
        let snapshotRepository = SnapshotRepository(database: database)

        return (
            database,
            migrator,
            projectRepository,
            sessionRepository,
            pomodoroBlockRepository,
            workIncrementRepository,
            eventRepository,
            snapshotRepository
        )
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
