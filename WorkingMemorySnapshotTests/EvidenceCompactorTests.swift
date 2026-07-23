import XCTest
@testable import WorkingMemorySnapshot

final class EvidenceCompactorTests: XCTestCase {
    func testCompactorPreservesBrainDumpVerbatimAndBoundsPassiveEvidence() throws {
        let project = makeProject()
        let session = makeCompletedSession(
            brainDump: "Decision: keep local data local.\nNext: wire retry without losing this text."
        )
        let compactor = EvidenceCompactor(
            configuration: EvidenceCompactionConfiguration(
                maxChangedPaths: 2,
                maxActiveApplications: 1,
                maxGitEvidenceLines: 3,
                maxNotes: 10
            )
        )
        let events = try [
            fileEvent(path: "Sources/App.swift", count: 2, at: 10),
            fileEvent(path: "Tests/AppTests.swift", count: 1, at: 20),
            fileEvent(path: "README.md", count: 1, at: 30),
            activeAppEvent(name: "Terminal", bundleIdentifier: "com.apple.Terminal", at: 40),
            activeAppEvent(name: "Xcode", bundleIdentifier: "com.apple.dt.Xcode", at: 50),
            gitEvent(body: "Branch: main\nHEAD: abc123\nDiff stat:\n Sources/App.swift | 2 +-\n Tests/AppTests.swift | 4 ++--")
        ]

        let digest = compactor.compact(project: project, session: session, events: events)

        XCTAssertEqual(digest.brainDump, session.brainDump)
        XCTAssertEqual(digest.changedPaths.map(\.relativePath), ["Sources/App.swift", "Tests/AppTests.swift"])
        XCTAssertEqual(digest.changedPaths.first?.changeCount, 2)
        XCTAssertEqual(digest.activeApplications.map(\.displayName), ["Terminal"])
        XCTAssertEqual(digest.gitEvidenceLines, ["[git_final_summary]", "Branch: main", "HEAD: abc123"])
        XCTAssertTrue(digest.compactorNotes.contains { $0.contains("changed path") })
        XCTAssertTrue(digest.compactorNotes.contains { $0.contains("active application") })
        XCTAssertTrue(digest.compactorNotes.contains { $0.contains("Git evidence") })
    }

    func testCompactorDeduplicatesActiveApplicationsInOrder() throws {
        let session = makeCompletedSession(brainDump: "")
        let events = try [
            activeAppEvent(name: "Terminal", bundleIdentifier: "com.apple.Terminal", at: 10),
            activeAppEvent(name: "Terminal", bundleIdentifier: "com.apple.Terminal", at: 20),
            activeAppEvent(name: "Safari", bundleIdentifier: "com.apple.Safari", at: 30)
        ]

        let digest = EvidenceCompactor().compact(
            project: makeProject(),
            session: session,
            events: events
        )

        XCTAssertEqual(digest.activeApplications.map(\.displayName), ["Terminal", "Safari"])
    }

    func testCompactorIncludesPomodoroBlocksAndManualIncrements() {
        let session = makeCompletedSession(brainDump: "Next: use block notes.")
        let block = PomodoroBlock(
            id: UUID(),
            sessionID: session.id,
            blockIndex: 1,
            plannedDurationSeconds: 1_200,
            intention: "Implement block capture",
            summary: "Completed repository and prompt wiring.",
            status: .completed,
            startedAt: Date(timeIntervalSince1970: 100),
            pausedAt: nil,
            accumulatedPauseSeconds: 0,
            endedAt: Date(timeIntervalSince1970: 700),
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 700)
        )
        let increment = WorkIncrement(
            id: UUID(),
            blockID: block.id,
            occurredAt: Date(timeIntervalSince1970: 300),
            kind: .decision,
            title: "Blocks live inside sessions",
            detail: "Passive events stay generic.",
            createdAt: Date(timeIntervalSince1970: 300),
            updatedAt: Date(timeIntervalSince1970: 300)
        )

        let digest = EvidenceCompactor().compact(
            project: makeProject(),
            session: session,
            events: [],
            pomodoroBlocks: [block],
            workIncrementsByBlockID: [block.id: [increment]]
        )

        XCTAssertEqual(digest.pomodoroBlocks.first?.intention, "Implement block capture")
        XCTAssertEqual(digest.pomodoroBlocks.first?.summary, "Completed repository and prompt wiring.")
        XCTAssertEqual(digest.pomodoroBlocks.first?.increments.first?.title, "Blocks live inside sessions")
    }

    func testCompactorGroupsCheckpointedEvidenceByBlockAndPreservesLegacyFallback() throws {
        let session = makeCompletedSession(brainDump: "")
        let firstBlock = makeBlock(sessionID: session.id, index: 1, start: 100, end: 150)
        let secondBlock = makeBlock(sessionID: session.id, index: 2, start: 170, end: 210)
        let firstBlockWindow = ObservationWindowPayload(kind: .block, blockID: firstBlock.id)
        let betweenBlocksWindow = ObservationWindowPayload(kind: .betweenBlocks, blockID: nil)
        let events = try [
            fileEvent(path: "Sources/First.swift", count: 2, at: 120, window: firstBlockWindow),
            activeAppEvent(
                name: "Xcode",
                bundleIdentifier: "com.apple.dt.Xcode",
                at: 125,
                window: firstBlockWindow
            ),
            fileEvent(path: "Notes/Between.md", count: 1, at: 160, window: betweenBlocksWindow),
            activeAppEvent(
                name: "Safari",
                bundleIdentifier: "com.apple.Safari",
                at: 165,
                window: betweenBlocksWindow
            ),
            fileEvent(path: "Sources/Legacy.swift", count: 1, at: 180)
        ]

        let digest = EvidenceCompactor().compact(
            project: makeProject(),
            session: session,
            events: events,
            pomodoroBlocks: [firstBlock, secondBlock]
        )

        XCTAssertEqual(
            digest.pomodoroBlocks[0].observedContext.changedPaths.map(\.relativePath),
            ["Sources/First.swift"]
        )
        XCTAssertEqual(
            digest.pomodoroBlocks[0].observedContext.activeApplications.map(\.displayName),
            ["Xcode"]
        )
        XCTAssertTrue(digest.pomodoroBlocks[1].observedContext.isEmpty)
        XCTAssertEqual(
            digest.betweenBlocksObservation.changedPaths.map(\.relativePath),
            ["Notes/Between.md"]
        )
        XCTAssertEqual(
            digest.betweenBlocksObservation.activeApplications.map(\.displayName),
            ["Safari"]
        )
        XCTAssertEqual(
            digest.unattributedObservation.changedPaths.map(\.relativePath),
            ["Sources/Legacy.swift"]
        )
    }

    func testCompactorBuildsStructuredGitSummary() throws {
        let initial = SessionEvent(
            sessionID: UUID(),
            source: .git,
            kind: SessionEventKind.gitInitialState,
            title: "Git initial state",
            payloadJSON: try EventPayloadCoding.encode(
                GitInitialStateEventPayload(
                    isRepository: true,
                    branchName: "main",
                    headSHA: "1111111111111111",
                    changedPaths: ["Preexisting.swift"],
                    isStatusTruncated: false
                )
            )
        )
        let final = SessionEvent(
            sessionID: UUID(),
            source: .git,
            kind: SessionEventKind.gitFinalSummary,
            title: "Git final summary",
            payloadJSON: try EventPayloadCoding.encode(
                GitFinalSummaryEventPayload(
                    isRepository: true,
                    branchName: "feature/context",
                    headSHA: "2222222222222222",
                    sessionObservedChangedPaths: ["Observed.swift"],
                    unobservedChangedPaths: ["Other.swift"],
                    diffStatLines: ["Observed.swift | 2 ++"],
                    commitsAfterStart: [
                        GitCommitEventPayload(hash: "2222222222222222", subject: "add context")
                    ],
                    hasSessionObservedChanges: true,
                    isStatusTruncated: false,
                    isDiffStatTruncated: true
                )
            )
        )

        let summary = EvidenceCompactor().compact(
            project: makeProject(),
            session: makeCompletedSession(brainDump: ""),
            events: [initial, final]
        ).gitSummary

        XCTAssertEqual(summary.initialBranchName, "main")
        XCTAssertEqual(summary.finalBranchName, "feature/context")
        XCTAssertEqual(summary.initialChangedPaths, ["Preexisting.swift"])
        XCTAssertEqual(summary.sessionObservedChangedPaths, ["Observed.swift"])
        XCTAssertEqual(summary.unobservedFinalChangedPaths, ["Other.swift"])
        XCTAssertEqual(summary.commitsAfterStart.map(\.subject), ["add context"])
        XCTAssertTrue(summary.isTruncated)
    }

    func testBlockAwareContextDeduplicatesWithinWindowsAndAppliesGlobalBounds() throws {
        let session = makeCompletedSession(brainDump: "")
        let block = makeBlock(sessionID: session.id, index: 1, start: 100, end: 150)
        let blockWindow = ObservationWindowPayload(kind: .block, blockID: block.id)
        let betweenBlocksWindow = ObservationWindowPayload(kind: .betweenBlocks, blockID: nil)
        let compactor = EvidenceCompactor(
            configuration: EvidenceCompactionConfiguration(
                maxChangedPaths: 2,
                maxActiveApplications: 1,
                maxGitEvidenceLines: 10,
                maxNotes: 10
            )
        )
        let events = try [
            fileEvent(path: "Sources/Block.swift", count: 1, at: 110, window: blockWindow),
            fileEvent(path: "Sources/Block.swift", count: 2, at: 120, window: blockWindow),
            fileEvent(path: "Sources/Between.swift", count: 1, at: 160, window: betweenBlocksWindow),
            fileEvent(path: "Sources/Omitted.swift", count: 1, at: 170),
            activeAppEvent(
                name: "Xcode",
                bundleIdentifier: "com.apple.dt.Xcode",
                at: 115,
                window: blockWindow
            ),
            activeAppEvent(
                name: "Xcode",
                bundleIdentifier: "com.apple.dt.Xcode",
                at: 125,
                window: blockWindow
            ),
            activeAppEvent(
                name: "Terminal",
                bundleIdentifier: "com.apple.Terminal",
                at: 165,
                window: betweenBlocksWindow
            )
        ]

        let digest = compactor.compact(
            project: makeProject(),
            session: session,
            events: events,
            pomodoroBlocks: [block]
        )

        XCTAssertEqual(digest.pomodoroBlocks[0].observedContext.changedPaths.count, 1)
        XCTAssertEqual(digest.pomodoroBlocks[0].observedContext.changedPaths[0].changeCount, 3)
        XCTAssertEqual(
            digest.pomodoroBlocks[0].observedContext.activeApplications.map(\.displayName),
            ["Xcode"]
        )
        XCTAssertEqual(
            digest.betweenBlocksObservation.changedPaths.map(\.relativePath),
            ["Sources/Between.swift"]
        )
        XCTAssertTrue(digest.betweenBlocksObservation.activeApplications.isEmpty)
        XCTAssertTrue(digest.unattributedObservation.isEmpty)
        XCTAssertTrue(digest.compactorNotes.contains { $0.contains("block-aware changed path") })
        XCTAssertTrue(digest.compactorNotes.contains { $0.contains("block-aware active application") })
    }

    private func makeProject() -> Project {
        Project(
            id: UUID(),
            name: "Example",
            rootPath: "/tmp/example",
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1)
        )
    }

    private func makeCompletedSession(brainDump: String) -> WorkSession {
        WorkSession(
            id: UUID(),
            projectID: UUID(),
            mission: "Build M6",
            brainDump: brainDump,
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 220),
            status: .completed,
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 220)
        )
    }

    private func makeBlock(
        sessionID: WorkSession.ID,
        index: Int,
        start: TimeInterval,
        end: TimeInterval
    ) -> PomodoroBlock {
        PomodoroBlock(
            id: UUID(),
            sessionID: sessionID,
            blockIndex: index,
            plannedDurationSeconds: 1_200,
            intention: nil,
            summary: nil,
            status: .completed,
            startedAt: Date(timeIntervalSince1970: start),
            pausedAt: nil,
            accumulatedPauseSeconds: 0,
            endedAt: Date(timeIntervalSince1970: end),
            createdAt: Date(timeIntervalSince1970: start),
            updatedAt: Date(timeIntervalSince1970: end)
        )
    }

    private func fileEvent(
        path: String,
        count: Int,
        at timestamp: TimeInterval,
        window: ObservationWindowPayload? = nil
    ) throws -> SessionEvent {
        let date = Date(timeIntervalSince1970: timestamp)
        return SessionEvent(
            sessionID: UUID(),
            occurredAt: date,
            source: .file,
            kind: SessionEventKind.fileChanged,
            title: path,
            payloadJSON: try EventPayloadCoding.encode(
                FileChangedEventPayload(
                    relativePath: path,
                    firstObservedAt: DateCoding.string(from: date),
                    lastObservedAt: DateCoding.string(from: date),
                    changeCount: count,
                    observationWindow: window
                )
            ),
            createdAt: date
        )
    }

    private func activeAppEvent(
        name: String,
        bundleIdentifier: String?,
        at timestamp: TimeInterval,
        window: ObservationWindowPayload? = nil
    ) throws -> SessionEvent {
        let date = Date(timeIntervalSince1970: timestamp)
        return SessionEvent(
            sessionID: UUID(),
            occurredAt: date,
            source: .activeApp,
            kind: SessionEventKind.appActivated,
            title: name,
            payloadJSON: try EventPayloadCoding.encode(
                ActiveAppEventPayload(
                    displayName: name,
                    bundleIdentifier: bundleIdentifier,
                    observationWindow: window
                )
            ),
            createdAt: date
        )
    }

    private func gitEvent(body: String) -> SessionEvent {
        SessionEvent(
            sessionID: UUID(),
            occurredAt: Date(timeIntervalSince1970: 60),
            source: .git,
            kind: SessionEventKind.gitFinalSummary,
            title: "Git final summary",
            body: body,
            createdAt: Date(timeIntervalSince1970: 60)
        )
    }
}
