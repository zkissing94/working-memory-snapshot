import Foundation

enum EventPayloadCoding {
    static func encode<Value: Encodable>(_ value: Value) throws -> String {
        let data = try JSONEncoder().encode(value)
        guard let json = String(data: data, encoding: .utf8) else {
            throw EventPayloadCodingError.invalidUTF8
        }
        return json
    }

    static func decode<Value: Decodable>(_ type: Value.Type, from json: String) throws -> Value {
        guard let data = json.data(using: .utf8) else {
            throw EventPayloadCodingError.invalidUTF8
        }
        return try JSONDecoder().decode(type, from: data)
    }
}

enum EventPayloadCodingError: Error, Equatable {
    case invalidUTF8
}

enum ObservationWindowKind: String, Codable, Equatable, Sendable {
    case block
    case betweenBlocks = "between_blocks"
}

struct ObservationWindowPayload: Codable, Equatable, Sendable {
    let kind: ObservationWindowKind
    let blockID: UUID?

    static func current(blockID: PomodoroBlock.ID?) -> ObservationWindowPayload {
        if let blockID {
            return ObservationWindowPayload(kind: .block, blockID: blockID)
        }
        return ObservationWindowPayload(kind: .betweenBlocks, blockID: nil)
    }
}

struct FileChangedEventPayload: Codable, Equatable, Sendable {
    let relativePath: String
    let firstObservedAt: String
    let lastObservedAt: String
    let changeCount: Int
    let observationWindow: ObservationWindowPayload?

    init(
        relativePath: String,
        firstObservedAt: String,
        lastObservedAt: String,
        changeCount: Int,
        observationWindow: ObservationWindowPayload? = nil
    ) {
        self.relativePath = relativePath
        self.firstObservedAt = firstObservedAt
        self.lastObservedAt = lastObservedAt
        self.changeCount = changeCount
        self.observationWindow = observationWindow
    }
}

struct ActiveAppEventPayload: Codable, Equatable, Sendable {
    let displayName: String
    let bundleIdentifier: String?
    let observationWindow: ObservationWindowPayload?

    init(
        displayName: String,
        bundleIdentifier: String?,
        observationWindow: ObservationWindowPayload? = nil
    ) {
        self.displayName = displayName
        self.bundleIdentifier = bundleIdentifier
        self.observationWindow = observationWindow
    }
}

struct GitInitialStateEventPayload: Codable, Equatable, Sendable {
    let isRepository: Bool
    let branchName: String?
    let headSHA: String?
    let changedPaths: [String]
    let isStatusTruncated: Bool
}

struct GitFinalSummaryEventPayload: Codable, Equatable, Sendable {
    let isRepository: Bool
    let branchName: String?
    let headSHA: String?
    let sessionObservedChangedPaths: [String]
    let unobservedChangedPaths: [String]
    let diffStatLines: [String]
    let commitsAfterStart: [GitCommitEventPayload]
    let hasSessionObservedChanges: Bool
    let isStatusTruncated: Bool
    let isDiffStatTruncated: Bool
}

struct GitCommitEventPayload: Codable, Equatable, Sendable {
    let hash: String
    let subject: String
}
