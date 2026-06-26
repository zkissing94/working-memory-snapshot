//
//  ContentView.swift
//  WorkingMemorySnapshot
//
//  Created by Zachary Kissinger on 6/26/26.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: ProjectsViewModel

    var body: some View {
        NavigationSplitView {
            ProjectSidebarView(viewModel: viewModel)
                .navigationSplitViewColumnWidth(min: 240, ideal: 280)
        } detail: {
            ProjectDetailContainerView(project: viewModel.selectedProject)
        }
        .task {
            await viewModel.loadProjects()
        }
        .alert("Project Error", isPresented: viewModel.isShowingError) {
            Button("OK", role: .cancel) {
                viewModel.clearError()
            }
        } message: {
            Text(viewModel.errorMessage ?? "The project could not be updated.")
        }
    }
}

#Preview {
    let database = Database(url: URL(fileURLWithPath: "/tmp/working-memory-preview.sqlite3"))
    let repository = ProjectRepository(database: database)
    let migrator = DatabaseMigrator(database: database)

    ContentView(
        viewModel: ProjectsViewModel(
            repository: repository,
            migrator: migrator
        )
    )
}
