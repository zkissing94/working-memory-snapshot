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
        XCTAssertEqual(viewModel.projectAccessState(for: project.id), .accessible)

        try FileManager.default.removeItem(at: projectFolder)
        await viewModel.checkProjectAccess(for: project)
        XCTAssertEqual(viewModel.projectAccessState(for: project.id), .inaccessible)
    }

    func testRepositoryLoaderBuildsLightweightDashboardSummary() async throws {
        let harness = try makeHarness()
        try await harness.migrator.migrate()
        let project = try await harness.projectRepository.createProject(
            at: makeTemporaryDirectory(named: "SummaryProject")
        )
        let session = try await harness.sessionRepository.createActiveSession(
            projectID: project.id,
            mission: "Keep project switching immediate"
        )
        let block = try await harness.pomodoroBlockRepository.createNextBlock(sessionID: session.id)
        _ = try await harness.pomodoroBlockRepository.completeBlock(id: block.id, summary: "Cached the summary")
        _ = try await harness.sessionRepository.completeSession(id: session.id, brainDump: "The cache is local.")
        let snapshot = try await harness.snapshotRepository.saveOrReplaceSnapshot(
            snapshotDraft(resumeBrief: "Resume the cached project summary."),
            for: session.id
        )
        let otherProject = try await harness.projectRepository.createProject(
            at: makeTemporaryDirectory(named: "OtherSummaryProject")
        )
        for index in 1...2 {
            let otherSession = try await harness.sessionRepository.createActiveSession(
                projectID: otherProject.id,
                mission: "Other project session \(index)"
            )
            let otherBlock = try await harness.pomodoroBlockRepository.createNextBlock(
                sessionID: otherSession.id
            )
            _ = try await harness.pomodoroBlockRepository.completeBlock(
                id: otherBlock.id,
                summary: "Other project block"
            )
            _ = try await harness.sessionRepository.completeSession(
                id: otherSession.id,
                brainDump: "This belongs to another project."
            )
        }
        let viewModel = makeViewModel(harness: harness)

        await viewModel.loadSummary(for: project.id)

        let summary = try XCTUnwrap(viewModel.summary(for: project.id))
        XCTAssertEqual(summary.latestSnapshot, snapshot)
        XCTAssertEqual(summary.latestSnapshotSession?.id, session.id)
        XCTAssertEqual(summary.completedSessionCount, 1)
        XCTAssertEqual(summary.completedBlockCount, 1)
        XCTAssertNil(viewModel.history(for: project.id))
    }

    func testCachedSummaryIsProjectScopedAndDoesNotReload() async throws {
        let firstProjectID = UUID()
        let secondProjectID = UUID()
        let firstSummary = summary(projectID: firstProjectID, resumeBrief: "First project memory")
        let secondSummary = summary(projectID: secondProjectID, resumeBrief: "Second project memory")
        let loader = StaticProjectDetailLoader(
            summaries: [firstProjectID: firstSummary, secondProjectID: secondSummary],
            histories: [
                firstProjectID: emptyHistory(projectID: firstProjectID),
                secondProjectID: emptyHistory(projectID: secondProjectID)
            ]
        )
        let viewModel = ProjectDetailViewModel(loader: loader)

        await viewModel.loadSummary(for: firstProjectID)

        XCTAssertEqual(viewModel.summary(for: firstProjectID), firstSummary)
        XCTAssertNil(viewModel.summary(for: secondProjectID))

        await viewModel.loadSummary(for: firstProjectID)
        let cachedCallCount = await loader.summaryCallCount(for: firstProjectID)
        XCTAssertEqual(cachedCallCount, 1)

        await viewModel.loadSummary(for: secondProjectID)
        XCTAssertEqual(viewModel.summary(for: secondProjectID), secondSummary)
        XCTAssertEqual(viewModel.summary(for: firstProjectID), firstSummary)
    }

    func testSupersededSummaryRequestCannotOverwriteOrClearNewerLoad() async throws {
        let projectID = UUID()
        let loader = ControlledSummaryLoader(projectID: projectID)
        let viewModel = ProjectDetailViewModel(loader: loader)
        let oldSummary = summary(projectID: projectID, resumeBrief: "Old memory")
        let newSummary = summary(projectID: projectID, resumeBrief: "Newest memory")

        let oldRequest = Task { await viewModel.loadSummary(for: projectID, forceRefresh: true) }
        await waitForPendingSummaryRequests(1, loader: loader)
        let newRequest = Task { await viewModel.loadSummary(for: projectID, forceRefresh: true) }
        await waitForPendingSummaryRequests(2, loader: loader)

        await loader.resumeOldestSummary(with: oldSummary)
        await oldRequest.value
        XCTAssertTrue(viewModel.isLoadingSummary(for: projectID))
        XCTAssertNil(viewModel.summary(for: projectID))

        await loader.resumeOldestSummary(with: newSummary)
        await newRequest.value
        XCTAssertFalse(viewModel.isLoadingSummary(for: projectID))
        XCTAssertEqual(viewModel.summary(for: projectID), newSummary)
    }

    func testOutOfOrderProjectLoadsRemainIsolated() async throws {
        let firstProjectID = UUID()
        let secondProjectID = UUID()
        let loader = ControlledProjectLoader()
        let viewModel = ProjectDetailViewModel(loader: loader)
        let firstSummary = summary(projectID: firstProjectID, resumeBrief: "First project memory")
        let secondSummary = summary(projectID: secondProjectID, resumeBrief: "Second project memory")

        let firstRequest = Task { await viewModel.loadSummary(for: firstProjectID) }
        let secondRequest = Task { await viewModel.loadSummary(for: secondProjectID) }
        await waitForPendingSummaryRequest(for: firstProjectID, loader: loader)
        await waitForPendingSummaryRequest(for: secondProjectID, loader: loader)

        await loader.resumeSummary(for: secondProjectID, with: secondSummary)
        await secondRequest.value
        XCTAssertEqual(viewModel.summary(for: secondProjectID), secondSummary)
        XCTAssertNil(viewModel.summary(for: firstProjectID))

        await loader.resumeSummary(for: firstProjectID, with: firstSummary)
        await firstRequest.value
        XCTAssertEqual(viewModel.summary(for: firstProjectID), firstSummary)
        XCTAssertEqual(viewModel.summary(for: secondProjectID), secondSummary)
    }

    func testOutOfOrderHistoryLoadsRemainIsolated() async throws {
        let firstProjectID = UUID()
        let secondProjectID = UUID()
        let firstSession = session(projectID: firstProjectID)
        let secondSession = session(projectID: secondProjectID)
        let firstSnapshot = snapshot(sessionID: firstSession.id, resumeBrief: "First project memory")
        let secondSnapshot = snapshot(sessionID: secondSession.id, resumeBrief: "Second project memory")
        let firstHistory = history(session: firstSession, snapshot: firstSnapshot)
        let secondHistory = history(session: secondSession, snapshot: secondSnapshot)
        let loader = ControlledProjectLoader()
        let viewModel = ProjectDetailViewModel(loader: loader)

        let firstRequest = Task { await viewModel.loadHistory(for: firstProjectID) }
        let secondRequest = Task { await viewModel.loadHistory(for: secondProjectID) }
        await waitForPendingHistoryRequest(for: firstProjectID, loader: loader)
        await waitForPendingHistoryRequest(for: secondProjectID, loader: loader)

        await loader.resumeHistory(for: secondProjectID, with: secondHistory)
        await secondRequest.value
        XCTAssertEqual(viewModel.history(for: secondProjectID), secondHistory)
        XCTAssertNil(viewModel.history(for: firstProjectID))

        await loader.resumeHistory(for: firstProjectID, with: firstHistory)
        await firstRequest.value
        XCTAssertEqual(viewModel.history(for: firstProjectID), firstHistory)
        XCTAssertEqual(viewModel.history(for: secondProjectID), secondHistory)
    }

    func testRemovingProjectDuringLoadPreventsLateRepopulation() async throws {
        let projectID = UUID()
        let summary = summary(projectID: projectID, resumeBrief: "Removed project memory")
        let loader = ControlledProjectLoader()
        let viewModel = ProjectDetailViewModel(loader: loader)

        let request = Task { await viewModel.loadSummary(for: projectID) }
        await waitForPendingSummaryRequest(for: projectID, loader: loader)

        viewModel.retainProjects([])
        await loader.resumeSummary(for: projectID, with: summary)
        await request.value

        XCTAssertNil(viewModel.summary(for: projectID))
        XCTAssertFalse(viewModel.isLoadingSummary(for: projectID))
    }

    func testMismatchedProjectResultsAreRejected() async throws {
        let requestedProjectID = UUID()
        let wrongProjectID = UUID()
        let loader = StaticProjectDetailLoader(
            summaries: [
                requestedProjectID: summary(
                    projectID: wrongProjectID,
                    resumeBrief: "Wrong project memory"
                )
            ],
            histories: [requestedProjectID: emptyHistory(projectID: wrongProjectID)]
        )
        let viewModel = ProjectDetailViewModel(loader: loader)

        await viewModel.loadSummary(for: requestedProjectID)

        XCTAssertNil(viewModel.summary(for: requestedProjectID))
        XCTAssertNotNil(viewModel.errorMessage)

        viewModel.clearError()
        await viewModel.loadHistory(for: requestedProjectID)

        XCTAssertNil(viewModel.history(for: requestedProjectID))
        XCTAssertNotNil(viewModel.errorMessage)
    }

    func testHistoryWithForeignNestedSessionIsRejected() async throws {
        let requestedProjectID = UUID()
        let foreignSession = session(projectID: UUID())
        let invalidHistory = ProjectHistory(
            projectID: requestedProjectID,
            sessions: [foreignSession],
            snapshotsBySessionID: [:],
            blocksBySessionID: [:],
            incrementsByBlockID: [:],
            eventsBySessionID: [:]
        )
        let loader = StaticProjectDetailLoader(
            summaries: [
                requestedProjectID: summary(
                    projectID: requestedProjectID,
                    resumeBrief: "Requested project memory"
                )
            ],
            histories: [requestedProjectID: invalidHistory]
        )
        let viewModel = ProjectDetailViewModel(loader: loader)

        await viewModel.loadHistory(for: requestedProjectID)

        XCTAssertNil(viewModel.history(for: requestedProjectID))
        XCTAssertNotNil(viewModel.errorMessage)
    }

    func testResetNavigationClearsOnlyTargetProject() async throws {
        let firstProjectID = UUID()
        let secondProjectID = UUID()
        let firstSession = session(projectID: firstProjectID)
        let secondSession = session(projectID: secondProjectID)
        let firstSnapshot = snapshot(sessionID: firstSession.id, resumeBrief: "First project memory")
        let secondSnapshot = snapshot(sessionID: secondSession.id, resumeBrief: "Second project memory")
        let loader = StaticProjectDetailLoader(
            summaries: [
                firstProjectID: summary(
                    projectID: firstProjectID,
                    session: firstSession,
                    snapshot: firstSnapshot
                ),
                secondProjectID: summary(
                    projectID: secondProjectID,
                    session: secondSession,
                    snapshot: secondSnapshot
                )
            ],
            histories: [
                firstProjectID: history(session: firstSession, snapshot: firstSnapshot),
                secondProjectID: history(session: secondSession, snapshot: secondSnapshot)
            ]
        )
        let viewModel = ProjectDetailViewModel(loader: loader)
        await viewModel.loadProject(for: firstProjectID)
        await viewModel.loadProject(for: secondProjectID)
        viewModel.selectSession(firstSession, for: firstProjectID)
        viewModel.presentLatestSnapshot(for: firstProjectID)
        viewModel.selectSession(secondSession, for: secondProjectID)
        viewModel.presentLatestSnapshot(for: secondProjectID)

        viewModel.resetNavigation(for: firstProjectID)

        XCTAssertNil(viewModel.presentedSnapshot(for: firstProjectID))
        XCTAssertNil(viewModel.selectedSessionID(for: firstProjectID))
        XCTAssertEqual(viewModel.presentedSnapshot(for: secondProjectID), secondSnapshot)
        XCTAssertEqual(viewModel.selectedSessionID(for: secondProjectID), secondSession.id)
        XCTAssertNil(viewModel.snapshot(for: secondSession, projectID: firstProjectID))
        XCTAssertEqual(viewModel.blocks(for: secondSession, projectID: firstProjectID), [])
        XCTAssertEqual(viewModel.events(for: secondSession, projectID: firstProjectID), [])
    }

    func testGeneratedSnapshotRefreshAndProjectRemovalAffectOnlyTargetCache() async throws {
        let firstProjectID = UUID()
        let secondProjectID = UUID()
        let firstSummary = summary(projectID: firstProjectID, resumeBrief: "First project memory")
        let secondSummary = summary(projectID: secondProjectID, resumeBrief: "Second project memory")
        let loader = StaticProjectDetailLoader(
            summaries: [firstProjectID: firstSummary, secondProjectID: secondSummary],
            histories: [
                firstProjectID: emptyHistory(projectID: firstProjectID),
                secondProjectID: emptyHistory(projectID: secondProjectID)
            ]
        )
        let viewModel = ProjectDetailViewModel(loader: loader)
        await viewModel.loadProject(for: firstProjectID)
        await viewModel.loadProject(for: secondProjectID)
        let generatedSnapshot = snapshot(sessionID: UUID(), resumeBrief: "Fresh generated memory")

        viewModel.presentGeneratedSnapshot(generatedSnapshot, for: firstProjectID)

        XCTAssertEqual(viewModel.summary(for: firstProjectID)?.latestSnapshot, generatedSnapshot)
        XCTAssertEqual(viewModel.summary(for: secondProjectID), secondSummary)

        await viewModel.refreshProject(firstProjectID)
        let firstProjectCallCount = await loader.summaryCallCount(for: firstProjectID)
        let secondProjectCallCount = await loader.summaryCallCount(for: secondProjectID)
        XCTAssertEqual(firstProjectCallCount, 2)
        XCTAssertEqual(secondProjectCallCount, 1)

        viewModel.removeProject(firstProjectID)
        XCTAssertNil(viewModel.summary(for: firstProjectID))
        XCTAssertNil(viewModel.history(for: firstProjectID))
        XCTAssertNil(viewModel.presentedSnapshot(for: firstProjectID))
        XCTAssertEqual(viewModel.summary(for: secondProjectID), secondSummary)
    }

    private func makeViewModel(harness: (
        database: Database,
        migrator: DatabaseMigrator,
        projectRepository: ProjectRepository,
        sessionRepository: SessionRepository,
        pomodoroBlockRepository: PomodoroBlockRepository,
        workIncrementRepository: WorkIncrementRepository,
        eventRepository: EventRepository,
        snapshotRepository: SnapshotRepository
    )) -> ProjectDetailViewModel {
        ProjectDetailViewModel(
            snapshotRepository: harness.snapshotRepository,
            sessionRepository: harness.sessionRepository,
            pomodoroBlockRepository: harness.pomodoroBlockRepository,
            workIncrementRepository: harness.workIncrementRepository,
            eventRepository: harness.eventRepository
        )
    }

    private func summary(projectID: Project.ID, resumeBrief: String) -> ProjectDashboardSummary {
        let session = session(projectID: projectID)
        let snapshot = snapshot(sessionID: session.id, resumeBrief: resumeBrief)
        return summary(projectID: projectID, session: session, snapshot: snapshot)
    }

    private func summary(
        projectID: Project.ID,
        session: WorkSession,
        snapshot: Snapshot
    ) -> ProjectDashboardSummary {
        ProjectDashboardSummary(
            projectID: projectID,
            latestSnapshot: snapshot,
            latestSnapshotSession: session,
            completedSessionCount: 1,
            completedBlockCount: 1
        )
    }

    private func history(session: WorkSession, snapshot: Snapshot) -> ProjectHistory {
        ProjectHistory(
            projectID: session.projectID,
            sessions: [session],
            snapshotsBySessionID: [session.id: snapshot],
            blocksBySessionID: [session.id: []],
            incrementsByBlockID: [:],
            eventsBySessionID: [session.id: []]
        )
    }

    private func emptyHistory(projectID: Project.ID) -> ProjectHistory {
        ProjectHistory(
            projectID: projectID,
            sessions: [],
            snapshotsBySessionID: [:],
            blocksBySessionID: [:],
            incrementsByBlockID: [:],
            eventsBySessionID: [:]
        )
    }

    private func snapshot(sessionID: WorkSession.ID, resumeBrief: String) -> Snapshot {
        Snapshot(
            id: UUID(),
            sessionID: sessionID,
            whatChanged: "Project switching is immediate.",
            decisions: [],
            openLoops: [],
            nextAction: "Switch projects without stale content.",
            resumeBrief: resumeBrief,
            generatorModel: "test-model",
            promptVersion: "test-v1",
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    private func session(projectID: Project.ID) -> WorkSession {
        let now = Date()
        return WorkSession(
            id: UUID(),
            projectID: projectID,
            mission: "Keep project memory isolated",
            brainDump: "This memory belongs only to its project.",
            startedAt: now.addingTimeInterval(-60),
            endedAt: now,
            status: .completed,
            createdAt: now.addingTimeInterval(-60),
            updatedAt: now
        )
    }

    private func snapshotDraft(resumeBrief: String) -> SnapshotDraft {
        SnapshotDraft(
            whatChanged: "Project switching is immediate.",
            decisions: [],
            openLoops: [],
            nextAction: "Switch projects without stale content.",
            resumeBrief: resumeBrief,
            generatorModel: "test-model",
            promptVersion: "test-v1"
        )
    }

    private func waitForPendingSummaryRequests(
        _ expectedCount: Int,
        loader: ControlledSummaryLoader
    ) async {
        for _ in 0..<100 {
            if await loader.pendingSummaryCount == expectedCount {
                return
            }
            await Task.yield()
        }
        XCTFail("Expected \(expectedCount) pending summary requests")
    }

    private func waitForPendingSummaryRequest(
        for projectID: Project.ID,
        loader: ControlledProjectLoader
    ) async {
        for _ in 0..<100 {
            if await loader.hasPendingSummary(for: projectID) {
                return
            }
            await Task.yield()
        }
        XCTFail("Expected a pending summary request for \(projectID)")
    }

    private func waitForPendingHistoryRequest(
        for projectID: Project.ID,
        loader: ControlledProjectLoader
    ) async {
        for _ in 0..<100 {
            if await loader.hasPendingHistory(for: projectID) {
                return
            }
            await Task.yield()
        }
        XCTFail("Expected a pending history request for \(projectID)")
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

private actor StaticProjectDetailLoader: ProjectDetailLoading {
    let summaries: [Project.ID: ProjectDashboardSummary]
    let histories: [Project.ID: ProjectHistory]
    private var summaryCalls: [Project.ID: Int] = [:]

    init(
        summaries: [Project.ID: ProjectDashboardSummary],
        histories: [Project.ID: ProjectHistory]
    ) {
        self.summaries = summaries
        self.histories = histories
    }

    func loadSummary(for projectID: Project.ID) async throws -> ProjectDashboardSummary {
        summaryCalls[projectID, default: 0] += 1
        return try XCTUnwrap(summaries[projectID])
    }

    func loadHistory(for projectID: Project.ID) async throws -> ProjectHistory {
        try XCTUnwrap(histories[projectID])
    }

    func summaryCallCount(for projectID: Project.ID) -> Int {
        summaryCalls[projectID, default: 0]
    }
}

private actor ControlledSummaryLoader: ProjectDetailLoading {
    let projectID: Project.ID
    private var summaryContinuations: [CheckedContinuation<ProjectDashboardSummary, Error>] = []

    init(projectID: Project.ID) {
        self.projectID = projectID
    }

    var pendingSummaryCount: Int {
        summaryContinuations.count
    }

    func loadSummary(for projectID: Project.ID) async throws -> ProjectDashboardSummary {
        try await withCheckedThrowingContinuation { continuation in
            summaryContinuations.append(continuation)
        }
    }

    func loadHistory(for projectID: Project.ID) async throws -> ProjectHistory {
        ProjectHistory(
            projectID: projectID,
            sessions: [],
            snapshotsBySessionID: [:],
            blocksBySessionID: [:],
            incrementsByBlockID: [:],
            eventsBySessionID: [:]
        )
    }

    func resumeOldestSummary(with summary: ProjectDashboardSummary) {
        summaryContinuations.removeFirst().resume(returning: summary)
    }
}

private actor ControlledProjectLoader: ProjectDetailLoading {
    private var summaryContinuations: [
        Project.ID: CheckedContinuation<ProjectDashboardSummary, Error>
    ] = [:]
    private var historyContinuations: [
        Project.ID: CheckedContinuation<ProjectHistory, Error>
    ] = [:]

    func loadSummary(for projectID: Project.ID) async throws -> ProjectDashboardSummary {
        try await withCheckedThrowingContinuation { continuation in
            summaryContinuations[projectID] = continuation
        }
    }

    func loadHistory(for projectID: Project.ID) async throws -> ProjectHistory {
        try await withCheckedThrowingContinuation { continuation in
            historyContinuations[projectID] = continuation
        }
    }

    func hasPendingSummary(for projectID: Project.ID) -> Bool {
        summaryContinuations[projectID] != nil
    }

    func resumeSummary(
        for projectID: Project.ID,
        with summary: ProjectDashboardSummary
    ) {
        summaryContinuations.removeValue(forKey: projectID)?.resume(returning: summary)
    }

    func hasPendingHistory(for projectID: Project.ID) -> Bool {
        historyContinuations[projectID] != nil
    }

    func resumeHistory(
        for projectID: Project.ID,
        with history: ProjectHistory
    ) {
        historyContinuations.removeValue(forKey: projectID)?.resume(returning: history)
    }
}
