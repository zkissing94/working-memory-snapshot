import SwiftUI

struct StartSessionView: View {
    let project: Project
    @ObservedObject var viewModel: SessionViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Header(project: project)

            VStack(alignment: .leading, spacing: 8) {
                Text("Mission")
                    .font(.headline)
                TextField(
                    "What are you trying to make true?",
                    text: $viewModel.mission,
                    axis: .vertical
                )
                .lineLimit(3, reservesSpace: true)
                .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 12) {
                Button {
                    Task {
                        await viewModel.startSession(for: project)
                    }
                } label: {
                    Label("Start Session", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(viewModel.isWorking)

                Button("Cancel") {
                    viewModel.dismissStartSession()
                }
                .disabled(viewModel.isWorking)
            }

            Spacer()
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct ActiveSessionView: View {
    let project: Project
    let session: WorkSession
    @ObservedObject var viewModel: SessionViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Session active")
                        .font(.title)
                        .fontWeight(.semibold)
                    Text(project.name)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Spacer()

                TimelineView(.periodic(from: session.startedAt, by: 1)) { context in
                    Text(elapsedString(from: session.startedAt, to: context.date))
                        .font(.system(.title, design: .monospaced))
                        .monospacedDigit()
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Mission")
                    .font(.headline)
                Text(session.mission)
                    .font(.title3)
                    .textSelection(.enabled)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Observed")
                    .font(.headline)
                Text(viewModel.observationSummary.displayText)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            HStack(spacing: 12) {
                Button {
                    viewModel.beginEndingActiveSession()
                } label: {
                    Label("End Session", systemImage: "checkmark.circle")
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isWorking)

                Button(role: .destructive) {
                    Task {
                        await viewModel.cancelActiveSession()
                    }
                } label: {
                    Label("Cancel Session", systemImage: "xmark.circle")
                }
                .disabled(viewModel.isWorking)
            }

            Spacer()
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func elapsedString(from startDate: Date, to endDate: Date) -> String {
        let elapsedSeconds = max(0, Int(endDate.timeIntervalSince(startDate)))
        let hours = elapsedSeconds / 3_600
        let minutes = (elapsedSeconds % 3_600) / 60
        let seconds = elapsedSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }

        return String(format: "%02d:%02d", minutes, seconds)
    }
}

struct EndSessionView: View {
    let project: Project
    let session: WorkSession
    @ObservedObject var viewModel: SessionViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Header(project: project)

            VStack(alignment: .leading, spacing: 8) {
                Text("What is still in your head?")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Include decisions, surprises, blockers, and what you would do next.")
                    .foregroundStyle(.secondary)
                TextEditor(text: $viewModel.brainDump)
                    .font(.body)
                    .frame(minHeight: 220)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(.secondary.opacity(0.25))
                    }
            }

            HStack(spacing: 12) {
                Button {
                    Task {
                        await viewModel.completeActiveSession()
                    }
                } label: {
                    Label("Generate Working Memory Snapshot", systemImage: "doc.text")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(viewModel.isWorking)

                Button("Return to Session") {
                    viewModel.returnToActiveSession()
                }
                .disabled(viewModel.isWorking)
            }

            if viewModel.isWorking {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Creating your Working Memory Snapshot locally...")
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

struct SessionRecoverySheet: View {
    let context: SessionRecoveryContext
    let onResume: () -> Void
    let onEnd: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("A session was active when the app closed.")
                .font(.title2)
                .fontWeight(.semibold)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                GridRow {
                    Text("Project")
                        .foregroundStyle(.secondary)
                    Text(context.project.name)
                }
                GridRow {
                    Text("Mission")
                        .foregroundStyle(.secondary)
                    Text(context.session.mission)
                }
                GridRow {
                    Text("Started")
                        .foregroundStyle(.secondary)
                    Text(context.session.startedAt.formatted(date: .abbreviated, time: .shortened))
                }
            }

            HStack(spacing: 12) {
                Button("Resume Session", action: onResume)
                    .buttonStyle(.borderedProminent)
                Button("End Session", action: onEnd)
                Button("Cancel Session", role: .destructive, action: onCancel)
            }
        }
        .padding(28)
        .frame(minWidth: 460, alignment: .leading)
    }
}

private struct Header: View {
    let project: Project

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(project.name)
                .font(.largeTitle)
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
}
