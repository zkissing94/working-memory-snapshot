import SwiftUI

struct SnapshotDetailView: View {
    let project: Project
    let snapshot: Snapshot
    let session: WorkSession?
    let canStartSession: Bool
    let onStartNewSession: () -> Void
    let onBackToProject: () -> Void

    var body: some View {
        ScrollView {
            AppWorkspace(
                maxWidth: AppVisualTokens.Layout.wideWorkspaceWidth,
                horizontalPadding: AppVisualTokens.Spacing.workspaceWide,
                verticalPadding: AppVisualTokens.Spacing.workspaceWide
            ) {
                VStack(alignment: .leading, spacing: 26) {
                    header

                DashboardSurface(style: .soft) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Prompt evidence")
                            .font(.headline)
                        HStack(spacing: 8) {
                            MetricPill(title: "Decisions", value: "\(snapshot.decisions.count)")
                            MetricPill(title: "Open loops", value: "\(snapshot.openLoops.count)")
                            MetricPill(title: "Prompt", value: snapshot.promptVersion)
                        }
                    }
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 14)], spacing: 14) {
                    SnapshotTextSection(
                        title: "What changed",
                        text: snapshot.whatChanged
                    )
                    SnapshotListSection(
                        title: "Decisions",
                        items: snapshot.decisions,
                        emptyText: "No supported decisions were identified."
                    )
                    SnapshotListSection(
                        title: "Open loops",
                        items: snapshot.openLoops,
                        emptyText: "No open loops were identified."
                    )
                    SnapshotTextSection(
                        title: "Next action",
                        text: snapshot.nextAction,
                        style: .emphasized
                    )
                    SnapshotTextSection(
                        title: "Resume Brief",
                        text: snapshot.resumeBrief,
                        style: .soft
                    )
                }

                    HStack(spacing: 12) {
                        Button(action: onStartNewSession) {
                            Label("Start New Session", systemImage: "play.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canStartSession)
                        .accessibilityHint("Start a new session from this project.")

                        Button(action: onBackToProject) {
                            Label("Back to Project", systemImage: "chevron.left")
                        }
                        .accessibilityHint("Return to the project resume view.")
                    }
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Working Memory Snapshot")
                .font(.largeTitle)
                .fontWeight(.semibold)
            Text(project.name)
                .font(.title3)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            if let endedAt = session?.endedAt {
                Text("Session ended \(endedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Text(generatorDescription)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var generatorDescription: String {
        if snapshot.generatorModel == PlaceholderSnapshotGenerator.generatorModel {
            return "Deterministic placeholder from mission and brain dump only."
        }

        if let generatorModel = snapshot.generatorModel {
            return "Generated locally with \(generatorModel)."
        }

        return "Generated locally."
    }
}

private struct SnapshotTextSection: View {
    let title: String
    let text: String
    let style: AppSurfaceStyle

    init(title: String, text: String, style: AppSurfaceStyle = .standard) {
        self.title = title
        self.text = text
        self.style = style
    }

    var body: some View {
        DashboardSurface(style: style) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                Text(text)
                    .textSelection(.enabled)
            }
        }
    }
}

private struct SnapshotListSection: View {
    let title: String
    let items: [String]
    let emptyText: String

    var body: some View {
        DashboardSurface {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)

                if items.isEmpty {
                    Text(emptyText)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(items, id: \.self) { item in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("-")
                                    .foregroundStyle(.secondary)
                                Text(item)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
            }
        }
    }
}
