import XCTest
@testable import WorkingMemorySnapshot

@MainActor
final class ProjectsViewModelTests: XCTestCase {
    private var temporaryURLs: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryURLs {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryURLs.removeAll()
    }

    func testRestoreProjectAccessUpdatesSelectedProjectPath() async throws {
        let harness = try makeHarness()
        let viewModel = ProjectsViewModel(
            repository: harness.repository,
            migrator: harness.migrator
        )
        let originalFolder = try makeTemporaryDirectory(named: "MovedProject")
        let restoredFolder = try makeTemporaryDirectory(named: "MovedProjectRestored")

        await viewModel.loadProjects()
        await viewModel.addProject(at: originalFolder)
        let project = try XCTUnwrap(viewModel.selectedProject)

        let restoredProject = await viewModel.restoreProjectAccess(for: project, to: restoredFolder)

        XCTAssertEqual(restoredProject?.id, project.id)
        XCTAssertEqual(
            viewModel.selectedProject?.rootPath,
            restoredFolder.standardizedFileURL.resolvingSymlinksInPath().path
        )
        XCTAssertNil(viewModel.errorMessage)
    }

    func testRestoreProjectAccessReportsDuplicatePath() async throws {
        let harness = try makeHarness()
        let viewModel = ProjectsViewModel(
            repository: harness.repository,
            migrator: harness.migrator
        )
        let firstFolder = try makeTemporaryDirectory(named: "FirstProject")
        let secondFolder = try makeTemporaryDirectory(named: "SecondProject")

        await viewModel.loadProjects()
        await viewModel.addProject(at: firstFolder)
        let firstProject = try XCTUnwrap(viewModel.selectedProject)
        await viewModel.addProject(at: secondFolder)

        let restoredProject = await viewModel.restoreProjectAccess(for: firstProject, to: secondFolder)

        XCTAssertNil(restoredProject)
        XCTAssertEqual(viewModel.errorMessage, "That project is already in the list.")
    }

    private func makeHarness() throws -> (
        database: Database,
        migrator: DatabaseMigrator,
        repository: ProjectRepository
    ) {
        let rootDirectory = try makeTemporaryDirectory(named: "DatabaseRoot")
        let database = Database(url: rootDirectory.appendingPathComponent("working-memory.sqlite3"))
        let migrator = DatabaseMigrator(database: database)
        let repository = ProjectRepository(database: database)

        return (database, migrator, repository)
    }

    private func makeTemporaryDirectory(named name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkingMemorySnapshotTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)

        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        temporaryURLs.append(url.deletingLastPathComponent())
        return url
    }
}
