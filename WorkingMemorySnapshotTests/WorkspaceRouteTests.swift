import XCTest
@testable import WorkingMemorySnapshot

final class WorkspaceRouteTests: XCTestCase {
    func testResolvesLibraryAndSettingsStates() {
        XCTAssertEqual(
            route(selectedItem: nil, selectedProjectID: nil, projectsIsEmpty: true),
            .emptyLibrary
        )
        XCTAssertEqual(
            route(selectedItem: nil, selectedProjectID: nil, projectsIsEmpty: false),
            .noProjectSelected
        )
        XCTAssertEqual(
            route(selectedItem: .settings, selectedProjectID: nil),
            .settings
        )
    }

    func testResolvesProjectDashboardAndStartSession() {
        let projectID = UUID()

        XCTAssertEqual(
            route(selectedItem: .project(projectID), selectedProjectID: projectID),
            .projectDashboard(projectID)
        )
        XCTAssertEqual(
            route(
                selectedItem: .project(projectID),
                selectedProjectID: projectID,
                flow: .starting(projectID)
            ),
            .startSession(projectID)
        )
    }

    func testSnapshotAndEndingStatesWinBeforeOtherProjectStates() {
        let projectID = UUID()
        let session = makeWorkSession(projectID: projectID)
        let snapshotID = UUID()

        XCTAssertEqual(
            route(
                selectedItem: .project(projectID),
                selectedProjectID: projectID,
                presentedSnapshotID: snapshotID,
                flow: .ending(session.id),
                activeSession: session
            ),
            .snapshotDetail(snapshotID)
        )
        XCTAssertEqual(
            route(
                selectedItem: .project(projectID),
                selectedProjectID: projectID,
                flow: .ending(session.id),
                activeSession: session
            ),
            .endSession(session.id)
        )
    }

    func testResolvesActivePausedAndBetweenBlockStates() {
        let projectID = UUID()
        let session = makeWorkSession(projectID: projectID)
        let activeBlock = makePomodoroBlock(sessionID: session.id, status: .active)
        let pausedBlock = makePomodoroBlock(sessionID: session.id, status: .paused)
        let completedBlock = makePomodoroBlock(sessionID: session.id, status: .completed)

        XCTAssertEqual(
            route(
                selectedItem: .project(projectID),
                selectedProjectID: projectID,
                activeSession: session,
                activeBlock: activeBlock,
                sessionBlocks: [activeBlock]
            ),
            .activeSession(session.id)
        )
        XCTAssertEqual(
            route(
                selectedItem: .project(projectID),
                selectedProjectID: projectID,
                activeSession: session,
                activeBlock: pausedBlock,
                sessionBlocks: [pausedBlock]
            ),
            .pausedBlock(session.id)
        )
        XCTAssertEqual(
            route(
                selectedItem: .project(projectID),
                selectedProjectID: projectID,
                activeSession: session,
                sessionBlocks: [completedBlock]
            ),
            .betweenBlocks(session.id)
        )
    }

    func testResolvesHistoricalAccessLostAndSnapshotFailureStates() {
        let projectID = UUID()
        let selectedSessionID = UUID()
        let failedSession = makeWorkSession(projectID: projectID, status: .completed)

        XCTAssertEqual(
            route(
                selectedItem: .project(projectID),
                selectedProjectID: projectID,
                selectedSessionID: selectedSessionID
            ),
            .historicalSession(selectedSessionID)
        )
        XCTAssertEqual(
            route(
                selectedItem: .project(projectID),
                selectedProjectID: projectID,
                projectAccessState: .inaccessible,
                failedSnapshotSession: failedSession
            ),
            .projectAccessLost(projectID)
        )
        XCTAssertEqual(
            route(
                selectedItem: .project(projectID),
                selectedProjectID: projectID,
                failedSnapshotSession: failedSession
            ),
            .snapshotGenerationFailed(failedSession.id)
        )
    }

    func testPresentationIdentityKeepsLiveSessionViewStableAcrossBlockStates() {
        let sessionID = UUID()
        let projectID = UUID()

        XCTAssertEqual(
            WorkspaceRoute.activeSession(sessionID).presentationIdentity,
            WorkspaceRoute.pausedBlock(sessionID).presentationIdentity
        )
        XCTAssertEqual(
            WorkspaceRoute.pausedBlock(sessionID).presentationIdentity,
            WorkspaceRoute.betweenBlocks(sessionID).presentationIdentity
        )
        XCTAssertNotEqual(
            WorkspaceRoute.projectDashboard(projectID).presentationIdentity,
            WorkspaceRoute.startSession(projectID).presentationIdentity
        )
    }

    private func route(
        selectedItem: SidebarSelection?,
        selectedProjectID: Project.ID?,
        projectsIsEmpty: Bool = false,
        presentedSnapshotID: Snapshot.ID? = nil,
        flow: SessionFlow = .idle,
        activeSession: WorkSession? = nil,
        activeBlock: PomodoroBlock? = nil,
        sessionBlocks: [PomodoroBlock] = [],
        selectedSessionID: WorkSession.ID? = nil,
        projectAccessState: ProjectAccessState = .accessible,
        failedSnapshotSession: WorkSession? = nil
    ) -> WorkspaceRoute {
        WorkspaceRoute.resolve(
            selectedItem: selectedItem,
            selectedProjectID: selectedProjectID,
            projectsIsEmpty: projectsIsEmpty,
            presentedSnapshotID: presentedSnapshotID,
            flow: flow,
            activeSession: activeSession,
            activeBlock: activeBlock,
            sessionBlocks: sessionBlocks,
            selectedSessionID: selectedSessionID,
            projectAccessState: projectAccessState,
            failedSnapshotSession: failedSnapshotSession
        )
    }

    private func makeWorkSession(
        id: UUID = UUID(),
        projectID: UUID,
        status: SessionStatus = .active
    ) -> WorkSession {
        let now = Date()
        return WorkSession(
            id: id,
            projectID: projectID,
            mission: "Validate workspace routing.",
            brainDump: status == .completed ? "Saved before generation." : nil,
            startedAt: now,
            endedAt: status == .active ? nil : now,
            status: status,
            createdAt: now,
            updatedAt: now
        )
    }

    private func makePomodoroBlock(
        id: UUID = UUID(),
        sessionID: UUID,
        status: PomodoroBlockStatus
    ) -> PomodoroBlock {
        let now = Date()
        return PomodoroBlock(
            id: id,
            sessionID: sessionID,
            blockIndex: 1,
            plannedDurationSeconds: PomodoroBlock.defaultPlannedDurationSeconds,
            intention: nil,
            summary: nil,
            status: status,
            startedAt: now,
            pausedAt: status == .paused ? now : nil,
            accumulatedPauseSeconds: 0,
            endedAt: status == .completed || status == .interrupted ? now : nil,
            createdAt: now,
            updatedAt: now
        )
    }
}
