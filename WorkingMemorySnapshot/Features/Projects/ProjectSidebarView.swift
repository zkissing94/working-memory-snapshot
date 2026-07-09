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

    var projectRowMessage: String {
        switch kind {
        case .activeBlock, .pausedBlock:
            "Current session"
        default:
            message
        }
    }

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

enum CurrentSessionSummaryStatus: Equatable {
    case active
    case paused

    var label: String {
        switch self {
        case .active:
            "Active"
        case .paused:
            "Paused"
        }
    }

    var systemImage: String {
        switch self {
        case .active:
            "timer"
        case .paused:
            "pause.circle"
        }
    }

    var tint: Color {
        tone.tint
    }

    var softFill: Color {
        tone.softFill
    }

    private var tone: AppStatusTone {
        switch self {
        case .active:
            .success
        case .paused:
            .warning
        }
    }
}

enum CurrentSessionBlockIndicatorStatus: Equatable {
    case active
    case paused
    case completed
    case interrupted

    var tint: Color {
        switch self {
        case .active:
            AppStatusTone.success.tint
        case .paused:
            AppStatusTone.warning.tint
        case .completed:
            AppStatusTone.success.tint
        case .interrupted:
            Color(nsColor: .tertiaryLabelColor)
        }
    }
}

struct CurrentSessionBlockIndicator: Equatable, Identifiable {
    let id: PomodoroBlock.ID
    let blockIndex: Int
    let status: CurrentSessionBlockIndicatorStatus
}

struct CurrentSessionSummary: Equatable {
    private static let maximumVisibleIndicators = 8

    let projectID: Project.ID
    let sessionStartedAt: Date
    let mission: String
    let status: CurrentSessionSummaryStatus
    let activeBlock: PomodoroBlock?
    let blocks: [PomodoroBlock]

    static func current(
        activeSession: WorkSession?,
        activeBlock: PomodoroBlock?,
        sessionBlocks: [PomodoroBlock]
    ) -> CurrentSessionSummary? {
        guard let activeSession, activeSession.status == .active else {
            return nil
        }

        let normalizedBlocks = normalizedBlocks(activeBlock: activeBlock, sessionBlocks: sessionBlocks)
        return CurrentSessionSummary(
            projectID: activeSession.projectID,
            sessionStartedAt: activeSession.startedAt,
            mission: activeSession.mission,
            status: activeBlock?.status == .paused ? .paused : .active,
            activeBlock: activeBlock,
            blocks: normalizedBlocks
        )
    }

    var statusText: String {
        status.label
    }

    var completedBlockCount: Int {
        blocks.filter { $0.status == .completed }.count
    }

    var blockProgressText: String {
        if let activeBlock {
            return "Block \(activeBlock.blockIndex) · \(completedBlockCount) completed"
        }

        if blocks.isEmpty {
            return "No blocks yet"
        }

        return "\(completedBlockCount) completed · \(blocks.count) recorded"
    }

    var visibleBlockIndicators: [CurrentSessionBlockIndicator] {
        blocks.prefix(Self.maximumVisibleIndicators).map { block in
            CurrentSessionBlockIndicator(
                id: block.id,
                blockIndex: block.blockIndex,
                status: indicatorStatus(for: block.status)
            )
        }
    }

    var remainingBlockIndicatorCount: Int {
        max(0, blocks.count - Self.maximumVisibleIndicators)
    }

    func elapsedSessionTimeText(at date: Date) -> String {
        DurationFormatter.elapsedTimerString(from: Int(date.timeIntervalSince(sessionStartedAt)))
    }

    func blockRemainingTimeText(at date: Date) -> String? {
        guard let activeBlock else {
            return nil
        }

        return DurationFormatter.timerString(from: activeBlock.remainingSeconds(at: date))
    }

    private static func normalizedBlocks(
        activeBlock: PomodoroBlock?,
        sessionBlocks: [PomodoroBlock]
    ) -> [PomodoroBlock] {
        var blocksByID: [PomodoroBlock.ID: PomodoroBlock] = [:]
        for block in sessionBlocks {
            blocksByID[block.id] = block
        }
        if let activeBlock {
            blocksByID[activeBlock.id] = activeBlock
        }
        return blocksByID.values.sorted { $0.blockIndex < $1.blockIndex }
    }

    private func indicatorStatus(for status: PomodoroBlockStatus) -> CurrentSessionBlockIndicatorStatus {
        switch status {
        case .active:
            .active
        case .paused:
            .paused
        case .completed:
            .completed
        case .interrupted:
            .interrupted
        }
    }
}

struct ProjectSidebarView: View {
    @ObservedObject var viewModel: ProjectsViewModel
    let activity: ProjectSidebarActivity?
    let currentSessionSummary: CurrentSessionSummary?
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
                    if let currentSessionSummary {
                        CurrentSessionSummaryView(summary: currentSessionSummary) {
                            viewModel.selectProject(id: currentSessionSummary.projectID)
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        projectsHeader

                        if listedProjects.isEmpty {
                            EmptyProjectsRow()
                        } else {
                            ForEach(listedProjects) { project in
                                projectRowButton(
                                    for: project,
                                    activity: activity?.projectID == project.id ? activity : nil,
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
            Image("WorkingMemoryIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
                }

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
        .buttonStyle(AppIconButtonStyle(tone: .accent))
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
        .buttonStyle(AppIconButtonStyle(tone: .error))
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
        .buttonStyle(
            AppClickableRowButtonStyle(
                isSelected: viewModel.selectedItem == .settings,
                baseFill: .clear
            )
        )
        .accessibilityLabel("Settings")
        .accessibilityHint("Configure local snapshot generation.")
    }

    private var listedProjects: [Project] {
        viewModel.projects
    }

    private func sidebarSection(_ title: String) -> some View {
        AppSectionLabel(title)
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
                        Text(activity.projectRowMessage)
                            .font(.caption)
                            .foregroundStyle(activity.kind.textStyle)
                            .lineLimit(1)
                } else {
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
            Button {
                selectProject(project)
            } label: {
                ProjectSidebarRow(
                    project: project,
                    metadata: viewModel.sidebarMetadata[project.id],
                    activity: activity,
                    isSelected: isSelected
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(AppClickableRowButtonStyle(isSelected: isSelected))
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

private struct CurrentSessionSummaryView: View {
    let summary: CurrentSessionSummary
    let onViewSession: () -> Void

    var body: some View {
        TimelineView(.periodic(from: summary.sessionStartedAt, by: 1)) { timeline in
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Label(summary.statusText, systemImage: summary.status.systemImage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(summary.status.tint)
                        .lineLimit(1)

                    Spacer(minLength: 6)
                }

                HStack(alignment: .top, spacing: 10) {
                    compactMetric(
                        label: "Elapsed",
                        value: summary.elapsedSessionTimeText(at: timeline.date),
                        countsDown: false
                    )

                    if let remaining = summary.blockRemainingTimeText(at: timeline.date) {
                        compactMetric(label: "Block", value: remaining, countsDown: true)
                    }
                }

                Text(summary.mission)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .center, spacing: 8) {
                    Text(summary.blockProgressText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    CurrentSessionBlockIndicators(summary: summary)
                }

                Button(action: onViewSession) {
                    Label("View session", systemImage: "arrow.right")
                        .font(.caption.weight(.semibold))
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.plain)
                .foregroundStyle(summary.status.tint)
                .accessibilityHint("Open the project for the active session.")
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(summary.status.softFill)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(summary.status.tint.opacity(0.24), lineWidth: 1)
            }
            .accessibilityElement(children: .contain)
        }
    }

    private func compactMetric(label: String, value: String, countsDown: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: countsDown))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CurrentSessionBlockIndicators: View {
    let summary: CurrentSessionSummary

    var body: some View {
        HStack(spacing: 4) {
            ForEach(summary.visibleBlockIndicators) { indicator in
                Circle()
                    .fill(indicator.status.tint)
                    .frame(width: 7, height: 7)
                    .accessibilityLabel("Block \(indicator.blockIndex)")
            }

            if summary.remainingBlockIndicatorCount > 0 {
                Text("+\(summary.remainingBlockIndicatorCount)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Block progress")
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
                    Text(activity.projectRowMessage)
                        .font(.caption)
                        .foregroundStyle(activity.kind.textStyle)
                        .lineLimit(1)
                } else {
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
            .shadow(color: kind.tint.opacity(0.24), radius: 3)
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
        tone.tint
    }

    var textStyle: Color {
        tone.tint
    }

    private var tone: AppStatusTone {
        switch self {
        case .activeBlock:
            .success
        case .pausedBlock, .ending, .accessLost:
            .warning
        case .snapshotFailed:
            .error
        case .preparing, .betweenBlocks, .recovery:
            .neutral
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
