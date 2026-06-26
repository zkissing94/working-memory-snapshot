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
    @StateObject private var settingsViewModel: SettingsViewModel

    init() {
        let environment = AppEnvironment.live()
        _projectsViewModel = StateObject(
            wrappedValue: ProjectsViewModel(
                repository: environment.projectRepository,
                migrator: environment.databaseMigrator
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
                settingsViewModel: settingsViewModel
            )
        }
    }
}
