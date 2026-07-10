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
}

struct ProjectHistory: Equatable, Sendable {
    let projectID: Project.ID
    var sessions: [WorkSession]
    var snapshotsBySessionID: [WorkSession.ID: Snapshot]
    var blocksBySessionID: [WorkSession.ID: [PomodoroBlock]]
    var incrementsByBlockID: [PomodoroBlock.ID: [WorkIncrement]]
    var eventsBySessionID: [WorkSession.ID: [SessionEvent]]
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
        presentedSnapshotsByProjectID[projectID] = snapshot
    }

    func dismissPresentedSnapshot(for projectID: Project.ID) {
        presentedSnapshotsByProjectID[projectID] = nil
    }

    func selectSession(_ session: WorkSession) {
        presentedSnapshotsByProjectID[session.projectID] = nil
        selectedSessionIDsByProjectID[session.projectID] = session.id
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

    func snapshot(for session: WorkSession) -> Snapshot? {
        historiesByProjectID[session.projectID]?.snapshotsBySessionID[session.id]
    }

    func session(for snapshot: Snapshot, projectID: Project.ID) -> WorkSession? {
        historiesByProjectID[projectID]?.sessions.first { $0.id == snapshot.sessionID }
            ?? summariesByProjectID[projectID]?.latestSnapshotSession
    }

    func blocks(for session: WorkSession) -> [PomodoroBlock] {
        historiesByProjectID[session.projectID]?.blocksBySessionID[session.id] ?? []
    }

    func increments(for block: PomodoroBlock, projectID: Project.ID) -> [WorkIncrement] {
        historiesByProjectID[projectID]?.incrementsByBlockID[block.id] ?? []
    }

    func events(for session: WorkSession) -> [SessionEvent] {
        historiesByProjectID[session.projectID]?.eventsBySessionID[session.id] ?? []
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
