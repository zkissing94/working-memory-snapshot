import AppKit
import SwiftUI

enum ProjectSidebarActivityKind: Equatable {
    case preparing
    case activeBlock
    case pausedBlock
    case betweenBlocks
    case ending
    case recovery
    case accessLost
    case snapshotFailed
}

struct ProjectSidebarActivity: Equatable {
    let projectID: Project.ID
    let message: String
    let kind: ProjectSidebarActivityKind

    static func current(
        flow: SessionFlow,
        activeSession: WorkSession?,
        activeBlock: PomodoroBlock?,
        sessionBlocks: [PomodoroBlock],
        recoveryContext: SessionRecoveryContext?,
        failedSnapshotSession: WorkSession?,
        selectedProjectID: Project.ID?,
        selectedProjectAccessState: ProjectAccessState
    ) -> ProjectSidebarActivity? {
        if let recoveryContext {
            return ProjectSidebarActivity(
                projectID: recoveryContext.project.id,
                message: recoveryContext.isProjectFolderAccessible ? "Recovery available" : "Folder missing",
                kind: recoveryContext.isProjectFolderAccessible ? .recovery : .accessLost
            )
        }

        if case .starting(let projectID) = flow {
            return ProjectSidebarActivity(
                projectID: projectID,
                message: "Preparing session...",
                kind: .preparing
            )
        }

        if let activeSession {
            if case .ending(let sessionID) = flow,
               sessionID == activeSession.id {
                return ProjectSidebarActivity(
                    projectID: activeSession.projectID,
                    message: "Ending session...",
                    kind: .ending
                )
            }

            if let activeBlock {
                switch activeBlock.status {
                case .active:
                    return ProjectSidebarActivity(
                        projectID: activeSession.projectID,
                        message: "Block \(activeBlock.blockIndex) active",
                        kind: .activeBlock
                    )
                case .paused:
                    return ProjectSidebarActivity(
                        projectID: activeSession.projectID,
                        message: "Block \(activeBlock.blockIndex) paused",
                        kind: .pausedBlock
                    )
                case .completed, .interrupted:
                    break
                }
            }

            if !sessionBlocks.isEmpty {
                return ProjectSidebarActivity(
                    projectID: activeSession.projectID,
                    message: "Between blocks",
                    kind: .betweenBlocks
                )
            }

            return ProjectSidebarActivity(
                projectID: activeSession.projectID,
                message: "Session in progress",
                kind: .activeBlock
            )
        }

        if let selectedProjectID,
           selectedProjectAccessState.isInaccessible {
            return ProjectSidebarActivity(
                projectID: selectedProjectID,
                message: "Folder missing",
                kind: .accessLost
            )
        }

        if let failedSnapshotSession {
            return ProjectSidebarActivity(
                projectID: failedSnapshotSession.projectID,
                message: "Snapshot needs attention",
                kind: .snapshotFailed
            )
        }

        return nil
    }
}

struct ProjectSidebarView: View {
    @ObservedObject var viewModel: ProjectsViewModel
    let activity: ProjectSidebarActivity?
    let canStartSessionForProject: (Project.ID) -> Bool
    let canPauseSessionForProject: (Project.ID) -> Bool
    let onStartSession: (Project) -> Void
    let onPauseSession: (Project) -> Void
    @State private var isDeleteProjectPromptVisible = false
    @State private var projectToDelete: Project?
    @State private var renamingProjectID: Project.ID?
    @State private var draftProjectName = ""
    @State private var sidebarWidth: CGFloat = 0
    @FocusState private var focusedRenamingProjectID: Project.ID?


    var body: some View {
        VStack(spacing: 0) {
            brandHeader

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let activityProject, let activity {
                        sidebarSection("Active")
                        projectRowButton(
                            for: activityProject,
                            activity: activity,
                            isSelected: viewModel.selectedItem == .project(activityProject.id)
                        )
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        projectsHeader

                        if listedProjects.isEmpty {
                            EmptyProjectsRow()
                        } else {
                            ForEach(listedProjects) { project in
                                projectRowButton(
                                    for: project,
                                    activity: nil,
                                    isSelected: viewModel.selectedItem == .project(project.id)
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 6)
                .padding(.bottom, 14)
            }

            Divider()

            settingsButton
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .background(
            GeometryReader { geometry in
                Color.clear.preference(key: SidebarWidthPreferenceKey.self, value: geometry.size.width)
            }
        )
        .onPreferenceChange(SidebarWidthPreferenceKey.self) { sidebarWidth = $0 }
        .navigationTitle("Projects")
    }

    private var brandHeader: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text("Working Memory")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("Snapshot")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 14)
        .accessibilityElement(children: .combine)
    }

    private var projectsHeader: some View {
        HStack {
            sidebarSection("Projects")
            Spacer(minLength: 8)
            HStack(spacing: 2) {
                deleteButton
                addProjectButton
            }
            .frame(width: max(54, sidebarWidth * 0.25), alignment: .trailing)
        }
        .alert("Delete Project", isPresented: $isDeleteProjectPromptVisible) {
            Button("Delete", role: .destructive) {
                guard let projectToDelete else {
                    return
                }
                Task {
                    await viewModel.deleteProject(projectToDelete)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let projectToDelete {
                Text("Delete \"\(projectToDelete.name)\" and all sessions, snapshots, and history for this project?")
            } else {
                Text("Delete this project?")
            }
        }
    }

    private var addProjectButton: some View {
        Button {
            Task {
                await viewModel.addProjectFromPicker()
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 26, height: 26)
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
        }
        .disabled(viewModel.isLoading)
        .help("Add Project")
        .accessibilityLabel("Add Project")
        .accessibilityHint("Choose a local project folder.")
    }

    private var deleteButton: some View {
        Button {
            projectToDelete = viewModel.selectedProject
            isDeleteProjectPromptVisible = projectToDelete != nil
        } label: {
            Image(systemName: "minus")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 26, height: 26)
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.red)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
        }
        .disabled(viewModel.selectedProject == nil || viewModel.isLoading)
        .help("Delete Project")
        .accessibilityLabel("Delete Project")
        .accessibilityHint("Delete the selected project.")
    }

    private var settingsButton: some View {
        Button {
            viewModel.selectSettings()
        } label: {
            SidebarSettingsRow(isSelected: viewModel.selectedItem == .settings)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Settings")
        .accessibilityHint("Configure local snapshot generation.")
    }

    private var activityProject: Project? {
        guard let activity else {
            return nil
        }
        return viewModel.projects.first { $0.id == activity.projectID }
    }

    private var listedProjects: [Project] {
        guard let activityProjectID = activity?.projectID else {
            return viewModel.projects
        }
        return viewModel.projects.filter { $0.id != activityProjectID }
    }

    private func sidebarSection(_ title: String) -> some View {
        Text(title)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.8)
    }

    @ViewBuilder
    private func projectRowButton(
        for project: Project,
        activity: ProjectSidebarActivity?,
        isSelected: Bool
    ) -> some View {
        let isRenameLocked = renamingProjectID != nil && renamingProjectID != project.id

        if renamingProjectID == project.id {
            HStack(alignment: .top, spacing: 10) {
                SidebarIcon(
                    systemName: activity?.kind.iconSystemName ?? "folder",
                    tint: activity?.kind.tint ?? Color(nsColor: .secondaryLabelColor),
                    isSelected: isSelected
                )

                VStack(alignment: .leading, spacing: 5) {
                    TextField("Project name", text: $draftProjectName, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isSelected ? Color.accentColor : Color(nsColor: .labelColor))
                        .lineLimit(1)
                        .focused($focusedRenamingProjectID, equals: project.id)
                        .onSubmit {
                            commitRename(for: project)
                        }
                        .onExitCommand {
                            cancelRename()
                        }

                    if let activity {
                        Text(activity.message)
                            .font(.caption)
                            .foregroundStyle(activity.kind.textStyle)
                            .lineLimit(1)
                    } else {
                        Text(project.rootPath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        if let metadataText = metadataText(for: project.id) {
                            Text(metadataText)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground(isSelected: isSelected))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(rowStroke(isSelected: isSelected), lineWidth: 1)
            }
            .onAppear {
                focusedRenamingProjectID = project.id
            }
            .contentShape(Rectangle())
        } else {
            ProjectSidebarRow(
                project: project,
                metadata: viewModel.sidebarMetadata[project.id],
                activity: activity,
                isSelected: isSelected
            )
            .contentShape(Rectangle())
            .onTapGesture {
                selectProject(project)
            }
            .contextMenu {
                Button {
                    selectProject(project)
                    beginRename(project)
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                .disabled(viewModel.isLoading || isRenameLocked)

                Button(role: .destructive) {
                    requestDelete(project)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(viewModel.isLoading || isRenameLocked)

                Divider()

                Button {
                    selectProject(project)
                    onStartSession(project)
                } label: {
                    Label("Start Session", systemImage: "play.fill")
                }
                .disabled(viewModel.isLoading || isRenameLocked || !canStartSessionForProject(project.id))

                Button {
                    selectProject(project)
                    onPauseSession(project)
                } label: {
                    Label("Pause Session", systemImage: "pause.fill")
                }
                .disabled(viewModel.isLoading || isRenameLocked || !canPauseSessionForProject(project.id))
            }
        }
    }

    private func metadataText(for projectID: Project.ID) -> String? {
        guard let metadata = viewModel.sidebarMetadata[projectID] else {
            return nil
        }

        if let latest = metadata.latestCompletedSessionEndedAt {
            return "Last: \(latest.formatted(date: .abbreviated, time: .shortened))"
        }

        return "\(metadata.sessionCount) sessions"
    }

    private func beginRename(_ project: Project) {
        guard renamingProjectID == nil || renamingProjectID == project.id else {
            return
        }

        selectProject(project)
        draftProjectName = project.name
        renamingProjectID = project.id
    }

    private func requestDelete(_ project: Project) {
        guard renamingProjectID == nil || renamingProjectID == project.id else {
            return
        }

        selectProject(project)
        projectToDelete = project
        isDeleteProjectPromptVisible = projectToDelete != nil
    }

    private func commitRename(for project: Project) {
        let updatedName = draftProjectName
        renamingProjectID = nil
        focusedRenamingProjectID = nil
        Task {
            await viewModel.renameProject(project, to: updatedName)
        }
    }

    private func cancelRename() {
        renamingProjectID = nil
        focusedRenamingProjectID = nil
    }

    private func selectProject(_ project: Project) {
        if let renamingProjectID, renamingProjectID != project.id {
            return
        }

        viewModel.selectProject(id: project.id)
    }

    private func rowBackground(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(isSelected ? Color.accentColor.opacity(0.10) : Color(nsColor: .controlBackgroundColor))
    }

    private func rowStroke(isSelected: Bool) -> Color {
        isSelected
            ? Color.accentColor.opacity(0.32)
            : Color(nsColor: .separatorColor).opacity(0.35)
    }
}

private struct SidebarWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ProjectSidebarRow: View {
    let project: Project
    let metadata: ProjectSidebarMetadata?
    let activity: ProjectSidebarActivity?
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            SidebarIcon(
                systemName: activity?.kind.iconSystemName ?? "folder",
                tint: activity?.kind.tint ?? Color(nsColor: .secondaryLabelColor),
                isSelected: isSelected
            )

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(project.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isSelected ? Color.accentColor : Color(nsColor: .labelColor))
                        .lineLimit(2)
                        .layoutPriority(1)

                    Spacer(minLength: 4)

                    if let activity {
                        SidebarStatusIndicator(kind: activity.kind)
                    } else if metadata?.hasSnapshot == true {
                        Image(systemName: "doc.text")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .help("Resume Brief available")
                            .accessibilityLabel("Resume Brief available")
                    } else {
                        Spacer(minLength: 4)
                    }

                }

                if let activity {
                    Text(activity.message)
                        .font(.caption)
                        .foregroundStyle(activity.kind.textStyle)
                        .lineLimit(1)
                } else {
                    Text(project.rootPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if let metadataText {
                        Text(metadataText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground)
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(rowStroke, lineWidth: 1)
        }
    }

    private var metadataText: String? {
        guard let metadata else {
            return nil
        }
        if let latest = metadata.latestCompletedSessionEndedAt {
            return "Last: \(latest.formatted(date: .abbreviated, time: .shortened))"
        }
        return "\(metadata.sessionCount) sessions"
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(isSelected ? Color.accentColor.opacity(0.10) : Color(nsColor: .controlBackgroundColor))
    }

    private var rowStroke: Color {
        isSelected
            ? Color.accentColor.opacity(0.32)
            : Color(nsColor: .separatorColor).opacity(0.35)
    }
}

private struct SidebarSettingsRow: View {
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            SidebarIcon(
                systemName: "gearshape",
                tint: isSelected ? Color.accentColor : Color(nsColor: .secondaryLabelColor),
                isSelected: isSelected
            )

            Text("Settings")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? Color.accentColor : Color(nsColor: .labelColor))

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.10) : Color.clear)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    isSelected ? Color.accentColor.opacity(0.32) : Color.clear,
                    lineWidth: 1
                )
        }
    }
}

private struct SidebarIcon: View {
    let systemName: String
    let tint: Color
    let isSelected: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(iconFill)

            Image(systemName: systemName)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(isSelected ? Color.accentColor : tint)
        }
        .frame(width: 32, height: 32)
    }

    private var iconFill: Color {
        if isSelected {
            return Color.accentColor.opacity(0.13)
        }
        return tint.opacity(0.11)
    }
}

private struct SidebarStatusIndicator: View {
    let kind: ProjectSidebarActivityKind

    var body: some View {
        Circle()
            .fill(kind.tint)
            .frame(width: 8, height: 8)
            .accessibilityLabel(kind.accessibilityLabel)
    }
}

private struct EmptyProjectsRow: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("No Projects")
                .font(.subheadline.weight(.semibold))
            Text("Add a local project folder to begin.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

private extension ProjectSidebarActivityKind {
    var iconSystemName: String {
        switch self {
        case .preparing:
            "clock"
        case .activeBlock:
            "timer"
        case .pausedBlock:
            "pause.circle"
        case .betweenBlocks:
            "checkmark.circle"
        case .ending:
            "square.and.arrow.down"
        case .recovery:
            "arrow.clockwise.circle"
        case .accessLost:
            "folder.badge.questionmark"
        case .snapshotFailed:
            "exclamationmark.triangle"
        }
    }

    var tint: Color {
        switch self {
        case .preparing, .betweenBlocks, .recovery:
            Color(nsColor: .secondaryLabelColor)
        case .activeBlock:
            Color(red: 0.08, green: 0.58, blue: 0.28)
        case .pausedBlock, .ending, .accessLost:
            Color(red: 0.73, green: 0.40, blue: 0.12)
        case .snapshotFailed:
            Color(red: 0.78, green: 0.18, blue: 0.16)
        }
    }

    var textStyle: Color {
        switch self {
        case .activeBlock:
            Color(red: 0.08, green: 0.48, blue: 0.24)
        case .pausedBlock, .ending, .accessLost:
            Color(red: 0.60, green: 0.32, blue: 0.09)
        case .snapshotFailed:
            Color(red: 0.66, green: 0.12, blue: 0.11)
        case .preparing, .betweenBlocks, .recovery:
            Color(nsColor: .secondaryLabelColor)
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .preparing:
            "Preparing session"
        case .activeBlock:
            "Focus block active"
        case .pausedBlock:
            "Focus block paused"
        case .betweenBlocks:
            "Between focus blocks"
        case .ending:
            "Ending session"
        case .recovery:
            "Recovery available"
        case .accessLost:
            "Folder missing"
        case .snapshotFailed:
            "Snapshot needs attention"
        }
    }
}
