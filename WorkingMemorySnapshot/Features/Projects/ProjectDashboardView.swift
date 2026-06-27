import SwiftUI

struct ProjectDashboardView: View {
    let project: Project
    @ObservedObject var sessionViewModel: SessionViewModel
    @ObservedObject var projectDetailViewModel: ProjectDetailViewModel
    let onStartSession: () -> Void
    let onViewSnapshot: () -> Void
    let onSelectSession: (WorkSession) -> Void
    let onRestoreProjectAccess: () -> Void
    let onRetrySnapshot: () -> Void

    private var activeSession: WorkSession? {
        guard sessionViewModel.activeSession?.projectID == project.id else {
            return nil
        }
        return sessionViewModel.activeSession
    }

    private var previousSessions: [WorkSession] {
        projectDetailViewModel.sessions
            .filter { $0.status != .active }
            .sorted { $0.startedAt > $1.startedAt }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header

                if projectDetailViewModel.projectAccessState.isInaccessible {
                    accessRecovery
                }

                if let latestSnapshot = projectDetailViewModel.latestSnapshot {
                    latestMemoryCard(latestSnapshot)
                }

                if let activeSession {
                    ActiveSessionDashboardCard(
                        session: activeSession,
                        activeBlock: sessionViewModel.activeBlock,
                        blocks: sessionViewModel.sessionBlocks,
                        captureCount: sessionViewModel.activeBlockIncrements.count,
                        onContinue: {
                            projectDetailViewModel.clearSelectedSession()
                        }
                    )
                } else {
                    startSessionCard
                }

                if let failedSnapshotSession = sessionViewModel.failedSnapshotSession,
                   failedSnapshotSession.projectID == project.id {
                    snapshotFailureCard(failedSnapshotSession)
                }

                sessionTimeline
            }
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle(project.name)
        .task(id: project.id) {
            await projectDetailViewModel.loadLatestSnapshot(for: project.id)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(project.name)
                .font(.title2)
                .fontWeight(.semibold)
                .lineLimit(2)
                .textSelection(.enabled)

            Text(project.rootPath)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }

    private var accessRecovery: some View {
        DashboardSurface {
            VStack(alignment: .leading, spacing: 10) {
                Label("This project folder is no longer accessible.", systemImage: "folder.badge.questionmark")
                    .font(.headline)
                Text("Choose the folder again to restore access before starting or resuming observation.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button(action: onRestoreProjectAccess) {
                    Label("Choose Folder Again", systemImage: "folder")
                }
            }
        }
    }

    private var startSessionCard: some View {
        DashboardSurface {
            VStack(alignment: .leading, spacing: 12) {
                Text("Session")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text("Create a working-memory boundary for this project.")
                    .font(.body)
                Button(action: onStartSession) {
                    Label("Start Session", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!sessionViewModel.canStartSession || projectDetailViewModel.projectAccessState.isInaccessible)
            }
        }
    }

    private func latestMemoryCard(_ snapshot: Snapshot) -> some View {
        DashboardSurface {
            VStack(alignment: .leading, spacing: 12) {
                Text("Latest Memory")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Text(snapshot.resumeBrief)
                    .font(.callout)
                    .lineLimit(5)
                    .textSelection(.enabled)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Start here")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(snapshot.nextAction)
                        .font(.headline)
                        .lineLimit(3)
                        .textSelection(.enabled)
                }

                Button(action: onViewSnapshot) {
                    Label("View Snapshot", systemImage: "doc.text.magnifyingglass")
                }
            }
        }
    }

    private func snapshotFailureCard(_ session: WorkSession) -> some View {
        DashboardSurface {
            VStack(alignment: .leading, spacing: 10) {
                Text("Snapshot generation needs attention.")
                    .font(.headline)
                Text("The session and brain dump are saved. Start LM Studio, check Settings, and retry local generation.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button(action: onRetrySnapshot) {
                    Label("Retry Snapshot", systemImage: "arrow.clockwise")
                }
                if let endedAt = session.endedAt {
                    Text("Session ended \(endedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var sessionTimeline: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Previous Sessions")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            if previousSessions.isEmpty {
                DashboardSurface {
                    Text("Completed sessions will appear here.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(groupedPreviousSessions, id: \.title) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(group.title)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        ForEach(group.sessions) { session in
                            SessionTimelineRow(
                                session: session,
                                snapshot: projectDetailViewModel.snapshot(for: session),
                                blocks: projectDetailViewModel.blocks(for: session),
                                isSelected: projectDetailViewModel.selectedSessionID == session.id,
                                onSelect: {
                                    onSelectSession(session)
                                }
                            )
                        }
                    }
                }
            }
        }
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
    let captureCount: Int
    let onContinue: () -> Void

    var body: some View {
        DashboardSurface {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "play.fill")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Color.accentColor))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Active Session")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        Text(session.mission)
                            .font(.headline)
                            .lineLimit(3)
                    }

                    Spacer()
                }

                HStack(spacing: 6) {
                    Text("Started \(session.startedAt.formatted(date: .omitted, time: .shortened))")
                    Text("·")
                    Text("\(captureCount) capture\(captureCount == 1 ? "" : "s") saved")
                    if let activeBlock {
                        Text("·")
                        Text("Focus block \(activeBlock.blockIndex)")
                    } else if completedBlocks > 0 {
                        Text("·")
                        Text("\(completedBlocks) focus block\(completedBlocks == 1 ? "" : "s") completed")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Button(action: onContinue) {
                    Label("Continue Session", systemImage: "rectangle.and.pencil.and.ellipsis")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var completedBlocks: Int {
        blocks.filter { $0.status == .completed }.count
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
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.18), lineWidth: isSelected ? 1.5 : 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var durationText: String? {
        guard let endedAt = session.endedAt else {
            return nil
        }
        return DurationFormatter.shortString(from: Int(endedAt.timeIntervalSince(session.startedAt)))
    }
}

struct DashboardSurface<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.16))
            }
            .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
    }
}

enum DurationFormatter {
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
