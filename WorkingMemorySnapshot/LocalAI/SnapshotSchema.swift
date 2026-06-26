import Foundation

struct SnapshotGenerationResult: Equatable, Sendable {
    var whatChanged: String
    var decisions: [String]
    var openLoops: [String]
    var nextAction: String
    var resumeBrief: String
}

enum SnapshotGenerationValidationError: Error, Equatable {
    case invalidJSON
    case emptyRequiredField(String)
    case emptyArrayItem(String)
    case resumeBriefTooLong(wordCount: Int)
}

enum SnapshotSchema {
    static let name = "working_memory_snapshot"
    static let resumeBriefWordLimit = 120

    static func schemaObject() -> [String: Any] {
        [
            "type": "object",
            "properties": [
                "what_changed": [
                    "type": "string"
                ],
                "decisions": [
                    "type": "array",
                    "items": [
                        "type": "string"
                    ]
                ],
                "open_loops": [
                    "type": "array",
                    "items": [
                        "type": "string"
                    ]
                ],
                "next_action": [
                    "type": "string"
                ],
                "resume_brief": [
                    "type": "string"
                ]
            ],
            "required": [
                "what_changed",
                "decisions",
                "open_loops",
                "next_action",
                "resume_brief"
            ],
            "additionalProperties": false
        ]
    }

    static func validateJSONContent(_ content: String) throws -> SnapshotGenerationResult {
        guard let data = content.data(using: .utf8) else {
            throw SnapshotGenerationValidationError.invalidJSON
        }

        let decoded: SnapshotGenerationResponse
        do {
            decoded = try JSONDecoder().decode(SnapshotGenerationResponse.self, from: data)
        } catch {
            throw SnapshotGenerationValidationError.invalidJSON
        }

        return try validate(decoded)
    }

    private static func validate(_ response: SnapshotGenerationResponse) throws -> SnapshotGenerationResult {
        let whatChanged = response.whatChanged.trimmed()
        let decisions = try validateArray(response.decisions, field: "decisions")
        let openLoops = try validateArray(response.openLoops, field: "open_loops")
        let nextAction = response.nextAction.trimmed()
        let resumeBrief = response.resumeBrief.trimmed()

        guard !whatChanged.isEmpty else {
            throw SnapshotGenerationValidationError.emptyRequiredField("what_changed")
        }

        guard !nextAction.isEmpty else {
            throw SnapshotGenerationValidationError.emptyRequiredField("next_action")
        }

        guard !resumeBrief.isEmpty else {
            throw SnapshotGenerationValidationError.emptyRequiredField("resume_brief")
        }

        let resumeBriefWordCount = resumeBrief.wordCount
        guard resumeBriefWordCount <= resumeBriefWordLimit else {
            throw SnapshotGenerationValidationError.resumeBriefTooLong(wordCount: resumeBriefWordCount)
        }

        return SnapshotGenerationResult(
            whatChanged: whatChanged,
            decisions: decisions,
            openLoops: openLoops,
            nextAction: nextAction,
            resumeBrief: resumeBrief
        )
    }

    private static func validateArray(_ values: [String], field: String) throws -> [String] {
        try values.map { value in
            let trimmedValue = value.trimmed()
            guard !trimmedValue.isEmpty else {
                throw SnapshotGenerationValidationError.emptyArrayItem(field)
            }
            return trimmedValue
        }
    }
}

private struct SnapshotGenerationResponse: Decodable {
    let whatChanged: String
    let decisions: [String]
    let openLoops: [String]
    let nextAction: String
    let resumeBrief: String

    enum CodingKeys: String, CodingKey {
        case whatChanged = "what_changed"
        case decisions
        case openLoops = "open_loops"
        case nextAction = "next_action"
        case resumeBrief = "resume_brief"
    }
}

private extension String {
    func trimmed() -> String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var wordCount: Int {
        split { $0.isWhitespace || $0.isNewline }.count
    }
}
