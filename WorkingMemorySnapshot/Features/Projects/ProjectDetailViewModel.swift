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
    @Published private(set) var projectAccessState: ProjectAccessState = .unknown
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoadingSnapshot = false

    private let snapshotRepository: SnapshotRepository
    private let sessionRepository: SessionRepository
    private let fileManager: FileManager
    private var requestedProjectID: Project.ID?

    init(
        snapshotRepository: SnapshotRepository,
        sessionRepository: SessionRepository,
        fileManager: FileManager = .default
    ) {
        self.snapshotRepository = snapshotRepository
        self.sessionRepository = sessionRepository
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
            guard requestedProjectID == projectID else {
                return
            }

            latestSnapshot = snapshot
            latestSnapshotSession = session
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

    func dismissPresentedSnapshot() {
        presentedSnapshot = nil
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
