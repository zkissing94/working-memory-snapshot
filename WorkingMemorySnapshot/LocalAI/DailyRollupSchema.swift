import Foundation

struct DailyRollupGeneratedProjectThread: Equatable, Sendable {
    var projectID: UUID
    var summary: String
}

struct DailyRollupGeneratedCarryForward: Equatable, Sendable {
    var projectID: UUID
    var text: String
}

struct DailyRollupGenerationResult: Equatable, Sendable {
    var daySummary: String
    var projectThreads: [DailyRollupGeneratedProjectThread]
    var carryForwards: [DailyRollupGeneratedCarryForward]
    var closureNote: String
}

enum DailyRollupValidationError: Error, Equatable {
    case invalidJSON
    case unexpectedField(String)
    case emptyRequiredField(String)
    case invalidProjectID(String)
    case unknownProjectID(UUID)
    case duplicateProjectID(UUID)
    case missingProjectID(UUID)
    case tooManyCarryForwards(Int)
    case fieldTooLong(field: String, wordCount: Int, limit: Int)
}

enum DailyRollupSchema {
    static let name = "working_memory_daily_rollup"
    static let daySummaryWordLimit = 100
    static let projectSummaryWordLimit = 90
    static let carryForwardWordLimit = 30
    static let closureNoteWordLimit = 60
    static let carryForwardLimit = 6

    static func schemaObject(projectIDs: Set<UUID>) -> [String: Any] {
        let projectIDStrings = projectIDs.map(\.uuidString).sorted()
        return [
            "type": "object",
            "properties": [
                "day_summary": ["type": "string"],
                "project_threads": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "properties": [
                            "project_id": ["type": "string", "enum": projectIDStrings],
                            "summary": ["type": "string"]
                        ],
                        "required": ["project_id", "summary"],
                        "additionalProperties": false
                    ]
                ],
                "carry_forwards": [
                    "type": "array",
                    "maxItems": carryForwardLimit,
                    "items": [
                        "type": "object",
                        "properties": [
                            "project_id": ["type": "string", "enum": projectIDStrings],
                            "text": ["type": "string"]
                        ],
                        "required": ["project_id", "text"],
                        "additionalProperties": false
                    ]
                ],
                "closure_note": ["type": "string"]
            ],
            "required": ["day_summary", "project_threads", "carry_forwards", "closure_note"],
            "additionalProperties": false
        ]
    }

    static func validateJSONContent(
        _ content: String,
        expectedProjectIDs: Set<UUID>
    ) throws -> DailyRollupGenerationResult {
        guard let data = content.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw DailyRollupValidationError.invalidJSON
        }
        try validateKeys(object, allowed: ["day_summary", "project_threads", "carry_forwards", "closure_note"], field: "root")
        try validateNestedKeys(object["project_threads"], allowed: ["project_id", "summary"], field: "project_threads")
        try validateNestedKeys(object["carry_forwards"], allowed: ["project_id", "text"], field: "carry_forwards")

        let decoded: Response
        do {
            decoded = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw DailyRollupValidationError.invalidJSON
        }

        let daySummary = try nonEmpty(decoded.daySummary, field: "day_summary")
        try enforceWordLimit(daySummary, field: "day_summary", limit: daySummaryWordLimit)
        let closureNote = try nonEmpty(decoded.closureNote, field: "closure_note")
        try enforceWordLimit(closureNote, field: "closure_note", limit: closureNoteWordLimit)

        var seen: Set<UUID> = []
        let threads = try decoded.projectThreads.map { value in
            let id = try projectID(value.projectID, expected: expectedProjectIDs)
            guard seen.insert(id).inserted else {
                throw DailyRollupValidationError.duplicateProjectID(id)
            }
            let summary = try nonEmpty(value.summary, field: "project_threads.summary")
            try enforceWordLimit(summary, field: "project_threads.summary", limit: projectSummaryWordLimit)
            return DailyRollupGeneratedProjectThread(projectID: id, summary: summary)
        }
        if let missing = expectedProjectIDs.subtracting(seen).sorted(by: { $0.uuidString < $1.uuidString }).first {
            throw DailyRollupValidationError.missingProjectID(missing)
        }

        guard decoded.carryForwards.count <= carryForwardLimit else {
            throw DailyRollupValidationError.tooManyCarryForwards(decoded.carryForwards.count)
        }
        let carryForwards = try decoded.carryForwards.map { value in
            let id = try projectID(value.projectID, expected: expectedProjectIDs)
            let text = try nonEmpty(value.text, field: "carry_forwards.text")
            try enforceWordLimit(text, field: "carry_forwards.text", limit: carryForwardWordLimit)
            return DailyRollupGeneratedCarryForward(projectID: id, text: text)
        }

        return DailyRollupGenerationResult(
            daySummary: daySummary,
            projectThreads: threads,
            carryForwards: carryForwards,
            closureNote: closureNote
        )
    }

    private static func projectID(_ value: String, expected: Set<UUID>) throws -> UUID {
        guard let id = UUID(uuidString: value) else {
            throw DailyRollupValidationError.invalidProjectID(value)
        }
        guard expected.contains(id) else {
            throw DailyRollupValidationError.unknownProjectID(id)
        }
        return id
    }

    private static func nonEmpty(_ value: String, field: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw DailyRollupValidationError.emptyRequiredField(field)
        }
        return trimmed
    }

    private static func enforceWordLimit(_ value: String, field: String, limit: Int) throws {
        let count = value.split { $0.isWhitespace || $0.isNewline }.count
        guard count <= limit else {
            throw DailyRollupValidationError.fieldTooLong(field: field, wordCount: count, limit: limit)
        }
    }

    private static func validateKeys(_ object: [String: Any], allowed: Set<String>, field: String) throws {
        if let extra = Set(object.keys).subtracting(allowed).sorted().first {
            throw DailyRollupValidationError.unexpectedField("\(field).\(extra)")
        }
    }

    private static func validateNestedKeys(_ value: Any?, allowed: Set<String>, field: String) throws {
        guard let values = value as? [[String: Any]] else { return }
        for object in values {
            try validateKeys(object, allowed: allowed, field: field)
        }
    }

    private struct Response: Decodable {
        var daySummary: String
        var projectThreads: [ProjectThread]
        var carryForwards: [CarryForward]
        var closureNote: String

        enum CodingKeys: String, CodingKey {
            case daySummary = "day_summary"
            case projectThreads = "project_threads"
            case carryForwards = "carry_forwards"
            case closureNote = "closure_note"
        }
    }

    private struct ProjectThread: Decodable {
        var projectID: String
        var summary: String

        enum CodingKeys: String, CodingKey {
            case projectID = "project_id"
            case summary
        }
    }

    private struct CarryForward: Decodable {
        var projectID: String
        var text: String

        enum CodingKeys: String, CodingKey {
            case projectID = "project_id"
            case text
        }
    }
}
