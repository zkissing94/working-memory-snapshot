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
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(iconFill)

                    Image(systemName: isActive ? "timer.circle.fill" : "folder")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(isActive ? Color.accentColor : secondaryTextColor)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(project.name)
                            .font(.headline.weight(isActive ? .semibold : .medium))
                            .foregroundStyle(primaryTextColor)
                            .lineLimit(2)
                            .layoutPriority(1)
                        if isActive {
                            Spacer(minLength: 4)
                            Text("Active")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundStyle(activeGreen)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule()
                                        .fill(activeGreen.opacity(0.15))
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
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(cardFill)
        )
        .overlay(alignment: .leading) {
            if isActive {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.accentColor)
                    .frame(width: 4)
                    .padding(.vertical, 10)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(cardStroke, lineWidth: 1)
        }
        .shadow(color: shadowColor, radius: shadowRadius, y: 2)
        .scaleEffect(isHovered ? 1.01 : 1)
        .animation(.easeInOut(duration: 0.18), value: isActive)
        .animation(.easeInOut(duration: 0.18), value: isSelected)
        .animation(.easeOut(duration: 0.18), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .padding(.vertical, 4)
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

    private var cornerRadius: CGFloat {
        14
    }

    private var cardFill: AnyShapeStyle {
        if isActive {
            return AnyShapeStyle(Color.accentColor.opacity(0.08))
        }
        return AnyShapeStyle(.regularMaterial)
    }

    private var cardStroke: Color {
        if isActive {
            return Color.accentColor.opacity(isHovered ? 0.42 : 0.35)
        }
        if isSelected {
            return Color(nsColor: .separatorColor).opacity(0.85)
        }
        if isHovered {
            return Color(nsColor: .separatorColor).opacity(0.70)
        }
        return Color(nsColor: .quaternaryLabelColor).opacity(0.70)
    }

    private var iconFill: AnyShapeStyle {
        if isActive {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [Color.accentColor.opacity(0.18), Color.cyan.opacity(0.10)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        return AnyShapeStyle(Color(nsColor: .secondaryLabelColor).opacity(0.08))
    }

    private var shadowColor: Color {
        if isActive {
            return Color.accentColor.opacity(isHovered ? 0.17 : 0.15)
        }
        return Color.black.opacity(isHovered ? 0.045 : 0.03)
    }

    private var shadowRadius: CGFloat {
        if isActive {
            return isHovered ? 13.8 : 12
        }
        return isHovered ? 6.9 : 6
    }
}
