import SwiftUI

struct ProjectDashboardView: View {
    let project: Project
    @ObservedObject var sessionViewModel: SessionViewModel
    @ObservedObject var projectDetailViewModel: ProjectDetailViewModel
    let onStartSession: () -> Void
    let onEndSession: () -> Void
    let onViewSnapshot: () -> Void
    let onSelectSession: (WorkSession) -> Void
    @State private var isPreviousSessionListExpanded = false
    @State private var expandedDayGroups = Set<String>()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var activeSession: WorkSession? {
        guard sessionViewModel.activeSession?.projectID == project.id else {
            return nil
        }
        return sessionViewModel.activeSession
    }

    private var previousSessions: [WorkSession] {
        (projectDetailViewModel.history(for: project.id)?.sessions ?? [])
            .filter { $0.status != .active }
            .sorted { $0.startedAt > $1.startedAt }
    }

    var body: some View {
        ScrollView {
            AppWorkspace(
                maxWidth: AppVisualTokens.Layout.wideWorkspaceWidth,
                horizontalPadding: 42,
                verticalPadding: 34
            ) {
                VStack(alignment: .leading, spacing: 22) {
                    header

                    if let activeSession {
                        ActiveSessionDashboardCard(
                            session: activeSession,
                            activeBlock: sessionViewModel.activeBlock,
                            blocks: sessionViewModel.sessionBlocks,
                            onContinue: {
                                projectDetailViewModel.clearSelectedSession(for: project.id)
                            },
                            onEnd: onEndSession
                        )
                    } else {
                        startSessionCard
                    }

                    sessionTimeline
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle(project.name)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(project.name)
                .font(.title)
                .fontWeight(.semibold)
                .lineLimit(2)
                .textSelection(.enabled)

            ProjectRootPathLink(path: project.rootPath)
                .font(.caption)
                .lineLimit(2)
                .truncationMode(.middle)

            HStack(spacing: 8) {
                MetricPill(title: "Sessions", value: summary.map { "\($0.completedSessionCount)" } ?? "—")
                MetricPill(title: "Blocks", value: summary.map { "\($0.completedBlockCount)" } ?? "—")
                if let latest = summary?.latestSnapshotSession?.endedAt {
                    MetricPill(title: "Last", value: latest.formatted(date: .omitted, time: .shortened))
                }
            }
        }
    }

    private var summary: ProjectDashboardSummary? {
        projectDetailViewModel.summary(for: project.id)
    }

    @ViewBuilder
    private var startSessionCard: some View {
        if let latestSnapshot = summary?.latestSnapshot {
            latestMemoryCard(latestSnapshot)
        } else if summary != nil {
            firstSessionCard
        } else {
            loadingMemoryCard
        }
    }

    private var loadingMemoryCard: some View {
        DashboardSurface(style: .soft) {
            HStack(spacing: 12) {
                ProgressView()
                    .controlSize(.small)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Loading project memory…")
                        .font(.headline)
                    Text("Reading the latest snapshot stored on this Mac.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minHeight: 72, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private var firstSessionCard: some View {
        DashboardSurface(style: .soft) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Start a new session")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text("Create a working-memory boundary for this project.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button(action: onStartSession) {
                    Label("Start Session", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    !sessionViewModel.canStartSession
                        || projectDetailViewModel.projectAccessState(for: project.id).isInaccessible
                )
            }
        }
    }

    private func latestMemoryCard(_ snapshot: Snapshot) -> some View {
        DashboardSurface(style: .emphasized) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Start a new session")
                    .font(.title2)
                    .fontWeight(.semibold)

                VStack(alignment: .leading, spacing: 5) {
                    Text("Continue from")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text(snapshot.nextAction)
                        .font(.headline)
                        .lineLimit(3)
                        .textSelection(.enabled)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Resume Brief")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text(snapshot.resumeBrief)
                        .font(.callout)
                        .lineLimit(5)
                        .textSelection(.enabled)
                }

                HStack(spacing: 12) {
                    Button(action: onStartSession) {
                        Label("Start Session", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        !sessionViewModel.canStartSession
                            || projectDetailViewModel.projectAccessState(for: project.id).isInaccessible
                    )

                    Button(action: onViewSnapshot) {
                        Label("View Snapshot", systemImage: "doc.text.magnifyingglass")
                    }
                }
            }
        }
    }

    private var sessionTimeline: some View {
        VStack(alignment: .leading, spacing: 12) {
            DisclosureGroup(
                isExpanded: $isPreviousSessionListExpanded,
                content: {
                    if projectDetailViewModel.history(for: project.id) == nil {
                        DashboardSurface {
                            HStack(spacing: 10) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Loading previous sessions…")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else if previousSessions.isEmpty {
                        DashboardSurface {
                            Text("Completed sessions will appear here.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        ForEach(groupedPreviousSessions, id: \.title) { group in
                            DisclosureGroup(
                                isExpanded: binding(for: group.title),
                                content: {
                                    VStack(alignment: .leading, spacing: 8) {
                                        ForEach(group.sessions) { session in
                                            SessionTimelineRow(
                                                session: session,
                                                snapshot: projectDetailViewModel.snapshot(for: session),
                                                blocks: projectDetailViewModel.blocks(for: session),
                                                isSelected: projectDetailViewModel.selectedSessionID(for: project.id) == session.id,
                                                onSelect: {
                                                    onSelectSession(session)
                                                }
                                            )
                                            .transition(AppMotion.insertionTransition(reduceMotion: reduceMotion))
                                        }
                                    }
                                    .padding(.leading, 12)
                                },
                                label: {
                                    Text(group.title)
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.secondary)
                                }
                            )
                            .padding(.leading, 12)
                        }
                    }
                },
            label: {
                Text("Previous Sessions")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
        )
        .animation(
            AppMotion.animation(.standard, reduceMotion: reduceMotion),
            value: isPreviousSessionListExpanded
        )
        .animation(
            AppMotion.animation(.standard, reduceMotion: reduceMotion),
            value: expandedDayGroups
        )
        }
    }

    private func binding(for title: String) -> Binding<Bool> {
        Binding(
            get: { expandedDayGroups.contains(title) },
            set: { isExpanded in
                if isExpanded {
                    expandedDayGroups.insert(title)
                } else {
                    expandedDayGroups.remove(title)
                }
            }
        )
    }

    private var groupedPreviousSessions: [(title: String, sessions: [WorkSession])] {
        let calendar = Calendar.current
        var groups: [(title: String, sessions: [WorkSession])] = []
        for session in previousSessions {
            let title: String
            if calendar.isDateInToday(session.startedAt) {
                title = "Today"
            } else if calendar.isDateInYesterday(session.startedAt) {
                title = "Yesterday"
            } else {
                title = session.startedAt.formatted(date: .abbreviated, time: .omitted)
            }

            if let index = groups.firstIndex(where: { $0.title == title }) {
                groups[index].sessions.append(session)
            } else {
                groups.append((title, [session]))
            }
        }
        return groups
    }
}

private struct ActiveSessionDashboardCard: View {
    let session: WorkSession
    let activeBlock: PomodoroBlock?
    let blocks: [PomodoroBlock]
    let onContinue: () -> Void
    let onEnd: () -> Void

    var body: some View {
        DashboardSurface(style: .status(.accent)) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "play.fill")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Color.accentColor))

                    VStack(alignment: .leading, spacing: 4) {
                        AppStatusPill("Active Session", systemImage: "timer", tone: .accent)
                        Text(session.mission)
                            .font(.headline)
                            .lineLimit(3)
                    }

                    Spacer()
                }

                HStack(spacing: 6) {
                    Text("Started \(session.startedAt.formatted(date: .omitted, time: .shortened))")
                    Text("·")
                    Text("\(completedBlocks) blocks completed")
                    if let activeBlock {
                        Text("·")
                        Text("Block \(activeBlock.blockIndex)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                ProgressView(value: progress)
                    .tint(.accentColor)

                HStack(spacing: 10) {
                    Button(action: onContinue) {
                        Label("Continue Session", systemImage: "rectangle.and.pencil.and.ellipsis")
                    }
                    .buttonStyle(.borderedProminent)

                    Button(action: onEnd) {
                        Label("End Session", systemImage: "stop")
                    }
                }
            }
        }
    }

    private var completedBlocks: Int {
        blocks.filter { $0.status == .completed }.count
    }

    private var progress: Double {
        guard let activeBlock else {
            return blocks.isEmpty ? 0 : 1
        }
        return min(1, Double(activeBlock.elapsedSeconds()) / Double(max(1, activeBlock.plannedDurationSeconds)))
    }
}

private struct SessionTimelineRow: View {
    let session: WorkSession
    let snapshot: Snapshot?
    let blocks: [PomodoroBlock]
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 12) {
                Text(session.startedAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 54, alignment: .leading)

                VStack(alignment: .leading, spacing: 7) {
                    Text(session.mission)
                        .font(.callout)
                        .fontWeight(.semibold)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        Text("\(blocks.count) blocks")
                        if let duration = durationText {
                            Text("·")
                            Text(duration)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    if let nextAction = snapshot?.nextAction {
                        Text("Next: \(nextAction)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(AppClickableRowButtonStyle(isSelected: isSelected))
    }

    private var durationText: String? {
        guard let endedAt = session.endedAt else {
            return nil
        }
        return DurationFormatter.shortString(from: Int(endedAt.timeIntervalSince(session.startedAt)))
    }
}

struct MetricPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout)
                .fontWeight(.semibold)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: AppVisualTokens.Radius.standard, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay {
            RoundedRectangle(cornerRadius: AppVisualTokens.Radius.standard, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.42))
        }
    }
}

enum DurationFormatter {
    static func elapsedTimerString(from seconds: Int) -> String {
        let clampedSeconds = max(0, seconds)
        let hours = clampedSeconds / 3_600
        let minutes = (clampedSeconds % 3_600) / 60
        let seconds = clampedSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }

        return String(format: "%02d:%02d", minutes, seconds)
    }

    static func shortString(from seconds: Int) -> String {
        let clampedSeconds = max(0, seconds)
        let hours = clampedSeconds / 3_600
        let minutes = (clampedSeconds % 3_600) / 60
        let seconds = clampedSeconds % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        if minutes > 0 {
            return "\(minutes)m"
        }
        return "\(seconds)s"
    }

    static func timerString(from seconds: Int) -> String {
        let clampedSeconds = max(0, seconds)
        let minutes = clampedSeconds / 60
        let seconds = clampedSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
