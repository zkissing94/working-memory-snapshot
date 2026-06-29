//
//  ContentView.swift
//  WorkingMemorySnapshot
//
//  Created by Zachary Kissinger on 6/26/26.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var projectsViewModel: ProjectsViewModel
    @ObservedObject var sessionViewModel: SessionViewModel
    @ObservedObject var projectDetailViewModel: ProjectDetailViewModel
    @ObservedObject var settingsViewModel: SettingsViewModel

    var body: some View {
        NavigationSplitView {
            ProjectSidebarView(
                viewModel: projectsViewModel,
                activity: sidebarActivity,
                canStartSessionForProject: { projectID in
                    guard
                        let project = projectsViewModel.projects.first(where: { $0.id == projectID })
                    else {
                        return false
                    }
                    return sessionViewModel.canStartSession && isReadableDirectory(at: project.rootPath)
                },
                canPauseSessionForProject: { projectID in
                    guard let activeSession = sessionViewModel.activeSession else {
                        return false
                    }
                    guard activeSession.projectID == projectID else {
                        return false
                    }
                    return sessionViewModel.activeBlock?.status == .active
                },
                onStartSession: { project in
                    sessionViewModel.beginStartSession(for: project)
                },
                onPauseSession: { _ in
                    Task {
                        await sessionViewModel.pauseCurrentBlock()
                    }
                }
            )
                .navigationSplitViewColumnWidth(min: 240, ideal: 280)
        } detail: {
            switch projectsViewModel.selectedItem {
            case .settings:
                SettingsView(viewModel: settingsViewModel)
            default:
                if projectsViewModel.projects.isEmpty {
                    EmptyLibraryWorkspaceView {
                        Task {
                            await projectsViewModel.addProjectFromPicker()
                        }
                    }
                } else {
                    ProjectDetailContainerView(
                        project: projectsViewModel.selectedProject,
                        projectsViewModel: projectsViewModel,
                        sessionViewModel: sessionViewModel,
                        projectDetailViewModel: projectDetailViewModel
                    )
                }
            }
        }
        .task {
            await projectsViewModel.loadProjects()
            await sessionViewModel.loadActiveSessionForRecovery()
            await settingsViewModel.loadSettings()
        }
        .alert("Project Error", isPresented: projectsViewModel.isShowingError) {
            Button("OK", role: .cancel) {
                projectsViewModel.clearError()
            }
        } message: {
            Text(projectsViewModel.errorMessage ?? "The project could not be updated.")
        }
        .alert("Session Error", isPresented: sessionViewModel.isShowingError) {
            Button("OK", role: .cancel) {
                sessionViewModel.clearError()
            }
        } message: {
            Text(sessionViewModel.errorMessage ?? "The session could not be updated.")
        }
        .alert("Snapshot Error", isPresented: projectDetailViewModel.isShowingError) {
            Button("OK", role: .cancel) {
                projectDetailViewModel.clearError()
            }
        } message: {
            Text(projectDetailViewModel.errorMessage ?? "The snapshot could not be loaded.")
        }
        .sheet(isPresented: sessionViewModel.isShowingRecoverySheet) {
            if let recoveryContext = sessionViewModel.recoveryContext {
                SessionRecoverySheet(
                    context: recoveryContext,
                    onResume: {
                        sessionViewModel.resumeRecoveredSession()
                        projectsViewModel.selectProject(id: recoveryContext.project.id)
                    },
                    onEnd: {
                        sessionViewModel.beginEndingRecoveredSession()
                        projectsViewModel.selectProject(id: recoveryContext.project.id)
                    },
                    onCancel: {
                        Task {
                            await sessionViewModel.cancelRecoveredSession()
                        }
                    },
                    onRestoreAccess: {
                        Task {
                            if let restoredProject = await projectsViewModel.restoreProjectAccessFromPicker(
                                for: recoveryContext.project
                            ) {
                                sessionViewModel.updateRecoveredProject(restoredProject)
                                projectsViewModel.selectProject(id: restoredProject.id)
                            }
                        }
                    }
                )
                .interactiveDismissDisabled()
            }
        }
    }

    private var sidebarActivity: ProjectSidebarActivity? {
        ProjectSidebarActivity.current(
            flow: sessionViewModel.flow,
            activeSession: sessionViewModel.activeSession,
            activeBlock: sessionViewModel.activeBlock,
            sessionBlocks: sessionViewModel.sessionBlocks,
            recoveryContext: sessionViewModel.recoveryContext,
            failedSnapshotSession: sessionViewModel.failedSnapshotSession,
            selectedProjectID: projectsViewModel.selectedProject?.id,
            selectedProjectAccessState: projectDetailViewModel.projectAccessState
        )
    }

    private func isReadableDirectory(at path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            && isDirectory.boolValue
            && FileManager.default.isReadableFile(atPath: path)
    }
}

#Preview {
    let database = Database(url: URL(fileURLWithPath: "/tmp/working-memory-preview.sqlite3"))
    let repository = ProjectRepository(database: database)
    let sessionRepository = SessionRepository(database: database)
    let snapshotRepository = SnapshotRepository(database: database)
    let settingsRepository = SettingsRepository(database: database)
    let migrator = DatabaseMigrator(database: database)

    ContentView(
        projectsViewModel: ProjectsViewModel(
            repository: repository,
            sessionRepository: sessionRepository,
            snapshotRepository: snapshotRepository,
            migrator: migrator
        ),
        sessionViewModel: SessionViewModel(
            sessionRepository: sessionRepository,
            projectRepository: repository,
            pomodoroBlockRepository: PomodoroBlockRepository(database: database),
            workIncrementRepository: WorkIncrementRepository(database: database),
            snapshotGenerator: PreviewSnapshotGenerator(snapshotRepository: snapshotRepository),
            observationCoordinator: PreviewObservationCoordinator()
        ),
        projectDetailViewModel: ProjectDetailViewModel(
            snapshotRepository: snapshotRepository,
            sessionRepository: sessionRepository,
            pomodoroBlockRepository: PomodoroBlockRepository(database: database),
            workIncrementRepository: WorkIncrementRepository(database: database),
            eventRepository: EventRepository(database: database)
        ),
        settingsViewModel: SettingsViewModel(
            repository: settingsRepository,
            tokenStore: PreviewTokenStore()
        )
    )
}

private actor PreviewTokenStore: LMStudioTokenStore {
    func loadToken() async throws -> String? {
        nil
    }

    func saveToken(_ token: String?) async throws {}

    func deleteToken() async throws {}
}

private struct PreviewSnapshotGenerator: SessionSnapshotGenerating {
    let snapshotRepository: SnapshotRepository

    func generateSnapshot(for project: Project, session: WorkSession) async throws -> Snapshot {
        let draft = SnapshotDraft(
            whatChanged: "Preview snapshot generation is not connected.",
            decisions: [],
            openLoops: [],
            nextAction: "Run the app to generate with LM Studio.",
            resumeBrief: "Preview mode uses a local stand-in snapshot.",
            generatorModel: "preview",
            promptVersion: PromptBuilder.promptVersion
        )
        return try await snapshotRepository.saveOrReplaceSnapshot(draft, for: session.id)
    }
}

@MainActor
private final class PreviewObservationCoordinator: SessionObservationCoordinating {
    var onSummaryChange: (@MainActor (ObservationSessionSummary) -> Void)?

    func startObserving(session: WorkSession, project: Project) async {
        onSummaryChange?(
            ObservationSessionSummary(
                changedFileCount: 0,
                droppedFileChangeCount: 0,
                activeApplicationNames: ["Preview"],
                isGitRepository: nil,
                notes: []
            )
        )
    }

    func stopObservingForCompletion(session: WorkSession, brainDump: String) async {}

    func stopObservingForCancellation(session: WorkSession) async {}
}
