import XCTest
@testable import WorkingMemorySnapshot

final class PomodoroBlockRepositoryTests: XCTestCase {
    private var temporaryURLs: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryURLs {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryURLs.removeAll()
    }

    func testCreateNextBlockStoresDefaultDurationAndIndex() async throws {
        let harness = try makeHarness()
        try await harness.migrator.migrate()
        let project = try await harness.projectRepository.createProject(
            at: makeTemporaryDirectory(named: "BlockProject")
        )
        let session = try await harness.sessionRepository.createActiveSession(
            projectID: project.id,
            mission: "Create focus blocks"
        )

        let block = try await harness.blockRepository.createNextBlock(
            sessionID: session.id,
            intention: "Setup"
        )

        XCTAssertEqual(block.sessionID, session.id)
        XCTAssertEqual(block.blockIndex, 1)
        XCTAssertEqual(block.plannedDurationSeconds, 1_200)
        XCTAssertEqual(block.status, .active)
        XCTAssertEqual(block.intention, "Setup")
    }

    func testOnlyOneOpenBlockExistsPerSession() async throws {
        let harness = try makeHarness()
        try await harness.migrator.migrate()
        let project = try await harness.projectRepository.createProject(
            at: makeTemporaryDirectory(named: "OpenBlockProject")
        )
        let session = try await harness.sessionRepository.createActiveSession(
            projectID: project.id,
            mission: "Reject overlapping blocks"
        )

        _ = try await harness.blockRepository.createNextBlock(sessionID: session.id)

        await XCTAssertThrowsAsyncError({
            try await harness.blockRepository.createNextBlock(sessionID: session.id)
        }) { error in
            XCTAssertEqual(error as? PomodoroBlockRepositoryError, .openBlockAlreadyExists)
        }
    }

    func testPauseResumeAndCompletePersistBlockState() async throws {
        let harness = try makeHarness()
        try await harness.migrator.migrate()
        let project = try await harness.projectRepository.createProject(
            at: makeTemporaryDirectory(named: "PauseProject")
        )
        let session = try await harness.sessionRepository.createActiveSession(
            projectID: project.id,
            mission: "Pause a block"
        )
        let block = try await harness.blockRepository.createNextBlock(sessionID: session.id)

        let paused = try await harness.blockRepository.pauseBlock(id: block.id)
        XCTAssertEqual(paused.status, .paused)
        XCTAssertNotNil(paused.pausedAt)

        let resumed = try await harness.blockRepository.resumeBlock(id: block.id)
        XCTAssertEqual(resumed.status, .active)
        XCTAssertNil(resumed.pausedAt)

        let completed = try await harness.blockRepository.completeBlock(
            id: block.id,
            summary: "Finished setup."
        )
        XCTAssertEqual(completed.status, .completed)
        XCTAssertEqual(completed.summary, "Finished setup.")
        XCTAssertNotNil(completed.endedAt)
    }

    func testWorkIncrementPersistsInsideActiveSessionBlock() async throws {
        let harness = try makeHarness()
        try await harness.migrator.migrate()
        let project = try await harness.projectRepository.createProject(
            at: makeTemporaryDirectory(named: "IncrementProject")
        )
        let session = try await harness.sessionRepository.createActiveSession(
            projectID: project.id,
            mission: "Store a decision"
        )
        let block = try await harness.blockRepository.createNextBlock(sessionID: session.id)

        let increment = try await harness.incrementRepository.addIncrement(
            blockID: block.id,
            kind: .decision,
            title: "Keep events generic",
            detail: "Do not add tool-specific tables."
        )

        let stored = try await harness.incrementRepository.listIncrements(for: block.id)
        XCTAssertEqual(stored, [increment])
        XCTAssertEqual(stored.first?.kind, .decision)
    }

    func testWorkIncrementRejectsCompletedBlock() async throws {
        let harness = try makeHarness()
        try await harness.migrator.migrate()
        let project = try await harness.projectRepository.createProject(
            at: makeTemporaryDirectory(named: "ClosedIncrementProject")
        )
        let session = try await harness.sessionRepository.createActiveSession(
            projectID: project.id,
            mission: "Reject stale increments"
        )
        let block = try await harness.blockRepository.createNextBlock(sessionID: session.id)
        _ = try await harness.blockRepository.completeBlock(id: block.id, summary: nil)

        await XCTAssertThrowsAsyncError({
            try await harness.incrementRepository.addIncrement(
                blockID: block.id,
                kind: .note,
                title: "Too late"
            )
        }) { error in
            XCTAssertEqual(error as? WorkIncrementRepositoryError, .blockNotOpen)
        }
    }

    func testProjectDeletionCascadesBlocksIncrementsEventsAndSnapshots() async throws {
        let harness = try makeHarness()
        try await harness.migrator.migrate()
        let project = try await harness.projectRepository.createProject(
            at: makeTemporaryDirectory(named: "CascadeProject")
        )
        let session = try await harness.sessionRepository.createActiveSession(
            projectID: project.id,
            mission: "Verify cascading delete"
        )
        let block = try await harness.blockRepository.createNextBlock(sessionID: session.id)
        _ = try await harness.incrementRepository.addIncrement(
            blockID: block.id,
            kind: .note,
            title: "A note"
        )
        try await harness.eventRepository.insertEvent(
            SessionEvent(
                sessionID: session.id,
                source: .file,
                kind: SessionEventKind.fileChanged,
                title: "README.md"
            )
        )
        _ = try await harness.blockRepository.completeBlock(id: block.id, summary: nil)
        let completedSession = try await harness.sessionRepository.completeSession(
            id: session.id,
            brainDump: "Done."
        )
        _ = try await harness.snapshotRepository.saveOrReplaceSnapshot(
            SnapshotDraft(
                whatChanged: "Cascade setup.",
                decisions: [],
                openLoops: [],
                nextAction: "Delete the project.",
                resumeBrief: "Cascade data should be removed.",
                generatorModel: "test",
                promptVersion: "test"
            ),
            for: completedSession.id
        )

        try await harness.projectRepository.deleteProject(id: project.id)

        let deletedSession = try await harness.sessionRepository.session(for: session.id)
        let remainingBlocks = try await harness.blockRepository.listBlocks(for: session.id)
        let remainingIncrements = try await harness.incrementRepository.listIncrements(for: block.id)
        let remainingEvents = try await harness.eventRepository.listEvents(for: session.id)
        let deletedSnapshot = try await harness.snapshotRepository.snapshot(for: completedSession.id)

        XCTAssertNil(deletedSession)
        XCTAssertEqual(remainingBlocks, [])
        XCTAssertEqual(remainingIncrements, [])
        XCTAssertEqual(remainingEvents, [])
        XCTAssertNil(deletedSnapshot)
    }

    private func makeHarness() throws -> (
        database: Database,
        migrator: DatabaseMigrator,
        projectRepository: ProjectRepository,
        sessionRepository: SessionRepository,
        blockRepository: PomodoroBlockRepository,
        incrementRepository: WorkIncrementRepository,
        eventRepository: EventRepository,
        snapshotRepository: SnapshotRepository
    ) {
        let rootDirectory = try makeTemporaryDirectory(named: "DatabaseRoot")
        let database = Database(url: rootDirectory.appendingPathComponent("working-memory.sqlite3"))
        let migrator = DatabaseMigrator(database: database)
        return (
            database,
            migrator,
            ProjectRepository(database: database),
            SessionRepository(database: database),
            PomodoroBlockRepository(database: database),
            WorkIncrementRepository(database: database),
            EventRepository(database: database),
            SnapshotRepository(database: database)
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
