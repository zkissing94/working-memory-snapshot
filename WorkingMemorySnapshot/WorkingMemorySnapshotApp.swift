//
//  WorkingMemorySnapshotApp.swift
//  WorkingMemorySnapshot
//
//  Created by Zachary Kissinger on 6/26/26.
//

import SwiftUI

@main
struct WorkingMemorySnapshotApp: App {
    @StateObject private var projectsViewModel: ProjectsViewModel
    @StateObject private var sessionViewModel: SessionViewModel
    @StateObject private var projectDetailViewModel: ProjectDetailViewModel
    @StateObject private var settingsViewModel: SettingsViewModel

    init() {
        let environment = AppEnvironment.live()
        _projectsViewModel = StateObject(
            wrappedValue: ProjectsViewModel(
                repository: environment.projectRepository,
                migrator: environment.databaseMigrator
            )
        )
        _sessionViewModel = StateObject(
            wrappedValue: SessionViewModel(
                sessionRepository: environment.sessionRepository,
                projectRepository: environment.projectRepository,
                snapshotGenerator: environment.snapshotGenerator,
                observationCoordinator: environment.observationCoordinator
            )
        )
        _projectDetailViewModel = StateObject(
            wrappedValue: ProjectDetailViewModel(
                snapshotRepository: environment.snapshotRepository,
                sessionRepository: environment.sessionRepository
            )
        )
        _settingsViewModel = StateObject(
            wrappedValue: SettingsViewModel(
                repository: environment.settingsRepository,
                tokenStore: environment.tokenStore,
                transport: environment.lmStudioHTTPTransport
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                projectsViewModel: projectsViewModel,
                sessionViewModel: sessionViewModel,
                projectDetailViewModel: projectDetailViewModel,
                settingsViewModel: settingsViewModel
            )
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Project or Session") {
                    handleNewCommand()
                }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(isNewCommandDisabled)
            }

            CommandGroup(replacing: .appSettings) {
                Button("Settings") {
                    projectsViewModel.selectedItem = .settings
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }

    @MainActor
    private func handleNewCommand() {
        if let project = projectsViewModel.selectedProject,
           sessionViewModel.canStartSession {
            sessionViewModel.beginStartSession(for: project)
        } else {
            Task {
                await projectsViewModel.addProjectFromPicker()
            }
        }
    }

    @MainActor
    private var isNewCommandDisabled: Bool {
        projectsViewModel.isLoading
            || sessionViewModel.isWorking
            || (projectsViewModel.selectedProject != nil && !sessionViewModel.canStartSession)
    }
}
