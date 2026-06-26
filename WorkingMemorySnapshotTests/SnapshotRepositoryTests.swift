import XCTest
@testable import WorkingMemorySnapshot

final class SnapshotRepositoryTests: XCTestCase {
    private var temporaryURLs: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryURLs {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryURLs.removeAll()
    }

    func testSaveOrReplaceSnapshotKeepsOneSnapshotPerSession() async throws {
        let harness = try makeHarness()
        try await harness.migrator.migrate()
        let project = try await harness.projectRepository.createProject(
            at: makeTemporaryDirectory(named: "SnapshotProject")
        )
        let session = try await harness.sessionRepository.createActiveSession(
            projectID: project.id,
            mission: "Build the placeholder slice"
        )
        let completed = try await harness.sessionRepository.completeSession(
            id: session.id,
            brainDump: "Next: verify persistence."
        )

        let firstSnapshot = try await harness.snapshotRepository.saveOrReplaceSnapshot(
            SnapshotDraft(
                whatChanged: "Brain dump: Next: verify persistence.",
                decisions: [],
                openLoops: [],
                nextAction: "verify persistence.",
                resumeBrief: "Mission: Build the placeholder slice. Brain dump: Next: verify persistence.",
                generatorModel: "deterministic-placeholder",
                promptVersion: "placeholder-v1"
            ),
            for: completed.id
        )
        let replacementSnapshot = try await harness.snapshotRepository.saveOrReplaceSnapshot(
            SnapshotDraft(
                whatChanged: "Brain dump: Next: verify latest query.",
                decisions: [],
                openLoops: ["Blocked: latest query is unverified."],
                nextAction: "verify latest query.",
                resumeBrief: "Mission: Build the placeholder slice. Brain dump: Next: verify latest query.",
                generatorModel: "deterministic-placeholder",
                promptVersion: "placeholder-v1"
            ),
            for: completed.id
        )

        let storedSnapshot = try await harness.snapshotRepository.snapshot(for: completed.id)
        let allSnapshots = try await harness.snapshotRepository.listSnapshots(for: project.id)

        XCTAssertEqual(replacementSnapshot.id, firstSnapshot.id)
        XCTAssertEqual(replacementSnapshot.createdAt, firstSnapshot.createdAt)
        XCTAssertGreaterThanOrEqual(replacementSnapshot.updatedAt, firstSnapshot.updatedAt)
        XCTAssertEqual(storedSnapshot, replacementSnapshot)
        XCTAssertEqual(allSnapshots, [replacementSnapshot])
        XCTAssertEqual(storedSnapshot?.openLoops, ["Blocked: latest query is unverified."])
    }

    func testLatestSnapshotForProjectIgnoresActiveAndOtherProjects() async throws {
        let harness = try makeHarness()
        try await harness.migrator.migrate()
        let firstProject = try await harness.projectRepository.createProject(
            at: makeTemporaryDirectory(named: "FirstSnapshotProject")
        )
        let secondProject = try await harness.projectRepository.createProject(
            at: makeTemporaryDirectory(named: "SecondSnapshotProject")
        )
        let firstSession = try await harness.sessionRepository.createActiveSession(
            projectID: firstProject.id,
            mission: "Finish first project"
        )
        let firstCompleted = try await harness.sessionRepository.completeSession(
            id: firstSession.id,
            brainDump: "Next: continue first project."
        )
        let firstSnapshot = try await harness.snapshotRepository.saveOrReplaceSnapshot(
            makeDraft(nextAction: "continue first project."),
            for: firstCompleted.id
        )
        let secondSession = try await harness.sessionRepository.createActiveSession(
            projectID: secondProject.id,
            mission: "Finish second project"
        )
        let secondCompleted = try await harness.sessionRepository.completeSession(
            id: secondSession.id,
            brainDump: "Next: continue second project."
        )
        _ = try await harness.snapshotRepository.saveOrReplaceSnapshot(
            makeDraft(nextAction: "continue second project."),
            for: secondCompleted.id
        )
        let activeSession = try await harness.sessionRepository.createActiveSession(
            projectID: firstProject.id,
            mission: "Active sessions are not resume snapshots yet"
        )
        _ = try await harness.snapshotRepository.saveOrReplaceSnapshot(
            makeDraft(nextAction: "ignore active session."),
            for: activeSession.id
        )

        let latestFirstSnapshot = try await harness.snapshotRepository.latestSnapshot(for: firstProject.id)

        XCTAssertEqual(latestFirstSnapshot, firstSnapshot)
    }

    private func makeDraft(nextAction: String) -> SnapshotDraft {
        SnapshotDraft(
            whatChanged: "Brain dump: Next: \(nextAction)",
            decisions: [],
            openLoops: [],
            nextAction: nextAction,
            resumeBrief: "Mission and brain dump were captured.",
            generatorModel: "deterministic-placeholder",
            promptVersion: "placeholder-v1"
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
