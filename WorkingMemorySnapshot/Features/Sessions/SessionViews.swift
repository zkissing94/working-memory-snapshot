import SwiftUI

struct StartSessionView: View {
    let project: Project
    @ObservedObject var viewModel: SessionViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Header(project: project)

            VStack(alignment: .leading, spacing: 8) {
                Text("Start New Session")
                    .font(.largeTitle)
                    .fontWeight(.semibold)
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

            DashboardSurface {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "timer")
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Block 1 will start automatically")
                            .font(.headline)
                        Text("20 min focus capture. Observing after start: Git, files, and active apps.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
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
    @State private var blockSummary = ""
    @State private var isShowingBlockCompletionInput = false
    @State private var nextBlockIntention = ""
    @State private var incrementKind: WorkIncrementKind = .note
    @State private var incrementTitle = ""
    @State private var incrementDetail = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                pomodoroBlockCard
                if viewModel.activeBlock?.status != .active && viewModel.activeBlock?.status != .paused {
                    workIncrementsSection
                }
                if viewModel.activeBlock?.status != .paused {
                    sessionInspectorDisclosure
                    sessionControls
                }
            }
            .padding(28)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: viewModel.activeBlock?.id) { _, _ in
            resetBlockCompletionInput()
        }
        .onChange(of: viewModel.activeBlock?.status) { _, status in
            if status != .active {
                resetBlockCompletionInput()
            }
        }
    }

    private var pomodoroBlockCard: some View {
        DashboardSurface {
            if let activeBlock = viewModel.activeBlock {
                activeBlockContent(activeBlock)
            } else {
                betweenBlocksContent
            }
        }
    }

    @ViewBuilder
    private func activeBlockContent(_ block: PomodoroBlock) -> some View {
        if block.status == .paused {
            pausedBlockContent(block)
        } else {
            activeFocusBlockContent(block)
        }
    }

    private func activeFocusBlockContent(_ block: PomodoroBlock) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 8) {
                        Text("Focus Block \(block.blockIndex)")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        Text("Focus Time")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.green)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(Color.green.opacity(0.12))
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

            HStack(alignment: .center, spacing: 12) {
                HStack(spacing: 8) {
                    Text("\(DurationFormatter.shortString(from: block.elapsedSeconds())) elapsed")
                    Text("·")
                    Text("\(DurationFormatter.shortString(from: block.plannedDurationSeconds)) total")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Spacer()

                HStack(spacing: 8) {
                    Button {
                        isShowingBlockCompletionInput = true
                    } label: {
                        Label("Complete Block", systemImage: "checkmark.circle")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isWorking || isShowingBlockCompletionInput)
                    .help("Complete Block")
                    .accessibilityLabel("Complete Block")

                    Button {
                        Task {
                            await viewModel.pauseCurrentBlock()
                        }
                    } label: {
                        Label("Pause", systemImage: "pause.fill")
                            .labelStyle(.iconOnly)
                    }
                    .disabled(viewModel.isWorking)
                    .help("Pause")
                    .accessibilityLabel("Pause")

                    Button {
                        let summary = isShowingBlockCompletionInput ? blockSummary : ""
                        Task {
                            await viewModel.completeCurrentBlock(summary: summary)
                            resetBlockCompletionInput()
                        }
                    } label: {
                        Label("Take Break", systemImage: "cup.and.saucer")
                            .labelStyle(.iconOnly)
                    }
                    .disabled(viewModel.isWorking)
                    .help("Take Break")
                    .accessibilityLabel("Take Break")
                }
            }

            if isShowingBlockCompletionInput {
                blockCompletionInput
            }

            Divider()

            workIncrementsContent
        }
    }

    private var blockCompletionInput: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Complete Block")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            TextField("What changed during this block?", text: $blockSummary, axis: .vertical)
                .lineLimit(2, reservesSpace: true)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 10) {
                Button("Cancel") {
                    resetBlockCompletionInput()
                }
                .disabled(viewModel.isWorking)

                Button {
                    let summary = blockSummary
                    Task {
                        await viewModel.completeCurrentBlock(summary: summary)
                        resetBlockCompletionInput()
                    }
                } label: {
                    Label("Save and Complete", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isWorking)
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

    private func pausedBlockContent(_ block: PomodoroBlock) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                Label("Paused checkpoint", systemImage: "pause.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                    .textCase(.uppercase)

                Spacer()

                HStack(spacing: 8) {
                    Button {
                        Task {
                            await viewModel.resumeCurrentBlock()
                        }
                    } label: {
                        Label("Resume", systemImage: "play.fill")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isWorking)
                    .help("Resume")
                    .accessibilityLabel("Resume")

                    Button {
                        Task {
                            await viewModel.completeCurrentBlock()
                        }
                    } label: {
                        Label("Complete Block", systemImage: "checkmark.circle")
                            .labelStyle(.iconOnly)
                    }
                    .foregroundStyle(.green)
                    .disabled(viewModel.isWorking)
                    .help("Complete Block")
                    .accessibilityLabel("Complete Block")

                    Button(role: .destructive) {
                        viewModel.beginEndingActiveSession()
                    } label: {
                        Label("End Session", systemImage: "xmark")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                    .disabled(viewModel.isWorking)
                    .help("End Session")
                    .accessibilityLabel("End Session")
                    .accessibilityHint("Open the brain dump form and prepare to generate a snapshot.")
                }
            }

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Focus Block \(block.blockIndex)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    Text(block.intention ?? session.mission)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .lineLimit(3)
                        .textSelection(.enabled)

                    Text("Ready whenever you are.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                TimelineView(.periodic(from: block.pausedAt ?? block.startedAt, by: 1)) { context in
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Time remaining")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(DurationFormatter.timerString(from: block.remainingSeconds(at: context.date)))
                            .font(.system(.title, design: .monospaced))
                            .monospacedDigit()
                        Text("of \(DurationFormatter.timerString(from: block.plannedDurationSeconds))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            TimelineView(.periodic(from: block.startedAt, by: 1)) { context in
                ProgressView(value: progress(for: block, at: context.date))
                    .tint(.orange)
            }

            Text("Paused time is tracked separately from elapsed focus time.")
                .font(.caption)
                .foregroundStyle(.secondary)

            pausedResumeContext
        }
    }

    private var betweenBlocksContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Between Blocks")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text("The session is still active. Start another 20-minute block when you are ready.")
                .font(.body)

            TextField("Next block intention", text: $nextBlockIntention, axis: .vertical)
                .lineLimit(2, reservesSpace: true)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 12) {
                Button {
                    let intention = nextBlockIntention
                    Task {
                        await viewModel.startNextBlock(intention: intention)
                        nextBlockIntention = ""
                    }
                } label: {
                    Label("Start Next Block", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isWorking)

                Button {
                    viewModel.beginEndingActiveSession()
                } label: {
                    Label("End Session", systemImage: "stop")
                }
            }
        }
    }

    private var workIncrementsSection: some View {
        DashboardSurface {
            workIncrementsContent
        }
    }

    private var workIncrementsContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Work Increments")
                .font(.headline)

            if viewModel.activeBlock == nil {
                Text("Start a focus block to capture notes, decisions, or blockers.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if viewModel.activeBlockIncrements.isEmpty {
                Text("No manual increments yet.")
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

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Picker("Kind", selection: $incrementKind) {
                    ForEach(WorkIncrementKind.allCases, id: \.self) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .pickerStyle(.segmented)

                TextField("Add a note, decision, or blocker", text: $incrementTitle)
                    .textFieldStyle(.roundedBorder)
                TextField("Detail (optional)", text: $incrementDetail, axis: .vertical)
                    .lineLimit(2, reservesSpace: true)
                    .textFieldStyle(.roundedBorder)

                Button {
                    let kind = incrementKind
                    let title = incrementTitle
                    let detail = incrementDetail
                    Task {
                        await viewModel.addIncrement(kind: kind, title: title, detail: detail)
                        if viewModel.errorMessage == nil {
                            incrementTitle = ""
                            incrementDetail = ""
                            incrementKind = .note
                        }
                    }
                } label: {
                    Label("Add Increment", systemImage: "plus")
                }
                .disabled(viewModel.activeBlock == nil || viewModel.isWorking)
            }
        }
    }

    private var pausedResumeContext: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()

            Text("Resume Context")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            if let lastIncrement = viewModel.activeBlockIncrements.last {
                VStack(alignment: .leading, spacing: 3) {
                    Text(lastIncrement.title)
                        .font(.callout.weight(.semibold))
                    HStack(spacing: 6) {
                        Text(lastIncrement.kind.displayName)
                        Text("·")
                        Text(lastIncrement.occurredAt.formatted(date: .omitted, time: .shortened))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            } else {
                Text("No manual increments captured yet. Resume from the block objective above.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var sessionControls: some View {
        HStack(spacing: 12) {
            if viewModel.activeBlock?.status != .paused {
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
    }

    private var sessionInspectorDisclosure: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 12) {
                inspectorSection(title: "State Contract", text: inspectorStateContract)
                inspectorSection(title: "Observed Context", text: viewModel.observationSummary.displayText)
                inspectorSection(
                    title: "Services",
                    text: "FSEvents, Git, and active app observation stay scoped to this active session."
                )
                inspectorSection(
                    title: "Privacy",
                    text: "No screenshots, clipboard, browser history, messages, keystrokes, or file contents."
                )

                if !viewModel.sessionBlocks.isEmpty {
                    Divider()
                    Text("Focus Blocks")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                        ForEach(viewModel.sessionBlocks) { block in
                            BlockChip(block: block)
                        }
                    }
                }
            }
            .padding(.top, 10)
        } label: {
            Label("Open Inspector", systemImage: "sidebar.right")
                .font(.callout.weight(.semibold))
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

    private func inspectorSection(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private var inspectorStateContract: String {
        guard let activeBlock = viewModel.activeBlock else {
            return "The session is active and currently between focus blocks."
        }

        return "activeSession.projectID matches the selected project and activeBlock.status is \(activeBlock.status.rawValue)."
    }

    private func progress(for block: PomodoroBlock, at date: Date) -> Double {
        min(1, Double(block.elapsedSeconds(at: date)) / Double(max(1, block.plannedDurationSeconds)))
    }

    private func resetBlockCompletionInput() {
        blockSummary = ""
        isShowingBlockCompletionInput = false
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

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 14)], spacing: 14) {
                endSessionStatCard("Block capture points") {
                    HStack(spacing: 8) {
                        MetricPill(title: "Blocks", value: "\(viewModel.sessionBlocks.count)")
                        MetricPill(title: "Completed", value: "\(completedBlockCount)")
                    }
                    Text("Block summaries and manual increments are included below the brain dump in the prompt digest.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                endSessionStatCard("Observed context") {
                    Text(viewModel.observationSummary.displayText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(6)
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

    private var completedBlockCount: Int {
        viewModel.sessionBlocks.filter { $0.status == .completed }.count
    }

    @ViewBuilder
    private func endSessionStatCard<T: View>(
        _ title: String,
        @ViewBuilder content: () -> T
    ) -> some View {
        DashboardSurface {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                content()
            }
            .frame(maxWidth: .infinity, minHeight: 124, alignment: .topLeading)
        }
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
                Text("Focus Block Timeline")
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
            Text(block.intention ?? "Block \(block.blockIndex)")
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
            ProjectRootPathLink(path: project.rootPath)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)
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
