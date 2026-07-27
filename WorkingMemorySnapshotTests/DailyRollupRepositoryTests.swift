import XCTest
@testable import WorkingMemorySnapshot

final class DailyRollupRepositoryTests: XCTestCase {
    private var temporaryRoot: URL?

    override func tearDownWithError() throws {
        if let temporaryRoot { try? FileManager.default.removeItem(at: temporaryRoot) }
        temporaryRoot = nil
    }

    func testMigrationNineIsIdempotentAndSameDayRevisionsArePreservedAtomically() async throws {
        let harness = try makeHarness()
        try await harness.migrator.migrate()
        try await harness.migrator.migrate()
        let versions = try await harness.migrator.appliedVersions()
        XCTAssertEqual(versions, Array(1...10))

        let projectID = UUID()
        let sessionID = UUID()
        let first = try await harness.repository.saveRevision(
            draft(
                date: "2026-07-13",
                projectID: projectID,
                sessionID: sessionID,
                summary: "First summary",
                carryForward: "Preserve the first run's open thread."
            )
        )
        let refreshed = try await harness.repository.saveRevision(
            draft(date: "2026-07-13", projectID: projectID, sessionID: sessionID, summary: "Refreshed summary")
        )

        XCTAssertNotEqual(first.id, refreshed.id)
        let latestForDay = try await harness.repository.rollup(for: "2026-07-13")
        XCTAssertEqual(latestForDay, refreshed)
        let rollups = try await harness.repository.listRollups()
        XCTAssertEqual(rollups.count, 2)
        XCTAssertEqual(
            rollups.first(where: { $0.id == first.id })?.carryForwards.first?.text,
            "Preserve the first run's open thread."
        )
        let firstSources = try await harness.repository.sources(for: first.id)
        let refreshedSources = try await harness.repository.sources(for: refreshed.id)
        XCTAssertEqual(firstSources.count, 1)
        XCTAssertEqual(refreshedSources.count, 1)
    }

    func testHistoryOrdersNewestDayAndSameDayRevisionFirst() async throws {
        let harness = try makeHarness()
        try await harness.migrator.migrate()
        _ = try await harness.repository.saveRevision(
            draft(date: "2026-07-12", projectID: UUID(), sessionID: UUID(), summary: "Earlier")
        )
        _ = try await harness.repository.saveRevision(
            draft(date: "2026-07-13", projectID: UUID(), sessionID: UUID(), summary: "First run")
        )
        let latest = try await harness.repository.saveRevision(
            draft(date: "2026-07-13", projectID: UUID(), sessionID: UUID(), summary: "Latest run")
        )

        let rollups = try await harness.repository.listRollups()
        XCTAssertEqual(rollups.map(\.rollupDate), ["2026-07-13", "2026-07-13", "2026-07-12"])
        XCTAssertEqual(rollups.first, latest)
    }

    func testSourceConstraintFailureRollsBackArtifactRevision() async throws {
        let harness = try makeHarness()
        try await harness.migrator.migrate()
        let projectID = UUID()
        let sessionID = UUID()
        let existing = try await harness.repository.saveRevision(
            draft(date: "2026-07-13", projectID: projectID, sessionID: sessionID, summary: "Keep this")
        )
        var invalid = draft(date: "2026-07-13", projectID: projectID, sessionID: sessionID, summary: "Do not persist")
        invalid.sources.append(invalid.sources[0])

        await XCTAssertThrowsAsyncError({ try await harness.repository.saveRevision(invalid) })

        let preserved = try await harness.repository.rollup(for: "2026-07-13")
        XCTAssertEqual(preserved, existing)
        let rollups = try await harness.repository.listRollups()
        XCTAssertEqual(rollups.count, 1)
    }

    func testDeletedProjectPreservesArtifactAndMarksSourceUnavailable() async throws {
        let harness = try makeHarness()
        try await harness.migrator.migrate()
        let projectURL = try makeDirectory("SourceProject")
        let project = try await harness.projectRepository.createProject(at: projectURL)
        let active = try await harness.sessionRepository.createActiveSession(projectID: project.id, mission: "Preserve source label")
        let session = try await harness.sessionRepository.completeSession(id: active.id, brainDump: "Done")
        let rollup = try await harness.repository.saveRevision(
            draft(date: "2026-07-13", projectID: project.id, sessionID: session.id, summary: "Preserved")
        )

        try await harness.projectRepository.deleteProject(id: project.id)

        let preserved = try await harness.repository.rollup(for: "2026-07-13")
        let sources = try await harness.repository.sources(for: rollup.id)
        let source = try XCTUnwrap(sources.first)
        XCTAssertEqual(preserved, rollup)
        XCTAssertFalse(source.isAvailable)
        XCTAssertEqual(source.mission, "Source mission")
    }

    private func makeHarness() throws -> (
        migrator: DatabaseMigrator,
        repository: DailyRollupRepository,
        projectRepository: ProjectRepository,
        sessionRepository: SessionRepository
    ) {
        let root = try makeDirectory("Database")
        let database = Database(url: root.appendingPathComponent("working-memory.sqlite3"))
        return (
            DatabaseMigrator(database: database),
            DailyRollupRepository(database: database),
            ProjectRepository(database: database),
            SessionRepository(database: database)
        )
    }

    private func draft(
        date: String,
        projectID: UUID,
        sessionID: UUID,
        summary: String,
        carryForward: String? = nil
    ) -> DailyRollupDraft {
        DailyRollupDraft(
            rollupDate: date,
            timezoneIdentifier: "America/Denver",
            daySummary: summary,
            projectThreads: [DailyProjectThread(projectID: projectID, projectName: "Project", summary: "Thread")],
            carryForwards: carryForward.map {
                [DailyCarryForward(projectID: projectID, projectName: "Project", text: $0)]
            } ?? [],
            closureNote: "Closed",
            generatorModel: "model",
            promptVersion: "daily-rollup-v1",
            sourceFingerprint: summary,
            sources: [DailyRollupSource(
                rollupID: UUID(), sessionID: sessionID, projectID: projectID,
                projectName: "Project", mission: "Source mission", endedAt: Date(), isAvailable: true
            )]
        )
    }

    private func makeDirectory(_ name: String) throws -> URL {
        if temporaryRoot == nil {
            temporaryRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent("DailyRollupRepositoryTests-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: temporaryRoot!, withIntermediateDirectories: true)
        }
        let url = temporaryRoot!.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
