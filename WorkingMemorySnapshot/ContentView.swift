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
                    sessionViewModel: sessionViewModel
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
    let settingsRepository = SettingsRepository(database: database)
    let migrator = DatabaseMigrator(database: database)

    ContentView(
        projectsViewModel: ProjectsViewModel(
            repository: repository,
            migrator: migrator
        ),
        sessionViewModel: SessionViewModel(
            sessionRepository: sessionRepository,
            projectRepository: repository
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
