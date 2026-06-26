import XCTest
@testable import WorkingMemorySnapshot

final class PlaceholderSnapshotGeneratorTests: XCTestCase {
    func testEmptyBrainDumpUsesFallbacksAndDoesNotInventDecisions() {
        let draft = PlaceholderSnapshotGenerator().makeSnapshot(
            mission: "Diagnose the launch crash",
            brainDump: ""
        )

        XCTAssertEqual(draft.whatChanged, "No change was captured in the brain dump.")
        XCTAssertEqual(draft.decisions, [])
        XCTAssertEqual(draft.openLoops, [])
        XCTAssertEqual(draft.nextAction, "Review the prior mission and choose the first verification step.")
        XCTAssertEqual(
            draft.resumeBrief,
            "Mission: Diagnose the launch crash Brain dump: No brain dump was captured."
        )
        XCTAssertEqual(draft.generatorModel, "deterministic-placeholder")
        XCTAssertEqual(draft.promptVersion, "placeholder-v1")
    }

    func testExplicitNextActionIsUsedWithoutGeneratingDecisions() {
        let draft = PlaceholderSnapshotGenerator().makeSnapshot(
            mission: "Make snapshots visible after ending a session",
            brainDump: "Changed the persistence boundary. Decision: keep M4 deterministic. Next: run SnapshotRepositoryTests."
        )

        XCTAssertEqual(draft.decisions, [])
        XCTAssertEqual(draft.openLoops, [])
        XCTAssertEqual(draft.whatChanged, "Brain dump: Changed the persistence boundary")
        XCTAssertEqual(draft.nextAction, "run SnapshotRepositoryTests")
        XCTAssertTrue(draft.resumeBrief.contains("Mission: Make snapshots visible after ending a session"))
        XCTAssertTrue(draft.resumeBrief.contains("Brain dump: Changed the persistence boundary. Decision: keep M4 deterministic. Next: run SnapshotRepositoryTests."))
    }

    func testOneExplicitOpenLoopIsCapturedWhenPresent() {
        let draft = PlaceholderSnapshotGenerator().makeSnapshot(
            mission: "Finish UI wiring",
            brainDump: """
            Added the detail route.
            Blocked: need to verify relaunch loads the latest snapshot.
            Open question: should regeneration be exposed now?
            Next action: launch the app and complete a session.
            """
        )

        XCTAssertEqual(
            draft.openLoops,
            ["Blocked: need to verify relaunch loads the latest snapshot"]
        )
        XCTAssertEqual(draft.nextAction, "launch the app and complete a session")
    }
}
