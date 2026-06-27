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
                .accessibilityLabel("Start Session")
                .accessibilityHint("Start observing this project for the current mission.")

                Button("Cancel") {
                    viewModel.dismissStartSession()
                }
                .disabled(viewModel.isWorking)
                .accessibilityHint("Return to the project without starting a session.")
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
    @State private var focusBlockSummary = ""
    @State private var nextFocusBlockIntention = ""
    @State private var captureKind: WorkIncrementKind = .note
    @State private var captureText = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                activeSessionHeader
                missionCard
                captureCard
                detailDisclosures
                cancelSessionButton
            }
            .padding(28)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var activeSessionHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Active Session")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Started \(session.startedAt.formatted(date: .omitted, time: .shortened)) · observation running locally")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Spacer()

            TimelineView(.periodic(from: session.startedAt, by: 1)) { context in
                Text("\(elapsedString(from: session.startedAt, to: context.date)) elapsed")
                    .font(.system(.callout, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.16))
                    }
            }
        }
    }

    private var missionCard: some View {
        DashboardSurface {
            VStack(alignment: .leading, spacing: 9) {
                Text("Mission")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(session.mission)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .lineLimit(5)
                    .textSelection(.enabled)
            }
        }
    }

    private var captureCard: some View {
        DashboardSurface {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Capture what matters")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        Text(capturePrompt)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    Picker("Capture kind", selection: $captureKind) {
                        ForEach(WorkIncrementKind.allCases, id: \.self) { kind in
                            Text(kind.displayName).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 320)
                }

                TextField("Decision, blocker, surprise, or next step", text: $captureText, axis: .vertical)
                    .lineLimit(4, reservesSpace: true)
                    .textFieldStyle(.roundedBorder)
                    .disabled(viewModel.activeBlock == nil || viewModel.isWorking)

                HStack(alignment: .center) {
                    Text(captureCountText)
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        let kind = captureKind
                        let text = captureText
                        Task {
                            await viewModel.addCapture(kind: kind, text: text)
                            if viewModel.errorMessage == nil {
                                captureText = ""
                                captureKind = .note
                            }
                        }
                    } label: {
                        Label("Save Capture", systemImage: "plus")
                    }
                    .disabled(viewModel.activeBlock == nil || viewModel.isWorking)

                    Button {
                        viewModel.beginEndingActiveSession()
                    } label: {
                        Label("End Session", systemImage: "stop")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isWorking)
                    .accessibilityLabel("End Session")
                    .accessibilityHint("Open the brain dump form and prepare to generate a snapshot.")
                }
            }
        }
    }

    private var capturePrompt: String {
        if viewModel.activeBlock == nil {
            return "Start a focus block to save notes, decisions, or blockers."
        }
        return "Short notes here feed the final snapshot."
    }

    private var captureCountText: String {
        let count = viewModel.activeBlockIncrements.count
        if count == 0 {
            return "No captures saved in the current focus block."
        }
        return "\(count) capture\(count == 1 ? "" : "s") saved in the current focus block."
    }

    private var detailDisclosures: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 12)], spacing: 12) {
            focusBlockDisclosure
            observedContextDisclosure
            capturesDisclosure
        }
    }

    private var focusBlockDisclosure: some View {
        DashboardSurface {
            DisclosureGroup {
                Divider()
                    .padding(.vertical, 8)
                if let activeBlock = viewModel.activeBlock {
                    activeBlockContent(activeBlock)
                } else {
                    betweenFocusBlocksContent
                }
            } label: {
                Label("Focus block", systemImage: "timer")
                    .font(.headline)
            }
        }
    }

    private func activeBlockContent(_ block: PomodoroBlock) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 8) {
                        Text("Focus block \(block.blockIndex)")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        Text(block.status == .paused ? "Paused" : "Focus time")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(block.status == .paused ? .orange : .green)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill((block.status == .paused ? Color.orange : Color.green).opacity(0.12))
                            )
                    }

                    Text(block.intention ?? session.mission)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .lineLimit(3)
                        .textSelection(.enabled)
                }

                Spacer()

                TimelineView(.periodic(from: block.startedAt, by: 1)) { context in
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(DurationFormatter.timerString(from: block.remainingSeconds(at: context.date)))
                            .font(.system(.title, design: .monospaced))
                            .monospacedDigit()
                        Text("remaining")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            TimelineView(.periodic(from: block.startedAt, by: 1)) { context in
                ProgressView(value: progress(for: block, at: context.date))
                    .tint(.green)
            }

            HStack(spacing: 8) {
                Text("\(DurationFormatter.shortString(from: block.elapsedSeconds())) elapsed")
                Text("·")
                Text("\(DurationFormatter.shortString(from: block.plannedDurationSeconds)) total")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("Focus block summary")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("What changed during this focus block?", text: $focusBlockSummary, axis: .vertical)
                    .lineLimit(2, reservesSpace: true)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 12) {
                Button {
                    Task {
                        if block.status == .paused {
                            await viewModel.resumeCurrentBlock()
                        } else {
                            await viewModel.pauseCurrentBlock()
                        }
                    }
                } label: {
                    Label(block.status == .paused ? "Resume" : "Pause", systemImage: block.status == .paused ? "play.fill" : "pause.fill")
                }
                .disabled(viewModel.isWorking)

                Button {
                    let summary = focusBlockSummary
                    Task {
                        await viewModel.completeCurrentBlock(summary: summary)
                        focusBlockSummary = ""
                    }
                } label: {
                    Label("Complete Focus Block", systemImage: "checkmark.circle")
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isWorking)

                Button {
                    let summary = focusBlockSummary
                    Task {
                        await viewModel.completeCurrentBlock(summary: summary)
                        focusBlockSummary = ""
                    }
                } label: {
                    Label("Take Break", systemImage: "cup.and.saucer")
                }
                .disabled(viewModel.isWorking)
            }
        }
    }

    private var betweenFocusBlocksContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Between focus blocks")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text("The session is still active. Start another 20-minute focus block when you are ready.")
                .font(.body)

            TextField("Next focus block intention", text: $nextFocusBlockIntention, axis: .vertical)
                .lineLimit(2, reservesSpace: true)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 12) {
                Button {
                    let intention = nextFocusBlockIntention
                    Task {
                        await viewModel.startNextBlock(intention: intention)
                        nextFocusBlockIntention = ""
                    }
                } label: {
                    Label("Start Focus Block", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isWorking)
            }
        }
    }

    private var observedContextDisclosure: some View {
        DashboardSurface {
            DisclosureGroup {
                Divider()
                    .padding(.vertical, 8)
                Text(viewModel.observationSummary.displayText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            } label: {
                Label("Observed context", systemImage: "macwindow")
                    .font(.headline)
            }
        }
    }

    private var capturesDisclosure: some View {
        DashboardSurface {
            DisclosureGroup {
                Divider()
                    .padding(.vertical, 8)

                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Current focus block captures")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        if viewModel.activeBlockIncrements.isEmpty {
                            Text("No captures saved in the current focus block.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(viewModel.activeBlockIncrements) { increment in
                                    IncrementRow(increment: increment)
                                    if increment.id != viewModel.activeBlockIncrements.last?.id {
                                        Divider()
                                    }
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Focus blocks in this session")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        if viewModel.sessionBlocks.isEmpty {
                            Text("No focus blocks recorded yet.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        } else {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                                ForEach(viewModel.sessionBlocks) { block in
                                    BlockChip(block: block)
                                }
                            }
                        }
                    }
                }
            } label: {
                Label("Captures", systemImage: "tray.full")
                    .font(.headline)
            }
        }
    }

    private var cancelSessionButton: some View {
        Button(role: .destructive) {
            Task {
                await viewModel.cancelActiveSession()
            }
        } label: {
            Label("Cancel Session", systemImage: "xmark.circle")
        }
        .disabled(viewModel.isWorking)
        .accessibilityHint("Cancel this session without generating a snapshot.")
    }

    private func progress(for block: PomodoroBlock, at date: Date) -> Double {
        min(1, Double(block.elapsedSeconds(at: date)) / Double(max(1, block.plannedDurationSeconds)))
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
                .accessibilityLabel("Generate Working Memory Snapshot")
                .accessibilityHint("Save the brain dump, complete the session, and generate a local snapshot.")

                Button("Return to Session") {
                    viewModel.returnToActiveSession()
                }
                .disabled(viewModel.isWorking)
                .accessibilityHint("Go back to the active session without ending it.")
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
    let onRestoreAccess: () -> Void

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
            .accessibilityElement(children: .combine)

            if !context.isProjectFolderAccessible {
                VStack(alignment: .leading, spacing: 8) {
                    Label(
                        "This project folder is no longer accessible.",
                        systemImage: "folder.badge.questionmark"
                    )
                    .font(.headline)

                    Text("Choose the folder again before resuming observation.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }

            HStack(spacing: 12) {
                Button("Resume Session", action: onResume)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!context.isProjectFolderAccessible)
                    .accessibilityHint("Resume the interrupted active session.")
                Button("End Session", action: onEnd)
                    .accessibilityHint("End the interrupted session and write the brain dump.")
                if !context.isProjectFolderAccessible {
                    Button("Choose Folder Again", action: onRestoreAccess)
                        .accessibilityHint("Restore access to the selected project folder.")
                }
                Button("Cancel Session", role: .destructive, action: onCancel)
                    .accessibilityHint("Cancel the interrupted session.")
            }
        }
        .padding(28)
        .frame(minWidth: 460, alignment: .leading)
    }
}

struct HistoricalSessionDetailView: View {
    let project: Project
    let session: WorkSession
    let snapshot: Snapshot?
    let blocks: [PomodoroBlock]
    let incrementsForBlock: (PomodoroBlock) -> [WorkIncrement]
    let events: [SessionEvent]
    let onBackToProject: () -> Void
    let onViewSnapshot: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Session Detail")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text(project.name)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    Spacer()
                    Button(action: onBackToProject) {
                        Label("Back", systemImage: "chevron.left")
                    }
                }

                DashboardSurface {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Session Summary")
                            .font(.headline)
                        Text(session.mission)
                            .font(.title3)
                            .fontWeight(.semibold)
                            .textSelection(.enabled)
                        HStack(spacing: 8) {
                            Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                            if let endedAt = session.endedAt {
                                Text("·")
                                Text(DurationFormatter.shortString(from: Int(endedAt.timeIntervalSince(session.startedAt))))
                            }
                            Text("·")
                            Text(session.status.rawValue.capitalized)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                snapshotSection
                blocksSection
                observedContextSection
            }
            .padding(28)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var snapshotSection: some View {
        DashboardSurface {
            VStack(alignment: .leading, spacing: 12) {
                Text("Working Memory Snapshot")
                    .font(.headline)
                if let snapshot {
                    Text(snapshot.resumeBrief)
                        .font(.body)
                        .textSelection(.enabled)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Next action")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(snapshot.nextAction)
                            .font(.headline)
                            .textSelection(.enabled)
                    }
                    Button(action: onViewSnapshot) {
                        Label("View Full Snapshot", systemImage: "doc.text.magnifyingglass")
                    }
                } else if session.status == .cancelled {
                    Text("Cancelled sessions do not generate snapshots.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No snapshot is saved for this session yet.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var blocksSection: some View {
        DashboardSurface {
            VStack(alignment: .leading, spacing: 12) {
                Text("Focus Blocks")
                    .font(.headline)
                if blocks.isEmpty {
                    Text("No focus blocks were recorded for this session.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 12) {
                        ForEach(blocks) { block in
                            HistoricalBlockRow(
                                block: block,
                                increments: incrementsForBlock(block)
                            )
                        }
                    }
                }
            }
        }
    }

    private var observedContextSection: some View {
        DashboardSurface {
            VStack(alignment: .leading, spacing: 12) {
                Text("Observed Context")
                    .font(.headline)
                ObservedContextFact(
                    title: "Git Repository",
                    value: gitSummary,
                    systemImage: "point.3.connected.trianglepath.dotted"
                )
                ObservedContextFact(
                    title: "Files Touched",
                    value: "\(changedFiles.count) file\(changedFiles.count == 1 ? "" : "s")",
                    systemImage: "doc.on.doc"
                )
                ObservedContextFact(
                    title: "Apps Observed",
                    value: activeApps.isEmpty ? "None observed" : activeApps.prefix(4).joined(separator: ", "),
                    systemImage: "macwindow"
                )
            }
        }
    }

    private var changedFiles: [String] {
        events
            .filter { $0.source == .file && $0.kind == SessionEventKind.fileChanged }
            .map(\.title)
            .orderedUnique()
    }

    private var activeApps: [String] {
        events
            .filter { $0.source == .activeApp && $0.kind == SessionEventKind.appActivated }
            .map(\.title)
            .orderedUnique()
    }

    private var gitSummary: String {
        let gitEvents = events.filter { $0.source == .git }
        if gitEvents.isEmpty {
            return "No Git evidence"
        }
        if gitEvents.contains(where: { $0.title.localizedCaseInsensitiveContains("not a git") }) {
            return "Not a Git repository"
        }
        return "\(gitEvents.count) event\(gitEvents.count == 1 ? "" : "s")"
    }
}

private struct HistoricalBlockRow: View {
    let block: PomodoroBlock
    let increments: [WorkIncrement]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                BlockStatusBadge(block: block)
                Spacer()
                Text(DurationFormatter.shortString(from: block.elapsedSeconds(at: block.endedAt ?? Date())))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let intention = block.intention {
                Text(intention)
                    .font(.callout)
                    .fontWeight(.semibold)
                    .textSelection(.enabled)
            }

            if let summary = block.summary {
                Text(summary)
                    .font(.callout)
                    .textSelection(.enabled)
            }

            if increments.isEmpty {
                Text("No manual increments.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(increments) { increment in
                        IncrementRow(increment: increment)
                        if increment.id != increments.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.16))
        }
    }
}

private struct ObservedContextFact: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout)
                    .fontWeight(.semibold)
                Text(value)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }
}

private struct IncrementRow: View {
    let increment: WorkIncrement

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(increment.occurredAt.formatted(date: .omitted, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 54, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(increment.title)
                        .font(.callout)
                    Text(increment.kind.displayName)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(kindColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(kindColor.opacity(0.12)))
                }
                if let detail = increment.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 8)
    }

    private var kindColor: Color {
        switch increment.kind {
        case .note:
            .blue
        case .decision:
            .green
        case .blocker:
            .orange
        }
    }
}

private struct BlockChip: View {
    let block: PomodoroBlock

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            BlockStatusBadge(block: block)
            Text(block.intention ?? "Focus block \(block.blockIndex)")
                .font(.callout)
                .fontWeight(.semibold)
                .lineLimit(2)
            Text(block.status == .active || block.status == .paused
                 ? "\(DurationFormatter.timerString(from: block.remainingSeconds())) left"
                 : DurationFormatter.shortString(from: block.elapsedSeconds(at: block.endedAt ?? Date())))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(statusColor.opacity(0.55), lineWidth: block.status == .active ? 1.5 : 1)
        }
    }

    private var statusColor: Color {
        switch block.status {
        case .active:
            .accentColor
        case .paused:
            .orange
        case .completed:
            .green
        case .interrupted:
            .secondary
        }
    }
}

private struct BlockStatusBadge: View {
    let block: PomodoroBlock

    var body: some View {
        HStack(spacing: 6) {
            Text("\(block.blockIndex)")
                .font(.callout)
                .fontWeight(.semibold)
            Text(block.status.rawValue.capitalized)
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(color)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(color.opacity(0.12)))
        }
    }

    private var color: Color {
        switch block.status {
        case .active:
            .accentColor
        case .paused:
            .orange
        case .completed:
            .green
        case .interrupted:
            .secondary
        }
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

private extension Array where Element == String {
    func orderedUnique() -> [String] {
        var seen = Set<String>()
        var values: [String] = []
        for value in self where !seen.contains(value) {
            seen.insert(value)
            values.append(value)
        }
        return values
    }
}
