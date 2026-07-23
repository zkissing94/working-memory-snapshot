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
    let betweenBlocksObservation: CompactedObservationContext
    let unattributedObservation: CompactedObservationContext
    let gitSummary: CompactedGitSummary
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
    let observedContext: CompactedObservationContext
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

struct CompactedObservationContext: Equatable, Sendable {
    let changedPaths: [CompactedChangedPath]
    let activeApplications: [CompactedActiveApplication]

    static let empty = CompactedObservationContext(changedPaths: [], activeApplications: [])

    var isEmpty: Bool {
        changedPaths.isEmpty && activeApplications.isEmpty
    }
}

struct CompactedGitCommit: Equatable, Sendable {
    let hash: String
    let subject: String
}

struct CompactedGitSummary: Equatable, Sendable {
    let isRepository: Bool?
    let initialBranchName: String?
    let finalBranchName: String?
    let initialHeadSHA: String?
    let finalHeadSHA: String?
    let initialChangedPaths: [String]
    let sessionObservedChangedPaths: [String]
    let unobservedFinalChangedPaths: [String]
    let diffStatLines: [String]
    let commitsAfterStart: [CompactedGitCommit]
    let isTruncated: Bool

    static let empty = CompactedGitSummary(
        isRepository: nil,
        initialBranchName: nil,
        finalBranchName: nil,
        initialHeadSHA: nil,
        finalHeadSHA: nil,
        initialChangedPaths: [],
        sessionObservedChangedPaths: [],
        unobservedFinalChangedPaths: [],
        diffStatLines: [],
        commitsAfterStart: [],
        isTruncated: false
    )
}

struct EvidenceCompactor: Sendable {
    private enum ObservationContextKey: Hashable {
        case block(PomodoroBlock.ID)
        case betweenBlocks
        case unattributed
    }

    private struct MutableObservationContext {
        struct MutablePath {
            var changeCount: Int
            var firstObservedAt: Date?
            var lastObservedAt: Date?
        }

        var orderedPaths: [String] = []
        var pathsByName: [String: MutablePath] = [:]
        var applications: [CompactedActiveApplication] = []
        var applicationKeys = Set<String>()

        var compacted: CompactedObservationContext {
            CompactedObservationContext(
                changedPaths: orderedPaths.compactMap { path in
                    guard let value = pathsByName[path] else {
                        return nil
                    }
                    return CompactedChangedPath(
                        relativePath: path,
                        changeCount: value.changeCount,
                        firstObservedAt: value.firstObservedAt,
                        lastObservedAt: value.lastObservedAt
                    )
                },
                activeApplications: applications
            )
        }
    }

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

        let changedPaths = compactChangedPaths(from: sortedEvents)
        let activeApplications = compactActiveApplications(from: sortedEvents)
        let gitEvidenceLines = compactGitEvidence(from: sortedEvents, notes: &notes)
        let validBlockIDs = Set(pomodoroBlocks.map(\.id))
        let observationContexts = compactObservationContexts(
            from: sortedEvents,
            validBlockIDs: validBlockIDs,
            notes: &notes
        )
        let compactedBlocks = compactPomodoroBlocks(
            pomodoroBlocks,
            workIncrementsByBlockID: workIncrementsByBlockID,
            observationContexts: observationContexts
        )
        let gitSummary = compactGitSummary(from: sortedEvents)
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
            betweenBlocksObservation: observationContexts[.betweenBlocks] ?? .empty,
            unattributedObservation: observationContexts[.unattributed] ?? .empty,
            gitSummary: gitSummary,
            compactorNotes: Array(notes.prefix(configuration.maxNotes))
        )
    }

    private func compactPomodoroBlocks(
        _ blocks: [PomodoroBlock],
        workIncrementsByBlockID: [PomodoroBlock.ID: [WorkIncrement]],
        observationContexts: [ObservationContextKey: CompactedObservationContext]
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
                    increments: increments,
                    observedContext: observationContexts[.block(block.id)] ?? .empty
                )
            }
    }

    private func compactObservationContexts(
        from events: [SessionEvent],
        validBlockIDs: Set<PomodoroBlock.ID>,
        notes: inout [String]
    ) -> [ObservationContextKey: CompactedObservationContext] {
        var mutableContexts: [ObservationContextKey: MutableObservationContext] = [:]
        var acceptedChangedPathCount = 0
        var acceptedApplicationCount = 0
        var omittedChangedPathCount = 0
        var omittedApplicationCount = 0

        for event in events {
            if event.source == .file, event.kind == SessionEventKind.fileChanged {
                let payload = decodePayload(FileChangedEventPayload.self, from: event.payloadJSON)
                let path = (payload?.relativePath ?? event.title)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !path.isEmpty else {
                    continue
                }

                let contextKey = observationContextKey(
                    for: payload?.observationWindow,
                    validBlockIDs: validBlockIDs
                )
                var context = mutableContexts[contextKey] ?? MutableObservationContext()
                let firstObservedAt = payload.flatMap {
                    try? DateCoding.date(from: $0.firstObservedAt)
                } ?? event.occurredAt
                let lastObservedAt = payload.flatMap {
                    try? DateCoding.date(from: $0.lastObservedAt)
                } ?? event.occurredAt
                let changeCount = max(1, payload?.changeCount ?? 1)

                if var existing = context.pathsByName[path] {
                    existing.changeCount += changeCount
                    existing.firstObservedAt = minDate(existing.firstObservedAt, firstObservedAt)
                    existing.lastObservedAt = maxDate(existing.lastObservedAt, lastObservedAt)
                    context.pathsByName[path] = existing
                } else if acceptedChangedPathCount < configuration.maxChangedPaths {
                    acceptedChangedPathCount += 1
                    context.orderedPaths.append(path)
                    context.pathsByName[path] = MutableObservationContext.MutablePath(
                        changeCount: changeCount,
                        firstObservedAt: firstObservedAt,
                        lastObservedAt: lastObservedAt
                    )
                } else {
                    omittedChangedPathCount += 1
                }

                mutableContexts[contextKey] = context
            } else if event.source == .activeApp, event.kind == SessionEventKind.appActivated {
                let payload = decodePayload(ActiveAppEventPayload.self, from: event.payloadJSON)
                let displayName = (payload?.displayName ?? event.title)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !displayName.isEmpty else {
                    continue
                }

                let contextKey = observationContextKey(
                    for: payload?.observationWindow,
                    validBlockIDs: validBlockIDs
                )
                var context = mutableContexts[contextKey] ?? MutableObservationContext()
                let applicationKey = "\(displayName)\u{0}\(payload?.bundleIdentifier ?? "")"

                if context.applicationKeys.contains(applicationKey) {
                    continue
                }

                if acceptedApplicationCount < configuration.maxActiveApplications {
                    acceptedApplicationCount += 1
                    context.applicationKeys.insert(applicationKey)
                    context.applications.append(
                        CompactedActiveApplication(
                            displayName: displayName,
                            bundleIdentifier: payload?.bundleIdentifier
                        )
                    )
                } else {
                    omittedApplicationCount += 1
                }

                mutableContexts[contextKey] = context
            }
        }

        if omittedChangedPathCount > 0 {
            notes.append(
                "\(omittedChangedPathCount) block-aware changed path(s) were omitted because of evidence bounds."
            )
        }
        if omittedApplicationCount > 0 {
            notes.append(
                "\(omittedApplicationCount) block-aware active application(s) were omitted because of evidence bounds."
            )
        }

        return mutableContexts.mapValues(\.compacted)
    }

    private func observationContextKey(
        for window: ObservationWindowPayload?,
        validBlockIDs: Set<PomodoroBlock.ID>
    ) -> ObservationContextKey {
        guard let window else {
            return .unattributed
        }

        switch window.kind {
        case .betweenBlocks:
            return .betweenBlocks
        case .block:
            guard let blockID = window.blockID, validBlockIDs.contains(blockID) else {
                return .unattributed
            }
            return .block(blockID)
        }
    }

    private func compactChangedPaths(from events: [SessionEvent]) -> [CompactedChangedPath] {
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

    private func compactActiveApplications(from events: [SessionEvent]) -> [CompactedActiveApplication] {
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

        return Array(applications.prefix(configuration.maxActiveApplications))
    }

    private func compactGitSummary(from events: [SessionEvent]) -> CompactedGitSummary {
        let initialPayload = events
            .first(where: {
                $0.source == .git && $0.kind == SessionEventKind.gitInitialState
            })
            .flatMap { decodePayload(GitInitialStateEventPayload.self, from: $0.payloadJSON) }
        let finalPayload = events
            .last(where: {
                $0.source == .git && $0.kind == SessionEventKind.gitFinalSummary
            })
            .flatMap { decodePayload(GitFinalSummaryEventPayload.self, from: $0.payloadJSON) }

        guard initialPayload != nil || finalPayload != nil else {
            return .empty
        }

        return CompactedGitSummary(
            isRepository: finalPayload?.isRepository ?? initialPayload?.isRepository,
            initialBranchName: initialPayload?.branchName,
            finalBranchName: finalPayload?.branchName,
            initialHeadSHA: initialPayload?.headSHA,
            finalHeadSHA: finalPayload?.headSHA,
            initialChangedPaths: initialPayload?.changedPaths ?? [],
            sessionObservedChangedPaths: finalPayload?.sessionObservedChangedPaths ?? [],
            unobservedFinalChangedPaths: finalPayload?.unobservedChangedPaths ?? [],
            diffStatLines: finalPayload?.diffStatLines ?? [],
            commitsAfterStart: (finalPayload?.commitsAfterStart ?? []).map {
                CompactedGitCommit(hash: $0.hash, subject: $0.subject)
            },
            isTruncated: (initialPayload?.isStatusTruncated ?? false)
                || (finalPayload?.isStatusTruncated ?? false)
                || (finalPayload?.isDiffStatTruncated ?? false)
        )
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
