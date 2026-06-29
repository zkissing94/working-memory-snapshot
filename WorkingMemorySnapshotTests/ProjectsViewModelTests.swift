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
        status: SessionStatus = .active
    ) -> WorkSession {
        let now = Date()
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
        status: PomodoroBlockStatus
    ) -> PomodoroBlock {
        let now = Date()
        return PomodoroBlock(
            id: id,
            sessionID: sessionID,
            blockIndex: blockIndex,
            plannedDurationSeconds: PomodoroBlock.defaultPlannedDurationSeconds,
            intention: nil,
            summary: nil,
            status: status,
            startedAt: now,
            pausedAt: status == .paused ? now : nil,
            accumulatedPauseSeconds: 0,
            endedAt: status == .completed || status == .interrupted ? now : nil,
            createdAt: now,
            updatedAt: now
        )
    }
}
