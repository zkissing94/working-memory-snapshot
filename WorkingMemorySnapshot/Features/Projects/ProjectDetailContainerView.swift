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
        } else if sessionViewModel.isStartingSession(for: project) {
            StartSessionView(project: project, viewModel: sessionViewModel)
        } else if let activeSession = sessionViewModel.activeSession,
                  activeSession.projectID == project.id,
                  sessionViewModel.isEndingSession(activeSession) {
            EndSessionView(
                project: project,
                session: activeSession,
                viewModel: sessionViewModel
            )
        } else if let selectedSession = projectDetailViewModel.selectedSession {
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
        } else if let activeSession = sessionViewModel.activeSession,
                  activeSession.projectID == project.id {
            ActiveSessionView(
                project: project,
                session: activeSession,
                viewModel: sessionViewModel
            )
        } else {
            ProjectMemoryOverviewView(
                project: project,
                latestSnapshot: projectDetailViewModel.latestSnapshot,
                latestSnapshotSession: projectDetailViewModel.latestSnapshotSession,
                projectAccessState: projectDetailViewModel.projectAccessState,
                canStartSession: sessionViewModel.canStartSession,
                failedSnapshotSession: sessionViewModel.failedSnapshotSession?.projectID == project.id
                    ? sessionViewModel.failedSnapshotSession
                    : nil,
                onStartSession: {
                    sessionViewModel.beginStartSession(for: project)
                },
                onViewSnapshot: {
                    projectDetailViewModel.presentLatestSnapshot()
                },
                onRestoreProjectAccess: {
                    Task {
                        if let restoredProject = await projectsViewModel.restoreProjectAccessFromPicker(for: project) {
                            await projectDetailViewModel.checkProjectAccess(for: restoredProject)
                            sessionViewModel.updateRecoveredProject(restoredProject)
                        }
                    }
                },
                onRetrySnapshot: {
                    Task {
                        await sessionViewModel.retrySnapshotGeneration()
                    }
                }
            )
        }
    }
}

private struct ProjectMemoryOverviewView: View {
    let project: Project
    let latestSnapshot: Snapshot?
    let latestSnapshotSession: WorkSession?
    let projectAccessState: ProjectAccessState
    let canStartSession: Bool
    let failedSnapshotSession: WorkSession?
    let onStartSession: () -> Void
    let onViewSnapshot: () -> Void
    let onRestoreProjectAccess: () -> Void
    let onRetrySnapshot: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let latestSnapshot {
                latestSnapshotSection(latestSnapshot)
                projectIdentitySection
            } else {
                projectIdentitySection

                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                    GridRow {
                        Text("Created")
                            .foregroundStyle(.secondary)
                        Text(project.createdAt.formatted(date: .abbreviated, time: .shortened))
                    }
                    GridRow {
                        Text("Updated")
                            .foregroundStyle(.secondary)
                        Text(project.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    }
                }
                .font(.body)
            }

            if projectAccessState.isInaccessible {
                projectAccessRecoverySection
            }

            VStack(alignment: .leading, spacing: 10) {
                Button(action: onStartSession) {
                    Label("Start Session", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canStartSession || projectAccessState.isInaccessible)
                .accessibilityLabel("Start Session")
                .accessibilityHint("Start a new working-memory session for \(project.name).")

                if projectAccessState.isInaccessible {
                    Text("Restore folder access before starting a session.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else if !canStartSession {
                    Text("End or cancel the active session before starting another.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Create the first working-memory boundary for this project.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if latestSnapshot != nil {
                    Button(action: onViewSnapshot) {
                        Label("View Snapshot", systemImage: "doc.text.magnifyingglass")
                    }
                    .disabled(latestSnapshot == nil)
                    .accessibilityHint("Open the full Working Memory Snapshot.")
                }
            }

            if let failedSnapshotSession {
                snapshotFailureSection(failedSnapshotSession)
            }

            Spacer()
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var projectIdentitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(project.name)
                .font(latestSnapshot == nil ? .largeTitle : .title3)
                .fontWeight(.semibold)
                .textSelection(.enabled)

            Text(project.rootPath)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }

    private var projectAccessRecoverySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                "This project folder is no longer accessible.",
                systemImage: "folder.badge.questionmark"
            )
            .font(.headline)

            Text("Choose the folder again to restore access.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Button(action: onRestoreProjectAccess) {
                Label("Choose Folder Again", systemImage: "folder")
            }
            .accessibilityHint("Open a folder picker and update the stored path for this project.")
        }
    }

    private func latestSnapshotSection(_ snapshot: Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Resume Brief")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text(snapshot.resumeBrief)
                    .font(.body)
                    .textSelection(.enabled)
            }
            .accessibilityElement(children: .combine)

            VStack(alignment: .leading, spacing: 8) {
                Text("Start here")
                    .font(.headline)
                Text(snapshot.nextAction)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .textSelection(.enabled)
            }
            .accessibilityElement(children: .combine)

            if let endedAt = latestSnapshotSession?.endedAt {
                Text("Latest session ended \(endedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func snapshotFailureSection(_ session: WorkSession) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Snapshot generation needs attention.")
                .font(.headline)
            Text("The session and brain dump are saved. Start LM Studio, check Settings, and retry local generation.")
                .font(.callout)
                .foregroundStyle(.secondary)

            if let brainDump = session.brainDump,
               !brainDump.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Saved brain dump")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(brainDump)
                    .font(.callout)
                    .lineLimit(4)
                    .textSelection(.enabled)
            }

            Button(action: onRetrySnapshot) {
                Label("Retry Snapshot", systemImage: "arrow.clockwise")
            }
            .accessibilityHint("Try local snapshot generation again for the saved session.")
        }
    }
}
