import Foundation
import XCTest
@testable import WorkingMemorySnapshot

final class FileObservationServiceTests: XCTestCase {
    private var temporaryURLs: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryURLs {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryURLs.removeAll()
    }

    func testPathFilterRejectsIgnoredDirectorySegments() throws {
        let projectRoot = try makeTemporaryDirectory(named: "Project")
        let filter = ProjectPathFilter(projectRootURL: projectRoot)

        XCTAssertEqual(
            filter.relativePath(for: projectRoot.appendingPathComponent("Sources/App.swift")),
            "Sources/App.swift"
        )
        XCTAssertEqual(
            filter.relativePath(for: projectRoot.appendingPathComponent(".gitignore")),
            ".gitignore"
        )
        XCTAssertNil(filter.relativePath(for: projectRoot.appendingPathComponent(".git/config")))
        XCTAssertNil(filter.relativePath(for: projectRoot.appendingPathComponent("node_modules/pkg/index.js")))
        XCTAssertNil(filter.relativePath(for: projectRoot.appendingPathComponent("DerivedData/Build/Products/app")))
    }

    func testPathFilterRejectsPathsOutsideProjectRoot() throws {
        let projectRoot = try makeTemporaryDirectory(named: "Project")
        let siblingRoot = try makeTemporaryDirectory(named: "ProjectSibling")
        let filter = ProjectPathFilter(projectRootURL: projectRoot)

        XCTAssertNil(filter.relativePath(for: siblingRoot.appendingPathComponent("Sources/App.swift")))
        XCTAssertNil(filter.relativePath(for: projectRoot))
    }

    func testAggregatorCompactsRepeatedChangesByRelativePath() {
        let firstTimestamp = Date(timeIntervalSince1970: 10)
        let middleTimestamp = Date(timeIntervalSince1970: 20)
        let finalTimestamp = Date(timeIntervalSince1970: 30)
        var aggregator = FileChangeAggregator(maximumUniquePaths: 10)

        aggregator.record(relativePath: "Sources/App.swift", at: firstTimestamp)
        aggregator.record(relativePath: "Tests/AppTests.swift", at: middleTimestamp)
        aggregator.record(relativePath: "Sources/App.swift", at: finalTimestamp)

        XCTAssertEqual(
            aggregator.summary(),
            FileChangeSummary(
                changes: [
                    ObservedFileChange(
                        relativePath: "Sources/App.swift",
                        firstObservedAt: firstTimestamp,
                        lastObservedAt: finalTimestamp,
                        changeCount: 2
                    ),
                    ObservedFileChange(
                        relativePath: "Tests/AppTests.swift",
                        firstObservedAt: middleTimestamp,
                        lastObservedAt: middleTimestamp,
                        changeCount: 1
                    )
                ],
                droppedChangeCount: 0
            )
        )
    }

    func testAggregatorBoundsUniquePathsAndKeepsExistingPathUpdates() {
        let firstTimestamp = Date(timeIntervalSince1970: 10)
        let secondTimestamp = Date(timeIntervalSince1970: 20)
        let thirdTimestamp = Date(timeIntervalSince1970: 30)
        let finalTimestamp = Date(timeIntervalSince1970: 40)
        var aggregator = FileChangeAggregator(maximumUniquePaths: 2)

        aggregator.record(relativePath: "Sources/App.swift", at: firstTimestamp)
        aggregator.record(relativePath: "Tests/AppTests.swift", at: secondTimestamp)
        aggregator.record(relativePath: "README.md", at: thirdTimestamp)
        aggregator.record(relativePath: "Sources/App.swift", at: finalTimestamp)

        XCTAssertEqual(
            aggregator.summary(),
            FileChangeSummary(
                changes: [
                    ObservedFileChange(
                        relativePath: "Sources/App.swift",
                        firstObservedAt: firstTimestamp,
                        lastObservedAt: finalTimestamp,
                        changeCount: 2
                    ),
                    ObservedFileChange(
                        relativePath: "Tests/AppTests.swift",
                        firstObservedAt: secondTimestamp,
                        lastObservedAt: secondTimestamp,
                        changeCount: 1
                    )
                ],
                droppedChangeCount: 1
            )
        )
        XCTAssertTrue(aggregator.summary().isTruncated)
    }

    func testServiceStopsWithoutEmittingAfterSessionEnd() async throws {
        let projectRoot = try makeTemporaryDirectory(named: "Project")
        let streamBox = FakeFileEventStreamBox()
        let recorder = SummaryRecorder()
        let firstTimestamp = Date(timeIntervalSince1970: 10)
        let secondTimestamp = Date(timeIntervalSince1970: 20)
        let service = FileObservationService { _, _, handler in
            let stream = FakeFileEventStream(handler: handler)
            streamBox.store(stream)
            return stream
        }

        try await service.start(
            configuration: FileObservationConfiguration(projectRootURL: projectRoot),
            onChange: { summary in
                recorder.append(summary)
            }
        )

        let stream = try XCTUnwrap(streamBox.stream())
        stream.emit(paths: [projectRoot.appendingPathComponent("Sources/App.swift").path], at: firstTimestamp)
        try await waitForRecorderCount(1, recorder: recorder)

        let stoppedSummary = await service.stop()
        XCTAssertEqual(stream.stopCallCount, 1)

        stream.emit(paths: [projectRoot.appendingPathComponent("Sources/AfterStop.swift").path], at: secondTimestamp)
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(recorder.count, 1)
        let finalSummary = await service.observedChanges()
        XCTAssertEqual(finalSummary, stoppedSummary)
        XCTAssertEqual(stoppedSummary.changes.map(\.relativePath), ["Sources/App.swift"])
    }

    func testCheckpointDrainsOnlyCurrentWindowWithoutStoppingObservation() async throws {
        let projectRoot = try makeTemporaryDirectory(named: "Project")
        let streamBox = FakeFileEventStreamBox()
        let recorder = SummaryRecorder()
        let service = FileObservationService { _, _, handler in
            let stream = FakeFileEventStream(handler: handler)
            streamBox.store(stream)
            return stream
        }

        try await service.start(
            configuration: FileObservationConfiguration(projectRootURL: projectRoot),
            onChange: { recorder.append($0) }
        )
        let stream = try XCTUnwrap(streamBox.stream())
        stream.emit(
            paths: [projectRoot.appendingPathComponent("Sources/First.swift").path],
            at: Date(timeIntervalSince1970: 10)
        )
        try await waitForRecorderCount(1, recorder: recorder)

        let firstCheckpoint = await service.checkpoint()
        XCTAssertEqual(firstCheckpoint.changes.map(\.relativePath), ["Sources/First.swift"])
        XCTAssertEqual(stream.stopCallCount, 0)

        stream.emit(
            paths: [projectRoot.appendingPathComponent("Sources/Second.swift").path],
            at: Date(timeIntervalSince1970: 20)
        )
        try await waitForRecorderCount(2, recorder: recorder)

        let stopped = await service.stopAndCheckpoint()
        XCTAssertEqual(stopped.finalCheckpoint.changes.map(\.relativePath), ["Sources/Second.swift"])
        XCTAssertEqual(
            stopped.sessionSummary.changes.map(\.relativePath),
            ["Sources/First.swift", "Sources/Second.swift"]
        )
        XCTAssertEqual(stream.stopCallCount, 1)
    }

    private func makeTemporaryDirectory(named name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkingMemorySnapshotTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)

        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        temporaryURLs.append(url.deletingLastPathComponent())
        return url
    }

    private func waitForRecorderCount(
        _ expectedCount: Int,
        recorder: SummaryRecorder,
        timeoutNanoseconds: UInt64 = 1_000_000_000
    ) async throws {
        let intervalNanoseconds: UInt64 = 10_000_000
        var waitedNanoseconds: UInt64 = 0

        while recorder.count < expectedCount && waitedNanoseconds < timeoutNanoseconds {
            try await Task.sleep(nanoseconds: intervalNanoseconds)
            waitedNanoseconds += intervalNanoseconds
        }

        XCTAssertEqual(recorder.count, expectedCount)
    }
}

private final class SummaryRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var summaries: [FileChangeSummary] = []

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return summaries.count
    }

    func append(_ summary: FileChangeSummary) {
        lock.lock()
        defer { lock.unlock() }
        summaries.append(summary)
    }
}

private final class FakeFileEventStreamBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storedStream: FakeFileEventStream?

    func store(_ stream: FakeFileEventStream) {
        lock.lock()
        defer { lock.unlock() }
        storedStream = stream
    }

    func stream() -> FakeFileEventStream? {
        lock.lock()
        defer { lock.unlock() }
        return storedStream
    }
}

private final class FakeFileEventStream: FileEventStreaming, @unchecked Sendable {
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
