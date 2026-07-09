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
            pomodoroBlockRepository: harness.pomodoroBlockRepository,
            workIncrementRepository: harness.workIncrementRepository,
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
            pomodoroBlockRepository: harness.pomodoroBlockRepository,
            workIncrementRepository: harness.workIncrementRepository,
            snapshotGenerator: FakeSessionSnapshotGenerator(snapshotRepository: harness.snapshotRepository),
            observationCoordinator: observationCoordinator
        )

        viewModel.beginStartSession(for: project)
        viewModel.mission = "Make the lifecycle usable"
        await viewModel.startSession(for: project)

        XCTAssertEqual(viewModel.activeSession?.projectID, project.id)
        XCTAssertEqual(viewModel.activeBlock?.blockIndex, 1)
        XCTAssertEqual(viewModel.activeBlock?.plannedDurationSeconds, 1_200)
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
        let blocks = try await harness.pomodoroBlockRepository.listBlocks(for: completed.id)
        XCTAssertEqual(blocks.first?.status, .interrupted)
    }

    func testInvalidChatCompletionEnvelopeShowsFriendlySnapshotErrorAndPreservesRetrySession() async throws {
        let harness = try makeHarness()
        try await harness.migrator.migrate()
        let project = try await harness.projectRepository.createProject(
            at: makeTemporaryDirectory(named: "InvalidEnvelopeProject")
        )
        let viewModel = SessionViewModel(
            sessionRepository: harness.sessionRepository,
            projectRepository: harness.projectRepository,
            pomodoroBlockRepository: harness.pomodoroBlockRepository,
            workIncrementRepository: harness.workIncrementRepository,
            snapshotGenerator: FailingSessionSnapshotGenerator(
                error: LMStudioGenerationError.invalidChatCompletionEnvelope
            ),
            observationCoordinator: RecordingSessionObservationCoordinator()
        )

        viewModel.beginStartSession(for: project)
        viewModel.mission = "Save the session before generation"
        await viewModel.startSession(for: project)
        viewModel.beginEndingActiveSession()
        viewModel.brainDump = "The session should remain retryable after a malformed model response."

        await viewModel.completeActiveSession()

        let latestCompleted = try await harness.sessionRepository.latestCompletedSession(for: project.id)
        let completed = try XCTUnwrap(latestCompleted)
        XCTAssertNil(viewModel.activeSession)
        XCTAssertEqual(completed.status, .completed)
        XCTAssertEqual(
            completed.brainDump,
            "The session should remain retryable after a malformed model response."
        )
        XCTAssertEqual(viewModel.failedSnapshotSession?.id, completed.id)
        XCTAssertEqual(
            viewModel.errorMessage,
            """
            The selected model did not return a valid snapshot.

            Your session and brain dump are saved. Try again or select another model.
            """
        )
    }

    func testCompletingBlockAllowsNextBlockWithoutEndingSession() async throws {
        let harness = try makeHarness()
        try await harness.migrator.migrate()
        let project = try await harness.projectRepository.createProject(
            at: makeTemporaryDirectory(named: "BlockFlowProject")
        )
        let viewModel = SessionViewModel(
            sessionRepository: harness.sessionRepository,
            projectRepository: harness.projectRepository,
            pomodoroBlockRepository: harness.pomodoroBlockRepository,
            workIncrementRepository: harness.workIncrementRepository,
            snapshotGenerator: FakeSessionSnapshotGenerator(snapshotRepository: harness.snapshotRepository),
            observationCoordinator: RecordingSessionObservationCoordinator()
        )

        viewModel.beginStartSession(for: project)
        viewModel.mission = "Capture blocks"
        await viewModel.startSession(for: project)
        let firstBlockID = try XCTUnwrap(viewModel.activeBlock?.id)

        await viewModel.completeCurrentBlock(summary: "Setup complete.")

        XCTAssertNotNil(viewModel.activeSession)
        XCTAssertNil(viewModel.activeBlock)
        let completedBlock = try await harness.pomodoroBlockRepository.block(for: firstBlockID)
        XCTAssertEqual(completedBlock?.status, .completed)
        XCTAssertEqual(completedBlock?.summary, "Setup complete.")

        await viewModel.startNextBlock(intention: "Implement next step")

        XCTAssertEqual(viewModel.activeBlock?.blockIndex, 2)
        XCTAssertEqual(viewModel.activeBlock?.intention, "Implement next step")
        XCTAssertEqual(viewModel.sessionBlocks.count, 2)
    }

    func testTakeBreakLeavesSessionActiveWithNoOpenBlock() async throws {
        let harness = try makeHarness()
        try await harness.migrator.migrate()
        let project = try await harness.projectRepository.createProject(
            at: makeTemporaryDirectory(named: "BreakProject")
        )
        let viewModel = SessionViewModel(
            sessionRepository: harness.sessionRepository,
            projectRepository: harness.projectRepository,
            pomodoroBlockRepository: harness.pomodoroBlockRepository,
            workIncrementRepository: harness.workIncrementRepository,
            snapshotGenerator: FakeSessionSnapshotGenerator(snapshotRepository: harness.snapshotRepository),
            observationCoordinator: RecordingSessionObservationCoordinator()
        )

        viewModel.beginStartSession(for: project)
        viewModel.mission = "Pause between blocks"
        await viewModel.startSession(for: project)
        await viewModel.completeCurrentBlock(summary: nil)

        XCTAssertNotNil(viewModel.activeSession)
        XCTAssertNil(viewModel.activeBlock)
        let activeSessionID = try XCTUnwrap(viewModel.activeSession?.id)
        let openBlock = try await harness.pomodoroBlockRepository.openBlock(for: activeSessionID)
        XCTAssertNil(openBlock)
    }

    func testManualIncrementIsAddedToActiveBlock() async throws {
        let harness = try makeHarness()
        try await harness.migrator.migrate()
        let project = try await harness.projectRepository.createProject(
            at: makeTemporaryDirectory(named: "IncrementProject")
        )
        let viewModel = SessionViewModel(
            sessionRepository: harness.sessionRepository,
            projectRepository: harness.projectRepository,
            pomodoroBlockRepository: harness.pomodoroBlockRepository,
            workIncrementRepository: harness.workIncrementRepository,
            snapshotGenerator: FakeSessionSnapshotGenerator(snapshotRepository: harness.snapshotRepository),
            observationCoordinator: RecordingSessionObservationCoordinator()
        )

        viewModel.beginStartSession(for: project)
        viewModel.mission = "Capture manual decisions"
        await viewModel.startSession(for: project)

        await viewModel.addIncrement(
            kind: .decision,
            title: "Blocks live inside sessions",
            detail: "Do not duplicate passive events."
        )

        XCTAssertEqual(viewModel.activeBlockIncrements.count, 1)
        XCTAssertEqual(viewModel.activeBlockIncrements.first?.kind, .decision)
        XCTAssertEqual(viewModel.activeBlockIncrements.first?.title, "Blocks live inside sessions")
    }

    func testStartSessionSchedulesFocusBlockDeadline() async throws {
        let harness = try makeHarness()
        try await harness.migrator.migrate()
        let project = try await harness.projectRepository.createProject(
            at: makeTemporaryDirectory(named: "DeadlineProject")
        )
        let deadlineAlertService = RecordingFocusBlockDeadlineAlertService()
        let viewModel = SessionViewModel(
            sessionRepository: harness.sessionRepository,
            projectRepository: harness.projectRepository,
            pomodoroBlockRepository: harness.pomodoroBlockRepository,
            workIncrementRepository: harness.workIncrementRepository,
            snapshotGenerator: FakeSessionSnapshotGenerator(snapshotRepository: harness.snapshotRepository),
            observationCoordinator: RecordingSessionObservationCoordinator(),
            focusBlockDeadlineAlertService: deadlineAlertService
        )

        viewModel.beginStartSession(for: project)
        viewModel.mission = "Schedule block deadline"
        await viewModel.startSession(for: project)

        let activeBlock = try XCTUnwrap(viewModel.activeBlock)
        XCTAssertEqual(deadlineAlertService.scheduledBlocks.map(\.id), [activeBlock.id])
        XCTAssertEqual(deadlineAlertService.cancelAllCallCount, 0)
    }

    func testPauseResumeAndCompletionManageFocusBlockDeadline() async throws {
        let harness = try makeHarness()
        try await harness.migrator.migrate()
        let project = try await harness.projectRepository.createProject(
            at: makeTemporaryDirectory(named: "DeadlineLifecycleProject")
        )
        let deadlineAlertService = RecordingFocusBlockDeadlineAlertService()
        let viewModel = SessionViewModel(
            sessionRepository: harness.sessionRepository,
            projectRepository: harness.projectRepository,
            pomodoroBlockRepository: harness.pomodoroBlockRepository,
            workIncrementRepository: harness.workIncrementRepository,
            snapshotGenerator: FakeSessionSnapshotGenerator(snapshotRepository: harness.snapshotRepository),
            observationCoordinator: RecordingSessionObservationCoordinator(),
            focusBlockDeadlineAlertService: deadlineAlertService
        )

        viewModel.beginStartSession(for: project)
        viewModel.mission = "Cancel and reschedule deadlines"
        await viewModel.startSession(for: project)
        let blockID = try XCTUnwrap(viewModel.activeBlock?.id)

        await viewModel.pauseCurrentBlock()

        XCTAssertEqual(deadlineAlertService.cancelledBlockIDs, [blockID])
        XCTAssertEqual(viewModel.activeBlock?.status, .paused)

        await viewModel.resumeCurrentBlock()

        XCTAssertEqual(deadlineAlertService.scheduledBlocks.map(\.id), [blockID, blockID])

        await viewModel.completeCurrentBlock(summary: "Deadline lifecycle works.")

        XCTAssertEqual(deadlineAlertService.cancelledBlockIDs, [blockID, blockID])
        XCTAssertNil(viewModel.activeBlock)
    }

    func testExpiredDeadlinePromptsWithoutCompletingBlockUntilConfirmed() async throws {
        let harness = try makeHarness()
        try await harness.migrator.migrate()
        let project = try await harness.projectRepository.createProject(
            at: makeTemporaryDirectory(named: "DeadlinePromptProject")
        )
        let deadlineAlertService = RecordingFocusBlockDeadlineAlertService()
        let viewModel = SessionViewModel(
            sessionRepository: harness.sessionRepository,
            projectRepository: harness.projectRepository,
            pomodoroBlockRepository: harness.pomodoroBlockRepository,
            workIncrementRepository: harness.workIncrementRepository,
            snapshotGenerator: FakeSessionSnapshotGenerator(snapshotRepository: harness.snapshotRepository),
            observationCoordinator: RecordingSessionObservationCoordinator(),
            focusBlockDeadlineAlertService: deadlineAlertService
        )

        viewModel.beginStartSession(for: project)
        viewModel.mission = "Prompt after deadline"
        await viewModel.startSession(for: project)
        let blockID = try XCTUnwrap(viewModel.activeBlock?.id)

        deadlineAlertService.triggerDeadline(for: blockID)

        XCTAssertEqual(viewModel.blockCompletionPrompt?.block.id, blockID)
        let storedBeforeConfirmation = try await harness.pomodoroBlockRepository.block(for: blockID)
        XCTAssertEqual(storedBeforeConfirmation?.status, .active)

        await viewModel.completePromptedBlock(summary: "Notification and in-app prompt wired.")

        let storedAfterConfirmation = try await harness.pomodoroBlockRepository.block(for: blockID)
        XCTAssertEqual(storedAfterConfirmation?.status, .completed)
        XCTAssertEqual(storedAfterConfirmation?.summary, "Notification and in-app prompt wired.")
        XCTAssertNil(viewModel.blockCompletionPrompt)
        XCTAssertNil(viewModel.activeBlock)
    }

    func testReturningToExpiredBlockDoesNotRepeatPromptForSameBlock() async throws {
        let harness = try makeHarness()
        try await harness.migrator.migrate()
        let project = try await harness.projectRepository.createProject(
            at: makeTemporaryDirectory(named: "DismissedDeadlineProject")
        )
        let deadlineAlertService = RecordingFocusBlockDeadlineAlertService()
        let viewModel = SessionViewModel(
            sessionRepository: harness.sessionRepository,
            projectRepository: harness.projectRepository,
            pomodoroBlockRepository: harness.pomodoroBlockRepository,
            workIncrementRepository: harness.workIncrementRepository,
            snapshotGenerator: FakeSessionSnapshotGenerator(snapshotRepository: harness.snapshotRepository),
            observationCoordinator: RecordingSessionObservationCoordinator(),
            focusBlockDeadlineAlertService: deadlineAlertService
        )

        viewModel.beginStartSession(for: project)
        viewModel.mission = "Dismiss one deadline prompt"
        await viewModel.startSession(for: project)
        let blockID = try XCTUnwrap(viewModel.activeBlock?.id)

        deadlineAlertService.triggerDeadline(for: blockID)
        XCTAssertNotNil(viewModel.blockCompletionPrompt)

        viewModel.dismissBlockCompletionPrompt()
        deadlineAlertService.triggerDeadline(for: blockID)

        XCTAssertNil(viewModel.blockCompletionPrompt)
        XCTAssertEqual(deadlineAlertService.cancelledBlockIDs, [blockID])
        let storedBlock = try await harness.pomodoroBlockRepository.block(for: blockID)
        XCTAssertEqual(storedBlock?.status, .active)
    }

    func testRecoveredExpiredBlockPromptsAfterResume() async throws {
        let harness = try makeHarness()
        try await harness.migrator.migrate()
        let project = try await harness.projectRepository.createProject(
            at: makeTemporaryDirectory(named: "ExpiredRecoveryProject")
        )
        let session = try await harness.sessionRepository.createActiveSession(
            projectID: project.id,
            mission: "Recover an expired block"
        )
        let expiredBlock = try await insertExpiredActiveBlock(
            sessionID: session.id,
            in: harness.database
        )
        let deadlineAlertService = RecordingFocusBlockDeadlineAlertService()
        deadlineAlertService.triggersExpiredBlocksOnSchedule = true
        let viewModel = SessionViewModel(
            sessionRepository: harness.sessionRepository,
            projectRepository: harness.projectRepository,
            pomodoroBlockRepository: harness.pomodoroBlockRepository,
            workIncrementRepository: harness.workIncrementRepository,
            snapshotGenerator: FakeSessionSnapshotGenerator(snapshotRepository: harness.snapshotRepository),
            observationCoordinator: RecordingSessionObservationCoordinator(),
            focusBlockDeadlineAlertService: deadlineAlertService
        )

        await viewModel.loadActiveSessionForRecovery()
        XCTAssertNil(viewModel.blockCompletionPrompt)

        viewModel.resumeRecoveredSession()
        await waitForBlockCompletionPrompt(in: viewModel)

        XCTAssertEqual(viewModel.blockCompletionPrompt?.block.id, expiredBlock.id)
        let storedBlock = try await harness.pomodoroBlockRepository.block(for: expiredBlock.id)
        XCTAssertEqual(storedBlock?.status, .active)
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
            pomodoroBlockRepository: harness.pomodoroBlockRepository,
            workIncrementRepository: harness.workIncrementRepository,
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
            pomodoroBlockRepository: harness.pomodoroBlockRepository,
            workIncrementRepository: harness.workIncrementRepository,
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

    private func insertExpiredActiveBlock(
        sessionID: WorkSession.ID,
        in database: Database
    ) async throws -> PomodoroBlock {
        let now = try DateCoding.now()
        let startedAt = now.addingTimeInterval(-120)
        let blockID = UUID()
        try await database.execute("""
        INSERT INTO pomodoro_blocks(
            id,
            session_id,
            block_index,
            planned_duration_seconds,
            intention,
            summary,
            status,
            started_at,
            paused_at,
            accumulated_pause_seconds,
            ended_at,
            created_at,
            updated_at
        )
        VALUES(?, ?, 1, 1, NULL, NULL, ?, ?, NULL, 0, NULL, ?, ?)
        """) { statement in
            try SQLiteValue.bind(blockID.uuidString, to: statement, at: 1)
            try SQLiteValue.bind(sessionID.uuidString, to: statement, at: 2)
            try SQLiteValue.bind(PomodoroBlockStatus.active.rawValue, to: statement, at: 3)
            try SQLiteValue.bind(DateCoding.string(from: startedAt), to: statement, at: 4)
            try SQLiteValue.bind(DateCoding.string(from: now), to: statement, at: 5)
            try SQLiteValue.bind(DateCoding.string(from: now), to: statement, at: 6)
        }

        return PomodoroBlock(
            id: blockID,
            sessionID: sessionID,
            blockIndex: 1,
            plannedDurationSeconds: 1,
            intention: nil,
            summary: nil,
            status: .active,
            startedAt: startedAt,
            pausedAt: nil,
            accumulatedPauseSeconds: 0,
            endedAt: nil,
            createdAt: now,
            updatedAt: now
        )
    }

    private func waitForBlockCompletionPrompt(
        in viewModel: SessionViewModel,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<100 {
            if viewModel.blockCompletionPrompt != nil {
                return
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Expected a block completion prompt.", file: file, line: line)
    }

    private func makeHarness() throws -> (
        database: Database,
        migrator: DatabaseMigrator,
        projectRepository: ProjectRepository,
        sessionRepository: SessionRepository,
        pomodoroBlockRepository: PomodoroBlockRepository,
        workIncrementRepository: WorkIncrementRepository,
        snapshotRepository: SnapshotRepository
    ) {
        let rootDirectory = try makeTemporaryDirectory(named: "DatabaseRoot")
        let database = Database(url: rootDirectory.appendingPathComponent("working-memory.sqlite3"))
        let migrator = DatabaseMigrator(database: database)
        let projectRepository = ProjectRepository(database: database)
        let sessionRepository = SessionRepository(database: database)
        let pomodoroBlockRepository = PomodoroBlockRepository(database: database)
        let workIncrementRepository = WorkIncrementRepository(database: database)
        let snapshotRepository = SnapshotRepository(database: database)

        return (
            database,
            migrator,
            projectRepository,
            sessionRepository,
            pomodoroBlockRepository,
            workIncrementRepository,
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

private struct FailingSessionSnapshotGenerator: SessionSnapshotGenerating {
    let error: Error

    func generateSnapshot(for project: Project, session: WorkSession) async throws -> Snapshot {
        throw error
    }
}

@MainActor
private final class RecordingFocusBlockDeadlineAlertService: FocusBlockDeadlineAlerting {
    var onDeadlineReached: (@MainActor @Sendable (PomodoroBlock.ID) -> Void)?
    var triggersExpiredBlocksOnSchedule = false

    private(set) var scheduledBlocks: [PomodoroBlock] = []
    private(set) var cancelledBlockIDs: [PomodoroBlock.ID] = []
    private(set) var cancelAllCallCount = 0

    func scheduleDeadline(for block: PomodoroBlock) {
        scheduledBlocks.append(block)
        if triggersExpiredBlocksOnSchedule, block.remainingSeconds() == 0 {
            onDeadlineReached?(block.id)
        }
    }

    func cancelDeadline(for blockID: PomodoroBlock.ID) {
        cancelledBlockIDs.append(blockID)
    }

    func cancelAllDeadlines() {
        cancelAllCallCount += 1
    }

    func triggerDeadline(for blockID: PomodoroBlock.ID) {
        onDeadlineReached?(blockID)
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
