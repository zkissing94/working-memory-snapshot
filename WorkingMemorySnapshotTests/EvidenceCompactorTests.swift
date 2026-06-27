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

    private func fileEvent(path: String, count: Int, at timestamp: TimeInterval) throws -> SessionEvent {
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
                    changeCount: count
                )
            ),
            createdAt: date
        )
    }

    private func activeAppEvent(
        name: String,
        bundleIdentifier: String?,
        at timestamp: TimeInterval
    ) throws -> SessionEvent {
        let date = Date(timeIntervalSince1970: timestamp)
        return SessionEvent(
            sessionID: UUID(),
            occurredAt: date,
            source: .activeApp,
            kind: SessionEventKind.appActivated,
            title: name,
            payloadJSON: try EventPayloadCoding.encode(
                ActiveAppEventPayload(displayName: name, bundleIdentifier: bundleIdentifier)
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
