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

@MainActor
final class ProjectDetailViewModel: ObservableObject {
    @Published private(set) var latestSnapshot: Snapshot?
    @Published private(set) var latestSnapshotSession: WorkSession?
    @Published private(set) var presentedSnapshot: Snapshot?
    @Published private(set) var sessions: [WorkSession] = []
    @Published private(set) var snapshotsBySessionID: [WorkSession.ID: Snapshot] = [:]
    @Published private(set) var blocksBySessionID: [WorkSession.ID: [PomodoroBlock]] = [:]
    @Published private(set) var incrementsByBlockID: [PomodoroBlock.ID: [WorkIncrement]] = [:]
    @Published private(set) var eventsBySessionID: [WorkSession.ID: [SessionEvent]] = [:]
    @Published private(set) var selectedSessionID: WorkSession.ID?
    @Published private(set) var projectAccessState: ProjectAccessState = .unknown
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoadingSnapshot = false

    private let snapshotRepository: SnapshotRepository
    private let sessionRepository: SessionRepository
    private let pomodoroBlockRepository: PomodoroBlockRepository
    private let workIncrementRepository: WorkIncrementRepository
    private let eventRepository: EventRepository
    private let fileManager: FileManager
    private var requestedProjectID: Project.ID?

    init(
        snapshotRepository: SnapshotRepository,
        sessionRepository: SessionRepository,
        pomodoroBlockRepository: PomodoroBlockRepository,
        workIncrementRepository: WorkIncrementRepository,
        eventRepository: EventRepository,
        fileManager: FileManager = .default
    ) {
        self.snapshotRepository = snapshotRepository
        self.sessionRepository = sessionRepository
        self.pomodoroBlockRepository = pomodoroBlockRepository
        self.workIncrementRepository = workIncrementRepository
        self.eventRepository = eventRepository
        self.fileManager = fileManager
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

    func loadLatestSnapshot(for projectID: Project.ID) async {
        requestedProjectID = projectID
        isLoadingSnapshot = true
        defer {
            isLoadingSnapshot = false
        }

        do {
            let snapshot = try await snapshotRepository.latestSnapshot(for: projectID)
            let session: WorkSession?
            if let snapshot {
                session = try await sessionRepository.session(for: snapshot.sessionID)
            } else {
                session = nil
            }
            let sessions = try await sessionRepository.listSessions(for: projectID)
            let snapshots = try await snapshotRepository.listSnapshots(for: projectID)
            var blocksBySessionID: [WorkSession.ID: [PomodoroBlock]] = [:]
            var incrementsByBlockID: [PomodoroBlock.ID: [WorkIncrement]] = [:]
            var eventsBySessionID: [WorkSession.ID: [SessionEvent]] = [:]

            for session in sessions {
                let blocks = try await pomodoroBlockRepository.listBlocks(for: session.id)
                blocksBySessionID[session.id] = blocks
                for block in blocks {
                    incrementsByBlockID[block.id] = try await workIncrementRepository.listIncrements(for: block.id)
                }
                eventsBySessionID[session.id] = try await eventRepository.listEvents(for: session.id)
            }

            guard requestedProjectID == projectID else {
                return
            }

            latestSnapshot = snapshot
            latestSnapshotSession = session
            self.sessions = sessions
            snapshotsBySessionID = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.sessionID, $0) })
            self.blocksBySessionID = blocksBySessionID
            self.incrementsByBlockID = incrementsByBlockID
            self.eventsBySessionID = eventsBySessionID
            if let selectedSessionID,
               !sessions.contains(where: { $0.id == selectedSessionID }) {
                self.selectedSessionID = nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func checkProjectAccess(for project: Project) async {
        projectAccessState = .checking
        projectAccessState = isReadableDirectory(at: project.rootPath) ? .accessible : .inaccessible
    }

    func presentLatestSnapshot() {
        presentedSnapshot = latestSnapshot
    }

    func presentGeneratedSnapshot(_ snapshot: Snapshot) {
        latestSnapshot = snapshot
        presentedSnapshot = snapshot
    }

    func presentSnapshot(_ snapshot: Snapshot) {
        presentedSnapshot = snapshot
    }

    func dismissPresentedSnapshot() {
        presentedSnapshot = nil
    }

    func selectSession(_ session: WorkSession) {
        presentedSnapshot = nil
        selectedSessionID = session.id
    }

    func clearSelectedSession() {
        selectedSessionID = nil
    }

    var selectedSession: WorkSession? {
        guard let selectedSessionID else {
            return nil
        }
        return sessions.first { $0.id == selectedSessionID }
    }

    func snapshot(for session: WorkSession) -> Snapshot? {
        snapshotsBySessionID[session.id]
    }

    func session(for snapshot: Snapshot) -> WorkSession? {
        sessions.first { $0.id == snapshot.sessionID } ?? latestSnapshotSession
    }

    func blocks(for session: WorkSession) -> [PomodoroBlock] {
        blocksBySessionID[session.id] ?? []
    }

    func increments(for block: PomodoroBlock) -> [WorkIncrement] {
        incrementsByBlockID[block.id] ?? []
    }

    func events(for session: WorkSession) -> [SessionEvent] {
        eventsBySessionID[session.id] ?? []
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
