import XCTest
@testable import WorkingMemorySnapshot

@MainActor
final class ProjectsViewModelTests: XCTestCase {
    private var temporaryURLs: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryURLs {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryURLs.removeAll()
    }

    func testRestoreProjectAccessUpdatesSelectedProjectPath() async throws {
        let harness = try makeHarness()
        let viewModel = ProjectsViewModel(
            repository: harness.repository,
            sessionRepository: harness.sessionRepository,
            snapshotRepository: harness.snapshotRepository,
            migrator: harness.migrator
        )
        let originalFolder = try makeTemporaryDirectory(named: "MovedProject")
        let restoredFolder = try makeTemporaryDirectory(named: "MovedProjectRestored")

        await viewModel.loadProjects()
        await viewModel.addProject(at: originalFolder)
        let project = try XCTUnwrap(viewModel.selectedProject)

        let restoredProject = await viewModel.restoreProjectAccess(for: project, to: restoredFolder)

        XCTAssertEqual(restoredProject?.id, project.id)
        XCTAssertEqual(
            viewModel.selectedProject?.rootPath,
            restoredFolder.standardizedFileURL.resolvingSymlinksInPath().path
        )
        XCTAssertNil(viewModel.errorMessage)
    }

    func testRestoreProjectAccessReportsDuplicatePath() async throws {
        let harness = try makeHarness()
        let viewModel = ProjectsViewModel(
            repository: harness.repository,
            sessionRepository: harness.sessionRepository,
            snapshotRepository: harness.snapshotRepository,
            migrator: harness.migrator
        )
        let firstFolder = try makeTemporaryDirectory(named: "FirstProject")
        let secondFolder = try makeTemporaryDirectory(named: "SecondProject")

        await viewModel.loadProjects()
        await viewModel.addProject(at: firstFolder)
        let firstProject = try XCTUnwrap(viewModel.selectedProject)
        await viewModel.addProject(at: secondFolder)

        let restoredProject = await viewModel.restoreProjectAccess(for: firstProject, to: secondFolder)

        XCTAssertNil(restoredProject)
        XCTAssertEqual(viewModel.errorMessage, "That project is already in the list.")
    }

    func testRenameProjectKeepsProjectReferenceIntact() async throws {
        let harness = try makeHarness()
        let viewModel = ProjectsViewModel(
            repository: harness.repository,
            sessionRepository: harness.sessionRepository,
            snapshotRepository: harness.snapshotRepository,
            migrator: harness.migrator
        )
        let folder = try makeTemporaryDirectory(named: "RenameProject")

        await viewModel.loadProjects()
        await viewModel.addProject(at: folder)
        let originalProject = try XCTUnwrap(viewModel.selectedProject)
        let originalID = originalProject.id
        let originalRoot = originalProject.rootPath

        await viewModel.renameProject(originalProject, to: "Renamed Project")

        let renamedProject = try XCTUnwrap(viewModel.selectedProject)
        XCTAssertEqual(renamedProject.id, originalID)
        XCTAssertEqual(renamedProject.name, "Renamed Project")
        XCTAssertEqual(renamedProject.rootPath, originalRoot)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testRenameProjectRejectsBlankName() async throws {
        let harness = try makeHarness()
        let viewModel = ProjectsViewModel(
            repository: harness.repository,
            sessionRepository: harness.sessionRepository,
            snapshotRepository: harness.snapshotRepository,
            migrator: harness.migrator
        )
        let folder = try makeTemporaryDirectory(named: "RejectRenameProject")

        await viewModel.loadProjects()
        await viewModel.addProject(at: folder)
        let project = try XCTUnwrap(viewModel.selectedProject)

        await viewModel.renameProject(project, to: "   ")

        let currentProject = try XCTUnwrap(viewModel.selectedProject)
        XCTAssertEqual(currentProject.name, project.name)
        XCTAssertEqual(viewModel.errorMessage, "Project name cannot be empty.")
    }

    func testPinningAndReorderingProjectsUpdatesSidebarGroups() async throws {
        let harness = try makeHarness()
        let viewModel = ProjectsViewModel(
            repository: harness.repository,
            sessionRepository: harness.sessionRepository,
            snapshotRepository: harness.snapshotRepository,
            migrator: harness.migrator
        )
        let firstFolder = try makeTemporaryDirectory(named: "FirstProject")
        let secondFolder = try makeTemporaryDirectory(named: "SecondProject")
        let thirdFolder = try makeTemporaryDirectory(named: "ThirdProject")

        await viewModel.loadProjects()
        await viewModel.addProject(at: firstFolder)
        await viewModel.addProject(at: secondFolder)
        await viewModel.addProject(at: thirdFolder)
        let first = try XCTUnwrap(viewModel.projects.first(where: { $0.name == "FirstProject" }))
        let second = try XCTUnwrap(viewModel.projects.first(where: { $0.name == "SecondProject" }))
        let third = try XCTUnwrap(viewModel.projects.first(where: { $0.name == "ThirdProject" }))

        await viewModel.setProjectPinned(second, isPinned: true)
        await viewModel.moveProject(third.id, to: first.id)

        XCTAssertEqual(viewModel.pinnedProjects.map(\.id), [second.id])
        XCTAssertEqual(viewModel.unpinnedProjects.map(\.id), [third.id, first.id])
        XCTAssertNil(viewModel.errorMessage)
    }

    func testProjectSidebarActivityDescribesSessionStates() {
        let projectID = UUID()
        let session = makeWorkSession(projectID: projectID)
        let activeBlock = makePomodoroBlock(sessionID: session.id, blockIndex: 2, status: .active)
        let pausedBlock = makePomodoroBlock(sessionID: session.id, blockIndex: 3, status: .paused)
        let completedBlock = makePomodoroBlock(sessionID: session.id, blockIndex: 1, status: .completed)

        XCTAssertEqual(
            ProjectSidebarActivity.current(
                flow: .starting(projectID),
                activeSession: nil,
                activeBlock: nil,
                sessionBlocks: [],
                recoveryContext: nil,
                failedSnapshotSession: nil,
                selectedProjectID: nil,
                selectedProjectAccessState: .unknown
            ),
            ProjectSidebarActivity(projectID: projectID, message: "Preparing session...", kind: .preparing)
        )
        XCTAssertEqual(
            ProjectSidebarActivity.current(
                flow: .idle,
                activeSession: session,
                activeBlock: activeBlock,
                sessionBlocks: [activeBlock],
                recoveryContext: nil,
                failedSnapshotSession: nil,
                selectedProjectID: nil,
                selectedProjectAccessState: .unknown
            ),
            ProjectSidebarActivity(projectID: projectID, message: "Block 2 active", kind: .activeBlock)
        )
        XCTAssertEqual(
            ProjectSidebarActivity.current(
                flow: .idle,
                activeSession: session,
                activeBlock: pausedBlock,
                sessionBlocks: [pausedBlock],
                recoveryContext: nil,
                failedSnapshotSession: nil,
                selectedProjectID: nil,
                selectedProjectAccessState: .unknown
            ),
            ProjectSidebarActivity(projectID: projectID, message: "Block 3 paused", kind: .pausedBlock)
        )
        XCTAssertEqual(
            ProjectSidebarActivity.current(
                flow: .idle,
                activeSession: session,
                activeBlock: nil,
                sessionBlocks: [completedBlock],
                recoveryContext: nil,
                failedSnapshotSession: nil,
                selectedProjectID: nil,
                selectedProjectAccessState: .unknown
            ),
            ProjectSidebarActivity(projectID: projectID, message: "Between blocks", kind: .betweenBlocks)
        )
        XCTAssertEqual(
            ProjectSidebarActivity.current(
                flow: .ending(session.id),
                activeSession: session,
                activeBlock: activeBlock,
                sessionBlocks: [activeBlock],
                recoveryContext: nil,
                failedSnapshotSession: nil,
                selectedProjectID: nil,
                selectedProjectAccessState: .unknown
            ),
            ProjectSidebarActivity(projectID: projectID, message: "Ending session...", kind: .ending)
        )
    }

    func testProjectSidebarActivityDescribesRecoveryAccessAndSnapshotFailure() {
        let project = makeProject()
        let session = makeWorkSession(projectID: project.id)
        let failedSession = makeWorkSession(projectID: project.id, status: .completed)

        XCTAssertEqual(
            ProjectSidebarActivity.current(
                flow: .starting(UUID()),
                activeSession: nil,
                activeBlock: nil,
                sessionBlocks: [],
                recoveryContext: SessionRecoveryContext(
                    session: session,
                    project: project,
                    isProjectFolderAccessible: true
                ),
                failedSnapshotSession: nil,
                selectedProjectID: nil,
                selectedProjectAccessState: .unknown
            ),
            ProjectSidebarActivity(projectID: project.id, message: "Recovery available", kind: .recovery)
        )
        XCTAssertEqual(
            ProjectSidebarActivity.current(
                flow: .idle,
                activeSession: nil,
                activeBlock: nil,
                sessionBlocks: [],
                recoveryContext: SessionRecoveryContext(
                    session: session,
                    project: project,
                    isProjectFolderAccessible: false
                ),
                failedSnapshotSession: nil,
                selectedProjectID: nil,
                selectedProjectAccessState: .unknown
            ),
            ProjectSidebarActivity(projectID: project.id, message: "Folder missing", kind: .accessLost)
        )
        XCTAssertEqual(
            ProjectSidebarActivity.current(
                flow: .idle,
                activeSession: nil,
                activeBlock: nil,
                sessionBlocks: [],
                recoveryContext: nil,
                failedSnapshotSession: nil,
                selectedProjectID: project.id,
                selectedProjectAccessState: .inaccessible
            ),
            ProjectSidebarActivity(projectID: project.id, message: "Folder missing", kind: .accessLost)
        )
        XCTAssertEqual(
            ProjectSidebarActivity.current(
                flow: .idle,
                activeSession: nil,
                activeBlock: nil,
                sessionBlocks: [],
                recoveryContext: nil,
                failedSnapshotSession: failedSession,
                selectedProjectID: nil,
                selectedProjectAccessState: .unknown
            ),
            ProjectSidebarActivity(projectID: project.id, message: "Snapshot needs attention", kind: .snapshotFailed)
        )
    }

    func testCurrentSessionSummaryIsHiddenWithoutActiveSession() {
        let projectID = UUID()
        let completedSession = makeWorkSession(projectID: projectID, status: .completed)

        XCTAssertNil(
            CurrentSessionSummary.current(
                activeSession: nil,
                activeBlock: nil,
                sessionBlocks: []
            )
        )
        XCTAssertNil(
            CurrentSessionSummary.current(
                activeSession: completedSession,
                activeBlock: nil,
                sessionBlocks: []
            )
        )
    }

    func testCurrentSessionSummaryFormatsActiveBlockTruthfully() throws {
        let projectID = UUID()
        let sessionStart = Date(timeIntervalSince1970: 1_000)
        let now = sessionStart.addingTimeInterval(180)
        let session = makeWorkSession(projectID: projectID, startedAt: sessionStart)
        let completedBlock = makePomodoroBlock(
            sessionID: session.id,
            blockIndex: 1,
            status: .completed,
            startedAt: sessionStart
        )
        let activeBlock = makePomodoroBlock(
            sessionID: session.id,
            blockIndex: 2,
            status: .active,
            startedAt: sessionStart.addingTimeInterval(60)
        )

        let summary = try XCTUnwrap(
            CurrentSessionSummary.current(
                activeSession: session,
                activeBlock: activeBlock,
                sessionBlocks: [completedBlock, activeBlock]
            )
        )

        XCTAssertEqual(summary.status, .active)
        XCTAssertEqual(summary.statusText, "Active")
        XCTAssertEqual(summary.elapsedSessionTimeText(at: now), "03:00")
        XCTAssertEqual(summary.blockRemainingTimeText(at: now), "18:00")
        XCTAssertEqual(summary.blockProgressText, "Block 2 · 1 completed")
        XCTAssertEqual(summary.visibleBlockIndicators.map(\.status), [.completed, .active])
    }

    func testCurrentSessionSummaryFormatsPausedBlockTruthfully() throws {
        let projectID = UUID()
        let sessionStart = Date(timeIntervalSince1970: 2_000)
        let now = sessionStart.addingTimeInterval(900)
        let session = makeWorkSession(projectID: projectID, startedAt: sessionStart)
        let completedBlock = makePomodoroBlock(
            sessionID: session.id,
            blockIndex: 1,
            status: .completed,
            startedAt: sessionStart
        )
        let pausedBlock = makePomodoroBlock(
            sessionID: session.id,
            blockIndex: 2,
            status: .paused,
            startedAt: sessionStart,
            pausedAt: sessionStart.addingTimeInterval(600)
        )

        let summary = try XCTUnwrap(
            CurrentSessionSummary.current(
                activeSession: session,
                activeBlock: pausedBlock,
                sessionBlocks: [completedBlock, pausedBlock]
            )
        )

        XCTAssertEqual(summary.status, .paused)
        XCTAssertEqual(summary.statusText, "Paused")
        XCTAssertEqual(summary.elapsedSessionTimeText(at: now), "15:00")
        XCTAssertEqual(summary.blockRemainingTimeText(at: now), "10:00")
        XCTAssertEqual(summary.blockProgressText, "Block 2 · 1 completed")
        XCTAssertEqual(summary.visibleBlockIndicators.map(\.status), [.completed, .paused])
    }

    func testActiveProjectRowMessageStaysSecondaryToCurrentSessionSummary() {
        let projectID = UUID()

        XCTAssertEqual(
            ProjectSidebarActivity(projectID: projectID, message: "Block 2 active", kind: .activeBlock)
                .projectRowMessage,
            "Current session"
        )
        XCTAssertEqual(
            ProjectSidebarActivity(projectID: projectID, message: "Block 2 paused", kind: .pausedBlock)
                .projectRowMessage,
            "Current session"
        )
    }

    private func makeHarness() throws -> (
        database: Database,
        migrator: DatabaseMigrator,
        repository: ProjectRepository,
        sessionRepository: SessionRepository,
        snapshotRepository: SnapshotRepository
    ) {
        let rootDirectory = try makeTemporaryDirectory(named: "DatabaseRoot")
        let database = Database(url: rootDirectory.appendingPathComponent("working-memory.sqlite3"))
        let migrator = DatabaseMigrator(database: database)
        let repository = ProjectRepository(database: database)
        let sessionRepository = SessionRepository(database: database)
        let snapshotRepository = SnapshotRepository(database: database)

        return (database, migrator, repository, sessionRepository, snapshotRepository)
    }

    private func makeTemporaryDirectory(named name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkingMemorySnapshotTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)

        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        temporaryURLs.append(url.deletingLastPathComponent())
        return url
    }

    private func makeProject(id: UUID = UUID()) -> Project {
        let now = Date()
        return Project(
            id: id,
            name: "Preview Project",
            rootPath: "/tmp/preview-project",
            createdAt: now,
            updatedAt: now
        )
    }

    private func makeWorkSession(
        id: UUID = UUID(),
        projectID: UUID,
        status: SessionStatus = .active,
        startedAt: Date = Date()
    ) -> WorkSession {
        let now = startedAt
        return WorkSession(
            id: id,
            projectID: projectID,
            mission: "Validate sidebar state.",
            brainDump: nil,
            startedAt: now,
            endedAt: status == .active ? nil : now,
            status: status,
            createdAt: now,
            updatedAt: now
        )
    }

    private func makePomodoroBlock(
        id: UUID = UUID(),
        sessionID: UUID,
        blockIndex: Int,
        status: PomodoroBlockStatus,
        startedAt: Date = Date(),
        pausedAt: Date? = nil
    ) -> PomodoroBlock {
        let now = startedAt
        return PomodoroBlock(
            id: id,
            sessionID: sessionID,
            blockIndex: blockIndex,
            plannedDurationSeconds: PomodoroBlock.defaultPlannedDurationSeconds,
            intention: nil,
            summary: nil,
            status: status,
            startedAt: now,
            pausedAt: status == .paused ? (pausedAt ?? now) : nil,
            accumulatedPauseSeconds: 0,
            endedAt: status == .completed || status == .interrupted ? now : nil,
            createdAt: now,
            updatedAt: now
        )
    }
}
