import SwiftUI

struct ProjectSidebarView: View {
    @ObservedObject var viewModel: ProjectsViewModel

    var body: some View {
        List(selection: $viewModel.selectedProjectID) {
            if viewModel.projects.isEmpty {
                ContentUnavailableView(
                    "No Projects",
                    systemImage: "folder",
                    description: Text("Add a local project folder to begin.")
                )
            } else {
                ForEach(viewModel.projects) { project in
                    ProjectRow(project: project)
                        .tag(project.id)
                }
            }
        }
        .navigationTitle("Projects")
        .toolbar {
            ToolbarItem {
                Button {
                    Task {
                        await viewModel.addProjectFromPicker()
                    }
                } label: {
                    Label("Add Project", systemImage: "plus")
                }
                .help("Add Project")
                .disabled(viewModel.isLoading)
            }
        }
    }
}

private struct ProjectRow: View {
    let project: Project

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(project.name)
                .font(.body)
                .lineLimit(1)
            Text(project.rootPath)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, 3)
    }
}
