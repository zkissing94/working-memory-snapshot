import XCTest
@testable import WorkingMemorySnapshot

final class DailyRollupSourceLoaderTests: XCTestCase {
    private var temporaryRoot: URL?

    override func tearDownWithError() throws {
        if let temporaryRoot { try? FileManager.default.removeItem(at: temporaryRoot) }
    }

    func testLoadsCompletedSessionsByLocalEndDateAndUsesSnapshotOrFallback() async throws {
        let harness = try makeHarness()
        try await harness.migrator.migrate()
        let calendar = fixedCalendar()
        let day = date(2026, 7, 13, 12, calendar: calendar)
        let projectA = try await harness.projects.createProject(at: try makeDirectory("ProjectA"))
        let projectB = try await harness.projects.createProject(at: try makeDirectory("ProjectB"))

        let firstActive = try await harness.sessions.createActiveSession(projectID: projectA.id, mission: "Snapshot-backed")
        let first = try await harness.sessions.completeSession(id: firstActive.id, brainDump: "Completed first")
        try await setEnd(date(2026, 7, 13, 9, calendar: calendar), sessionID: first.id, database: harness.database)
        _ = try await harness.snapshots.saveOrReplaceSnapshot(
            SnapshotDraft(
                whatChanged: "Persistence landed", decisions: [], openLoops: [],
                nextAction: "Wire UI", resumeBrief: "The durable rollup storage is ready.",
                generatorModel: "model", promptVersion: "v1"
            ),
            for: first.id
        )

        let secondActive = try await harness.sessions.createActiveSession(projectID: projectB.id, mission: "Fallback-backed")
        let block = try await harness.blocks.createNextBlock(sessionID: secondActive.id, intention: "Capture the fallback")
        _ = try await harness.increments.addIncrement(blockID: block.id, kind: .decision, title: "Use saved capture points")
        _ = try await harness.blocks.completeBlock(id: block.id, summary: "Fallback evidence is present")
        let second = try await harness.sessions.completeSession(id: secondActive.id, brainDump: "No snapshot yet")
        try await setEnd(date(2026, 7, 13, 23, calendar: calendar), sessionID: second.id, database: harness.database)

        let outsideActive = try await harness.sessions.createActiveSession(projectID: projectA.id, mission: "Tomorrow")
        let outside = try await harness.sessions.completeSession(id: outsideActive.id, brainDump: "Outside")
        try await setEnd(date(2026, 7, 14, 0, calendar: calendar), sessionID: outside.id, database: harness.database)

        let eligibility = try await harness.loader.load(for: day, calendar: calendar)

        XCTAssertEqual(eligibility.rollupDate, "2026-07-13")
        XCTAssertEqual(eligibility.sessions.map(\.session.id), [first.id, second.id])
        XCTAssertNotNil(eligibility.sessions[0].snapshot)
        XCTAssertTrue(eligibility.sessions[1].fallbackCapture.contains("Use saved capture points"))
        XCTAssertEqual(eligibility.participatingProjectCount, 2)
    }

    func testActiveSessionBlocksGenerationAndSnapshotChangeMakesFingerprintChange() async throws {
        let harness = try makeHarness()
        try await harness.migrator.migrate()
        let calendar = fixedCalendar()
        let today = Date()
        let project = try await harness.projects.createProject(at: try makeDirectory("Project"))
        let completedActive = try await harness.sessions.createActiveSession(projectID: project.id, mission: "Completed")
        let completed = try await harness.sessions.completeSession(id: completedActive.id, brainDump: "Saved")
        try await setEnd(today, sessionID: completed.id, database: harness.database)

        let before = try await harness.loader.load(for: today, calendar: calendar)
        _ = try await harness.snapshots.saveOrReplaceSnapshot(
            SnapshotDraft(
                whatChanged: "Added later", decisions: [], openLoops: [], nextAction: "Refresh",
                resumeBrief: "A snapshot now exists.", generatorModel: "model", promptVersion: "v1"
            ),
            for: completed.id
        )
        let active = try await harness.sessions.createActiveSession(projectID: project.id, mission: "Still working")
        let after = try await harness.loader.load(for: today, calendar: calendar)

        XCTAssertNotEqual(before.sourceFingerprint, after.sourceFingerprint)
        XCTAssertTrue(after.hasActiveSession)
        XCTAssertFalse(after.canGenerate)
        _ = try await harness.sessions.cancelSession(id: active.id)
    }

    private func makeHarness() throws -> (
        database: Database, migrator: DatabaseMigrator, projects: ProjectRepository,
        sessions: SessionRepository, snapshots: SnapshotRepository,
        blocks: PomodoroBlockRepository, increments: WorkIncrementRepository,
        loader: DailyRollupSourceLoader
    ) {
        let root = try makeDirectory("Database")
        let database = Database(url: root.appendingPathComponent("working-memory.sqlite3"))
        let projects = ProjectRepository(database: database)
        let sessions = SessionRepository(database: database)
        let snapshots = SnapshotRepository(database: database)
        let blocks = PomodoroBlockRepository(database: database)
        let increments = WorkIncrementRepository(database: database)
        return (
            database, DatabaseMigrator(database: database), projects, sessions, snapshots, blocks, increments,
            DailyRollupSourceLoader(
                projectRepository: projects, sessionRepository: sessions, snapshotRepository: snapshots,
                pomodoroBlockRepository: blocks, workIncrementRepository: increments
            )
        )
    }

    private func setEnd(_ date: Date, sessionID: UUID, database: Database) async throws {
        try await database.execute("UPDATE sessions SET ended_at = ?, updated_at = ? WHERE id = ?") { statement in
            try SQLiteValue.bind(DateCoding.string(from: date), to: statement, at: 1)
            try SQLiteValue.bind(DateCoding.string(from: date), to: statement, at: 2)
            try SQLiteValue.bind(sessionID.uuidString, to: statement, at: 3)
        }
    }

    private func fixedCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Denver")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func makeDirectory(_ name: String) throws -> URL {
        if temporaryRoot == nil {
            temporaryRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent("DailyRollupSourceLoaderTests-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: temporaryRoot!, withIntermediateDirectories: true)
        }
        let url = temporaryRoot!.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
