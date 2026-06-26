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
                activeProjectID: sessionViewModel.activeSession?.projectID
            )
                .navigationSplitViewColumnWidth(min: 240, ideal: 280)
        } detail: {
            switch projectsViewModel.selectedItem {
            case .settings:
                SettingsView(viewModel: settingsViewModel)
            default:
                ProjectDetailContainerView(
                    project: projectsViewModel.selectedProject,
                    sessionViewModel: sessionViewModel,
                    projectDetailViewModel: projectDetailViewModel
                )
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
                    }
                )
                .interactiveDismissDisabled()
            }
        }
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
            migrator: migrator
        ),
        sessionViewModel: SessionViewModel(
            sessionRepository: sessionRepository,
            projectRepository: repository,
            snapshotGenerator: PreviewSnapshotGenerator(snapshotRepository: snapshotRepository),
            observationCoordinator: PreviewObservationCoordinator()
        ),
        projectDetailViewModel: ProjectDetailViewModel(
            snapshotRepository: snapshotRepository,
            sessionRepository: sessionRepository
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
