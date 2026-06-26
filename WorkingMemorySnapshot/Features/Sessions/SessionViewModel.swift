import SwiftUI

enum SessionFlow: Equatable {
    case idle
    case starting(Project.ID)
    case ending(WorkSession.ID)
}

struct SessionRecoveryContext: Equatable {
    let session: WorkSession
    let project: Project
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
    @Published var mission = ""
    @Published var brainDump = ""
    @Published private(set) var errorMessage: String?
    @Published private(set) var isWorking = false
    @Published private(set) var observationSummary = ObservationSessionSummary()

    private let sessionRepository: SessionRepository
    private let projectRepository: ProjectRepository
    private let snapshotGenerator: any SessionSnapshotGenerating
    private let observationCoordinator: any SessionObservationCoordinating
    private let fileManager: FileManager

    init(
        sessionRepository: SessionRepository,
        projectRepository: ProjectRepository,
        snapshotGenerator: any SessionSnapshotGenerating,
        observationCoordinator: any SessionObservationCoordinating,
        fileManager: FileManager = .default
    ) {
        self.sessionRepository = sessionRepository
        self.projectRepository = projectRepository
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
                recoveryContext = nil
                return
            }

            activeSession = session
            if let project = try await projectRepository.project(for: session.projectID) {
                recoveryContext = SessionRecoveryContext(
                    session: session,
                    project: project
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

            activeSession = session
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
            await observationCoordinator.stopObservingForCompletion(
                session: endingSession,
                brainDump: endingBrainDump
            )
            let completedSession = try await sessionRepository.completeSession(
                id: endingSession.id,
                brainDump: endingBrainDump
            )

            self.activeSession = nil
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
            await observationCoordinator.stopObservingForCancellation(session: activeSession)
            _ = try await sessionRepository.cancelSession(id: activeSession.id)
            self.activeSession = nil
            recoveryContext = nil
            brainDump = ""
            flow = .idle
        }
    }

    func resumeRecoveredSession() {
        guard let recoveryContext else {
            return
        }

        activeSession = recoveryContext.session
        self.recoveryContext = nil
        flow = .idle
        Task {
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

    private func validateAccess(to project: Project) throws {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: project.rootPath, isDirectory: &isDirectory),
              isDirectory.boolValue,
              fileManager.isReadableFile(atPath: project.rootPath)
        else {
            throw SessionViewModelError.projectFolderInaccessible
        }
    }
}

enum SessionViewModelError: Error, LocalizedError {
    case projectFolderInaccessible
    case projectMissing

    var errorDescription: String? {
        switch self {
        case .projectFolderInaccessible:
            "This project folder is no longer accessible."
        case .projectMissing:
            "The project for this session could not be found."
        }
    }
}
