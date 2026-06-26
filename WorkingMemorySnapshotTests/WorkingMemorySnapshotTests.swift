//
//  WorkingMemorySnapshotTests.swift
//  WorkingMemorySnapshotTests
//
//  Created by Zachary Kissinger on 6/26/26.
//

import XCTest
@testable import WorkingMemorySnapshot

final class WorkingMemorySnapshotTests: XCTestCase {
    private var temporaryURLs: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryURLs {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryURLs.removeAll()
    }

    func testMigrationIsIdempotent() async throws {
        let harness = try makeHarness()

        try await harness.migrator.migrate()
        try await harness.migrator.migrate()

        let versions = try await harness.migrator.appliedVersions()
        XCTAssertEqual(versions, [1, 2, 3, 4, 5])
    }

    func testCreatesAndListsProjects() async throws {
        let harness = try makeHarness()
        try await harness.migrator.migrate()
        let projectFolder = try makeTemporaryDirectory(named: "ExampleProject")

        let createdProject = try await harness.repository.createProject(at: projectFolder)
        let projects = try await harness.repository.listProjects()

        XCTAssertEqual(projects, [createdProject])
        XCTAssertEqual(projects.first?.name, "ExampleProject")
        XCTAssertEqual(projects.first?.rootPath, projectFolder.standardizedFileURL.resolvingSymlinksInPath().path)
    }

    func testDuplicateRootPathIsRejected() async throws {
        let harness = try makeHarness()
        try await harness.migrator.migrate()
        let projectFolder = try makeTemporaryDirectory(named: "DuplicateProject")

        _ = try await harness.repository.createProject(at: projectFolder)

        do {
            _ = try await harness.repository.createProject(at: projectFolder)
            XCTFail("Expected duplicate project insertion to fail.")
        } catch ProjectRepositoryError.duplicateProject(let rootPath) {
            XCTAssertEqual(rootPath, projectFolder.standardizedFileURL.resolvingSymlinksInPath().path)
        }
    }

    func testUpdateProjectRootRestoresAccessPath() async throws {
        let harness = try makeHarness()
        try await harness.migrator.migrate()
        let originalFolder = try makeTemporaryDirectory(named: "OriginalProject")
        let restoredFolder = try makeTemporaryDirectory(named: "RestoredProject")
        let project = try await harness.repository.createProject(at: originalFolder)

        let restoredProject = try await harness.repository.updateProjectRoot(
            id: project.id,
            to: restoredFolder
        )

        XCTAssertEqual(restoredProject.id, project.id)
        XCTAssertEqual(restoredProject.name, project.name)
        XCTAssertEqual(
            restoredProject.rootPath,
            restoredFolder.standardizedFileURL.resolvingSymlinksInPath().path
        )
        XCTAssertGreaterThanOrEqual(restoredProject.updatedAt, project.updatedAt)
    }

    func testUpdateProjectRootRejectsDuplicateRestoredPath() async throws {
        let harness = try makeHarness()
        try await harness.migrator.migrate()
        let firstFolder = try makeTemporaryDirectory(named: "FirstProject")
        let secondFolder = try makeTemporaryDirectory(named: "SecondProject")
        let firstProject = try await harness.repository.createProject(at: firstFolder)
        _ = try await harness.repository.createProject(at: secondFolder)

        do {
            _ = try await harness.repository.updateProjectRoot(id: firstProject.id, to: secondFolder)
            XCTFail("Expected duplicate project path update to fail.")
        } catch ProjectRepositoryError.duplicateProject(let rootPath) {
            XCTAssertEqual(rootPath, secondFolder.standardizedFileURL.resolvingSymlinksInPath().path)
        }
    }

    func testProjectsPersistAcrossRepositoryReload() async throws {
        let rootDirectory = try makeTemporaryDirectory(named: "DatabaseRoot")
        let databaseURL = rootDirectory.appendingPathComponent("working-memory.sqlite3")
        let projectFolder = try makeTemporaryDirectory(named: "PersistentProject")

        let firstDatabase = Database(url: databaseURL)
        let firstMigrator = DatabaseMigrator(database: firstDatabase)
        let firstRepository = ProjectRepository(database: firstDatabase)

        try await firstMigrator.migrate()
        let createdProject = try await firstRepository.createProject(at: projectFolder)

        let secondDatabase = Database(url: databaseURL)
        let secondMigrator = DatabaseMigrator(database: secondDatabase)
        let secondRepository = ProjectRepository(database: secondDatabase)

        try await secondMigrator.migrate()
        let loadedProjects = try await secondRepository.listProjects()

        XCTAssertEqual(loadedProjects, [createdProject])
    }

    private func makeHarness() throws -> (database: Database, migrator: DatabaseMigrator, repository: ProjectRepository) {
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
