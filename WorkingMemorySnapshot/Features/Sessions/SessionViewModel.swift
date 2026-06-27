import SwiftUI

enum SessionFlow: Equatable {
    case idle
    case starting(Project.ID)
    case ending(WorkSession.ID)
}

struct SessionRecoveryContext: Equatable {
    let session: WorkSession
    let project: Project
    let isProjectFolderAccessible: Bool
}

struct GeneratedSnapshotContext: Equatable {
    let projectID: Project.ID
    let snapshot: Snapshot
}

@MainActor
final class SessionViewModel: ObservableObject {
    @Published private(set) var activeSession: WorkSession?
    @Published private(set) var recoveryContext: SessionRecoveryContext?
    @Published private(set) var generatedSnapshotContext: GeneratedSnapshotContext?
    @Published private(set) var failedSnapshotSession: WorkSession?
    @Published private(set) var flow: SessionFlow = .idle
    @Published private(set) var activeBlock: PomodoroBlock?
    @Published private(set) var sessionBlocks: [PomodoroBlock] = []
    @Published private(set) var activeBlockIncrements: [WorkIncrement] = []
    @Published var mission = ""
    @Published var brainDump = ""
    @Published private(set) var errorMessage: String?
    @Published private(set) var isWorking = false
    @Published private(set) var observationSummary = ObservationSessionSummary()

    private let sessionRepository: SessionRepository
    private let projectRepository: ProjectRepository
    private let pomodoroBlockRepository: PomodoroBlockRepository
    private let workIncrementRepository: WorkIncrementRepository
    private let snapshotGenerator: any SessionSnapshotGenerating
    private let observationCoordinator: any SessionObservationCoordinating
    private let fileManager: FileManager

    init(
        sessionRepository: SessionRepository,
        projectRepository: ProjectRepository,
        pomodoroBlockRepository: PomodoroBlockRepository,
        workIncrementRepository: WorkIncrementRepository,
        snapshotGenerator: any SessionSnapshotGenerating,
        observationCoordinator: any SessionObservationCoordinating,
        fileManager: FileManager = .default
    ) {
        self.sessionRepository = sessionRepository
        self.projectRepository = projectRepository
        self.pomodoroBlockRepository = pomodoroBlockRepository
        self.workIncrementRepository = workIncrementRepository
        self.snapshotGenerator = snapshotGenerator
        self.observationCoordinator = observationCoordinator
        self.fileManager = fileManager
        self.observationCoordinator.onSummaryChange = { [weak self] summary in
            self?.observationSummary = summary
        }
    }

    var canStartSession: Bool {
        activeSession == nil
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

    var isShowingRecoverySheet: Binding<Bool> {
        Binding(
            get: { self.recoveryContext != nil },
            set: { _ in }
        )
    }

    func loadActiveSessionForRecovery() async {
        do {
            guard let session = try await sessionRepository.activeSession() else {
                activeSession = nil
                activeBlock = nil
                sessionBlocks = []
                activeBlockIncrements = []
                recoveryContext = nil
                return
            }

            activeSession = session
            try await ensureAndLoadBlocks(for: session)
            if let project = try await projectRepository.project(for: session.projectID) {
                recoveryContext = SessionRecoveryContext(
                    session: session,
                    project: project,
                    isProjectFolderAccessible: isReadableDirectory(at: project.rootPath)
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func beginStartSession(for project: Project) {
        guard canStartSession else {
            errorMessage = SessionRepositoryError.activeSessionAlreadyExists.localizedDescription
            return
        }

        mission = ""
        brainDump = ""
        flow = .starting(project.id)
    }

    func dismissStartSession() {
        mission = ""
        flow = .idle
    }

    func startSession(for project: Project) async {
        await performSessionUpdate {
            try validateAccess(to: project)
            let session = try await sessionRepository.createActiveSession(
                projectID: project.id,
                mission: mission
            )
            let block = try await pomodoroBlockRepository.createNextBlock(sessionID: session.id)

            activeSession = session
            activeBlock = block
            sessionBlocks = [block]
            activeBlockIncrements = []
            mission = ""
            flow = .idle
            await observationCoordinator.startObserving(session: session, project: project)
        }
    }

    func beginEndingActiveSession() {
        guard let activeSession else {
            return
        }

        if brainDump.isEmpty {
            brainDump = activeSession.brainDump ?? ""
        }
        flow = .ending(activeSession.id)
    }

    func beginEndingRecoveredSession() {
        guard let recoveryContext else {
            return
        }

        activeSession = recoveryContext.session
        brainDump = recoveryContext.session.brainDump ?? ""
        flow = .ending(recoveryContext.session.id)
        self.recoveryContext = nil
    }

    func returnToActiveSession() {
        flow = .idle
    }

    func completeActiveSession() async {
        guard let activeSession else {
            return
        }

        await performSessionUpdate {
            let endingSession = activeSession
            let endingBrainDump = brainDump
            _ = try await pomodoroBlockRepository.interruptOpenBlock(for: endingSession.id)
            await observationCoordinator.stopObservingForCompletion(
                session: endingSession,
                brainDump: endingBrainDump
            )
            let completedSession = try await sessionRepository.completeSession(
                id: endingSession.id,
                brainDump: endingBrainDump
            )

            self.activeSession = nil
            activeBlock = nil
            sessionBlocks = []
            activeBlockIncrements = []
            recoveryContext = nil
            brainDump = ""
            flow = .idle

            do {
                try await saveGeneratedSnapshot(for: completedSession)
                failedSnapshotSession = nil
            } catch {
                failedSnapshotSession = completedSession
                throw error
            }
        }
    }

    func retrySnapshotGeneration() async {
        guard let failedSnapshotSession else {
            return
        }

        await performSessionUpdate {
            try await saveGeneratedSnapshot(for: failedSnapshotSession)
            self.failedSnapshotSession = nil
        }
    }

    func cancelActiveSession() async {
        guard let activeSession else {
            return
        }

        await performSessionUpdate {
            _ = try await pomodoroBlockRepository.interruptOpenBlock(for: activeSession.id)
            await observationCoordinator.stopObservingForCancellation(session: activeSession)
            _ = try await sessionRepository.cancelSession(id: activeSession.id)
            self.activeSession = nil
            activeBlock = nil
            sessionBlocks = []
            activeBlockIncrements = []
            recoveryContext = nil
            brainDump = ""
            flow = .idle
        }
    }

    func resumeRecoveredSession() {
        guard let recoveryContext else {
            return
        }

        guard recoveryContext.isProjectFolderAccessible else {
            errorMessage = SessionViewModelError.projectFolderInaccessible.localizedDescription
            return
        }

        activeSession = recoveryContext.session
        self.recoveryContext = nil
        flow = .idle
        Task {
            try? await self.ensureAndLoadBlocks(for: recoveryContext.session)
            await observationCoordinator.startObserving(
                session: recoveryContext.session,
                project: recoveryContext.project
            )
        }
    }

    func cancelRecoveredSession() async {
        guard let recoveryContext else {
            return
        }

        activeSession = recoveryContext.session
        await cancelActiveSession()
    }

    func updateRecoveredProject(_ project: Project) {
        guard let recoveryContext, recoveryContext.project.id == project.id else {
            return
        }

        self.recoveryContext = SessionRecoveryContext(
            session: recoveryContext.session,
            project: project,
            isProjectFolderAccessible: isReadableDirectory(at: project.rootPath)
        )
    }

    func isStartingSession(for project: Project) -> Bool {
        flow == .starting(project.id)
    }

    func isEndingSession(_ session: WorkSession) -> Bool {
        flow == .ending(session.id)
    }

    func clearError() {
        errorMessage = nil
    }

    func clearGeneratedSnapshotContext() {
        generatedSnapshotContext = nil
    }

    func pauseCurrentBlock() async {
        guard let activeBlock, activeBlock.status == .active else {
            return
        }

        await performSessionUpdate {
            let paused = try await pomodoroBlockRepository.pauseBlock(id: activeBlock.id)
            self.activeBlock = paused
            try await loadBlocksAndIncrements(for: paused.sessionID)
        }
    }

    func resumeCurrentBlock() async {
        guard let activeBlock, activeBlock.status == .paused else {
            return
        }

        await performSessionUpdate {
            let resumed = try await pomodoroBlockRepository.resumeBlock(id: activeBlock.id)
            self.activeBlock = resumed
            try await loadBlocksAndIncrements(for: resumed.sessionID)
        }
    }

    func completeCurrentBlock(summary: String? = nil) async {
        guard let activeBlock else {
            return
        }

        await performSessionUpdate {
            _ = try await pomodoroBlockRepository.completeBlock(id: activeBlock.id, summary: summary)
            self.activeBlock = nil
            self.activeBlockIncrements = []
            try await loadBlocksAndIncrements(for: activeBlock.sessionID)
        }
    }

    func startNextBlock(intention: String? = nil) async {
        guard let activeSession else {
            return
        }

        await performSessionUpdate {
            let block = try await pomodoroBlockRepository.createNextBlock(
                sessionID: activeSession.id,
                intention: intention
            )
            self.activeBlock = block
            self.activeBlockIncrements = []
            try await loadBlocksAndIncrements(for: activeSession.id)
        }
    }

    func addIncrement(kind: WorkIncrementKind, title: String, detail: String?) async {
        guard let activeBlock else {
            errorMessage = "Start a focus block before adding a work increment."
            return
        }

        await performSessionUpdate {
            _ = try await workIncrementRepository.addIncrement(
                blockID: activeBlock.id,
                kind: kind,
                title: title,
                detail: detail
            )
            try await loadBlocksAndIncrements(for: activeBlock.sessionID)
        }
    }

    private func performSessionUpdate(_ body: () async throws -> Void) async {
        guard !isWorking else {
            return
        }

        isWorking = true
        defer {
            isWorking = false
        }

        do {
            try await body()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveGeneratedSnapshot(for session: WorkSession) async throws {
        guard let project = try await projectRepository.project(for: session.projectID) else {
            throw SessionViewModelError.projectMissing
        }

        let snapshot = try await snapshotGenerator.generateSnapshot(
            for: project,
            session: session
        )
        generatedSnapshotContext = GeneratedSnapshotContext(
            projectID: session.projectID,
            snapshot: snapshot
        )
    }

    private func ensureAndLoadBlocks(for session: WorkSession) async throws {
        activeBlock = try await pomodoroBlockRepository.ensureFirstBlock(for: session.id)
        try await loadBlocksAndIncrements(for: session.id)
    }

    private func loadBlocksAndIncrements(for sessionID: WorkSession.ID) async throws {
        let blocks = try await pomodoroBlockRepository.listBlocks(for: sessionID)
        sessionBlocks = blocks
        activeBlock = blocks.first(where: \.isOpen)
        if let activeBlock {
            activeBlockIncrements = try await workIncrementRepository.listIncrements(for: activeBlock.id)
        } else {
            activeBlockIncrements = []
        }
    }

    private func validateAccess(to project: Project) throws {
        guard isReadableDirectory(at: project.rootPath) else {
            throw SessionViewModelError.projectFolderInaccessible
        }
    }

    private func isReadableDirectory(at path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: path, isDirectory: &isDirectory)
            && isDirectory.boolValue
            && fileManager.isReadableFile(atPath: path)
    }
}

enum SessionViewModelError: Error, LocalizedError {
    case projectFolderInaccessible
    case projectMissing

    var errorDescription: String? {
        switch self {
        case .projectFolderInaccessible:
            "This project folder is no longer accessible. Choose the folder again to restore access."
        case .projectMissing:
            "The project for this session could not be found."
        }
    }
}
