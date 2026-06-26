import XCTest
@testable import WorkingMemorySnapshot

@MainActor
final class SessionViewModelTests: XCTestCase {
    private var temporaryURLs: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryURLs {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryURLs.removeAll()
    }

    func testStartSessionRejectsMissingProjectFolder() async throws {
        let harness = try makeHarness()
        try await harness.migrator.migrate()
        let projectFolder = try makeTemporaryDirectory(named: "MissingProject")
        let project = try await harness.projectRepository.createProject(at: projectFolder)
        try FileManager.default.removeItem(at: projectFolder)

        let viewModel = SessionViewModel(
            sessionRepository: harness.sessionRepository,
            projectRepository: harness.projectRepository,
            snapshotRepository: harness.snapshotRepository
        )
        viewModel.mission = "Start only when the folder is reachable"

        await viewModel.startSession(for: project)

        XCTAssertNil(viewModel.activeSession)
        XCTAssertEqual(viewModel.errorMessage, "This project folder is no longer accessible.")
        let activeSession = try await harness.sessionRepository.activeSession()
        XCTAssertNil(activeSession)
    }

    func testStartAndCompleteSessionThroughViewModel() async throws {
        let harness = try makeHarness()
        try await harness.migrator.migrate()
        let project = try await harness.projectRepository.createProject(
            at: makeTemporaryDirectory(named: "ViewModelProject")
        )
        let viewModel = SessionViewModel(
            sessionRepository: harness.sessionRepository,
            projectRepository: harness.projectRepository,
            snapshotRepository: harness.snapshotRepository
        )

        viewModel.beginStartSession(for: project)
        viewModel.mission = "Make the lifecycle usable"
        await viewModel.startSession(for: project)

        XCTAssertEqual(viewModel.activeSession?.projectID, project.id)
        XCTAssertEqual(viewModel.flow, .idle)

        viewModel.beginEndingActiveSession()
        viewModel.brainDump = "Next: wire placeholder snapshots."
        await viewModel.completeActiveSession()

        let latestCompleted = try await harness.sessionRepository.latestCompletedSession(for: project.id)
        let completed = try XCTUnwrap(latestCompleted)
        XCTAssertNil(viewModel.activeSession)
        XCTAssertEqual(completed.brainDump, "Next: wire placeholder snapshots.")
        XCTAssertEqual(completed.status, .completed)
        let storedSnapshot = try await harness.snapshotRepository.snapshot(for: completed.id)
        let snapshot = try XCTUnwrap(storedSnapshot)
        XCTAssertEqual(snapshot.decisions, [])
        XCTAssertEqual(snapshot.nextAction, "wire placeholder snapshots")
        XCTAssertEqual(viewModel.generatedSnapshotContext?.snapshot, snapshot)
    }

    func testLoadActiveSessionCreatesRecoveryContext() async throws {
        let harness = try makeHarness()
        try await harness.migrator.migrate()
        let project = try await harness.projectRepository.createProject(
            at: makeTemporaryDirectory(named: "RecoveryProject")
        )
        let session = try await harness.sessionRepository.createActiveSession(
            projectID: project.id,
            mission: "Recover on launch"
        )
        let viewModel = SessionViewModel(
            sessionRepository: harness.sessionRepository,
            projectRepository: harness.projectRepository,
            snapshotRepository: harness.snapshotRepository
        )

        await viewModel.loadActiveSessionForRecovery()

        XCTAssertEqual(viewModel.activeSession, session)
        XCTAssertEqual(viewModel.recoveryContext?.session, session)
        XCTAssertEqual(viewModel.recoveryContext?.project, project)

        viewModel.resumeRecoveredSession()
        XCTAssertNil(viewModel.recoveryContext)
        XCTAssertEqual(viewModel.activeSession, session)
    }

    private func makeHarness() throws -> (
        database: Database,
        migrator: DatabaseMigrator,
        projectRepository: ProjectRepository,
        sessionRepository: SessionRepository,
        snapshotRepository: SnapshotRepository
    ) {
        let rootDirectory = try makeTemporaryDirectory(named: "DatabaseRoot")
        let database = Database(url: rootDirectory.appendingPathComponent("working-memory.sqlite3"))
        let migrator = DatabaseMigrator(database: database)
        let projectRepository = ProjectRepository(database: database)
        let sessionRepository = SessionRepository(database: database)
        let snapshotRepository = SnapshotRepository(database: database)

        return (database, migrator, projectRepository, sessionRepository, snapshotRepository)
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
