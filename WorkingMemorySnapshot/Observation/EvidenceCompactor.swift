import Foundation

struct EvidenceCompactionConfiguration: Equatable, Sendable {
    var maxChangedPaths: Int = 80
    var maxActiveApplications: Int = 20
    var maxGitEvidenceLines: Int = 80
    var maxNotes: Int = 20
}

struct SnapshotEvidenceDigest: Equatable, Sendable {
    let projectName: String
    let mission: String
    let startedAt: Date
    let endedAt: Date?
    let durationSeconds: Int?
    let brainDump: String
    let pomodoroBlocks: [CompactedPomodoroBlock]
    let changedPaths: [CompactedChangedPath]
    let gitEvidenceLines: [String]
    let activeApplications: [CompactedActiveApplication]
    let compactorNotes: [String]
}

struct CompactedPomodoroBlock: Equatable, Sendable {
    let blockIndex: Int
    let status: PomodoroBlockStatus
    let intention: String?
    let summary: String?
    let startedAt: Date
    let endedAt: Date?
    let plannedDurationSeconds: Int
    let elapsedSeconds: Int
    let increments: [CompactedWorkIncrement]
}

struct CompactedWorkIncrement: Equatable, Sendable {
    let occurredAt: Date
    let kind: WorkIncrementKind
    let title: String
    let detail: String?
}

struct CompactedChangedPath: Equatable, Sendable {
    let relativePath: String
    let changeCount: Int
    let firstObservedAt: Date?
    let lastObservedAt: Date?
}

struct CompactedActiveApplication: Equatable, Sendable {
    let displayName: String
    let bundleIdentifier: String?
}

struct EvidenceCompactor: Sendable {
    private let configuration: EvidenceCompactionConfiguration

    init(configuration: EvidenceCompactionConfiguration = EvidenceCompactionConfiguration()) {
        self.configuration = configuration
    }

    func compact(
        project: Project,
        session: WorkSession,
        events: [SessionEvent],
        pomodoroBlocks: [PomodoroBlock] = [],
        workIncrementsByBlockID: [PomodoroBlock.ID: [WorkIncrement]] = [:]
    ) -> SnapshotEvidenceDigest {
        var notes: [String] = []
        let sortedEvents = events.sorted { first, second in
            if first.occurredAt == second.occurredAt {
                return first.createdAt < second.createdAt
            }
            return first.occurredAt < second.occurredAt
        }

        let changedPaths = compactChangedPaths(from: sortedEvents, notes: &notes)
        let activeApplications = compactActiveApplications(from: sortedEvents, notes: &notes)
        let gitEvidenceLines = compactGitEvidence(from: sortedEvents, notes: &notes)
        let compactedBlocks = compactPomodoroBlocks(
            pomodoroBlocks,
            workIncrementsByBlockID: workIncrementsByBlockID
        )
        appendObservationIssues(from: sortedEvents, notes: &notes)

        let endedAt = session.endedAt
        let durationSeconds = endedAt.map { max(0, Int($0.timeIntervalSince(session.startedAt))) }

        return SnapshotEvidenceDigest(
            projectName: project.name,
            mission: session.mission,
            startedAt: session.startedAt,
            endedAt: endedAt,
            durationSeconds: durationSeconds,
            brainDump: session.brainDump ?? "",
            pomodoroBlocks: compactedBlocks,
            changedPaths: changedPaths,
            gitEvidenceLines: gitEvidenceLines,
            activeApplications: activeApplications,
            compactorNotes: Array(notes.prefix(configuration.maxNotes))
        )
    }

    private func compactPomodoroBlocks(
        _ blocks: [PomodoroBlock],
        workIncrementsByBlockID: [PomodoroBlock.ID: [WorkIncrement]]
    ) -> [CompactedPomodoroBlock] {
        blocks
            .sorted { $0.blockIndex < $1.blockIndex }
            .map { block in
                let increments = (workIncrementsByBlockID[block.id] ?? [])
                    .sorted { first, second in
                        if first.occurredAt == second.occurredAt {
                            return first.createdAt < second.createdAt
                        }
                        return first.occurredAt < second.occurredAt
                    }
                    .map {
                        CompactedWorkIncrement(
                            occurredAt: $0.occurredAt,
                            kind: $0.kind,
                            title: $0.title,
                            detail: $0.detail
                        )
                    }

                return CompactedPomodoroBlock(
                    blockIndex: block.blockIndex,
                    status: block.status,
                    intention: block.intention,
                    summary: block.summary,
                    startedAt: block.startedAt,
                    endedAt: block.endedAt,
                    plannedDurationSeconds: block.plannedDurationSeconds,
                    elapsedSeconds: block.elapsedSeconds(at: block.endedAt ?? Date()),
                    increments: increments
                )
            }
    }

    private func compactChangedPaths(
        from events: [SessionEvent],
        notes: inout [String]
    ) -> [CompactedChangedPath] {
        struct MutablePath {
            var changeCount: Int
            var firstObservedAt: Date?
            var lastObservedAt: Date?
        }

        var orderedPaths: [String] = []
        var pathsByName: [String: MutablePath] = [:]

        for event in events where event.source == .file && event.kind == SessionEventKind.fileChanged {
            let payload = decodePayload(FileChangedEventPayload.self, from: event.payloadJSON)
            let relativePath = (payload?.relativePath ?? event.title)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !relativePath.isEmpty else {
                continue
            }

            let firstObservedAt = payload.flatMap { try? DateCoding.date(from: $0.firstObservedAt) } ?? event.occurredAt
            let lastObservedAt = payload.flatMap { try? DateCoding.date(from: $0.lastObservedAt) } ?? event.occurredAt
            let changeCount = max(1, payload?.changeCount ?? 1)

            if var existing = pathsByName[relativePath] {
                existing.changeCount += changeCount
                existing.firstObservedAt = minDate(existing.firstObservedAt, firstObservedAt)
                existing.lastObservedAt = maxDate(existing.lastObservedAt, lastObservedAt)
                pathsByName[relativePath] = existing
            } else {
                orderedPaths.append(relativePath)
                pathsByName[relativePath] = MutablePath(
                    changeCount: changeCount,
                    firstObservedAt: firstObservedAt,
                    lastObservedAt: lastObservedAt
                )
            }
        }

        if orderedPaths.count > configuration.maxChangedPaths {
            notes.append(
                "\(orderedPaths.count - configuration.maxChangedPaths) changed path(s) were omitted from the prompt because of evidence bounds."
            )
        }

        return orderedPaths
            .prefix(configuration.maxChangedPaths)
            .compactMap { path in
                guard let compacted = pathsByName[path] else {
                    return nil
                }
                return CompactedChangedPath(
                    relativePath: path,
                    changeCount: compacted.changeCount,
                    firstObservedAt: compacted.firstObservedAt,
                    lastObservedAt: compacted.lastObservedAt
                )
            }
    }

    private func compactActiveApplications(
        from events: [SessionEvent],
        notes: inout [String]
    ) -> [CompactedActiveApplication] {
        var seen = Set<String>()
        var applications: [CompactedActiveApplication] = []

        for event in events where event.source == .activeApp && event.kind == SessionEventKind.appActivated {
            let payload = decodePayload(ActiveAppEventPayload.self, from: event.payloadJSON)
            let displayName = (payload?.displayName ?? event.title)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !displayName.isEmpty else {
                continue
            }

            let key = "\(displayName)\u{0}\(payload?.bundleIdentifier ?? "")"
            guard !seen.contains(key) else {
                continue
            }

            seen.insert(key)
            applications.append(
                CompactedActiveApplication(
                    displayName: displayName,
                    bundleIdentifier: payload?.bundleIdentifier
                )
            )
        }

        if applications.count > configuration.maxActiveApplications {
            notes.append(
                "\(applications.count - configuration.maxActiveApplications) active application(s) were omitted from the prompt because of evidence bounds."
            )
        }

        return Array(applications.prefix(configuration.maxActiveApplications))
    }

    private func compactGitEvidence(
        from events: [SessionEvent],
        notes: inout [String]
    ) -> [String] {
        var lines: [String] = []

        for event in events where event.source == .git {
            if let body = event.body, !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines.append("[\(event.kind)]")
                lines.append(contentsOf: bodyLines(from: body))
            } else if event.kind == SessionEventKind.gitInitialState || event.kind == SessionEventKind.gitFinalSummary {
                lines.append("[\(event.kind)] \(event.title)")
            }
        }

        if lines.count > configuration.maxGitEvidenceLines {
            notes.append(
                "\(lines.count - configuration.maxGitEvidenceLines) Git evidence line(s) were omitted from the prompt because of evidence bounds."
            )
        }

        return Array(lines.prefix(configuration.maxGitEvidenceLines))
    }

    private func appendObservationIssues(from events: [SessionEvent], notes: inout [String]) {
        for event in events where event.kind == SessionEventKind.observationIssue {
            if let body = event.body, !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                notes.append(body)
            } else {
                notes.append(event.title)
            }
        }
    }

    private func bodyLines(from body: String) -> [String] {
        body.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func decodePayload<Value: Decodable>(_ type: Value.Type, from json: String?) -> Value? {
        guard let json else {
            return nil
        }
        return try? EventPayloadCoding.decode(type, from: json)
    }

    private func minDate(_ first: Date?, _ second: Date?) -> Date? {
        switch (first, second) {
        case (nil, nil):
            nil
        case (.some(let date), nil), (nil, .some(let date)):
            date
        case (.some(let first), .some(let second)):
            min(first, second)
        }
    }

    private func maxDate(_ first: Date?, _ second: Date?) -> Date? {
        switch (first, second) {
        case (nil, nil):
            nil
        case (.some(let date), nil), (nil, .some(let date)):
            date
        case (.some(let first), .some(let second)):
            max(first, second)
        }
    }
}
