import SwiftUI

struct ProjectSidebarView: View {
    @ObservedObject var viewModel: ProjectsViewModel
    let activeProjectID: Project.ID?

    var body: some View {
        List {
            if let activeProject {
                Section("Active") {
                    projectRowButton(for: activeProject, isActive: true)
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
                        projectRowButton(for: project, isActive: project.id == activeProjectID)
                    }
                }
            }

            Section {
                Button {
                    viewModel.selectSettings()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
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

    private func projectRowButton(for project: Project, isActive: Bool) -> some View {
        Button {
            viewModel.selectProject(id: project.id)
        } label: {
            ProjectRow(
                project: project,
                metadata: viewModel.sidebarMetadata[project.id],
                isActive: isActive,
                isSelected: viewModel.selectedItem == .project(project.id)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
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
                    .foregroundStyle(isActive ? activeGreen : secondaryTextColor)
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
                                .foregroundStyle(activeGreen)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(activeGreen.opacity(0.14))
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
                    .fill(activeGreen)
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

    private var activeGreen: Color {
        Color(red: 0.08, green: 0.63, blue: 0.31)
    }

    private var cardFill: Color {
        if isActive {
            return activeGreen.opacity(0.10)
        }
        return Color(nsColor: .controlBackgroundColor)
    }

    private var cardStroke: Color {
        if isActive {
            return activeGreen.opacity(0.45)
        }
        if isSelected {
            return Color(nsColor: .separatorColor).opacity(0.85)
        }
        return Color(nsColor: .separatorColor).opacity(0.55)
    }
}
