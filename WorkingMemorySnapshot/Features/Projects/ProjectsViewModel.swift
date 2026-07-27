import SwiftUI

enum SidebarSelection: Hashable {
    case dailyRollup
    case project(Project.ID)
    case settings
}

struct ProjectSidebarMetadata: Equatable {
    var sessionCount: Int
    var latestCompletedSessionEndedAt: Date?
    var hasSnapshot: Bool
}

@MainActor
final class ProjectsViewModel: ObservableObject {
    @Published private(set) var projects: [Project] = []
    @Published private(set) var sidebarMetadata: [Project.ID: ProjectSidebarMetadata] = [:]
    @Published var selectedItem: SidebarSelection?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoading = false

    private let repository: ProjectRepository
    private let sessionRepository: SessionRepository
    private let snapshotRepository: SnapshotRepository
    private let migrator: DatabaseMigrator

    init(
        repository: ProjectRepository,
        sessionRepository: SessionRepository,
        snapshotRepository: SnapshotRepository,
        migrator: DatabaseMigrator
    ) {
        self.repository = repository
        self.sessionRepository = sessionRepository
        self.snapshotRepository = snapshotRepository
        self.migrator = migrator
    }

    var selectedProject: Project? {
        guard case .project(let selectedProjectID) = selectedItem else {
            return nil
        }

        return projects.first { $0.id == selectedProjectID }
    }

    var pinnedProjects: [Project] {
        projects.filter(\.isPinned)
    }

    var unpinnedProjects: [Project] {
        projects.filter { !$0.isPinned }
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

    func loadProjects() async {
        isLoading = true
        defer {
            isLoading = false
        }

        do {
            try await migrator.migrate()
            projects = try await repository.listProjects()
            sidebarMetadata = try await loadSidebarMetadata(for: projects)
            if case .settings = selectedItem {
                return
            }
            if case .dailyRollup = selectedItem {
                return
            }
            if let selectedProject = selectedProject {
                selectedItem = .project(selectedProject.id)
            } else {
                selectedItem = projects.first.map { .project($0.id) }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addProjectFromPicker() async {
        guard let url = ProjectFolderPicker.pickFolder() else {
            return
        }

        await addProject(at: url)
    }

    func addProject(at url: URL) async {
        do {
            let project = try await repository.createProject(at: url)
            projects = try await repository.listProjects()
            sidebarMetadata = try await loadSidebarMetadata(for: projects)
            selectedItem = .project(project.id)
        } catch {
            errorMessage = error.localizedDescription
            projects = (try? await repository.listProjects()) ?? projects
            sidebarMetadata = (try? await loadSidebarMetadata(for: projects)) ?? sidebarMetadata
        }
    }

    func deleteProject(_ project: Project) async {
        do {
            try await repository.deleteProject(id: project.id)
            projects = try await repository.listProjects()
            sidebarMetadata = try await loadSidebarMetadata(for: projects)

            if case .project(let selectedProjectID) = selectedItem, selectedProjectID == project.id {
                selectedItem = projects.isEmpty ? nil : .project(projects[0].id)
            }
        } catch {
            errorMessage = error.localizedDescription
            projects = (try? await repository.listProjects()) ?? projects
            sidebarMetadata = (try? await loadSidebarMetadata(for: projects)) ?? sidebarMetadata
            if case .project(let selectedProjectID) = selectedItem,
               !projects.contains(where: { $0.id == selectedProjectID }) {
                selectedItem = projects.isEmpty ? nil : .project(projects[0].id)
            }
        }
    }

    func renameProject(_ project: Project, to name: String) async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Project name cannot be empty."
            return
        }
        guard trimmedName != project.name else {
            return
        }

        do {
            let renamedProject = try await repository.updateProjectName(id: project.id, to: trimmedName)
            projects = try await repository.listProjects()
            sidebarMetadata = try await loadSidebarMetadata(for: projects)
            selectedItem = .project(renamedProject.id)
        } catch {
            errorMessage = error.localizedDescription
            projects = (try? await repository.listProjects()) ?? projects
            sidebarMetadata = (try? await loadSidebarMetadata(for: projects)) ?? sidebarMetadata
        }
    }

    func setProjectPinned(_ project: Project, isPinned: Bool) async {
        guard project.isPinned != isPinned else {
            return
        }

        do {
            _ = try await repository.setProjectPinned(id: project.id, isPinned: isPinned)
            projects = try await repository.listProjects()
        } catch {
            errorMessage = error.localizedDescription
            projects = (try? await repository.listProjects()) ?? projects
        }
    }

    func moveProject(_ projectID: Project.ID, to targetProjectID: Project.ID) async {
        guard projectID != targetProjectID,
              let project = projects.first(where: { $0.id == projectID }),
              let targetProject = projects.first(where: { $0.id == targetProjectID }),
              project.isPinned == targetProject.isPinned
        else {
            return
        }

        let previousProjects = projects
        var group = projects.filter { $0.isPinned == project.isPinned }
        guard let sourceIndex = group.firstIndex(where: { $0.id == projectID }),
              let originalTargetIndex = group.firstIndex(where: { $0.id == targetProjectID })
        else {
            return
        }

        let movedProject = group.remove(at: sourceIndex)
        guard let targetIndex = group.firstIndex(where: { $0.id == targetProjectID }) else {
            return
        }
        let insertionIndex = sourceIndex < originalTargetIndex ? targetIndex + 1 : targetIndex
        group.insert(movedProject, at: insertionIndex)

        let normalizedGroup = group.enumerated().map { position, project in
            var reorderedProject = project
            reorderedProject.sortOrder = position
            return reorderedProject
        }
        let otherGroup = projects.filter { $0.isPinned != project.isPinned }
        projects = project.isPinned
            ? normalizedGroup + otherGroup
            : otherGroup + normalizedGroup

        do {
            try await repository.reorderProjects(normalizedGroup.map(\.id), pinned: project.isPinned)
            projects = try await repository.listProjects()
        } catch {
            errorMessage = error.localizedDescription
            projects = (try? await repository.listProjects()) ?? previousProjects
        }
    }

    func restoreProjectAccessFromPicker(for project: Project) async -> Project? {
        guard let url = ProjectFolderPicker.pickFolder(prompt: "Restore Access") else {
            return nil
        }

        return await restoreProjectAccess(for: project, to: url)
    }

    func restoreProjectAccess(for project: Project, to url: URL) async -> Project? {
        do {
            let restoredProject = try await repository.updateProjectRoot(id: project.id, to: url)
            projects = try await repository.listProjects()
            sidebarMetadata = try await loadSidebarMetadata(for: projects)
            selectedItem = .project(project.id)
            return restoredProject
        } catch {
            errorMessage = error.localizedDescription
            projects = (try? await repository.listProjects()) ?? projects
            sidebarMetadata = (try? await loadSidebarMetadata(for: projects)) ?? sidebarMetadata
            return nil
        }
    }

    func clearError() {
        errorMessage = nil
    }

    func selectProject(id: Project.ID) {
        selectedItem = .project(id)
    }

    func selectDailyRollup() {
        selectedItem = .dailyRollup
    }

    func selectSettings() {
        selectedItem = .settings
    }

    func refreshSidebarMetadata() async {
        do {
            sidebarMetadata = try await loadSidebarMetadata(for: projects)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadSidebarMetadata(for projects: [Project]) async throws -> [Project.ID: ProjectSidebarMetadata] {
        var values: [Project.ID: ProjectSidebarMetadata] = [:]
        for project in projects {
            let sessions = try await sessionRepository.listSessions(for: project.id)
            let latestCompleted = sessions.first {
                $0.status == .completed && $0.endedAt != nil
            }
            let latestSnapshot = try await snapshotRepository.latestSnapshot(for: project.id)
            values[project.id] = ProjectSidebarMetadata(
                sessionCount: sessions.filter { $0.status == .completed }.count,
                latestCompletedSessionEndedAt: latestCompleted?.endedAt,
                hasSnapshot: latestSnapshot != nil
            )
        }
        return values
    }
}
