import Foundation

struct ObservationSessionSummary: Equatable, Sendable {
    var changedFileCount: Int = 0
    var droppedFileChangeCount: Int = 0
    var activeApplicationNames: [String] = []
    var isGitRepository: Bool?
    var notes: [String] = []

    var displayText: String {
        var parts: [String] = []

        if changedFileCount == 1 {
            parts.append("1 file changed")
        } else if changedFileCount > 1 {
            parts.append("\(changedFileCount) files changed")
        } else {
            parts.append("Watching files")
        }

        if isGitRepository == true {
            parts.append("Git repository")
        } else if isGitRepository == false {
            parts.append("No Git repository")
        } else {
            parts.append("Checking Git")
        }

        if activeApplicationNames.isEmpty {
            parts.append("Waiting for app activity")
        } else {
            parts.append(activeApplicationNames.prefix(4).joined(separator: ", "))
        }

        return parts.joined(separator: " · ")
    }
}

@MainActor
protocol SessionObservationCoordinating: AnyObject {
    var onSummaryChange: (@MainActor (ObservationSessionSummary) -> Void)? { get set }

    func startObserving(session: WorkSession, project: Project) async
    func stopObservingForCompletion(session: WorkSession, brainDump: String) async
    func stopObservingForCancellation(session: WorkSession) async
}

@MainActor
final class ObservationCoordinator: SessionObservationCoordinating {
    var onSummaryChange: (@MainActor (ObservationSessionSummary) -> Void)?

    private let eventRepository: EventRepository
    private let fileObservationService: FileObservationService
    private let activeAppObservationService: ActiveAppObservationService
    private let gitService: GitService
    private var state: ObservationState?

    init(
        eventRepository: EventRepository,
        fileObservationService: FileObservationService = FileObservationService(),
        activeAppObservationService: ActiveAppObservationService = ActiveAppObservationService(),
        gitService: GitService = GitService()
    ) {
        self.eventRepository = eventRepository
        self.fileObservationService = fileObservationService
        self.activeAppObservationService = activeAppObservationService
        self.gitService = gitService
    }

    func startObserving(session: WorkSession, project: Project) async {
        guard session.status == .active else {
            return
        }

        if state?.session.id == session.id {
            return
        }

        await stopCurrentObservers()

        state = ObservationState(session: session, project: project)
        publishSummary()

        await insertBestEffort(
            SessionEvent(
                sessionID: session.id,
                occurredAt: session.startedAt,
                source: .system,
                kind: SessionEventKind.sessionStarted,
                title: "Session started",
                body: session.mission
            )
        )

        await startFileObservation(project: project)
        startActiveAppObservation()
        await captureInitialGitEvidence(project: project)
    }

    func stopObservingForCompletion(session: WorkSession, brainDump: String) async {
        guard let currentState = state, currentState.session.id == session.id else {
            return
        }

        let fileSummary = await fileObservationService.stop()
        activeAppObservationService.stop()
        apply(fileSummary: fileSummary)

        let observedPaths = Set(fileSummary.changes.map(\.relativePath))
        await insertBestEffort(fileEvents(from: fileSummary, sessionID: session.id))
        await captureFinalGitEvidence(
            sessionID: session.id,
            projectURL: URL(fileURLWithPath: currentState.project.rootPath),
            startHead: currentState.initialGitHead,
            observedRelativePaths: observedPaths
        )

        await insertBestEffort([
            SessionEvent(
                sessionID: session.id,
                source: .user,
                kind: SessionEventKind.brainDump,
                title: "Brain dump",
                body: brainDump
            ),
            SessionEvent(
                sessionID: session.id,
                source: .system,
                kind: SessionEventKind.sessionEnded,
                title: "Session ended"
            )
        ])

        state = nil
        publishSummary()
    }

    func stopObservingForCancellation(session: WorkSession) async {
        guard state?.session.id == session.id else {
            return
        }

        await stopCurrentObservers()
        await insertBestEffort(
            SessionEvent(
                sessionID: session.id,
                source: .system,
                kind: SessionEventKind.sessionCancelled,
                title: "Session cancelled"
            )
        )
        state = nil
        publishSummary()
    }

    private func startFileObservation(project: Project) async {
        do {
            try await fileObservationService.start(
                configuration: FileObservationConfiguration(
                    projectRootURL: URL(fileURLWithPath: project.rootPath)
                ),
                onChange: { [weak self] summary in
                    Task { @MainActor in
                        self?.apply(fileSummary: summary)
                    }
                }
            )
        } catch {
            recordObservationIssue("File observation could not start: \(error.localizedDescription)")
        }
    }

    private func startActiveAppObservation() {
        activeAppObservationService.start { [weak self] event in
            Task { @MainActor in
                await self?.recordActiveAppEvent(event)
            }
        }
    }

    private func captureInitialGitEvidence(project: Project) async {
        guard let currentState = state else {
            return
        }

        do {
            let evidence = try await gitService.captureInitialState(
                projectURL: URL(fileURLWithPath: project.rootPath)
            )
            switch evidence {
            case .notRepository:
                state?.summary.isGitRepository = false
                await insertBestEffort(
                    SessionEvent(
                        sessionID: currentState.session.id,
                        source: .git,
                        kind: SessionEventKind.gitInitialState,
                        title: "Not a Git repository",
                        body: "The selected project is not inside a Git repository.",
                        payloadJSON: try? EventPayloadCoding.encode(
                            GitInitialStateEventPayload(
                                isRepository: false,
                                branchName: nil,
                                headSHA: nil,
                                changedPaths: [],
                                isStatusTruncated: false
                            )
                        )
                    )
                )
            case .repository(let snapshot):
                state?.summary.isGitRepository = true
                state?.initialGitHead = snapshot.headSHA
                await insertBestEffort(initialGitEvent(from: snapshot, sessionID: currentState.session.id))
            }
        } catch {
            recordObservationIssue("Initial Git evidence failed: \(error.localizedDescription)")
        }

        publishSummary()
    }

    private func captureFinalGitEvidence(
        sessionID: WorkSession.ID,
        projectURL: URL,
        startHead: String?,
        observedRelativePaths: Set<String>
    ) async {
        do {
            let evidence = try await gitService.captureFinalSummary(
                projectURL: projectURL,
                startHead: startHead,
                observedRelativePaths: observedRelativePaths
            )

            switch evidence {
            case .notRepository:
                await insertBestEffort(
                    SessionEvent(
                        sessionID: sessionID,
                        source: .git,
                        kind: SessionEventKind.gitFinalSummary,
                        title: "Not a Git repository",
                        body: "No Git final summary was captured because the project is not in a Git repository.",
                        payloadJSON: try? EventPayloadCoding.encode(
                            GitFinalSummaryEventPayload(
                                isRepository: false,
                                branchName: nil,
                                headSHA: nil,
                                sessionObservedChangedPaths: [],
                                unobservedChangedPaths: [],
                                diffStatLines: [],
                                commitsAfterStart: [],
                                hasSessionObservedChanges: false,
                                isStatusTruncated: false,
                                isDiffStatTruncated: false
                            )
                        )
                    )
                )
            case .repository(let summary):
                await insertBestEffort(finalGitEvent(from: summary, sessionID: sessionID))
            }
        } catch {
            recordObservationIssue("Final Git evidence failed: \(error.localizedDescription)")
        }
    }

    private func recordActiveAppEvent(_ event: ActiveAppObservationEvent) async {
        guard let currentState = state else {
            return
        }

        if !currentState.summary.activeApplicationNames.contains(event.application.displayName) {
            state?.summary.activeApplicationNames.append(event.application.displayName)
            publishSummary()
        }

        await insertBestEffort(
            SessionEvent(
                sessionID: currentState.session.id,
                occurredAt: event.occurredAt,
                source: .activeApp,
                kind: SessionEventKind.appActivated,
                title: event.title,
                body: event.body,
                payloadJSON: try? EventPayloadCoding.encode(
                    ActiveAppEventPayload(
                        displayName: event.application.displayName,
                        bundleIdentifier: event.application.bundleIdentifier
                    )
                )
            )
        )
    }

    private func apply(fileSummary: FileChangeSummary) {
        guard state != nil else {
            return
        }

        state?.summary.changedFileCount = fileSummary.changes.count
        state?.summary.droppedFileChangeCount = fileSummary.droppedChangeCount
        publishSummary()
    }

    private func recordObservationIssue(_ message: String) {
        guard let currentState = state else {
            return
        }

        state?.summary.notes.append(message)
        publishSummary()

        Task {
            await insertBestEffort(
                SessionEvent(
                    sessionID: currentState.session.id,
                    source: .system,
                    kind: SessionEventKind.observationIssue,
                    title: "Observation issue",
                    body: message
                )
            )
        }
    }

    private func stopCurrentObservers() async {
        _ = await fileObservationService.stop()
        activeAppObservationService.stop()
    }

    private func insertBestEffort(_ event: SessionEvent) async {
        do {
            try await eventRepository.insertEvent(event)
        } catch {
            // Observation must never block the user from ending or recovering a session.
        }
    }

    private func insertBestEffort(_ events: [SessionEvent]) async {
        do {
            try await eventRepository.insertEvents(events)
        } catch {
            // Observation must never block the user from ending or recovering a session.
        }
    }

    private func initialGitEvent(
        from snapshot: GitRepositorySnapshot,
        sessionID: WorkSession.ID
    ) -> SessionEvent {
        SessionEvent(
            sessionID: sessionID,
            source: .git,
            kind: SessionEventKind.gitInitialState,
            title: "Git initial state",
            body: gitInitialBody(from: snapshot),
            payloadJSON: try? EventPayloadCoding.encode(
                GitInitialStateEventPayload(
                    isRepository: true,
                    branchName: snapshot.branchName,
                    headSHA: snapshot.headSHA,
                    changedPaths: snapshot.status.changedPaths,
                    isStatusTruncated: snapshot.status.isOutputTruncated
                )
            )
        )
    }

    private func finalGitEvent(
        from summary: GitRepositoryFinalSummary,
        sessionID: WorkSession.ID
    ) -> SessionEvent {
        SessionEvent(
            sessionID: sessionID,
            source: .git,
            kind: SessionEventKind.gitFinalSummary,
            title: "Git final summary",
            body: gitFinalBody(from: summary),
            payloadJSON: try? EventPayloadCoding.encode(
                GitFinalSummaryEventPayload(
                    isRepository: true,
                    branchName: summary.branchName,
                    headSHA: summary.headSHA,
                    sessionObservedChangedPaths: summary.sessionObservedChangedPaths,
                    unobservedChangedPaths: summary.unobservedChangedPaths,
                    diffStatLines: summary.diffStat.lines,
                    commitsAfterStart: summary.commitsAfterStart.map {
                        GitCommitEventPayload(hash: $0.hash, subject: $0.subject)
                    },
                    hasSessionObservedChanges: summary.hasSessionObservedChanges,
                    isStatusTruncated: summary.status.isOutputTruncated,
                    isDiffStatTruncated: summary.diffStat.isOutputTruncated
                )
            )
        )
    }

    private func fileEvents(from summary: FileChangeSummary, sessionID: WorkSession.ID) -> [SessionEvent] {
        summary.changes.map { change in
            SessionEvent(
                sessionID: sessionID,
                occurredAt: change.lastObservedAt,
                source: .file,
                kind: SessionEventKind.fileChanged,
                title: change.relativePath,
                body: "\(change.changeCount) observed change(s)",
                payloadJSON: try? EventPayloadCoding.encode(
                    FileChangedEventPayload(
                        relativePath: change.relativePath,
                        firstObservedAt: DateCoding.string(from: change.firstObservedAt),
                        lastObservedAt: DateCoding.string(from: change.lastObservedAt),
                        changeCount: change.changeCount
                    )
                )
            )
        }
    }

    private func gitInitialBody(from snapshot: GitRepositorySnapshot) -> String {
        var lines: [String] = []
        if let branchName = snapshot.branchName {
            lines.append("Branch: \(branchName)")
        }
        if let headSHA = snapshot.headSHA {
            lines.append("HEAD: \(shortSHA(headSHA))")
        }
        if snapshot.status.changedPaths.isEmpty {
            lines.append("Initial status: clean")
        } else {
            lines.append("Initial changed paths: \(snapshot.status.changedPaths.joined(separator: ", "))")
        }
        if snapshot.status.isOutputTruncated {
            lines.append("Initial status output was truncated.")
        }
        return lines.joined(separator: "\n")
    }

    private func gitFinalBody(from summary: GitRepositoryFinalSummary) -> String {
        var lines: [String] = []
        if let branchName = summary.branchName {
            lines.append("Branch: \(branchName)")
        }
        if let headSHA = summary.headSHA {
            lines.append("HEAD: \(shortSHA(headSHA))")
        }
        if summary.sessionObservedChangedPaths.isEmpty {
            lines.append("Session-observed changed paths: none")
        } else {
            lines.append("Session-observed changed paths: \(summary.sessionObservedChangedPaths.joined(separator: ", "))")
        }
        if !summary.unobservedChangedPaths.isEmpty {
            lines.append("Other final changed paths: \(summary.unobservedChangedPaths.joined(separator: ", "))")
        }
        if !summary.diffStat.lines.isEmpty {
            lines.append("Diff stat:")
            lines.append(contentsOf: summary.diffStat.lines)
        }
        if !summary.commitsAfterStart.isEmpty {
            lines.append("Commits after start:")
            lines.append(contentsOf: summary.commitsAfterStart.map { "- \(shortSHA($0.hash)) \($0.subject)" })
        }
        if summary.status.isOutputTruncated || summary.diffStat.isOutputTruncated {
            lines.append("Git output was truncated.")
        }
        return lines.joined(separator: "\n")
    }

    private func shortSHA(_ sha: String) -> String {
        String(sha.prefix(12))
    }

    private func publishSummary() {
        onSummaryChange?(state?.summary ?? ObservationSessionSummary())
    }
}

private struct ObservationState {
    let session: WorkSession
    let project: Project
    var initialGitHead: String?
    var summary = ObservationSessionSummary()
}
