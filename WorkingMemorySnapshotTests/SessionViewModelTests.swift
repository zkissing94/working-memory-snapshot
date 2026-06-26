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
            snapshotGenerator: FakeSessionSnapshotGenerator(snapshotRepository: harness.snapshotRepository),
            observationCoordinator: RecordingSessionObservationCoordinator()
        )
        viewModel.mission = "Start only when the folder is reachable"

        await viewModel.startSession(for: project)

        XCTAssertNil(viewModel.activeSession)
        XCTAssertEqual(
            viewModel.errorMessage,
            "This project folder is no longer accessible. Choose the folder again to restore access."
        )
        let activeSession = try await harness.sessionRepository.activeSession()
        XCTAssertNil(activeSession)
    }

    func testStartAndCompleteSessionThroughViewModel() async throws {
        let harness = try makeHarness()
        try await harness.migrator.migrate()
        let project = try await harness.projectRepository.createProject(
            at: makeTemporaryDirectory(named: "ViewModelProject")
        )
        let observationCoordinator = RecordingSessionObservationCoordinator()
        let viewModel = SessionViewModel(
            sessionRepository: harness.sessionRepository,
            projectRepository: harness.projectRepository,
            snapshotGenerator: FakeSessionSnapshotGenerator(snapshotRepository: harness.snapshotRepository),
            observationCoordinator: observationCoordinator
        )

        viewModel.beginStartSession(for: project)
        viewModel.mission = "Make the lifecycle usable"
        await viewModel.startSession(for: project)

        XCTAssertEqual(viewModel.activeSession?.projectID, project.id)
        XCTAssertEqual(viewModel.flow, .idle)
        XCTAssertEqual(observationCoordinator.startCallCount, 1)

        viewModel.beginEndingActiveSession()
        viewModel.brainDump = "Next: wire grounded snapshots."
        await viewModel.completeActiveSession()

        let latestCompleted = try await harness.sessionRepository.latestCompletedSession(for: project.id)
        let completed = try XCTUnwrap(latestCompleted)
        XCTAssertNil(viewModel.activeSession)
        XCTAssertEqual(completed.brainDump, "Next: wire grounded snapshots.")
        XCTAssertEqual(completed.status, .completed)
        let storedSnapshot = try await harness.snapshotRepository.snapshot(for: completed.id)
        let snapshot = try XCTUnwrap(storedSnapshot)
        XCTAssertEqual(snapshot.generatorModel, "fake-model")
        XCTAssertEqual(snapshot.nextAction, "Review generated snapshot wiring.")
        XCTAssertEqual(viewModel.generatedSnapshotContext?.snapshot, snapshot)
        XCTAssertEqual(observationCoordinator.completedBrainDump, "Next: wire grounded snapshots.")
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
            snapshotGenerator: FakeSessionSnapshotGenerator(snapshotRepository: harness.snapshotRepository),
            observationCoordinator: RecordingSessionObservationCoordinator()
        )

        await viewModel.loadActiveSessionForRecovery()

        XCTAssertEqual(viewModel.activeSession, session)
        XCTAssertEqual(viewModel.recoveryContext?.session, session)
        XCTAssertEqual(viewModel.recoveryContext?.project, project)
        XCTAssertEqual(viewModel.recoveryContext?.isProjectFolderAccessible, true)

        viewModel.resumeRecoveredSession()
        XCTAssertNil(viewModel.recoveryContext)
        XCTAssertEqual(viewModel.activeSession, session)
    }

    func testLoadActiveSessionMarksMissingFolderInRecoveryContext() async throws {
        let harness = try makeHarness()
        try await harness.migrator.migrate()
        let projectFolder = try makeTemporaryDirectory(named: "MissingRecoveryProject")
        let project = try await harness.projectRepository.createProject(at: projectFolder)
        let session = try await harness.sessionRepository.createActiveSession(
            projectID: project.id,
            mission: "Recover only after folder access is restored"
        )
        try FileManager.default.removeItem(at: projectFolder)
        let viewModel = SessionViewModel(
            sessionRepository: harness.sessionRepository,
            projectRepository: harness.projectRepository,
            snapshotGenerator: FakeSessionSnapshotGenerator(snapshotRepository: harness.snapshotRepository),
            observationCoordinator: RecordingSessionObservationCoordinator()
        )

        await viewModel.loadActiveSessionForRecovery()

        XCTAssertEqual(viewModel.activeSession, session)
        XCTAssertEqual(viewModel.recoveryContext?.isProjectFolderAccessible, false)

        viewModel.resumeRecoveredSession()

        XCTAssertNotNil(viewModel.recoveryContext)
        XCTAssertEqual(
            viewModel.errorMessage,
            "This project folder is no longer accessible. Choose the folder again to restore access."
        )
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

private struct FakeSessionSnapshotGenerator: SessionSnapshotGenerating {
    let snapshotRepository: SnapshotRepository

    func generateSnapshot(for project: Project, session: WorkSession) async throws -> Snapshot {
        try await snapshotRepository.saveOrReplaceSnapshot(
            SnapshotDraft(
                whatChanged: "Grounded generation returned a fake test snapshot.",
                decisions: [],
                openLoops: [],
                nextAction: "Review generated snapshot wiring.",
                resumeBrief: "A fake snapshot confirms the view model calls the generator after completion.",
                generatorModel: "fake-model",
                promptVersion: PromptBuilder.promptVersion
            ),
            for: session.id
        )
    }
}

@MainActor
private final class RecordingSessionObservationCoordinator: SessionObservationCoordinating {
    var onSummaryChange: (@MainActor (ObservationSessionSummary) -> Void)?
    private(set) var startCallCount = 0
    private(set) var completionStopCallCount = 0
    private(set) var cancellationStopCallCount = 0
    private(set) var completedBrainDump: String?

    func startObserving(session: WorkSession, project: Project) async {
        startCallCount += 1
        onSummaryChange?(
            ObservationSessionSummary(
                changedFileCount: 1,
                droppedFileChangeCount: 0,
                activeApplicationNames: ["Terminal"],
                isGitRepository: true,
                notes: []
            )
        )
    }

    func stopObservingForCompletion(session: WorkSession, brainDump: String) async {
        completionStopCallCount += 1
        completedBrainDump = brainDump
    }

    func stopObservingForCancellation(session: WorkSession) async {
        cancellationStopCallCount += 1
    }
}
