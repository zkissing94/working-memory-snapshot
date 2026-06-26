import Foundation

struct PlaceholderSnapshotGenerator {
    static let generatorModel = "deterministic-placeholder"
    static let promptVersion = "placeholder-v1"

    func makeSnapshot(mission: String, brainDump: String?) -> SnapshotDraft {
        let normalizedMission = normalizedText(mission)
        let normalizedBrainDump = normalizedText(brainDump ?? "")

        return SnapshotDraft(
            whatChanged: whatChanged(from: normalizedBrainDump),
            decisions: [],
            openLoops: explicitOpenLoop(from: normalizedBrainDump).map { [$0] } ?? [],
            nextAction: explicitNextAction(from: normalizedBrainDump)
                ?? "Review the prior mission and choose the first verification step.",
            resumeBrief: resumeBrief(mission: normalizedMission, brainDump: normalizedBrainDump),
            generatorModel: Self.generatorModel,
            promptVersion: Self.promptVersion
        )
    }

    private func whatChanged(from brainDump: String) -> String {
        guard !brainDump.isEmpty else {
            return "No change was captured in the brain dump."
        }

        return "Brain dump: \(limitedWords(firstStatement(from: brainDump) ?? brainDump, maxWords: 40))"
    }

    private func explicitNextAction(from brainDump: String) -> String? {
        for statement in statements(from: brainDump) {
            let candidates = [
                "next action",
                "next",
                "start here",
                "do next",
                "todo",
                "to do",
                "i would do next",
                "what i would do next"
            ]

            for candidate in candidates {
                if let value = value(afterPrefix: candidate, in: statement) {
                    return value
                }
            }
        }

        return nil
    }

    private func explicitOpenLoop(from brainDump: String) -> String? {
        for statement in statements(from: brainDump) {
            let lowercased = statement.lowercased()
            if isNextActionStatement(lowercased) {
                continue
            }
            if lowercased.contains("blocked")
                || lowercased.contains("blocker")
                || lowercased.contains("stuck")
                || lowercased.contains("unresolved")
                || lowercased.contains("open question")
                || lowercased.contains("open loop")
                || lowercased.contains("unfinished")
                || lowercased.contains("not finished")
                || lowercased.contains("still need")
                || lowercased.contains("need to") {
                return statement
            }
        }

        return nil
    }

    private func resumeBrief(mission: String, brainDump: String) -> String {
        let missionPart: String
        if mission.isEmpty {
            missionPart = "Mission: No mission was captured."
        } else {
            missionPart = "Mission: \(limitedWords(mission, maxWords: 45))"
        }

        let brainDumpPart: String
        if brainDump.isEmpty {
            brainDumpPart = "Brain dump: No brain dump was captured."
        } else {
            brainDumpPart = "Brain dump: \(limitedWords(brainDump, maxWords: 90))"
        }

        return limitedWords("\(missionPart) \(brainDumpPart)", maxWords: 120)
    }

    private func statements(from text: String) -> [String] {
        text.split { character in
            character == "\n" || character == "." || character == "!" || character == "?"
        }
        .map { normalizedText(String($0)) }
        .filter { !$0.isEmpty }
    }

    private func firstStatement(from text: String) -> String? {
        statements(from: text).first
    }

    private func value(afterPrefix prefix: String, in statement: String) -> String? {
        let normalizedStatement = normalizedText(statement)
        let lowercased = normalizedStatement.lowercased()
        guard lowercased.hasPrefix(prefix) else {
            return nil
        }

        let remaining = normalizedStatement.dropFirst(prefix.count)
        let value = remaining
            .trimmingCharacters(in: CharacterSet(charactersIn: " :-\t"))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return value.isEmpty ? nil : value
    }

    private func isNextActionStatement(_ lowercasedStatement: String) -> Bool {
        lowercasedStatement.hasPrefix("next action")
            || lowercasedStatement.hasPrefix("next")
            || lowercasedStatement.hasPrefix("start here")
            || lowercasedStatement.hasPrefix("do next")
            || lowercasedStatement.hasPrefix("todo")
            || lowercasedStatement.hasPrefix("to do")
    }

    private func normalizedText(_ text: String) -> String {
        text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func limitedWords(_ text: String, maxWords: Int) -> String {
        let words = text.split(separator: " ")
        guard words.count > maxWords else {
            return text
        }

        return words.prefix(maxWords).joined(separator: " ") + "..."
    }
}
