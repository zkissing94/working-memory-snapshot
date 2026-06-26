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
        XCTAssertEqual(versions, [1, 2])
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
