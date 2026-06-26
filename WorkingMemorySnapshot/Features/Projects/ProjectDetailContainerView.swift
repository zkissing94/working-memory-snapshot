import SwiftUI

struct ProjectDetailContainerView: View {
    let project: Project?
    @ObservedObject var sessionViewModel: SessionViewModel

    var body: some View {
        if let project {
            ProjectSessionRouteView(
                project: project,
                viewModel: sessionViewModel
            )
        } else {
            ContentUnavailableView(
                "No Project Selected",
                systemImage: "folder.badge.questionmark",
                description: Text("Select or add a project from the sidebar.")
            )
        }
    }
}

private struct ProjectSessionRouteView: View {
    let project: Project
    @ObservedObject var viewModel: SessionViewModel

    var body: some View {
        if viewModel.isStartingSession(for: project) {
            StartSessionView(project: project, viewModel: viewModel)
        } else if let activeSession = viewModel.activeSession,
                  activeSession.projectID == project.id {
            if viewModel.isEndingSession(activeSession) {
                EndSessionView(
                    project: project,
                    session: activeSession,
                    viewModel: viewModel
                )
            } else {
                ActiveSessionView(
                    project: project,
                    session: activeSession,
                    viewModel: viewModel
                )
            }
        } else {
            ProjectDetailView(
                project: project,
                canStartSession: viewModel.canStartSession,
                onStartSession: {
                    viewModel.beginStartSession(for: project)
                }
            )
        }
    }
}

private struct ProjectDetailView: View {
    let project: Project
    let canStartSession: Bool
    let onStartSession: () -> Void

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
            }

            Spacer()
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
