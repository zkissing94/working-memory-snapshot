import SwiftUI

struct ProjectSidebarView: View {
    @ObservedObject var viewModel: ProjectsViewModel
    let activeProjectID: Project.ID?

    var body: some View {
        List(selection: $viewModel.selectedItem) {
            Section("Projects") {
                if viewModel.projects.isEmpty {
                    ContentUnavailableView(
                        "No Projects",
                        systemImage: "folder",
                        description: Text("Add a local project folder to begin.")
                    )
                } else {
                    ForEach(viewModel.projects) { project in
                        ProjectRow(
                            project: project,
                            isActive: project.id == activeProjectID
                        )
                            .tag(SidebarSelection.project(project.id))
                    }
                }
            }

            Section {
                Label("Settings", systemImage: "gearshape")
                    .tag(SidebarSelection.settings)
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
    let isActive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(project.name)
                    .font(.body)
                    .lineLimit(1)
                if isActive {
                    Image(systemName: "timer")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help("Session active")
                }
            }
            Text(project.rootPath)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, 3)
    }
}
