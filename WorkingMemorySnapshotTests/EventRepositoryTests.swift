import XCTest
@testable import WorkingMemorySnapshot

final class EventRepositoryTests: XCTestCase {
    private var temporaryURLs: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryURLs {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryURLs.removeAll()
    }

    func testInsertAndListEventsForActiveSession() async throws {
        let harness = try makeHarness()
        try await harness.migrator.migrate()
        let project = try await harness.projectRepository.createProject(
            at: makeTemporaryDirectory(named: "EventProject")
        )
        let session = try await harness.sessionRepository.createActiveSession(
            projectID: project.id,
            mission: "Capture generic events"
        )
        let event = SessionEvent(
            sessionID: session.id,
            occurredAt: Date(timeIntervalSince1970: 10),
            source: .activeApp,
            kind: SessionEventKind.appActivated,
            title: "Terminal",
            payloadJSON: try EventPayloadCoding.encode(
                ActiveAppEventPayload(displayName: "Terminal", bundleIdentifier: "com.apple.Terminal")
            ),
            createdAt: Date(timeIntervalSince1970: 11)
        )

        let inserted = try await harness.eventRepository.insertEvent(event)
        let events = try await harness.eventRepository.listEvents(for: session.id)
        let activeApps = try await harness.eventRepository.listDistinctActiveApps(for: session.id)

        XCTAssertEqual(inserted, event)
        XCTAssertEqual(events, [event])
        XCTAssertEqual(activeApps, ["Terminal"])
    }

    func testRejectsEventsForCompletedSessions() async throws {
        let harness = try makeHarness()
        try await harness.migrator.migrate()
        let project = try await harness.projectRepository.createProject(
            at: makeTemporaryDirectory(named: "CompletedEventProject")
        )
        let session = try await harness.sessionRepository.createActiveSession(
            projectID: project.id,
            mission: "Reject late events"
        )
        let completed = try await harness.sessionRepository.completeSession(
            id: session.id,
            brainDump: "This should stay saved."
        )

        await XCTAssertThrowsAsyncError({
            try await harness.eventRepository.insertEvent(
                SessionEvent(
                    sessionID: completed.id,
                    source: .file,
                    kind: SessionEventKind.fileChanged,
                    title: "Sources/App.swift"
                )
            )
        }) { error in
            XCTAssertEqual(error as? EventRepositoryError, .sessionNotActive)
        }

        let events = try await harness.eventRepository.listEvents(for: completed.id)
        XCTAssertTrue(events.isEmpty)
    }

    func testInsertEventsRollsBackBatchWhenOneEventIsInvalid() async throws {
        let harness = try makeHarness()
        try await harness.migrator.migrate()
        let project = try await harness.projectRepository.createProject(
            at: makeTemporaryDirectory(named: "BatchRollbackProject")
        )
        let session = try await harness.sessionRepository.createActiveSession(
            projectID: project.id,
            mission: "Reject partial event batches"
        )
        let validEvent = SessionEvent(
            sessionID: session.id,
            occurredAt: Date(timeIntervalSince1970: 20),
            source: .file,
            kind: SessionEventKind.fileChanged,
            title: "Sources/App.swift",
            createdAt: Date(timeIntervalSince1970: 21)
        )
        let invalidEvent = SessionEvent(
            sessionID: UUID(),
            occurredAt: Date(timeIntervalSince1970: 22),
            source: .git,
            kind: SessionEventKind.gitFinalSummary,
            title: "No matching active session",
            createdAt: Date(timeIntervalSince1970: 23)
        )

        await XCTAssertThrowsAsyncError({
            try await harness.eventRepository.insertEvents([validEvent, invalidEvent])
        }) { error in
            XCTAssertEqual(error as? EventRepositoryError, .sessionNotActive)
        }

        let events = try await harness.eventRepository.listEvents(for: session.id)
        XCTAssertEqual(events, [])
    }

    func testInsertEventNormalizesTimestamps() async throws {
        let harness = try makeHarness()
        try await harness.migrator.migrate()
        let project = try await harness.projectRepository.createProject(
            at: makeTemporaryDirectory(named: "TimestampNormalizationProject")
        )
        let session = try await harness.sessionRepository.createActiveSession(
            projectID: project.id,
            mission: "Normalize stored timestamps"
        )
        let occurredAt = Date(timeIntervalSince1970: 30.123456)
        let createdAt = Date(timeIntervalSince1970: 31.654321)
        let event = SessionEvent(
            sessionID: session.id,
            occurredAt: occurredAt,
            source: .user,
            kind: SessionEventKind.brainDump,
            title: "Captured note",
            createdAt: createdAt
        )

        let inserted = try await harness.eventRepository.insertEvent(event)
        let events = try await harness.eventRepository.listEvents(for: session.id)

        XCTAssertEqual(inserted.occurredAt, try DateCoding.normalized(occurredAt))
        XCTAssertEqual(inserted.createdAt, try DateCoding.normalized(createdAt))
        XCTAssertEqual(events, [inserted])
    }

    func testChangedFilePathsAreDistinctInObservationOrder() async throws {
        let harness = try makeHarness()
        try await harness.migrator.migrate()
        let project = try await harness.projectRepository.createProject(
            at: makeTemporaryDirectory(named: "FileEventProject")
        )
        let session = try await harness.sessionRepository.createActiveSession(
            projectID: project.id,
            mission: "List paths"
        )

        try await harness.eventRepository.insertEvents([
            SessionEvent(sessionID: session.id, source: .file, kind: SessionEventKind.fileChanged, title: "A.swift"),
            SessionEvent(sessionID: session.id, source: .file, kind: SessionEventKind.fileChanged, title: "B.swift"),
            SessionEvent(sessionID: session.id, source: .file, kind: SessionEventKind.fileChanged, title: "A.swift")
        ])

        let paths = try await harness.eventRepository.listChangedFilePaths(for: session.id)
        XCTAssertEqual(paths, ["A.swift", "B.swift"])
    }

    private func makeHarness() throws -> (
        database: Database,
        migrator: DatabaseMigrator,
        projectRepository: ProjectRepository,
        sessionRepository: SessionRepository,
        eventRepository: EventRepository
    ) {
        let rootDirectory = try makeTemporaryDirectory(named: "DatabaseRoot")
        let database = Database(url: rootDirectory.appendingPathComponent("working-memory.sqlite3"))
        let migrator = DatabaseMigrator(database: database)
        let projectRepository = ProjectRepository(database: database)
        let sessionRepository = SessionRepository(database: database)
        let eventRepository = EventRepository(database: database)

        return (database, migrator, projectRepository, sessionRepository, eventRepository)
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
