import Foundation
import AppKit
import SwiftUI

struct ProjectDetailContainerView: View {
    let project: Project?
    @ObservedObject var projectsViewModel: ProjectsViewModel
    @ObservedObject var sessionViewModel: SessionViewModel
    @ObservedObject var projectDetailViewModel: ProjectDetailViewModel

    var body: some View {
        if let project {
            ProjectSessionRouteView(
                project: project,
                projectsViewModel: projectsViewModel,
                sessionViewModel: sessionViewModel,
                projectDetailViewModel: projectDetailViewModel
            )
            .task(id: project.id) {
                projectDetailViewModel.dismissPresentedSnapshot()
                await projectDetailViewModel.loadLatestSnapshot(for: project.id)
                presentGeneratedSnapshotIfNeeded(for: project)
            }
            .task(id: project.rootPath) {
                await projectDetailViewModel.checkProjectAccess(for: project)
            }
            .onChange(of: sessionViewModel.generatedSnapshotContext) { _, _ in
                presentGeneratedSnapshotIfNeeded(for: project)
            }
        } else {
            ContentUnavailableView(
                "No Project Selected",
                systemImage: "folder.badge.questionmark",
                description: Text("Select or add a project from the sidebar.")
            )
        }
    }

    private func presentGeneratedSnapshotIfNeeded(for project: Project) {
        guard let context = sessionViewModel.generatedSnapshotContext,
              context.projectID == project.id
        else {
            return
        }

        projectDetailViewModel.presentGeneratedSnapshot(context.snapshot)
        sessionViewModel.clearGeneratedSnapshotContext()
        Task {
            await projectDetailViewModel.loadLatestSnapshot(for: project.id)
        }
    }
}

private struct ProjectSessionRouteView: View {
    let project: Project
    @ObservedObject var projectsViewModel: ProjectsViewModel
    @ObservedObject var sessionViewModel: SessionViewModel
    @ObservedObject var projectDetailViewModel: ProjectDetailViewModel

    var body: some View {
        switch route {
        case .snapshotDetail:
            snapshotDetail
        case .startSession:
            StartSessionView(project: project, viewModel: sessionViewModel)
        case .endSession:
            if let activeSession = sessionViewModel.activeSession {
                EndSessionView(project: project, session: activeSession, viewModel: sessionViewModel)
            } else {
                dashboard
            }
        case .activeSession, .pausedBlock, .betweenBlocks:
            if let activeSession = sessionViewModel.activeSession {
                ActiveSessionView(project: project, session: activeSession, viewModel: sessionViewModel)
            } else {
                dashboard
            }
        case .historicalSession:
            historicalSessionDetail
        case .projectAccessLost:
            ProjectAccessLostWorkspaceView(
                project: project,
                latestSnapshot: projectDetailViewModel.latestSnapshot,
                onRestoreProjectAccess: restoreProjectAccess,
                onViewSnapshot: {
                    projectDetailViewModel.presentLatestSnapshot()
                }
            )
        case .snapshotGenerationFailed:
            if let failedSnapshotSession = sessionViewModel.failedSnapshotSession {
                SnapshotFailureWorkspaceView(
                    project: project,
                    session: failedSnapshotSession,
                    blocks: projectDetailViewModel.blocks(for: failedSnapshotSession),
                    onRetrySnapshot: {
                        Task {
                            await sessionViewModel.retrySnapshotGeneration()
                        }
                    },
                    onOpenSettings: {
                        projectsViewModel.selectSettings()
                    }
                )
            } else {
                dashboard
            }
        case .projectDashboard, .emptyLibrary, .noProjectSelected, .settings:
            dashboard
        }
    }

    private var route: WorkspaceRoute {
        WorkspaceRoute.resolve(
            selectedItem: projectsViewModel.selectedItem,
            selectedProjectID: project.id,
            projectsIsEmpty: projectsViewModel.projects.isEmpty,
            presentedSnapshotID: projectDetailViewModel.presentedSnapshot?.id,
            flow: sessionViewModel.flow,
            activeSession: sessionViewModel.activeSession,
            activeBlock: sessionViewModel.activeBlock,
            sessionBlocks: sessionViewModel.sessionBlocks,
            selectedSessionID: projectDetailViewModel.selectedSessionID,
            projectAccessState: projectDetailViewModel.projectAccessState,
            failedSnapshotSession: sessionViewModel.failedSnapshotSession
        )
    }

    @ViewBuilder
    private var snapshotDetail: some View {
        if let snapshot = projectDetailViewModel.presentedSnapshot {
            SnapshotDetailView(
                project: project,
                snapshot: snapshot,
                session: projectDetailViewModel.session(for: snapshot),
                canStartSession: sessionViewModel.canStartSession,
                onStartNewSession: {
                    projectDetailViewModel.dismissPresentedSnapshot()
                    sessionViewModel.beginStartSession(for: project)
                },
                onBackToProject: {
                    projectDetailViewModel.dismissPresentedSnapshot()
                }
            )
        } else {
            dashboard
        }
    }

    @ViewBuilder
    private var historicalSessionDetail: some View {
        if let selectedSession = projectDetailViewModel.selectedSession {
            HistoricalSessionDetailView(
                project: project,
                session: selectedSession,
                snapshot: projectDetailViewModel.snapshot(for: selectedSession),
                blocks: projectDetailViewModel.blocks(for: selectedSession),
                incrementsForBlock: { block in
                    projectDetailViewModel.increments(for: block)
                },
                events: projectDetailViewModel.events(for: selectedSession),
                onBackToProject: {
                    projectDetailViewModel.clearSelectedSession()
                },
                onViewSnapshot: {
                    if let snapshot = projectDetailViewModel.snapshot(for: selectedSession) {
                        projectDetailViewModel.presentSnapshot(snapshot)
                    }
                }
            )
        } else {
            dashboard
        }
    }

    private var dashboard: some View {
        ProjectDashboardView(
            project: project,
            sessionViewModel: sessionViewModel,
            projectDetailViewModel: projectDetailViewModel,
            onStartSession: {
                sessionViewModel.beginStartSession(for: project)
            },
            onEndSession: {
                sessionViewModel.beginEndingActiveSession()
            },
            onViewSnapshot: {
                projectDetailViewModel.presentLatestSnapshot()
            },
            onSelectSession: { session in
                projectDetailViewModel.selectSession(session)
            }
        )
    }

    private func restoreProjectAccess() {
        Task {
            if let restoredProject = await projectsViewModel.restoreProjectAccessFromPicker(for: project) {
                await projectDetailViewModel.checkProjectAccess(for: restoredProject)
                await projectDetailViewModel.loadLatestSnapshot(for: restoredProject.id)
                sessionViewModel.updateRecoveredProject(restoredProject)
            }
        }
    }
}

struct EmptyLibraryWorkspaceView: View {
    let onAddProject: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 24)

            DashboardSurface {
                VStack(alignment: .leading, spacing: 14) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 48, height: 48)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.accentColor.opacity(0.12))
                        )

                    Text("No project selected")
                        .font(.largeTitle)
                        .fontWeight(.semibold)

                    Text("Add a project folder to create the first Working Memory Snapshot.")
                        .font(.body)
                        .foregroundStyle(.secondary)

                    Button(action: onAddProject) {
                        Label("Add Project", systemImage: "folder.badge.plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityHint("Choose a local project folder.")
                }
            }
            .frame(maxWidth: 620)

            Spacer()
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct ProjectAccessLostWorkspaceView: View {
    let project: Project
    let latestSnapshot: Snapshot?
    let onRestoreProjectAccess: () -> Void
    let onViewSnapshot: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                WorkspaceHeader(
                    title: project.name,
                    subtitle: "Project Root",
                    path: project.rootPath
                )

                DashboardSurface {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(
                            "This project folder is no longer accessible.",
                            systemImage: "folder.badge.questionmark"
                        )
                        .font(.headline)

                        Text("Choose the folder again to restore access before starting or resuming observation.")
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        Button(action: onRestoreProjectAccess) {
                            Label("Choose Folder Again", systemImage: "folder")
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityHint("Open a folder picker and update the stored path for this project.")
                    }
                }
                .tint(.orange)

                DashboardSurface {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Latest Memory")
                            .font(.headline)
                        if let latestSnapshot {
                            Text(latestSnapshot.resumeBrief)
                                .font(.callout)
                                .textSelection(.enabled)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Start here")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(latestSnapshot.nextAction)
                                    .font(.headline)
                                    .textSelection(.enabled)
                            }
                            Button(action: onViewSnapshot) {
                                Label("View Snapshot", systemImage: "doc.text.magnifyingglass")
                            }
                        } else {
                            Text("Existing snapshots, completed blocks, and manual increments remain readable because they are stored locally.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct SnapshotFailureWorkspaceView: View {
    let project: Project
    let session: WorkSession
    let blocks: [PomodoroBlock]
    let onRetrySnapshot: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                WorkspaceHeader(
                    title: "Snapshot generation needs attention.",
                    subtitle: "The completed session and brain dump are saved locally."
                )

                DashboardSurface {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Model response was not accepted", systemImage: "exclamationmark.triangle")
                            .font(.headline)
                        Text("Start LM Studio, check Settings, and retry local generation. Nothing was lost.")
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            Button(action: onRetrySnapshot) {
                                Label("Retry Snapshot", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(.borderedProminent)

                            Button(action: onOpenSettings) {
                                Label("Open Settings", systemImage: "gearshape")
                            }
                        }
                    }
                }
                .tint(.orange)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 14)], spacing: 14) {
                    DashboardSurface {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Saved brain dump")
                                .font(.headline)
                            Text(savedBrainDumpText)
                                .font(.callout)
                                .foregroundStyle(session.brainDump == nil ? .secondary : .primary)
                                .lineLimit(8)
                                .textSelection(.enabled)
                        }
                    }

                    DashboardSurface {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Saved block context")
                                .font(.headline)
                            HStack(spacing: 8) {
                                MetricPill(title: "Blocks", value: "\(blocks.count)")
                                MetricPill(title: "Completed", value: "\(completedBlocks)")
                            }
                            Text(project.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var savedBrainDumpText: String {
        guard let brainDump = session.brainDump,
              !brainDump.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return "The brain dump was saved, but it was empty."
        }
        return brainDump
    }

    private var completedBlocks: Int {
        blocks.filter { $0.status == .completed }.count
    }
}

private struct WorkspaceHeader: View {
    let title: String
    let subtitle: String
    let path: String?

    init(title: String, subtitle: String, path: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.path = path
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.title)
                .fontWeight(.semibold)
                .lineLimit(2)
                .textSelection(.enabled)

            if let path {
                ProjectRootPathLink(path: path, displayText: subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            } else {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
        }
    }
}

struct ProjectRootPathLink: View {
    let path: String
    let displayText: String

    init(path: String, displayText: String = "Project Root") {
        self.path = path
        self.displayText = displayText
    }

    var body: some View {
        Text(displayText)
            .underline()
            .contentShape(Rectangle())
            .highPriorityGesture(
                TapGesture().onEnded {
                    openProjectPath()
                }
            )
        .help(path)
        .foregroundStyle(.blue)
        .lineLimit(2)
        .truncationMode(.middle)
    }

    private func openProjectPath() {
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }
}
