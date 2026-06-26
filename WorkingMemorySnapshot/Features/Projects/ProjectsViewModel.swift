import SwiftUI

enum SidebarSelection: Hashable {
    case project(Project.ID)
    case settings
}

@MainActor
final class ProjectsViewModel: ObservableObject {
    @Published private(set) var projects: [Project] = []
    @Published var selectedItem: SidebarSelection?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoading = false

    private let repository: ProjectRepository
    private let migrator: DatabaseMigrator

    init(repository: ProjectRepository, migrator: DatabaseMigrator) {
        self.repository = repository
        self.migrator = migrator
    }

    var selectedProject: Project? {
        guard case .project(let selectedProjectID) = selectedItem else {
            return nil
        }

        return projects.first { $0.id == selectedProjectID }
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
            if case .settings = selectedItem {
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
            selectedItem = .project(project.id)
        } catch {
            errorMessage = error.localizedDescription
            projects = (try? await repository.listProjects()) ?? projects
        }
    }

    func clearError() {
        errorMessage = nil
    }

    func selectProject(id: Project.ID) {
        selectedItem = .project(id)
    }
}
