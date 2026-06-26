//
//  WorkingMemorySnapshotApp.swift
//  WorkingMemorySnapshot
//
//  Created by Zachary Kissinger on 6/26/26.
//

import SwiftUI

@main
struct WorkingMemorySnapshotApp: App {
    @StateObject private var viewModel: ProjectsViewModel

    init() {
        let environment = AppEnvironment.live()
        _viewModel = StateObject(
            wrappedValue: ProjectsViewModel(
                repository: environment.projectRepository,
                migrator: environment.databaseMigrator
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
    }
}
