import AppKit
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

            DashboardSurface(style: .soft) {
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
        .padding(AppVisualTokens.Spacing.workspaceWide)
        .frame(maxWidth: AppVisualTokens.Layout.compactWorkspaceWidth, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct FocusBlockCompletionSheet: View {
    let prompt: FocusBlockCompletionPrompt
    let isWorking: Bool
    let onReturn: () -> Void
    let onComplete: (String) -> Void

    @State private var summary = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.green)
                    .frame(width: 36)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Focus Block \(prompt.block.blockIndex) complete")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("The session is still active. Capture what changed before starting another block.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Intention")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(prompt.intention)
                    .font(.body)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("What changed during this block?")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                TextField("Notification and in-app prompt wired...", text: $summary, axis: .vertical)
                    .lineLimit(4, reservesSpace: true)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 12) {
                Spacer()

                Button("Return to Block") {
                    onReturn()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(isWorking)

                Button {
                    onComplete(summary)
                } label: {
                    Label("Save and Complete Block", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(isWorking)
            }
        }
        .padding(24)
        .frame(width: 480)
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
    @State private var isWorkIncrementsExpanded = true
    @State private var completionHaloTrigger = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            AppWorkspace {
                VStack(alignment: .leading, spacing: 20) {
                    pomodoroBlockCard
                    if let activeBlock = viewModel.activeBlock, activeBlock.status != .active && activeBlock.status != .paused {
                        workIncrementsSection
                    }
                    if viewModel.activeBlock?.status != .paused {
                        sessionInspectorDisclosure
                    }
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: viewModel.activeBlock?.id) { _, _ in
            resetBlockCompletionInput()
        }
        .onChange(of: viewModel.activeBlock?.id) { oldBlockID, newBlockID in
            if oldBlockID != nil && newBlockID == nil {
                completionHaloTrigger += 1
            }
        }
        .onChange(of: viewModel.activeBlock?.status) { _, status in
            if status != .active {
                resetBlockCompletionInput()
            }
        }
    }

    private var pomodoroBlockCard: some View {
        DashboardSurface(style: blockSurfaceStyle) {
            Group {
                if let activeBlock = viewModel.activeBlock {
                    activeBlockContent(activeBlock)
                } else {
                    betweenBlocksContent
                }
            }
            .id(blockPresentationIdentity)
            .transition(AppMotion.stateTransition(reduceMotion: reduceMotion))
        }
        .animation(
            AppMotion.animation(.standard, reduceMotion: reduceMotion),
            value: blockPresentationIdentity
        )
    }

    private var blockSurfaceStyle: AppSurfaceStyle {
        switch viewModel.activeBlock?.status {
        case .active:
            .emphasized
        case .paused:
            .status(.warning)
        case .completed, .interrupted:
            .soft
        case nil:
            .status(.success)
        }
    }

    private var blockPresentationIdentity: String {
        guard let block = viewModel.activeBlock else {
            return "between-blocks"
        }
        return "\(block.id.uuidString)-\(block.status.rawValue)"
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
                        AppStatusPill("Focus Time", systemImage: "timer", tone: .success)
                    }

                    Text(block.intention ?? session.mission)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .lineLimit(3)
                        .textSelection(.enabled)
                }

                Spacer()

                TimelineView(.periodic(from: block.startedAt, by: 1)) { context in
                    let remainingSeconds = block.remainingSeconds(at: context.date)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(DurationFormatter.timerString(from: remainingSeconds))
                            .font(.system(.title, design: .monospaced))
                            .monospacedDigit()
                            .contentTransition(.numericText(countsDown: true))
                            .animation(
                                AppMotion.animation(.quick, reduceMotion: reduceMotion),
                                value: remainingSeconds
                            )
                        Text("remaining")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            TimelineView(.periodic(from: block.startedAt, by: 1)) { context in
                let blockProgress = progress(for: block, at: context.date)
                ProgressView(value: blockProgress)
                    .tint(.green)
                    .animation(
                        reduceMotion ? .linear(duration: AppMotion.reducedDuration) : .linear(duration: 0.16),
                        value: blockProgress
                    )
            }

            if isShowingBlockCompletionInput {
                blockCompletionInput
                    .transition(AppMotion.stateTransition(reduceMotion: reduceMotion))
            }

            Divider()
            workIncrementsContent()
        }
        .animation(
            AppMotion.animation(.standard, reduceMotion: reduceMotion),
            value: isShowingBlockCompletionInput
        )
    }

    private var blockCompletionInput: some View {
        AppSurface(style: .soft) {
            VStack(alignment: .leading, spacing: 10) {
                AppSectionLabel("Complete Block")

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
        }
    }

    private func pausedBlockContent(_ block: PomodoroBlock) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                AppStatusPill("Paused checkpoint", systemImage: "pause.circle", tone: .warning)
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
                    let remainingSeconds = block.remainingSeconds(at: context.date)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Time remaining")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(DurationFormatter.timerString(from: remainingSeconds))
                            .font(.system(.title, design: .monospaced))
                            .monospacedDigit()
                            .contentTransition(.numericText(countsDown: true))
                            .animation(
                                AppMotion.animation(.quick, reduceMotion: reduceMotion),
                                value: remainingSeconds
                            )
                        Text("of \(DurationFormatter.timerString(from: block.plannedDurationSeconds))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            TimelineView(.periodic(from: block.startedAt, by: 1)) { context in
                let blockProgress = progress(for: block, at: context.date)
                ProgressView(value: blockProgress)
                    .tint(.orange)
                    .animation(
                        reduceMotion ? .linear(duration: AppMotion.reducedDuration) : .linear(duration: 0.16),
                        value: blockProgress
                    )
            }

            Text("Paused time is tracked separately from elapsed focus time.")
                .font(.caption)
                .foregroundStyle(.secondary)

            pausedResumeContext
        }
    }

    private var pausedBlockActionButtons: some View {
        HStack(spacing: 8) {
            Button {
                Task {
                    await viewModel.resumeCurrentBlock()
                }
            } label: {
                Label("Resume Focus Block", systemImage: "play.fill")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(AppIconButtonStyle(tone: .accent))
            .disabled(viewModel.isWorking)
            .appTooltip("Resume Focus Block")
            .accessibilityLabel("Resume Focus Block")

            Button {
                Task {
                    await viewModel.completeCurrentBlock()
                }
            } label: {
                Label("Complete Focus Block", systemImage: "checkmark")
                    .labelStyle(.iconOnly)
                    .font(.title3)
            }
            .buttonStyle(AppIconButtonStyle(tone: .success))
            .disabled(viewModel.isWorking)
            .appTooltip("Complete Focus Block")
            .accessibilityLabel("Complete Focus Block")

            Button(role: .destructive) {
                viewModel.beginEndingActiveSession()
            } label: {
                Label("Complete Session", systemImage: "xmark")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(AppIconButtonStyle(tone: .error))
            .disabled(viewModel.isWorking)
            .appTooltip("Complete Session")
            .accessibilityLabel("Complete Session")
            .accessibilityHint("Open the brain dump form and prepare to generate a snapshot.")
        }
    }

    private var betweenBlocksContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                AppCompletionHalo(trigger: completionHaloTrigger)
                AppSectionLabel("Between Blocks")
            }
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
            workIncrementsContent()
        }
    }

    private func workIncrementsContent() -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if viewModel.activeBlock == nil {
                Text("Start a focus block to capture notes, decisions, or blockers.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if viewModel.activeBlockIncrements.isEmpty {
                Text("No manual increments yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                DisclosureGroup(isExpanded: $isWorkIncrementsExpanded) {
                    VStack(spacing: 0) {
                        ForEach(viewModel.activeBlockIncrements) { increment in
                            IncrementRow(increment: increment)
                                .transition(AppMotion.insertionTransition(reduceMotion: reduceMotion))
                            if increment.id != viewModel.activeBlockIncrements.last?.id {
                                Divider()
                            }
                        }
                    }
                } label: {
                    Text("Work Increments")
                        .font(.headline)
                }
                .animation(
                    AppMotion.animation(.standard, reduceMotion: reduceMotion),
                    value: viewModel.activeBlockIncrements.map(\.id)
                )
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Picker("", selection: $incrementKind) {
                    ForEach(WorkIncrementKind.allCases, id: \.self) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                TextField("Add a title", text: $incrementTitle)
                    .textFieldStyle(.roundedBorder)
                RichTextField(
                    "Detail (optional)",
                    text: $incrementDetail
                )

                HStack(alignment: .center) {
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

                    Spacer()

                    Button {
                        isShowingBlockCompletionInput = true
                    } label: {
                        Label("Complete Block", systemImage: "checkmark")
                            .labelStyle(.iconOnly)
                            .font(.title3)
                    }
                    .buttonStyle(AppIconButtonStyle(tone: .success))
                    .disabled(viewModel.activeBlock == nil || viewModel.isWorking || isShowingBlockCompletionInput)
                    .appTooltip("Complete Focus Block")
                    .accessibilityLabel("Complete Focus Block")

                    Button {
                        Task {
                            await viewModel.pauseCurrentBlock()
                        }
                    } label: {
                        Label("Pause", systemImage: "pause.fill")
                            .labelStyle(.iconOnly)
                            .font(.title3)
                    }
                    .buttonStyle(AppIconButtonStyle(tone: .warning))
                    .disabled(viewModel.activeBlock == nil || viewModel.isWorking)
                    .appTooltip("Pause Block")
                    .accessibilityLabel("Pause Block")

                    Button(role: .destructive) {
                        viewModel.beginEndingActiveSession()
                    } label: {
                        Label("End Session", systemImage: "xmark")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(AppIconButtonStyle(tone: .error))
                    .disabled(viewModel.activeBlock == nil || viewModel.isWorking)
                    .appTooltip("Complete Session")
                    .accessibilityLabel("Complete Session")
                    .accessibilityHint("Open the brain dump form and prepare to generate a snapshot.")
                }
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

            HStack(alignment: .center, spacing: 12) {
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
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("No manual increments captured yet. Resume from the block objective above.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                pausedBlockActionButtons
            }
        }
    }
    private var sessionInspectorDisclosure: some View {
        DashboardSurface(style: .soft) {
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
                        AppSectionLabel("Focus Blocks")
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

private struct RichTextField: View {
    let placeholder: String
    @Binding var text: String
    @StateObject private var formatter = RichTextFieldFormatter()

    init(_ placeholder: String, text: Binding<String>) {
        self.placeholder = placeholder
        self._text = text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(placeholder)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer()

                HStack(spacing: 8) {
                    Button {
                        formatter.toggleBold()
                    } label: {
                        Image(systemName: "bold")
                    }
                    .buttonStyle(RichTextFormattingButtonStyle(isActive: formatter.isBoldActive))
                    .help(formatter.isBoldActive ? "Turn off bold" : "Turn on bold")
                    .accessibilityLabel("Bold")
                    .accessibilityValue(formatter.isBoldActive ? "On" : "Off")

                    Button {
                        formatter.toggleItalic()
                    } label: {
                        Image(systemName: "italic")
                    }
                    .buttonStyle(RichTextFormattingButtonStyle(isActive: formatter.isItalicActive))
                    .help(formatter.isItalicActive ? "Turn off italic" : "Turn on italic")
                    .accessibilityLabel("Italic")
                    .accessibilityValue(formatter.isItalicActive ? "On" : "Off")

                    Button {
                        formatter.toggleBullet()
                    } label: {
                        Image(systemName: "list.bullet")
                    }
                    .buttonStyle(RichTextFormattingButtonStyle(isActive: formatter.isBulletActive))
                    .help(formatter.isBulletActive ? "Turn off bullets" : "Turn on bullets")
                    .accessibilityLabel("Bullets")
                    .accessibilityValue(formatter.isBulletActive ? "On" : "Off")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            Divider()
                .padding(.horizontal, 8)
                .foregroundStyle(.secondary.opacity(0.16))

            RichTextFieldRepresentable(text: $text, formatter: formatter)
                .frame(minHeight: 76)
                .font(.body)
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
        }
        .overlay {
            RoundedRectangle(cornerRadius: AppVisualTokens.Radius.standard, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.56))
        }
    }
}

private struct RichTextFormattingButtonStyle: ButtonStyle {
    let isActive: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(
                minWidth: AppVisualTokens.Layout.minimumIconTarget,
                minHeight: AppVisualTokens.Layout.minimumIconTarget
            )
            .foregroundStyle(isActive ? Color.white : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: AppVisualTokens.Radius.standard, style: .continuous)
                    .fill(backgroundFill(isPressed: configuration.isPressed))
            )
            .overlay {
                RoundedRectangle(cornerRadius: AppVisualTokens.Radius.standard, style: .continuous)
                    .strokeBorder(isActive ? Color.accentColor : Color(nsColor: .separatorColor).opacity(0.42))
            }
            .contentShape(RoundedRectangle(cornerRadius: AppVisualTokens.Radius.standard, style: .continuous))
    }

    private func backgroundFill(isPressed: Bool) -> Color {
        if isPressed {
            return Color.accentColor.opacity(isActive ? 0.78 : 0.16)
        }
        return isActive ? Color.accentColor : Color.clear
    }
}

@MainActor
private final class RichTextFieldFormatter: ObservableObject {
    fileprivate weak var textView: NSTextView?
    @Published private(set) var isBoldActive = false
    @Published private(set) var isItalicActive = false
    @Published private(set) var isBulletActive = false

    func toggleBold() {
        setFontTrait(.boldFontMask, enabled: !isBoldActive)
    }

    func toggleItalic() {
        setFontTrait(.italicFontMask, enabled: !isItalicActive)
    }

    private func setFontTrait(_ trait: NSFontTraitMask, enabled: Bool) {
        guard let textView else {
            return
        }

        let selection = textView.selectedRange()
        if selection.length == 0 {
            let baseFont = (textView.typingAttributes[.font] as? NSFont)
                ?? textView.font
                ?? NSFont.preferredFont(forTextStyle: .body)
            textView.typingAttributes[.font] = font(from: baseFont, trait: trait, enabled: enabled)
            refreshSelectionState()
            return
        }

        guard let textStorage = textView.textStorage else {
            return
        }

        textStorage.beginEditing()
        textStorage.enumerateAttributes(in: selection, options: []) { attributes, range, _ in
            let currentFont = (attributes[.font] as? NSFont)
                ?? textView.font
                ?? NSFont.preferredFont(forTextStyle: .body)
            let updatedFont = font(from: currentFont, trait: trait, enabled: enabled)
            textStorage.addAttribute(.font, value: updatedFont, range: range)
        }
        textStorage.endEditing()
        textView.didChangeText()
        textView.setSelectedRange(selection)
        refreshSelectionState()
    }

    private func font(from font: NSFont, trait: NSFontTraitMask, enabled: Bool) -> NSFont {
        let fontManager = NSFontManager.shared
        if enabled {
            return fontManager.convert(font, toHaveTrait: trait)
        }
        return fontManager.convert(font, toNotHaveTrait: trait)
    }

    func toggleBullet() {
        guard let textView else {
            return
        }

        let storage = textView.textStorage ?? NSTextStorage(string: textView.string)
        let fullString = storage.string as NSString
        let selection = textView.selectedRange()
        let lineRange = fullString.lineRange(for: selection)
        let shouldEnable = !isBulletActive

        if selection.length == 0 {
            let lineTextRange = lineRangeWithoutLineBreak(from: lineRange, in: fullString)
            let lineText = fullString.substring(with: lineTextRange)
            let leadingWhitespace = String(lineText.prefix(while: { $0 == " " || $0 == "\t" }))
            let remainingText = String(lineText.dropFirst(leadingWhitespace.count))
            let replacement: String
            let cursorDelta: Int

            if shouldEnable {
                guard !remainingText.hasPrefix("• ") else {
                    refreshSelectionState()
                    return
                }
                replacement = "\(leadingWhitespace)• \(remainingText)"
                cursorDelta = 2
            } else {
                guard remainingText.hasPrefix("• ") else {
                    refreshSelectionState()
                    return
                }
                replacement = leadingWhitespace + remainingText.dropFirst(2)
                cursorDelta = -2
            }

            storage.replaceCharacters(in: lineTextRange, with: replacement)
            textView.didChangeText()

            let newCursorLocation = max(
                lineTextRange.location + (leadingWhitespace as NSString).length,
                selection.location + cursorDelta
            )
            textView.setSelectedRange(NSRange(location: newCursorLocation, length: 0))
            refreshSelectionState()
            return
        }

        let selectedText = fullString.substring(with: lineRange)
        let lines = selectedText.split(separator: "\n", omittingEmptySubsequences: false)
        let transformedLines = lines.map { line -> String in
            let value = String(line)
            let leadingWhitespace = String(value.prefix(while: { $0 == " " || $0 == "\t" }))
            let remainingText = String(value.dropFirst(leadingWhitespace.count))

            if shouldEnable {
                guard !remainingText.isEmpty, !remainingText.hasPrefix("• ") else {
                    return value
                }
                return "\(leadingWhitespace)• \(remainingText)"
            }

            guard remainingText.hasPrefix("• ") else {
                return value
            }
            return leadingWhitespace + remainingText.dropFirst(2)
        }
        let replacedText = transformedLines.joined(separator: "\n")
        guard replacedText != selectedText else {
            refreshSelectionState()
            return
        }

        storage.replaceCharacters(in: lineRange, with: replacedText)
        textView.didChangeText()
        textView.setSelectedRange(NSRange(location: lineRange.location, length: (replacedText as NSString).length))
        refreshSelectionState()
    }

    func refreshSelectionState() {
        guard let textView else {
            isBoldActive = false
            isItalicActive = false
            isBulletActive = false
            return
        }

        isBoldActive = isFontTraitActive(.boldFontMask, in: textView)
        isItalicActive = isFontTraitActive(.italicFontMask, in: textView)
        isBulletActive = isBulletActive(in: textView)
    }

    private func isFontTraitActive(_ trait: NSFontTraitMask, in textView: NSTextView) -> Bool {
        let selection = textView.selectedRange()
        if selection.length == 0 {
            let font = (textView.typingAttributes[.font] as? NSFont)
                ?? textView.font
                ?? NSFont.preferredFont(forTextStyle: .body)
            return NSFontManager.shared.traits(of: font).contains(trait)
        }

        guard let textStorage = textView.textStorage,
              selection.location + selection.length <= textStorage.length else {
            return false
        }

        var isActive = true
        textStorage.enumerateAttribute(.font, in: selection, options: []) { value, _, stop in
            let font = (value as? NSFont)
                ?? textView.font
                ?? NSFont.preferredFont(forTextStyle: .body)
            if !NSFontManager.shared.traits(of: font).contains(trait) {
                isActive = false
                stop.pointee = true
            }
        }
        return isActive
    }

    private func isBulletActive(in textView: NSTextView) -> Bool {
        let fullString = textView.string as NSString
        let selection = textView.selectedRange()
        guard selection.location <= fullString.length else {
            return false
        }

        let lineRange = fullString.lineRange(for: selection)
        let selectedLines = fullString.substring(with: lineRange)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        guard !selectedLines.isEmpty else {
            return false
        }

        return selectedLines.allSatisfy { line in
            let remainder = line.drop(while: { $0 == " " || $0 == "\t" })
            return remainder.hasPrefix("• ")
        }
    }

    private func lineRangeWithoutLineBreak(from lineRange: NSRange, in fullString: NSString) -> NSRange {
        var end = lineRange.location + lineRange.length
        if end > lineRange.location && end <= fullString.length {
            let lastCharacterIndex = end - 1
            let lastCharacter = fullString.character(at: lastCharacterIndex)
            if lastCharacter == 10 {
                end -= 1
                if end > lineRange.location && fullString.character(at: end - 1) == 13 {
                    end -= 1
                }
            }
        }

        return NSRange(location: lineRange.location, length: max(0, end - lineRange.location))
    }
}

private struct RichTextFieldRepresentable: NSViewRepresentable {
    @Binding var text: String
    let formatter: RichTextFieldFormatter

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isAutomaticTextCompletionEnabled = true
        textView.font = NSFont.preferredFont(forTextStyle: .body)
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.string = text

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        formatter.textView = textView
        formatter.refreshSelectionState()

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else {
            return
        }

        if textView.string != text {
            textView.string = text
        }

        context.coordinator.parent = self
        formatter.textView = textView
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichTextFieldRepresentable

        init(_ parent: RichTextFieldRepresentable) {
            self.parent = parent
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString string: String?) -> Bool {
            guard let string, string == "\n" || string == "\r" else {
                return true
            }

            guard affectedCharRange.length == 0 else {
                return true
            }

            let currentText = textView.string as NSString
            let cursorLocation = affectedCharRange.location
            guard cursorLocation <= currentText.length else {
                return true
            }

            let lineRange = currentText.lineRange(for: NSRange(location: cursorLocation, length: 0))
            let lineText = currentText.substring(with: NSRange(location: lineRange.location, length: cursorLocation - lineRange.location))
            guard let prefix = bulletPrefix(from: lineText) else {
                return true
            }

            let contentAfterPrefix = bulletContent(after: prefix, in: lineText)
            guard !contentAfterPrefix.trimmingCharacters(in: .whitespaces).isEmpty else {
                return true
            }

            let replacement = string + prefix
            textView.textStorage?.replaceCharacters(in: affectedCharRange, with: replacement)
            if let text = textView.textStorage?.string {
                parent.text = text
            }
            textView.didChangeText()
            let newCursor = cursorLocation + (replacement as NSString).length
            textView.setSelectedRange(NSRange(location: newCursor, length: 0))
            parent.formatter.refreshSelectionState()
            return false
        }

        private func bulletPrefix(from line: String) -> String? {
            guard !line.isEmpty else {
                return nil
            }

            let leadingWhitespace = line.prefix { $0 == " " || $0 == "\t" }
            let remainderStart = line.dropFirst(leadingWhitespace.count)
            guard remainderStart.hasPrefix("• ") else {
                return nil
            }

            return String(leadingWhitespace) + "• "
        }

        private func bulletContent(after prefix: String, in line: String) -> String {
            let contentStart = line.index(line.startIndex, offsetBy: prefix.count)
            if contentStart > line.endIndex {
                return ""
            }
            return String(line[contentStart..<line.endIndex])
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else {
                return
            }
            if parent.text != textView.string {
                parent.text = textView.string
            }
            parent.formatter.refreshSelectionState()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            parent.formatter.refreshSelectionState()
        }
    }
}

struct EndSessionView: View {
    let project: Project
    let session: WorkSession
    @ObservedObject var viewModel: SessionViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Header(project: project)

            DashboardSurface(style: .emphasized) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("What is still in your head?")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Include decisions, surprises, blockers, and what you would do next.")
                        .foregroundStyle(.secondary)
                    TextEditor(text: $viewModel.brainDump)
                        .font(.body)
                        .frame(minHeight: 140, maxHeight: 180)
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: AppVisualTokens.Radius.compact, style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor))
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: AppVisualTokens.Radius.compact, style: .continuous)
                                .stroke(Color(nsColor: .separatorColor).opacity(0.56))
                        }
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
                .transition(AppMotion.stateTransition(reduceMotion: reduceMotion))
            }

            Spacer()
        }
        .padding(AppVisualTokens.Spacing.workspaceWide)
        .frame(maxWidth: AppVisualTokens.Layout.compactWorkspaceWidth, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .animation(AppMotion.animation(.standard, reduceMotion: reduceMotion), value: viewModel.isWorking)
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
                AppSurface(style: .status(.warning)) {
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
    let evidenceDigest: SnapshotEvidenceDigest
    let onBackToProject: () -> Void
    let onViewSnapshot: () -> Void

    var body: some View {
        ScrollView {
            AppWorkspace {
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
            }
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
                                increments: incrementsForBlock(block),
                                observedContext: evidenceDigest.pomodoroBlocks.first {
                                    $0.blockIndex == block.blockIndex
                                }?.observedContext ?? .empty
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
                    value: gitOverview,
                    systemImage: "point.3.connected.trianglepath.dotted"
                )
                ObservedContextFact(
                    title: "Files Touched",
                    value: "\(evidenceDigest.changedPaths.count) file\(evidenceDigest.changedPaths.count == 1 ? "" : "s")",
                    systemImage: "doc.on.doc"
                )
                ObservedContextFact(
                    title: "Apps Observed",
                    value: evidenceDigest.activeApplications.isEmpty
                        ? "None observed"
                        : evidenceDigest.activeApplications
                            .prefix(4)
                            .map(\.displayName)
                            .joined(separator: ", "),
                    systemImage: "macwindow"
                )

                HistoricalGitEvidenceView(summary: evidenceDigest.gitSummary)

                if !evidenceDigest.betweenBlocksObservation.isEmpty {
                    ObservedWindowDisclosure(
                        title: "Between blocks",
                        context: evidenceDigest.betweenBlocksObservation
                    )
                }

                if !evidenceDigest.unattributedObservation.isEmpty {
                    ObservedWindowDisclosure(
                        title: blocks.isEmpty ? "Session-wide evidence" : "Legacy session-wide evidence",
                        context: evidenceDigest.unattributedObservation
                    )
                }
            }
        }
    }

    private var gitOverview: String {
        guard let isRepository = evidenceDigest.gitSummary.isRepository else {
            return "No Git evidence"
        }
        if !isRepository {
            return "Not a Git repository"
        }
        let branch = evidenceDigest.gitSummary.finalBranchName
            ?? evidenceDigest.gitSummary.initialBranchName
            ?? "Detached HEAD"
        let commitCount = evidenceDigest.gitSummary.commitsAfterStart.count
        return commitCount == 0
            ? branch
            : "\(branch) · \(commitCount) commit\(commitCount == 1 ? "" : "s")"
    }
}

private struct HistoricalBlockRow: View {
    let block: PomodoroBlock
    let increments: [WorkIncrement]
    let observedContext: CompactedObservationContext
    @State private var isIncrementsExpanded = true

    var body: some View {
        AppSurface(style: .soft) {
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
                    DisclosureGroup(isExpanded: $isIncrementsExpanded) {
                        VStack(spacing: 0) {
                            ForEach(increments) { increment in
                                IncrementRow(increment: increment)
                                if increment.id != increments.last?.id {
                                    Divider()
                                }
                            }
                        }
                    } label: {
                        Text("Work Increments")
                            .font(.headline)
                    }
                }

                if !observedContext.isEmpty {
                    ObservedWindowDisclosure(
                        title: "Observed during this block",
                        context: observedContext
                    )
                }
            }
        }
    }
}

private struct ObservedWindowDisclosure: View {
    let title: String
    let context: CompactedObservationContext
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                if !context.changedPaths.isEmpty {
                    Text("Changed paths")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)

                    ForEach(Array(context.changedPaths.enumerated()), id: \.offset) { _, path in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "doc")
                                .foregroundStyle(.secondary)
                            Text(path.relativePath)
                                .font(.caption)
                                .textSelection(.enabled)
                            Spacer(minLength: 8)
                            Text("\(path.changeCount)×")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if !context.activeApplications.isEmpty {
                    Text("Applications observed")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)

                    Text(context.activeApplications.map(\.displayName).joined(separator: " → "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .padding(.top, 8)
        } label: {
            HStack(spacing: 8) {
                Text(title)
                    .font(.callout)
                    .fontWeight(.semibold)
                Text(contextSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var contextSummary: String {
        var parts: [String] = []
        if !context.changedPaths.isEmpty {
            parts.append("\(context.changedPaths.count) file\(context.changedPaths.count == 1 ? "" : "s")")
        }
        if !context.activeApplications.isEmpty {
            parts.append("\(context.activeApplications.count) app\(context.activeApplications.count == 1 ? "" : "s")")
        }
        return parts.joined(separator: " · ")
    }
}

private struct HistoricalGitEvidenceView: View {
    let summary: CompactedGitSummary
    @State private var isExpanded = false

    var body: some View {
        if summary.isRepository == true, hasDetails {
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 10) {
                    gitIdentity
                    pathList(title: "Changed before the session", paths: summary.initialChangedPaths)
                    pathList(
                        title: "Session-observed final changes",
                        paths: summary.sessionObservedChangedPaths
                    )
                    pathList(
                        title: "Other final changes not observed during the session",
                        paths: summary.unobservedFinalChangedPaths
                    )

                    if !summary.commitsAfterStart.isEmpty {
                        gitSectionTitle("Commits created after session start")
                        ForEach(Array(summary.commitsAfterStart.enumerated()), id: \.offset) { _, commit in
                            Text("\(shortSHA(commit.hash))  \(commit.subject)")
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                        }
                    }

                    if !summary.diffStatLines.isEmpty {
                        gitSectionTitle("Bounded diff stat")
                        Text(summary.diffStatLines.joined(separator: "\n"))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

                    if summary.isTruncated {
                        Label("Some Git evidence was truncated to stay within local bounds.", systemImage: "ellipsis")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 8)
            } label: {
                Text("Git evidence")
                    .font(.callout)
                    .fontWeight(.semibold)
            }
        }
    }

    @ViewBuilder
    private var gitIdentity: some View {
        if summary.initialBranchName != nil || summary.finalBranchName != nil {
            gitSectionTitle("Branch")
            Text(branchDescription)
                .font(.caption.monospaced())
                .textSelection(.enabled)
        }
        if summary.initialHeadSHA != nil || summary.finalHeadSHA != nil {
            gitSectionTitle("HEAD")
            Text(headDescription)
                .font(.caption.monospaced())
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func pathList(title: String, paths: [String]) -> some View {
        if !paths.isEmpty {
            gitSectionTitle(title)
            ForEach(Array(paths.enumerated()), id: \.offset) { _, path in
                Text(path)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }
        }
    }

    private func gitSectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
    }

    private var hasDetails: Bool {
        summary.initialBranchName != nil
            || summary.finalBranchName != nil
            || summary.initialHeadSHA != nil
            || summary.finalHeadSHA != nil
            || !summary.initialChangedPaths.isEmpty
            || !summary.sessionObservedChangedPaths.isEmpty
            || !summary.unobservedFinalChangedPaths.isEmpty
            || !summary.commitsAfterStart.isEmpty
            || !summary.diffStatLines.isEmpty
            || summary.isTruncated
    }

    private var branchDescription: String {
        let initial = summary.initialBranchName ?? "(unknown)"
        let final = summary.finalBranchName ?? "(unknown)"
        return initial == final ? final : "\(initial) → \(final)"
    }

    private var headDescription: String {
        let initial = summary.initialHeadSHA.map(shortSHA) ?? "(unknown)"
        let final = summary.finalHeadSHA.map(shortSHA) ?? "(unknown)"
        return initial == final ? final : "\(initial) → \(final)"
    }

    private func shortSHA(_ value: String) -> String {
        String(value.prefix(12))
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
        if let detail = increment.detail, !detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                incrementHeader
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 64)
            }
            .padding(.vertical, 8)
        } else {
            incrementHeader
                .padding(.vertical, 8)
        }
    }

    private var incrementHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(increment.occurredAt.formatted(date: .omitted, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 54, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(increment.title)
                        .font(.callout)
                    AppStatusPill(increment.kind.displayName, tone: increment.kind.appTone)
                }
            }
            Spacer()
        }
    }
}

private struct BlockChip: View {
    let block: PomodoroBlock

    var body: some View {
        AppSurface(style: .soft) {
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
        }
        .overlay {
            RoundedRectangle(cornerRadius: AppVisualTokens.Radius.standard, style: .continuous)
                .stroke(statusColor.opacity(0.55), lineWidth: block.status == .active ? 1.5 : 1)
        }
    }

    private var statusColor: Color {
        block.status.appTone.tint
    }
}

private struct BlockStatusBadge: View {
    let block: PomodoroBlock

    var body: some View {
        HStack(spacing: 6) {
            Text("\(block.blockIndex)")
                .font(.callout)
                .fontWeight(.semibold)
            AppStatusPill(block.status.rawValue.capitalized, tone: block.status.appTone)
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

private extension PomodoroBlockStatus {
    var appTone: AppStatusTone {
        switch self {
        case .active:
            .accent
        case .paused:
            .warning
        case .completed:
            .success
        case .interrupted:
            .neutral
        }
    }
}

private extension WorkIncrementKind {
    var appTone: AppStatusTone {
        switch self {
        case .note:
            .accent
        case .decision:
            .success
        case .blocker:
            .warning
        }
    }
}
