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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                pomodoroBlockCard
                if let activeBlock = viewModel.activeBlock, activeBlock.status != .active && activeBlock.status != .paused {
                    workIncrementsSection
                }
                if viewModel.activeBlock?.status != .paused {
                    sessionInspectorDisclosure
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

            if isShowingBlockCompletionInput {
                blockCompletionInput
            }

            Divider()
            workIncrementsContent()
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
            .buttonStyle(.plain)
            .foregroundStyle(.blue)
            .disabled(viewModel.isWorking)
            .fastTooltip("Resume Focus Block")
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
            .buttonStyle(.plain)
            .foregroundStyle(.green)
            .disabled(viewModel.isWorking)
            .fastTooltip("Complete Focus Block")
            .accessibilityLabel("Complete Focus Block")

            Button(role: .destructive) {
                viewModel.beginEndingActiveSession()
            } label: {
                Label("Complete Session", systemImage: "xmark")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
            .disabled(viewModel.isWorking)
            .fastTooltip("Complete Session")
            .accessibilityLabel("Complete Session")
            .accessibilityHint("Open the brain dump form and prepare to generate a snapshot.")
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
                            if increment.id != viewModel.activeBlockIncrements.last?.id {
                                Divider()
                            }
                        }
                    }
                } label: {
                    Text("Work Increments")
                        .font(.headline)
                }
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
                    .buttonStyle(.plain)
                    .foregroundStyle(.green)
                    .disabled(viewModel.activeBlock == nil || viewModel.isWorking || isShowingBlockCompletionInput)
                    .fastTooltip("Complete Focus Block")
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
                    .buttonStyle(.plain)
                    .foregroundStyle(.orange)
                    .disabled(viewModel.activeBlock == nil || viewModel.isWorking)
                    .fastTooltip("Pause Block")
                    .accessibilityLabel("Pause Block")

                    Button(role: .destructive) {
                        viewModel.beginEndingActiveSession()
                    } label: {
                        Label("End Session", systemImage: "xmark")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                    .disabled(viewModel.activeBlock == nil || viewModel.isWorking)
                    .fastTooltip("Complete Session")
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

private struct FastTooltipModifier: ViewModifier {
    let text: String
    let delay: TimeInterval

    @State private var isShowingTooltip = false
    @State private var scheduledWorkItem: DispatchWorkItem?

    init(_ text: String, delayFactor: Double = 0.7, baseDelay: TimeInterval = 0.5) {
        self.text = text
        self.delay = baseDelay * delayFactor
    }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if isShowingTooltip {
                    Text(text)
                        .font(.caption2)
                        .lineLimit(2)
                        .fixedSize(horizontal: true, vertical: true)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .foregroundStyle(.white)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.black.opacity(0.9))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
                        )
                        .padding(.top, 6)
                        .offset(y: 24.2)
                        .allowsHitTesting(false)
                        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 2)
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .onAppear {
                isShowingTooltip = false
            }
            .onDisappear {
                scheduledWorkItem?.cancel()
                isShowingTooltip = false
            }
            .onHover { hovering in
                scheduledWorkItem?.cancel()
                if hovering {
                    let workItem = DispatchWorkItem {
                        isShowingTooltip = true
                    }
                    scheduledWorkItem = workItem
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
                } else {
                    isShowingTooltip = false
                }
            }
    }
}

private extension View {
    func fastTooltip(_ text: String, delayFactor: Double = 0.7, baseDelay: TimeInterval = 0.5) -> some View {
        modifier(FastTooltipModifier(text, delayFactor: delayFactor, baseDelay: baseDelay))
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
                    .foregroundStyle(.black)

                Spacer()

                HStack(spacing: 8) {
                    Button {
                        formatter.toggleBold()
                    } label: {
                        Image(systemName: "bold")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                    .fastTooltip("Bold")

                    Button {
                        formatter.toggleItalic()
                    } label: {
                        Image(systemName: "italic")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                    .fastTooltip("Italic")

                    Button {
                        formatter.insertBullet()
                    } label: {
                        Image(systemName: "list.bullet")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                    .fastTooltip("Insert bullets")
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
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.24))
        }
    }
}

private final class RichTextFieldFormatter: ObservableObject {
    fileprivate weak var textView: NSTextView?

    func toggleBold() {
        toggleFontTrait(.boldFontMask)
    }

    func toggleItalic() {
        toggleFontTrait(.italicFontMask)
    }

    private func toggleFontTrait(_ trait: NSFontTraitMask) {
        guard let textView else {
            return
        }

        let selection = textView.selectedRange()
        if selection.length == 0 {
            let baseFont = (textView.typingAttributes[.font] as? NSFont)
                ?? textView.font
                ?? NSFont.preferredFont(forTextStyle: .body)
            textView.typingAttributes[.font] = toggledFont(from: baseFont, trait: trait)
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
            let updatedFont = toggledFont(from: currentFont, trait: trait)
            textStorage.addAttribute(.font, value: updatedFont, range: range)
        }
        textStorage.endEditing()
        textView.didChangeText()
        textView.setSelectedRange(selection)
    }

    private func toggledFont(from font: NSFont, trait: NSFontTraitMask) -> NSFont {
        let fontManager = NSFontManager.shared
        if fontManager.traits(of: font).contains(trait) {
            return fontManager.convert(font, toNotHaveTrait: trait)
        }
        return fontManager.convert(font, toHaveTrait: trait)
    }

    func insertBullet() {
        guard let textView else {
            return
        }

        let storage = textView.textStorage ?? NSTextStorage(string: textView.string)
        let fullString = storage.string as NSString
        let selection = textView.selectedRange()
        let lineRange = fullString.lineRange(for: selection)

        if selection.length == 0 {
            let lineTextRange = lineRangeWithoutLineBreak(from: lineRange, in: fullString)
            let lineText = fullString.substring(with: lineTextRange)

            if lineText.hasPrefix("• ") {
                return
            }

            let leadingWhitespace = String(lineText.prefix(while: { $0 == " " || $0 == "\t" }))
            let remainingText = String(lineText.dropFirst(leadingWhitespace.count))
            let replacement = "\(leadingWhitespace)• \(remainingText)"

            storage.replaceCharacters(in: lineTextRange, with: replacement)
            textView.textStorage?.setAttributedString(storage)
            textView.didChangeText()

            let newCursorLocation = lineTextRange.location + (leadingWhitespace as NSString).length + 2
            textView.setSelectedRange(NSRange(location: newCursorLocation, length: 0))
            return
        }

        let selectedText = fullString.substring(with: lineRange)
        let lines = selectedText.split(separator: "\n", omittingEmptySubsequences: false)
        var transformedLines: [String] = []
        transformedLines.reserveCapacity(lines.count)

        var didChangeSelection = false
        var insertionOffset = 0

        for line in lines {
            if line.hasPrefix("• ") || line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                transformedLines.append(String(line))
            } else {
                transformedLines.append("• " + line)
                if lineRange.location < selection.location {
                    insertionOffset += 2
                }
                didChangeSelection = true
            }
            transformedLines.append("")
        }
        if !transformedLines.isEmpty {
            transformedLines.removeLast()
        }

        let replacedText = transformedLines.joined(separator: "\n")
        guard replacedText != selectedText else {
            return
        }

        storage.replaceCharacters(in: lineRange, with: replacedText)
        textView.textStorage?.setAttributedString(storage)
        textView.didChangeText()

        if didChangeSelection {
            let newLocation = max(0, min(storage.length, selection.location + insertionOffset))
            textView.setSelectedRange(NSRange(location: newLocation, length: 0))
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

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else {
            return
        }

        if textView.string != text {
            textView.string = text
        }

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
        }
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
                    .frame(minHeight: 140, maxHeight: 180)
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
    @State private var isIncrementsExpanded = true

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
                    Text(increment.kind.displayName)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(kindColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(kindColor.opacity(0.12)))
                }
            }
            Spacer()
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
