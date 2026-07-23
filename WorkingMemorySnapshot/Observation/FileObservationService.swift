import CoreServices
import Foundation

struct FileObservationConfiguration: Equatable, Sendable {
    var projectRootURL: URL
    var ignoredDirectorySegments: Set<String>
    var maximumChangedPathCount: Int
    var eventLatency: TimeInterval

    init(
        projectRootURL: URL,
        ignoredDirectorySegments: Set<String> = ProjectPathFilter.defaultIgnoredDirectorySegments,
        maximumChangedPathCount: Int = 500,
        eventLatency: TimeInterval = 0.5
    ) {
        self.projectRootURL = projectRootURL
        self.ignoredDirectorySegments = ignoredDirectorySegments
        self.maximumChangedPathCount = max(1, maximumChangedPathCount)
        self.eventLatency = eventLatency
    }
}

struct ProjectPathFilter: Equatable, Sendable {
    static let defaultIgnoredDirectorySegments: Set<String> = [
        ".git",
        "node_modules",
        ".next",
        "dist",
        "build",
        "DerivedData",
        ".venv",
        "venv",
        ".swiftpm",
        ".build"
    ]

    private let rootPathComponents: [String]
    private let ignoredDirectorySegments: Set<String>

    init(
        projectRootURL: URL,
        ignoredDirectorySegments: Set<String> = ProjectPathFilter.defaultIgnoredDirectorySegments
    ) {
        rootPathComponents = ProjectPathFilter.normalizedURL(projectRootURL).pathComponents
        self.ignoredDirectorySegments = ignoredDirectorySegments
    }

    func relativePath(for changedPath: String) -> String? {
        relativePath(for: URL(fileURLWithPath: changedPath))
    }

    func relativePath(for changedURL: URL) -> String? {
        let changedPathComponents = ProjectPathFilter.normalizedURL(changedURL).pathComponents

        guard changedPathComponents.count > rootPathComponents.count else {
            return nil
        }

        guard zip(rootPathComponents, changedPathComponents).allSatisfy({ rootComponent, changedComponent in
            rootComponent == changedComponent
        }) else {
            return nil
        }

        let relativeComponents = Array(changedPathComponents.dropFirst(rootPathComponents.count))
        guard !relativeComponents.contains(where: { ignoredDirectorySegments.contains($0) }) else {
            return nil
        }

        return relativeComponents.joined(separator: "/")
    }

    private static func normalizedURL(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }
}

struct ObservedFileChange: Equatable, Sendable {
    let relativePath: String
    let firstObservedAt: Date
    let lastObservedAt: Date
    let changeCount: Int
}

struct FileChangeSummary: Equatable, Sendable {
    let changes: [ObservedFileChange]
    let droppedChangeCount: Int

    var isTruncated: Bool {
        droppedChangeCount > 0
    }
}

struct FileObservationStopSummary: Equatable, Sendable {
    let finalCheckpoint: FileChangeSummary
    let sessionSummary: FileChangeSummary
}

struct FileChangeAggregator: Equatable, Sendable {
    private struct MutableChange: Equatable, Sendable {
        var firstObservedAt: Date
        var lastObservedAt: Date
        var changeCount: Int
    }

    private let maximumUniquePaths: Int
    private var relativePathsInObservationOrder: [String] = []
    private var changesByRelativePath: [String: MutableChange] = [:]
    private(set) var droppedChangeCount = 0

    init(maximumUniquePaths: Int = 500) {
        self.maximumUniquePaths = max(1, maximumUniquePaths)
    }

    @discardableResult
    mutating func record(relativePath: String, at timestamp: Date) -> Bool {
        guard !relativePath.isEmpty else {
            return false
        }

        if var existingChange = changesByRelativePath[relativePath] {
            existingChange.lastObservedAt = timestamp
            existingChange.changeCount += 1
            changesByRelativePath[relativePath] = existingChange
            return true
        }

        guard changesByRelativePath.count < maximumUniquePaths else {
            droppedChangeCount += 1
            return true
        }

        relativePathsInObservationOrder.append(relativePath)
        changesByRelativePath[relativePath] = MutableChange(
            firstObservedAt: timestamp,
            lastObservedAt: timestamp,
            changeCount: 1
        )
        return true
    }

    mutating func reset() {
        relativePathsInObservationOrder.removeAll()
        changesByRelativePath.removeAll()
        droppedChangeCount = 0
    }

    func contains(relativePath: String) -> Bool {
        changesByRelativePath[relativePath] != nil
    }

    mutating func recordDroppedChange() {
        droppedChangeCount += 1
    }

    func summary() -> FileChangeSummary {
        let changes = relativePathsInObservationOrder.compactMap { relativePath -> ObservedFileChange? in
            guard let change = changesByRelativePath[relativePath] else {
                return nil
            }

            return ObservedFileChange(
                relativePath: relativePath,
                firstObservedAt: change.firstObservedAt,
                lastObservedAt: change.lastObservedAt,
                changeCount: change.changeCount
            )
        }

        return FileChangeSummary(changes: changes, droppedChangeCount: droppedChangeCount)
    }
}

protocol FileEventStreaming: AnyObject {
    func start() throws
    func stop()
}

enum FileObservationError: Error, Equatable, LocalizedError {
    case streamCreationFailed
    case streamStartFailed

    var errorDescription: String? {
        switch self {
        case .streamCreationFailed:
            "File observation could not be created for this project."
        case .streamStartFailed:
            "File observation could not be started for this project."
        }
    }
}

actor FileObservationService {
    typealias StreamBuilder = @Sendable (
        _ projectRootURL: URL,
        _ eventLatency: TimeInterval,
        _ handler: @escaping @Sendable ([String], Date) -> Void
    ) -> FileEventStreaming

    private let streamBuilder: StreamBuilder
    private var stream: FileEventStreaming?
    private var pathFilter: ProjectPathFilter?
    private var sessionAggregator = FileChangeAggregator()
    private var checkpointAggregator = FileChangeAggregator()
    private var onChange: (@Sendable (FileChangeSummary) -> Void)?
    private var isObserving = false

    init(streamBuilder: @escaping StreamBuilder = FileObservationService.defaultStreamBuilder) {
        self.streamBuilder = streamBuilder
    }

    func start(
        configuration: FileObservationConfiguration,
        onChange: (@Sendable (FileChangeSummary) -> Void)? = nil
    ) throws {
        stopCurrentStream()

        let normalizedRootURL = configuration.projectRootURL.standardizedFileURL.resolvingSymlinksInPath()
        let pathFilter = ProjectPathFilter(
            projectRootURL: normalizedRootURL,
            ignoredDirectorySegments: configuration.ignoredDirectorySegments
        )
        let stream = streamBuilder(normalizedRootURL, configuration.eventLatency) { [weak self] paths, occurredAt in
            Task {
                await self?.record(paths: paths, occurredAt: occurredAt)
            }
        }

        self.pathFilter = pathFilter
        self.sessionAggregator = FileChangeAggregator(maximumUniquePaths: configuration.maximumChangedPathCount)
        self.checkpointAggregator = FileChangeAggregator(maximumUniquePaths: configuration.maximumChangedPathCount)
        self.onChange = onChange
        self.stream = stream
        self.isObserving = true

        do {
            try stream.start()
        } catch {
            stopCurrentStream()
            throw error
        }
    }

    func stop() -> FileChangeSummary {
        stopAndCheckpoint().sessionSummary
    }

    func stopAndCheckpoint() -> FileObservationStopSummary {
        stopCurrentStream()
        return FileObservationStopSummary(
            finalCheckpoint: checkpointAggregator.summary(),
            sessionSummary: sessionAggregator.summary()
        )
    }

    func checkpoint() -> FileChangeSummary {
        guard isObserving else {
            return FileChangeSummary(changes: [], droppedChangeCount: 0)
        }

        let summary = checkpointAggregator.summary()
        checkpointAggregator.reset()
        return summary
    }

    func observedChanges() -> FileChangeSummary {
        sessionAggregator.summary()
    }

    private func record(paths: [String], occurredAt: Date) {
        guard isObserving, let pathFilter else {
            return
        }

        var didChange = false
        for path in paths {
            guard let relativePath = pathFilter.relativePath(for: path) else {
                continue
            }

            let sessionDidChange = sessionAggregator.record(relativePath: relativePath, at: occurredAt)
            let checkpointDidChange: Bool
            if sessionAggregator.contains(relativePath: relativePath) {
                checkpointDidChange = checkpointAggregator.record(relativePath: relativePath, at: occurredAt)
            } else {
                checkpointAggregator.recordDroppedChange()
                checkpointDidChange = true
            }
            didChange = sessionDidChange || checkpointDidChange || didChange
        }

        if didChange, let onChange {
            onChange(sessionAggregator.summary())
        }
    }

    private func stopCurrentStream() {
        isObserving = false
        stream?.stop()
        stream = nil
        pathFilter = nil
        onChange = nil
    }

    private static let defaultStreamBuilder: StreamBuilder = { projectRootURL, eventLatency, handler in
        FSEventsFileEventStream(
            projectRootURL: projectRootURL,
            eventLatency: eventLatency,
            eventHandler: handler
        )
    }
}

final class FSEventsFileEventStream: FileEventStreaming {
    private let projectRootURL: URL
    private let eventLatency: TimeInterval
    private let eventHandler: @Sendable ([String], Date) -> Void
    private let eventQueue = DispatchQueue(label: "com.broceps.WorkingMemorySnapshot.fileObservation")
    private var stream: FSEventStreamRef?

    init(
        projectRootURL: URL,
        eventLatency: TimeInterval,
        eventHandler: @escaping @Sendable ([String], Date) -> Void
    ) {
        self.projectRootURL = projectRootURL
        self.eventLatency = eventLatency
        self.eventHandler = eventHandler
    }

    deinit {
        stop()
    }

    func start() throws {
        guard stream == nil else {
            return
        }

        var context = FSEventStreamContext(
            version: 0,
            info: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagUseCFTypes |
                kFSEventStreamCreateFlagFileEvents |
                kFSEventStreamCreateFlagNoDefer
        )

        guard let createdStream = FSEventStreamCreate(
            kCFAllocatorDefault,
            FSEventsFileEventStream.handleEvents,
            &context,
            [projectRootURL.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            eventLatency,
            flags
        ) else {
            throw FileObservationError.streamCreationFailed
        }

        stream = createdStream
        FSEventStreamSetDispatchQueue(createdStream, eventQueue)

        guard FSEventStreamStart(createdStream) else {
            stop()
            throw FileObservationError.streamStartFailed
        }
    }

    func stop() {
        guard let stream else {
            return
        }

        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    private static let handleEvents: FSEventStreamCallback = { _, contextInfo, eventCount, eventPaths, _, _ in
        guard let contextInfo else {
            return
        }

        let observer = Unmanaged<FSEventsFileEventStream>
            .fromOpaque(contextInfo)
            .takeUnretainedValue()
        let paths = observer.paths(from: eventPaths, eventCount: eventCount)

        guard !paths.isEmpty else {
            return
        }

        observer.eventHandler(paths, Date())
    }

    private func paths(from eventPaths: UnsafeMutableRawPointer, eventCount: Int) -> [String] {
        let pathArray = unsafeBitCast(eventPaths, to: NSArray.self)
        var paths: [String] = []
        paths.reserveCapacity(eventCount)

        for index in 0..<eventCount {
            guard let path = pathArray[index] as? String else {
                continue
            }
            paths.append(path)
        }

        return paths
    }
}
