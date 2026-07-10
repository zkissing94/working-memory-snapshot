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
        ProjectDashboardSummary(
            projectID: projectID,
            latestSnapshot: snapshot(sessionID: UUID(), resumeBrief: resumeBrief),
            latestSnapshotSession: nil,
            completedSessionCount: 1,
            completedBlockCount: 1
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
