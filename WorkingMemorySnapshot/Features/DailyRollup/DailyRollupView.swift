import SwiftUI

struct DailyRollupView: View {
    @ObservedObject var viewModel: DailyRollupViewModel
    let onOpenProject: (Project.ID) -> Void
    let onOpenSession: (DailyRollupSource) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppVisualTokens.Spacing.workspace) {
                header
                Divider()
                stateContent
            }
            .frame(maxWidth: AppVisualTokens.Layout.wideWorkspaceWidth, alignment: .leading)
            .padding(.horizontal, AppVisualTokens.Spacing.workspaceWide)
            .padding(.vertical, AppVisualTokens.Spacing.workspace)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("Daily Rollup")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Daily Rollup")
                    .font(.largeTitle.weight(.bold))
                Text(dateTitle)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                if let metadata = headerMetadata {
                    Text(metadata)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if !viewModel.history.isEmpty {
                Menu {
                    ForEach(viewModel.history) { rollup in
                        Button(historyTitle(rollup)) {
                            Task { await viewModel.select(rollup) }
                        }
                    }
                } label: {
                    Label("Previous Rollups", systemImage: "calendar")
                }
                .accessibilityHint("Choose a previously generated Daily Rollup.")
            }
        }
    }

    @ViewBuilder
    private var stateContent: some View {
        switch viewModel.state {
        case .loading:
            centeredState(
                icon: "arrow.triangle.2.circlepath",
                title: "Gathering the day",
                message: "Loading completed sessions and any saved rollup."
            ) { ProgressView().controlSize(.small) }
        case .empty:
            centeredState(
                icon: "moon.stars",
                title: "Nothing to close yet",
                message: "Completed sessions for this day will appear here when you are ready to close the loop."
            ) { EmptyView() }
        case .blocked(let eligibility):
            centeredState(
                icon: "timer",
                title: "Finish the active session first",
                message: "Daily Rollup waits for the current session to end so its saved evidence can be included. \(countText(eligibility))"
            ) { EmptyView() }
        case .ready(let eligibility):
            centeredState(
                icon: "sparkles",
                title: "Ready to close the day",
                message: countText(eligibility)
            ) {
                Button("Generate Daily Rollup") {
                    Task { await viewModel.generate() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityHint("Uses the selected local LM Studio model.")
            }
        case .generating(let preserved):
            statusBanner(
                tone: .accent,
                icon: "sparkles",
                title: "Generating locally with LM Studio",
                message: "Your sessions and source evidence remain saved while the rollup is synthesized."
            )
            if let preserved { generatedContent(preserved, isStale: true) }
        case .generated(let rollup, let isStale):
            if viewModel.hasActiveSession && !isHistoricalRollup {
                statusBanner(
                    tone: .neutral,
                    icon: "timer",
                    title: "Refresh waits for the active session",
                    message: "The saved rollup remains readable. End the current session before including its evidence."
                )
            }
            if isStale {
                statusBanner(
                    tone: .warning,
                    icon: "arrow.clockwise",
                    title: "New session context is available",
                    message: "This saved rollup is still readable. Refresh when you are ready to include the latest sources."
                )
            }
            generatedContent(rollup, isStale: isStale)
        case .failed(let message, let preserved):
            statusBanner(
                tone: .error,
                icon: "exclamationmark.triangle",
                title: "The rollup could not be generated",
                message: message
            )
            if let preserved { generatedContent(preserved, isStale: true) }
        }
    }

    private func generatedContent(_ rollup: DailyRollup, isStale: Bool) -> some View {
        VStack(alignment: .leading, spacing: AppVisualTokens.Spacing.workspace) {
            HStack(alignment: .center, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    AppSectionLabel("Today in brief")
                    Text(rollup.daySummary)
                        .font(.title3.weight(.medium))
                        .lineSpacing(4)
                        .textSelection(.enabled)
                }
                Spacer()
                refreshButton(isStale: isStale)
            }

            Divider()

            HStack(alignment: .top, spacing: AppVisualTokens.Spacing.section) {
                VStack(alignment: .leading, spacing: AppVisualTokens.Spacing.section) {
                    AppSectionLabel("Today's project summaries")
                    ForEach(Array(rollup.projectThreads.enumerated()), id: \.element.id) { index, thread in
                        projectThread(thread)
                        if index < rollup.projectThreads.count - 1 {
                            Divider()
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                carryForwardPanel(rollup)
                    .frame(width: 300, alignment: .topLeading)
            }

            VStack(alignment: .leading, spacing: 10) {
                AppSectionLabel("Closure note")
                Text(rollup.closureNote)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .textSelection(.enabled)
            }
            .padding(.top, 2)
        }
    }

    private func projectThread(_ thread: DailyProjectThread) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "folder")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: AppVisualTokens.Radius.standard, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: AppVisualTokens.Radius.standard, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.55))
                }

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(thread.projectName)
                        .font(.headline)
                }
                Text(thread.summary)
                    .font(.body)
                    .lineSpacing(3)
                    .textSelection(.enabled)

                let projectSources = viewModel.sources.filter { $0.projectID == thread.projectID }
                HStack(spacing: 16) {
                    sourceSessionControl(projectSources)
                    Spacer()
                    Button("Open Project") { onOpenProject(thread.projectID) }
                        .buttonStyle(.link)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func sourceSessionControl(_ sources: [DailyRollupSource]) -> some View {
        if sources.count == 1, let source = sources.first {
            Button("View source session") {
                if source.isAvailable { onOpenSession(source) }
            }
            .buttonStyle(.link)
            .disabled(!source.isAvailable)
            .help(source.isAvailable ? "Open source session" : "Source session is no longer available")
        } else if !sources.isEmpty {
            Menu("View \(sources.count) source sessions") {
                ForEach(sources) { source in
                    Button("\(source.mission) · \(source.endedAt.formatted(date: .omitted, time: .shortened))") {
                        onOpenSession(source)
                    }
                    .disabled(!source.isAvailable)
                }
            }
            .menuStyle(.borderlessButton)
        }
    }

    private func carryForwardPanel(_ rollup: DailyRollup) -> some View {
        AppSurface(style: .emphasized) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.forward.circle.fill")
                        .foregroundStyle(Color.accentColor)
                    Text("Carry forward")
                        .font(.headline)
                }
                if rollup.carryForwards.isEmpty {
                    Text("No supported unresolved thread needs to be carried forward.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(rollup.carryForwards.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { Divider() }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.projectName)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                            Text(item.text)
                                .font(.subheadline.weight(.medium))
                                .lineSpacing(2)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
    }

    private func centeredState<Action: View>(
        icon: String,
        title: String,
        message: String,
        @ViewBuilder action: () -> Action
    ) -> some View {
        AppSurface(style: .soft) {
            VStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                Text(title)
                    .font(.title2.weight(.semibold))
                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
                action()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 54)
        }
    }

    private func statusBanner(
        tone: AppStatusTone,
        icon: String,
        title: String,
        message: String
    ) -> some View {
        AppSurface(style: .status(tone)) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon).foregroundStyle(tone.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline)
                    Text(message).font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func refreshButton(isStale: Bool) -> some View {
        if isStale {
            Button("Refresh Rollup") { Task { await viewModel.generate() } }
                .buttonStyle(.borderedProminent)
                .disabled(isHistoricalRollup || !viewModel.canGenerate)
        } else {
            Button("Refresh") { Task { await viewModel.generate() } }
                .buttonStyle(.bordered)
                .disabled(isHistoricalRollup || !viewModel.canGenerate)
        }
    }

    private var dateTitle: String {
        viewModel.selectedDate.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
    }

    private var headerMetadata: String? {
        if let rollup = viewModel.displayedRollup {
            return "\(viewModel.sources.count) completed \(viewModel.sources.count == 1 ? "session" : "sessions") · \(rollup.projectThreads.count) \(rollup.projectThreads.count == 1 ? "project" : "projects") · Generated locally"
        }
        switch viewModel.state {
        case .ready(let eligibility), .blocked(let eligibility), .empty(let eligibility):
            return "\(eligibility.completedSessionCount) completed \(eligibility.completedSessionCount == 1 ? "session" : "sessions") · \(eligibility.participatingProjectCount) \(eligibility.participatingProjectCount == 1 ? "project" : "projects")"
        default:
            return nil
        }
    }

    private var isHistoricalRollup: Bool {
        DailyRollupDay.key(for: viewModel.selectedDate) != DailyRollupDay.key(for: Date())
    }

    private func countText(_ eligibility: DailyRollupEligibility) -> String {
        "\(eligibility.completedSessionCount) completed \(eligibility.completedSessionCount == 1 ? "session" : "sessions") across \(eligibility.participatingProjectCount) \(eligibility.participatingProjectCount == 1 ? "project" : "projects")."
    }

    private func historyTitle(_ rollup: DailyRollup) -> String {
        let formatter = DateFormatter()
        formatter.calendar = .autoupdatingCurrent
        formatter.timeZone = .autoupdatingCurrent
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let date = formatter.date(from: rollup.rollupDate) ?? rollup.generatedAt
        formatter.locale = .current
        formatter.dateFormat = "MMM d, yyyy"
        let day = formatter.string(from: date)
        let time = rollup.generatedAt.formatted(.dateTime.hour().minute().second())
        return "\(day) · \(time)"
    }
}
