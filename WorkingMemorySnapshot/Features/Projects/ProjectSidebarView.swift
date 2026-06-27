import SwiftUI

struct ProjectSidebarView: View {
    @ObservedObject var viewModel: ProjectsViewModel
    let activeProjectID: Project.ID?

    var body: some View {
        List(selection: $viewModel.selectedItem) {
            if let activeProject {
                Section("Active") {
                    ProjectRow(
                        project: activeProject,
                        metadata: viewModel.sidebarMetadata[activeProject.id],
                        isActive: true,
                        isSelected: viewModel.selectedItem == .project(activeProject.id)
                    )
                    .tag(SidebarSelection.project(activeProject.id))
                }
            }

            Section("Projects") {
                if listedProjects.isEmpty {
                    ContentUnavailableView(
                        "No Projects",
                        systemImage: "folder",
                        description: Text("Add a local project folder to begin.")
                    )
                } else {
                    ForEach(listedProjects) { project in
                        ProjectRow(
                            project: project,
                            metadata: viewModel.sidebarMetadata[project.id],
                            isActive: project.id == activeProjectID,
                            isSelected: viewModel.selectedItem == .project(project.id)
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

    private var activeProject: Project? {
        guard let activeProjectID else {
            return nil
        }
        return viewModel.projects.first { $0.id == activeProjectID }
    }

    private var listedProjects: [Project] {
        viewModel.projects.filter { $0.id != activeProjectID }
    }
}

private struct ProjectRow: View {
    let project: Project
    let metadata: ProjectSidebarMetadata?
    let isActive: Bool
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isActive ? "timer.circle.fill" : "folder")
                    .font(.title3)
                    .foregroundStyle(isActive ? Color.accentColor : secondaryTextColor)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(project.name)
                            .font(.body)
                            .fontWeight(isActive ? .semibold : .regular)
                            .foregroundStyle(primaryTextColor)
                            .lineLimit(2)
                        if isActive {
                            Text("Active")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundStyle(.green)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(Color.green.opacity(0.12))
                                )
                        }
                    }

                    Text(project.rootPath)
                        .font(.caption)
                        .foregroundStyle(secondaryTextColor)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if let metadata {
                        HStack(spacing: 6) {
                            if let latest = metadata.latestCompletedSessionEndedAt {
                                Text("Last: \(latest.formatted(date: .abbreviated, time: .shortened))")
                            } else {
                                Text("\(metadata.sessionCount) sessions")
                            }
                            if metadata.hasSnapshot {
                                Image(systemName: "doc.text")
                                    .help("Resume Brief available")
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(secondaryTextColor)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(cardFill)
        )
        .overlay(alignment: .leading) {
            if isActive {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor)
                    .frame(width: 3)
                    .padding(.vertical, 6)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(cardStroke, lineWidth: isSelected ? 1.5 : 1)
        }
        .padding(.vertical, 3)
    }

    private var primaryTextColor: Color {
        Color(nsColor: .labelColor)
    }

    private var secondaryTextColor: Color {
        Color(nsColor: .secondaryLabelColor)
    }

    private var cardFill: Color {
        if isActive || isSelected {
            return Color.accentColor.opacity(isActive ? 0.10 : 0.07)
        }
        return Color(nsColor: .controlBackgroundColor)
    }

    private var cardStroke: Color {
        if isActive || isSelected {
            return Color.accentColor.opacity(0.45)
        }
        return Color(nsColor: .separatorColor).opacity(0.55)
    }
}
