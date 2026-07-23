import SwiftUI

enum ProjectAccessState: Equatable {
    case unknown
    case checking
    case accessible
    case inaccessible

    var isInaccessible: Bool {
        self == .inaccessible
    }
}

struct ProjectDashboardSummary: Equatable, Sendable {
    let projectID: Project.ID
    var latestSnapshot: Snapshot?
    var latestSnapshotSession: WorkSession?
    var completedSessionCount: Int
    var completedBlockCount: Int

    func belongs(to projectID: Project.ID) -> Bool {
        guard self.projectID == projectID else {
            return false
        }

        guard let latestSnapshot else {
            return latestSnapshotSession == nil
        }

        guard let latestSnapshotSession else {
            return false
        }

        return latestSnapshotSession.projectID == projectID
            && latestSnapshot.sessionID == latestSnapshotSession.id
    }
}

struct ProjectHistory: Equatable, Sendable {
    let projectID: Project.ID
    var sessions: [WorkSession]
    var snapshotsBySessionID: [WorkSession.ID: Snapshot]
    var blocksBySessionID: [WorkSession.ID: [PomodoroBlock]]
    var incrementsByBlockID: [PomodoroBlock.ID: [WorkIncrement]]
    var eventsBySessionID: [WorkSession.ID: [SessionEvent]]

    func belongs(to projectID: Project.ID) -> Bool {
        guard self.projectID == projectID,
              sessions.allSatisfy({ $0.projectID == projectID })
        else {
            return false
        }

        let sessionIDs = Set(sessions.map(\.id))
        guard snapshotsBySessionID.allSatisfy({ sessionID, snapshot in
            sessionIDs.contains(sessionID) && snapshot.sessionID == sessionID
        }), blocksBySessionID.allSatisfy({ sessionID, blocks in
            sessionIDs.contains(sessionID) && blocks.allSatisfy { $0.sessionID == sessionID }
        }), eventsBySessionID.allSatisfy({ sessionID, events in
            sessionIDs.contains(sessionID) && events.allSatisfy { $0.sessionID == sessionID }
        }) else {
            return false
        }

        let blockIDs = Set(blocksBySessionID.values.flatMap { $0 }.map(\.id))
        return incrementsByBlockID.allSatisfy { blockID, increments in
            blockIDs.contains(blockID) && increments.allSatisfy { $0.blockID == blockID }
        }
    }
}

enum ProjectDetailLoadingError: LocalizedError, Equatable {
    case projectMismatch

    var errorDescription: String? {
        "Working Memory received information for the wrong project. Try selecting the project again."
    }
}

protocol ProjectDetailLoading {
    func loadSummary(for projectID: Project.ID) async throws -> ProjectDashboardSummary
    func loadHistory(for projectID: Project.ID) async throws -> ProjectHistory
}

struct RepositoryProjectDetailLoader: ProjectDetailLoading {
    let snapshotRepository: SnapshotRepository
    let sessionRepository: SessionRepository
    let pomodoroBlockRepository: PomodoroBlockRepository
    let workIncrementRepository: WorkIncrementRepository
    let eventRepository: EventRepository

    func loadSummary(for projectID: Project.ID) async throws -> ProjectDashboardSummary {
        async let snapshotResult = snapshotRepository.latestSnapshot(for: projectID)
        async let completedSessionCountResult = sessionRepository.completedSessionCount(for: projectID)
        async let completedBlockCountResult = pomodoroBlockRepository.completedBlockCount(for: projectID)

        let snapshot = try await snapshotResult
        let session: WorkSession?
        if let snapshot {
            session = try await sessionRepository.session(for: snapshot.sessionID)
        } else {
            session = nil
        }

        return try await ProjectDashboardSummary(
            projectID: projectID,
            latestSnapshot: snapshot,
            latestSnapshotSession: session,
            completedSessionCount: completedSessionCountResult,
            completedBlockCount: completedBlockCountResult
        )
    }

    func loadHistory(for projectID: Project.ID) async throws -> ProjectHistory {
        let sessions = try await sessionRepository.listSessions(for: projectID)
        let snapshots = try await snapshotRepository.listSnapshots(for: projectID)
        var blocksBySessionID: [WorkSession.ID: [PomodoroBlock]] = [:]
        var incrementsByBlockID: [PomodoroBlock.ID: [WorkIncrement]] = [:]
        var eventsBySessionID: [WorkSession.ID: [SessionEvent]] = [:]

        for session in sessions {
            try Task.checkCancellation()
            let blocks = try await pomodoroBlockRepository.listBlocks(for: session.id)
            blocksBySessionID[session.id] = blocks
            for block in blocks {
                try Task.checkCancellation()
                incrementsByBlockID[block.id] = try await workIncrementRepository.listIncrements(for: block.id)
            }
            eventsBySessionID[session.id] = try await eventRepository.listEvents(for: session.id)
        }

        return ProjectHistory(
            projectID: projectID,
            sessions: sessions,
            snapshotsBySessionID: Dictionary(uniqueKeysWithValues: snapshots.map { ($0.sessionID, $0) }),
            blocksBySessionID: blocksBySessionID,
            incrementsByBlockID: incrementsByBlockID,
            eventsBySessionID: eventsBySessionID
        )
    }
}

@MainActor
final class ProjectDetailViewModel: ObservableObject {
    @Published private(set) var summariesByProjectID: [Project.ID: ProjectDashboardSummary] = [:]
    @Published private(set) var historiesByProjectID: [Project.ID: ProjectHistory] = [:]
    @Published private(set) var presentedSnapshotsByProjectID: [Project.ID: Snapshot] = [:]
    @Published private(set) var selectedSessionIDsByProjectID: [Project.ID: WorkSession.ID] = [:]
    @Published private(set) var projectAccessStates: [Project.ID: ProjectAccessState] = [:]
    @Published private(set) var loadingSummaryProjectIDs = Set<Project.ID>()
    @Published private(set) var loadingHistoryProjectIDs = Set<Project.ID>()
    @Published private(set) var errorMessage: String?

    private let loader: any ProjectDetailLoading
    private let fileManager: FileManager
    private var summaryRequestTokens: [Project.ID: UUID] = [:]
    private var historyRequestTokens: [Project.ID: UUID] = [:]

    init(loader: any ProjectDetailLoading, fileManager: FileManager = .default) {
        self.loader = loader
        self.fileManager = fileManager
    }

    convenience init(
        snapshotRepository: SnapshotRepository,
        sessionRepository: SessionRepository,
        pomodoroBlockRepository: PomodoroBlockRepository,
        workIncrementRepository: WorkIncrementRepository,
        eventRepository: EventRepository,
        fileManager: FileManager = .default
    ) {
        self.init(
            loader: RepositoryProjectDetailLoader(
                snapshotRepository: snapshotRepository,
                sessionRepository: sessionRepository,
                pomodoroBlockRepository: pomodoroBlockRepository,
                workIncrementRepository: workIncrementRepository,
                eventRepository: eventRepository
            ),
            fileManager: fileManager
        )
    }

    var isShowingError: Binding<Bool> {
        Binding(
            get: { self.errorMessage != nil },
            set: { isShowing in
                if !isShowing {
                    self.errorMessage = nil
                }
            }
        )
    }

    func preloadSummaries(for projectIDs: [Project.ID]) async {
        for projectID in projectIDs where !Task.isCancelled {
            await loadSummary(for: projectID)
        }
    }

    func loadProject(for projectID: Project.ID, forceRefresh: Bool = false) async {
        async let summary: Void = loadSummary(for: projectID, forceRefresh: forceRefresh)
        async let history: Void = loadHistory(for: projectID, forceRefresh: forceRefresh)
        _ = await (summary, history)
    }

    func loadSummary(for projectID: Project.ID, forceRefresh: Bool = false) async {
        guard forceRefresh || (
            summariesByProjectID[projectID] == nil
                && !loadingSummaryProjectIDs.contains(projectID)
        ) else {
            return
        }

        let token = UUID()
        summaryRequestTokens[projectID] = token
        loadingSummaryProjectIDs.insert(projectID)
        defer {
            if summaryRequestTokens[projectID] == token {
                summaryRequestTokens[projectID] = nil
                loadingSummaryProjectIDs.remove(projectID)
            }
        }

        do {
            let summary = try await loader.loadSummary(for: projectID)
            guard !Task.isCancelled, summaryRequestTokens[projectID] == token else {
                return
            }
            guard summary.belongs(to: projectID) else {
                throw ProjectDetailLoadingError.projectMismatch
            }
            summariesByProjectID[projectID] = summary
        } catch is CancellationError {
            return
        } catch {
            guard summaryRequestTokens[projectID] == token else {
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    func loadHistory(for projectID: Project.ID, forceRefresh: Bool = false) async {
        guard forceRefresh || (
            historiesByProjectID[projectID] == nil
                && !loadingHistoryProjectIDs.contains(projectID)
        ) else {
            return
        }

        let token = UUID()
        historyRequestTokens[projectID] = token
        loadingHistoryProjectIDs.insert(projectID)
        defer {
            if historyRequestTokens[projectID] == token {
                historyRequestTokens[projectID] = nil
                loadingHistoryProjectIDs.remove(projectID)
            }
        }

        do {
            let history = try await loader.loadHistory(for: projectID)
            guard !Task.isCancelled, historyRequestTokens[projectID] == token else {
                return
            }
            guard history.belongs(to: projectID) else {
                throw ProjectDetailLoadingError.projectMismatch
            }
            historiesByProjectID[projectID] = history
            if let selectedSessionID = selectedSessionIDsByProjectID[projectID],
               !history.sessions.contains(where: { $0.id == selectedSessionID }) {
                selectedSessionIDsByProjectID[projectID] = nil
            }
        } catch is CancellationError {
            return
        } catch {
            guard historyRequestTokens[projectID] == token else {
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    func refreshProject(_ projectID: Project.ID) async {
        await loadProject(for: projectID, forceRefresh: true)
    }

    func removeProject(_ projectID: Project.ID) {
        summaryRequestTokens[projectID] = nil
        historyRequestTokens[projectID] = nil
        loadingSummaryProjectIDs.remove(projectID)
        loadingHistoryProjectIDs.remove(projectID)
        summariesByProjectID[projectID] = nil
        historiesByProjectID[projectID] = nil
        presentedSnapshotsByProjectID[projectID] = nil
        selectedSessionIDsByProjectID[projectID] = nil
        projectAccessStates[projectID] = nil
    }

    func retainProjects(_ projectIDs: Set<Project.ID>) {
        let cachedProjectIDs = Set(summariesByProjectID.keys)
            .union(historiesByProjectID.keys)
            .union(presentedSnapshotsByProjectID.keys)
            .union(selectedSessionIDsByProjectID.keys)
            .union(projectAccessStates.keys)
            .union(summaryRequestTokens.keys)
            .union(historyRequestTokens.keys)
            .union(loadingSummaryProjectIDs)
            .union(loadingHistoryProjectIDs)
        for projectID in cachedProjectIDs.subtracting(projectIDs) {
            removeProject(projectID)
        }
    }

    func summary(for projectID: Project.ID) -> ProjectDashboardSummary? {
        summariesByProjectID[projectID]
    }

    func history(for projectID: Project.ID) -> ProjectHistory? {
        historiesByProjectID[projectID]
    }

    func isLoadingSummary(for projectID: Project.ID) -> Bool {
        loadingSummaryProjectIDs.contains(projectID)
    }

    func isLoadingHistory(for projectID: Project.ID) -> Bool {
        loadingHistoryProjectIDs.contains(projectID)
    }

    func checkProjectAccess(for project: Project) async {
        projectAccessStates[project.id] = .checking
        projectAccessStates[project.id] = isReadableDirectory(at: project.rootPath) ? .accessible : .inaccessible
    }

    func projectAccessState(for projectID: Project.ID) -> ProjectAccessState {
        projectAccessStates[projectID] ?? .unknown
    }

    func presentedSnapshot(for projectID: Project.ID) -> Snapshot? {
        presentedSnapshotsByProjectID[projectID]
    }

    func presentLatestSnapshot(for projectID: Project.ID) {
        presentedSnapshotsByProjectID[projectID] = summary(for: projectID)?.latestSnapshot
    }

    func presentGeneratedSnapshot(_ snapshot: Snapshot, for projectID: Project.ID) {
        presentedSnapshotsByProjectID[projectID] = snapshot
        guard var summary = summariesByProjectID[projectID] else {
            return
        }
        summary.latestSnapshot = snapshot
        summary.latestSnapshotSession = historiesByProjectID[projectID]?.sessions.first {
            $0.id == snapshot.sessionID
        }
        summariesByProjectID[projectID] = summary
    }

    func presentSnapshot(_ snapshot: Snapshot, for projectID: Project.ID) {
        guard historiesByProjectID[projectID]?.snapshotsBySessionID[snapshot.sessionID] == snapshot else {
            return
        }
        presentedSnapshotsByProjectID[projectID] = snapshot
    }

    func dismissPresentedSnapshot(for projectID: Project.ID) {
        presentedSnapshotsByProjectID[projectID] = nil
    }

    func resetNavigation(for projectID: Project.ID) {
        presentedSnapshotsByProjectID[projectID] = nil
        selectedSessionIDsByProjectID[projectID] = nil
    }

    func selectSession(_ session: WorkSession, for projectID: Project.ID) {
        guard session.projectID == projectID,
              historiesByProjectID[projectID]?.sessions.contains(where: { $0.id == session.id }) == true
        else {
            return
        }
        presentedSnapshotsByProjectID[projectID] = nil
        selectedSessionIDsByProjectID[projectID] = session.id
    }

    func selectSession(id sessionID: WorkSession.ID, for projectID: Project.ID) {
        guard let session = historiesByProjectID[projectID]?.sessions.first(where: { $0.id == sessionID }) else {
            return
        }
        selectSession(session, for: projectID)
    }

    func clearSelectedSession(for projectID: Project.ID) {
        selectedSessionIDsByProjectID[projectID] = nil
    }

    func selectedSessionID(for projectID: Project.ID) -> WorkSession.ID? {
        selectedSessionIDsByProjectID[projectID]
    }

    func selectedSession(for projectID: Project.ID) -> WorkSession? {
        guard let selectedSessionID = selectedSessionIDsByProjectID[projectID] else {
            return nil
        }
        return historiesByProjectID[projectID]?.sessions.first { $0.id == selectedSessionID }
    }

    func snapshot(for session: WorkSession, projectID: Project.ID) -> Snapshot? {
        guard session.projectID == projectID,
              historiesByProjectID[projectID]?.sessions.contains(where: { $0.id == session.id }) == true,
              let snapshot = historiesByProjectID[projectID]?.snapshotsBySessionID[session.id],
              snapshot.sessionID == session.id
        else {
            return nil
        }
        return snapshot
    }

    func session(for snapshot: Snapshot, projectID: Project.ID) -> WorkSession? {
        if let session = historiesByProjectID[projectID]?.sessions.first(where: {
            $0.id == snapshot.sessionID && $0.projectID == projectID
        }) {
            return session
        }

        guard let latestSession = summariesByProjectID[projectID]?.latestSnapshotSession,
              latestSession.id == snapshot.sessionID,
              latestSession.projectID == projectID
        else {
            return nil
        }
        return latestSession
    }

    func blocks(for session: WorkSession, projectID: Project.ID) -> [PomodoroBlock] {
        guard session.projectID == projectID,
              historiesByProjectID[projectID]?.sessions.contains(where: { $0.id == session.id }) == true
        else {
            return []
        }
        return historiesByProjectID[projectID]?.blocksBySessionID[session.id] ?? []
    }

    func increments(for block: PomodoroBlock, projectID: Project.ID) -> [WorkIncrement] {
        guard historiesByProjectID[projectID]?.blocksBySessionID[block.sessionID]?.contains(
            where: { $0.id == block.id }
        ) == true else {
            return []
        }
        return historiesByProjectID[projectID]?.incrementsByBlockID[block.id] ?? []
    }

    func events(for session: WorkSession, projectID: Project.ID) -> [SessionEvent] {
        guard session.projectID == projectID,
              historiesByProjectID[projectID]?.sessions.contains(where: { $0.id == session.id }) == true
        else {
            return []
        }
        return historiesByProjectID[projectID]?.eventsBySessionID[session.id] ?? []
    }

    func evidenceDigest(
        for session: WorkSession,
        project: Project
    ) -> SnapshotEvidenceDigest? {
        guard session.projectID == project.id,
              let history = historiesByProjectID[project.id],
              history.sessions.contains(where: { $0.id == session.id })
        else {
            return nil
        }

        let blocks = history.blocksBySessionID[session.id] ?? []
        let incrementsByBlockID = Dictionary(
            uniqueKeysWithValues: blocks.map {
                ($0.id, history.incrementsByBlockID[$0.id] ?? [])
            }
        )
        return EvidenceCompactor().compact(
            project: project,
            session: session,
            events: history.eventsBySessionID[session.id] ?? [],
            pomodoroBlocks: blocks,
            workIncrementsByBlockID: incrementsByBlockID
        )
    }

    func clearError() {
        errorMessage = nil
    }

    private func isReadableDirectory(at path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: path, isDirectory: &isDirectory)
            && isDirectory.boolValue
            && fileManager.isReadableFile(atPath: path)
    }
}
