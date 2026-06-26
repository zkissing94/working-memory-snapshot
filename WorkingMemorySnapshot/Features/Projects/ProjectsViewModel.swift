import SwiftUI

@MainActor
final class ProjectsViewModel: ObservableObject {
    @Published private(set) var projects: [Project] = []
    @Published var selectedProjectID: Project.ID?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoading = false

    private let repository: ProjectRepository
    private let migrator: DatabaseMigrator

    init(repository: ProjectRepository, migrator: DatabaseMigrator) {
        self.repository = repository
        self.migrator = migrator
    }

    var selectedProject: Project? {
        projects.first { $0.id == selectedProjectID }
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
            if selectedProjectID == nil {
                selectedProjectID = projects.first?.id
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
            selectedProjectID = project.id
        } catch {
            errorMessage = error.localizedDescription
            projects = (try? await repository.listProjects()) ?? projects
        }
    }

    func clearError() {
        errorMessage = nil
    }
}
