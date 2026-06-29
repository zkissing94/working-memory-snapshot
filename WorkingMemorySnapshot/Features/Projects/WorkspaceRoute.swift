import Foundation

enum WorkspaceRoute: Equatable {
    case emptyLibrary
    case noProjectSelected
    case settings
    case projectDashboard(Project.ID)
    case startSession(Project.ID)
    case activeSession(WorkSession.ID)
    case pausedBlock(WorkSession.ID)
    case betweenBlocks(WorkSession.ID)
    case endSession(WorkSession.ID)
    case snapshotGenerationFailed(WorkSession.ID)
    case snapshotDetail(Snapshot.ID)
    case historicalSession(WorkSession.ID)
    case projectAccessLost(Project.ID)

    static func resolve(
        selectedItem: SidebarSelection?,
        selectedProjectID: Project.ID?,
        projectsIsEmpty: Bool,
        presentedSnapshotID: Snapshot.ID?,
        flow: SessionFlow,
        activeSession: WorkSession?,
        activeBlock: PomodoroBlock?,
        sessionBlocks: [PomodoroBlock],
        selectedSessionID: WorkSession.ID?,
        projectAccessState: ProjectAccessState,
        failedSnapshotSession: WorkSession?
    ) -> WorkspaceRoute {
        if selectedItem == .settings {
            return .settings
        }

        guard case .project(let projectID) = selectedItem,
              selectedProjectID == projectID
        else {
            return projectsIsEmpty ? .emptyLibrary : .noProjectSelected
        }

        if let presentedSnapshotID {
            return .snapshotDetail(presentedSnapshotID)
        }

        if flow == .starting(projectID) {
            return .startSession(projectID)
        }

        if let activeSession,
           activeSession.projectID == projectID {
            if flow == .ending(activeSession.id) {
                return .endSession(activeSession.id)
            }

            if let activeBlock {
                switch activeBlock.status {
                case .active:
                    return .activeSession(activeSession.id)
                case .paused:
                    return .pausedBlock(activeSession.id)
                case .completed, .interrupted:
                    break
                }
            }

            if !sessionBlocks.isEmpty {
                return .betweenBlocks(activeSession.id)
            }

            return .activeSession(activeSession.id)
        }

        if let selectedSessionID {
            return .historicalSession(selectedSessionID)
        }

        if projectAccessState.isInaccessible {
            return .projectAccessLost(projectID)
        }

        if let failedSnapshotSession,
           failedSnapshotSession.projectID == projectID {
            return .snapshotGenerationFailed(failedSnapshotSession.id)
        }

        return .projectDashboard(projectID)
    }
}
