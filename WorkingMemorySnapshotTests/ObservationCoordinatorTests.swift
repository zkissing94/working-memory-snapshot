import XCTest
@testable import WorkingMemorySnapshot

@MainActor
final class ObservationCoordinatorTests: XCTestCase {
    private var temporaryURLs: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryURLs {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryURLs.removeAll()
    }

    func testStartAndStopObserversOnceAndSuppressEventsAfterStop() async throws {
        let harness = try makeHarness()
        try await harness.migrator.migrate()
        let projectURL = try makeTemporaryDirectory(named: "ObservedProject")
        let project = try await harness.projectRepository.createProject(at: projectURL)
        let session = try await harness.sessionRepository.createActiveSession(
            projectID: project.id,
            mission: "Observe only during active sessions"
        )
        let terminal = try XCTUnwrap(
            ActiveAppIdentity(displayName: "Terminal", bundleIdentifier: "com.apple.Terminal")
        )
        let xcode = try XCTUnwrap(
            ActiveAppIdentity(displayName: "Xcode", bundleIdentifier: "com.apple.dt.Xcode")
        )
        let fileStreamBox = CoordinatorFakeFileEventStreamBox()
        let fileObservationService = FileObservationService { _, _, handler in
            let stream = CoordinatorFakeFileEventStream(handler: handler)
            fileStreamBox.store(stream)
            return stream
        }
        let activeAppSource = CoordinatorFakeActiveAppObservationSource(frontmostApplication: terminal)
        let activeAppService = ActiveAppObservationService(source: activeAppSource)
        let coordinator = ObservationCoordinator(
            eventRepository: harness.eventRepository,
            fileObservationService: fileObservationService,
            activeAppObservationService: activeAppService,
            gitService: GitService()
        )
        var summaries: [ObservationSessionSummary] = []
        coordinator.onSummaryChange = { summaries.append($0) }
        let blockID = UUID()

        await coordinator.startObserving(
            session: session,
            project: project,
            activeBlockID: blockID
        )
        let stream = try XCTUnwrap(fileStreamBox.stream())
        XCTAssertEqual(stream.startCallCount, 1)
        XCTAssertEqual(activeAppSource.addedObserverCount, 1)

        stream.emit(paths: [projectURL.appendingPathComponent("Sources/App.swift").path], at: Date(timeIntervalSince1970: 20))
        activeAppSource.emit(xcode)
        try await waitForEventCount(2, source: .activeApp, sessionID: session.id, repository: harness.eventRepository)
        try await waitForObservedFileCount(1, service: fileObservationService)

        await coordinator.checkpointObservation(activeBlockID: nil)
        stream.emit(
            paths: [projectURL.appendingPathComponent("Sources/Between.swift").path],
            at: Date(timeIntervalSince1970: 25)
        )
        activeAppSource.emit(terminal)
        try await waitForObservedFileCount(2, service: fileObservationService)

        await coordinator.stopObservingForCompletion(session: session, brainDump: "Next: generate the snapshot.")
        XCTAssertEqual(stream.stopCallCount, 1)
        XCTAssertEqual(activeAppSource.removedObserverCount, 1)

        let countAfterStop = try await harness.eventRepository.countEvents(for: session.id)
        stream.emit(paths: [projectURL.appendingPathComponent("Sources/AfterStop.swift").path], at: Date(timeIntervalSince1970: 30))
        activeAppSource.emit(terminal)
        try await Task.sleep(nanoseconds: 50_000_000)

        let finalCount = try await harness.eventRepository.countEvents(for: session.id)
        let changedPaths = try await harness.eventRepository.listChangedFilePaths(for: session.id)
        XCTAssertEqual(finalCount, countAfterStop)
        XCTAssertEqual(changedPaths, ["Sources/App.swift", "Sources/Between.swift"])
        XCTAssertTrue(summaries.contains { $0.changedFileCount == 2 })
        XCTAssertEqual(summaries.last, ObservationSessionSummary())

        let events = try await harness.eventRepository.listEvents(for: session.id)
        let filePayloads = try events
            .filter { $0.source == .file }
            .compactMap(\.payloadJSON)
            .map { try EventPayloadCoding.decode(FileChangedEventPayload.self, from: $0) }
        XCTAssertEqual(filePayloads[0].observationWindow, .current(blockID: blockID))
        XCTAssertEqual(filePayloads[1].observationWindow, .current(blockID: nil))

        let appPayloads = try events
            .filter { $0.source == .activeApp }
            .compactMap(\.payloadJSON)
            .map { try EventPayloadCoding.decode(ActiveAppEventPayload.self, from: $0) }
        XCTAssertTrue(appPayloads.contains { $0.displayName == "Xcode" && $0.observationWindow == .current(blockID: blockID) })
        XCTAssertTrue(appPayloads.contains { $0.displayName == "Terminal" && $0.observationWindow == .current(blockID: nil) })
    }

    func testStartIsIgnoredForCompletedSession() async throws {
        let harness = try makeHarness()
        try await harness.migrator.migrate()
        let projectURL = try makeTemporaryDirectory(named: "CompletedProject")
        let project = try await harness.projectRepository.createProject(at: projectURL)
        let activeSession = try await harness.sessionRepository.createActiveSession(
            projectID: project.id,
            mission: "Do not observe completed sessions"
        )
        let completedSession = try await harness.sessionRepository.completeSession(
            id: activeSession.id,
            brainDump: "Already done."
        )
        let fileStreamBox = CoordinatorFakeFileEventStreamBox()
        let coordinator = ObservationCoordinator(
            eventRepository: harness.eventRepository,
            fileObservationService: FileObservationService { _, _, handler in
                let stream = CoordinatorFakeFileEventStream(handler: handler)
                fileStreamBox.store(stream)
                return stream
            },
            activeAppObservationService: ActiveAppObservationService(
                source: CoordinatorFakeActiveAppObservationSource(frontmostApplication: nil)
            ),
            gitService: GitService()
        )

        await coordinator.startObserving(
            session: completedSession,
            project: project,
            activeBlockID: nil
        )

        XCTAssertNil(fileStreamBox.stream())
        let eventCount = try await harness.eventRepository.countEvents(for: completedSession.id)
        XCTAssertEqual(eventCount, 0)
    }

    private func waitForEventCount(
        _ expectedCount: Int,
        source: EventSource,
        sessionID: WorkSession.ID,
        repository: EventRepository,
        timeoutNanoseconds: UInt64 = 1_000_000_000
    ) async throws {
        let intervalNanoseconds: UInt64 = 10_000_000
        var waitedNanoseconds: UInt64 = 0

        while waitedNanoseconds < timeoutNanoseconds {
            let count = try await repository.countEvents(for: sessionID, source: source)
            if count >= expectedCount {
                return
            }
            try await Task.sleep(nanoseconds: intervalNanoseconds)
            waitedNanoseconds += intervalNanoseconds
        }

        let count = try await repository.countEvents(for: sessionID, source: source)
        XCTAssertEqual(count, expectedCount)
    }

    private func waitForObservedFileCount(
        _ expectedCount: Int,
        service: FileObservationService,
        timeoutNanoseconds: UInt64 = 1_000_000_000
    ) async throws {
        let intervalNanoseconds: UInt64 = 10_000_000
        var waitedNanoseconds: UInt64 = 0

        while waitedNanoseconds < timeoutNanoseconds {
            if await service.observedChanges().changes.count >= expectedCount {
                return
            }
            try await Task.sleep(nanoseconds: intervalNanoseconds)
            waitedNanoseconds += intervalNanoseconds
        }

        let count = await service.observedChanges().changes.count
        XCTAssertEqual(count, expectedCount)
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

private final class CoordinatorFakeFileEventStreamBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storedStream: CoordinatorFakeFileEventStream?

    func store(_ stream: CoordinatorFakeFileEventStream) {
        lock.lock()
        defer { lock.unlock() }
        storedStream = stream
    }

    func stream() -> CoordinatorFakeFileEventStream? {
        lock.lock()
        defer { lock.unlock() }
        return storedStream
    }
}

private final class CoordinatorFakeFileEventStream: FileEventStreaming, @unchecked Sendable {
    private let handler: @Sendable ([String], Date) -> Void
    private let lock = NSLock()
    private var starts = 0
    private var stops = 0

    var startCallCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return starts
    }

    var stopCallCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return stops
    }

    init(handler: @escaping @Sendable ([String], Date) -> Void) {
        self.handler = handler
    }

    func start() throws {
        lock.lock()
        defer { lock.unlock() }
        starts += 1
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }
        stops += 1
    }

    func emit(paths: [String], at timestamp: Date) {
        handler(paths, timestamp)
    }
}

private final class CoordinatorFakeActiveAppObservationSource: ActiveAppObservationSource {
    var frontmostApplication: ActiveAppIdentity?

    private var handlers: [UUID: (ActiveAppIdentity) -> Void] = [:]
    private(set) var addedObserverCount = 0
    private(set) var removedObserverCount = 0

    init(frontmostApplication: ActiveAppIdentity?) {
        self.frontmostApplication = frontmostApplication
    }

    func addActivationObserver(
        _ handler: @escaping (ActiveAppIdentity) -> Void
    ) -> ActiveAppObservationToken {
        let id = UUID()
        addedObserverCount += 1
        handlers[id] = handler

        return CoordinatorFakeActiveAppObservationToken { [weak self] in
            guard let self else {
                return
            }
            if handlers.removeValue(forKey: id) != nil {
                removedObserverCount += 1
            }
        }
    }

    func emit(_ application: ActiveAppIdentity) {
        for handler in handlers.values {
            handler(application)
        }
    }
}

private final class CoordinatorFakeActiveAppObservationToken: ActiveAppObservationToken {
    private var onCancel: (() -> Void)?

    init(onCancel: @escaping () -> Void) {
        self.onCancel = onCancel
    }

    func cancel() {
        guard let onCancel else {
            return
        }
        self.onCancel = nil
        onCancel()
    }
}
