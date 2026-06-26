import XCTest
@testable import WorkingMemorySnapshot

final class SessionRepositoryTests: XCTestCase {
    private var temporaryURLs: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryURLs {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryURLs.removeAll()
    }

    func testCreateActiveSessionTrimsMission() async throws {
        let harness = try makeHarness()
        try await harness.migrator.migrate()
        let project = try await harness.projectRepository.createProject(
            at: makeTemporaryDirectory(named: "SessionProject")
        )

        let session = try await harness.sessionRepository.createActiveSession(
            projectID: project.id,
            mission: "  Ship the session lifecycle  "
        )

        XCTAssertEqual(session.projectID, project.id)
        XCTAssertEqual(session.mission, "Ship the session lifecycle")
        XCTAssertEqual(session.status, .active)
        XCTAssertNil(session.brainDump)
        XCTAssertNil(session.endedAt)
    }

    func testEmptyMissionIsRejected() async throws {
        let harness = try makeHarness()
        try await harness.migrator.migrate()
        let project = try await harness.projectRepository.createProject(
            at: makeTemporaryDirectory(named: "EmptyMissionProject")
        )

        await XCTAssertThrowsAsyncError({
            try await harness.sessionRepository.createActiveSession(
                projectID: project.id,
                mission: "  \n\t "
            )
        }) { error in
            XCTAssertEqual(error as? SessionRepositoryError, .emptyMission)
        }
    }

    func testSecondActiveSessionIsRejected() async throws {
        let harness = try makeHarness()
        try await harness.migrator.migrate()
        let firstProject = try await harness.projectRepository.createProject(
            at: makeTemporaryDirectory(named: "FirstProject")
        )
        let secondProject = try await harness.projectRepository.createProject(
            at: makeTemporaryDirectory(named: "SecondProject")
        )

        _ = try await harness.sessionRepository.createActiveSession(
            projectID: firstProject.id,
            mission: "First mission"
        )

        await XCTAssertThrowsAsyncError({
            try await harness.sessionRepository.createActiveSession(
                projectID: secondProject.id,
                mission: "Second mission"
            )
        }) { error in
            XCTAssertEqual(error as? SessionRepositoryError, .activeSessionAlreadyExists)
        }
    }

    func testCompleteSessionPersistsBrainDumpAndClearsActiveSession() async throws {
        let harness = try makeHarness()
        try await harness.migrator.migrate()
        let project = try await harness.projectRepository.createProject(
            at: makeTemporaryDirectory(named: "CompleteProject")
        )
        let session = try await harness.sessionRepository.createActiveSession(
            projectID: project.id,
            mission: "Complete the lifecycle"
        )

        let completed = try await harness.sessionRepository.completeSession(
            id: session.id,
            brainDump: "Decision: keep M3 scoped to lifecycle."
        )
        let latestCompleted = try await harness.sessionRepository.latestCompletedSession(for: project.id)

        XCTAssertEqual(completed.status, .completed)
        XCTAssertEqual(completed.brainDump, "Decision: keep M3 scoped to lifecycle.")
        XCTAssertNotNil(completed.endedAt)
        let activeSession = try await harness.sessionRepository.activeSession()
        XCTAssertNil(activeSession)
        XCTAssertEqual(latestCompleted, completed)
    }

    func testCancelSessionClearsActiveSessionWithoutBrainDump() async throws {
        let harness = try makeHarness()
        try await harness.migrator.migrate()
        let project = try await harness.projectRepository.createProject(
            at: makeTemporaryDirectory(named: "CancelProject")
        )
        let session = try await harness.sessionRepository.createActiveSession(
            projectID: project.id,
            mission: "Cancel this session"
        )

        let cancelled = try await harness.sessionRepository.cancelSession(id: session.id)

        XCTAssertEqual(cancelled.status, .cancelled)
        XCTAssertNil(cancelled.brainDump)
        XCTAssertNotNil(cancelled.endedAt)
        let activeSession = try await harness.sessionRepository.activeSession()
        XCTAssertNil(activeSession)
    }

    func testActiveSessionIsRecoverableAcrossRepositoryReload() async throws {
        let rootDirectory = try makeTemporaryDirectory(named: "DatabaseRoot")
        let databaseURL = rootDirectory.appendingPathComponent("working-memory.sqlite3")
        let projectFolder = try makeTemporaryDirectory(named: "RecoveredProject")

        let firstDatabase = Database(url: databaseURL)
        let firstMigrator = DatabaseMigrator(database: firstDatabase)
        let firstProjectRepository = ProjectRepository(database: firstDatabase)
        let firstSessionRepository = SessionRepository(database: firstDatabase)

        try await firstMigrator.migrate()
        let project = try await firstProjectRepository.createProject(at: projectFolder)
        let createdSession = try await firstSessionRepository.createActiveSession(
            projectID: project.id,
            mission: "Recover after relaunch"
        )

        let secondDatabase = Database(url: databaseURL)
        let secondMigrator = DatabaseMigrator(database: secondDatabase)
        let secondSessionRepository = SessionRepository(database: secondDatabase)

        try await secondMigrator.migrate()
        let recoveredSession = try await secondSessionRepository.activeSession()

        XCTAssertEqual(recoveredSession, createdSession)
    }

    private func makeHarness() throws -> (
        database: Database,
        migrator: DatabaseMigrator,
        projectRepository: ProjectRepository,
        sessionRepository: SessionRepository
    ) {
        let rootDirectory = try makeTemporaryDirectory(named: "DatabaseRoot")
        let database = Database(url: rootDirectory.appendingPathComponent("working-memory.sqlite3"))
        let migrator = DatabaseMigrator(database: database)
        let projectRepository = ProjectRepository(database: database)
        let sessionRepository = SessionRepository(database: database)

        return (database, migrator, projectRepository, sessionRepository)
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
