import SwiftUI

struct ProjectDetailContainerView: View {
    let project: Project?
    @ObservedObject var sessionViewModel: SessionViewModel
    @ObservedObject var projectDetailViewModel: ProjectDetailViewModel

    var body: some View {
        if let project {
            ProjectSessionRouteView(
                project: project,
                sessionViewModel: sessionViewModel,
                projectDetailViewModel: projectDetailViewModel
            )
            .task(id: project.id) {
                projectDetailViewModel.dismissPresentedSnapshot()
                await projectDetailViewModel.loadLatestSnapshot(for: project.id)
                presentGeneratedSnapshotIfNeeded(for: project)
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
    @ObservedObject var sessionViewModel: SessionViewModel
    @ObservedObject var projectDetailViewModel: ProjectDetailViewModel

    var body: some View {
        if let snapshot = projectDetailViewModel.presentedSnapshot {
            SnapshotDetailView(
                project: project,
                snapshot: snapshot,
                session: projectDetailViewModel.latestSnapshotSession,
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
                  activeSession.projectID == project.id {
            if sessionViewModel.isEndingSession(activeSession) {
                EndSessionView(
                    project: project,
                    session: activeSession,
                    viewModel: sessionViewModel
                )
            } else {
                ActiveSessionView(
                    project: project,
                    session: activeSession,
                    viewModel: sessionViewModel
                )
            }
        } else {
            ProjectDetailView(
                project: project,
                latestSnapshot: projectDetailViewModel.latestSnapshot,
                latestSnapshotSession: projectDetailViewModel.latestSnapshotSession,
                canStartSession: sessionViewModel.canStartSession,
                hasSnapshotGenerationFailure: sessionViewModel.failedSnapshotSession?.projectID == project.id,
                onStartSession: {
                    sessionViewModel.beginStartSession(for: project)
                },
                onViewSnapshot: {
                    projectDetailViewModel.presentLatestSnapshot()
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

private struct ProjectDetailView: View {
    let project: Project
    let latestSnapshot: Snapshot?
    let latestSnapshotSession: WorkSession?
    let canStartSession: Bool
    let hasSnapshotGenerationFailure: Bool
    let onStartSession: () -> Void
    let onViewSnapshot: () -> Void
    let onRetrySnapshot: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text(project.name)
                    .font(.largeTitle)
                    .fontWeight(.semibold)
                    .textSelection(.enabled)

                Text(project.rootPath)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            if let latestSnapshot {
                latestSnapshotSection(latestSnapshot)
            } else {
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

            VStack(alignment: .leading, spacing: 10) {
                Button(action: onStartSession) {
                    Label("Start Session", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canStartSession)

                if !canStartSession {
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
                }
            }

            if hasSnapshotGenerationFailure {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Snapshot generation did not finish.")
                        .font(.headline)
                    Text("The session and brain dump are saved. Retry the deterministic placeholder snapshot.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button(action: onRetrySnapshot) {
                        Label("Retry Snapshot", systemImage: "arrow.clockwise")
                    }
                }
            }

            Spacer()
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

            VStack(alignment: .leading, spacing: 8) {
                Text("Start here")
                    .font(.headline)
                Text(snapshot.nextAction)
                    .font(.title3)
                    .textSelection(.enabled)
            }

            if let endedAt = latestSnapshotSession?.endedAt {
                Text("Latest session ended \(endedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
