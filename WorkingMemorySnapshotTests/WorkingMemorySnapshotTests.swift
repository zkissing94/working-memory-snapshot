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

    private enum ForcedTransactionError: Error, Equatable {
        case rollbackProbe
    }

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
        XCTAssertEqual(versions, [1, 2, 3, 4, 5, 6, 7])
    }

    func testTransactionRollsBackPartialWritesOnFailure() async throws {
        let harness = try makeHarness()
        try await harness.migrator.migrate()
        let projectFolder = try makeTemporaryDirectory(named: "RollbackProject")
        let projectID = UUID()
        let timestamp = DateCoding.string(from: try DateCoding.now())

        await XCTAssertThrowsAsyncError({
            try await harness.database.withTransaction { database in
                try database.execute("""
                INSERT INTO projects(id, name, root_path, created_at, updated_at)
                VALUES(?, ?, ?, ?, ?)
                """) { statement in
                    try SQLiteValue.bind(projectID.uuidString, to: statement, at: 1)
                    try SQLiteValue.bind("RollbackProject", to: statement, at: 2)
                    try SQLiteValue.bind(projectFolder.path, to: statement, at: 3)
                    try SQLiteValue.bind(timestamp, to: statement, at: 4)
                    try SQLiteValue.bind(timestamp, to: statement, at: 5)
                }
                throw ForcedTransactionError.rollbackProbe
            }
        }) { error in
            XCTAssertEqual(error as? ForcedTransactionError, .rollbackProbe)
        }

        let projects = try await harness.repository.listProjects()
        XCTAssertEqual(projects, [])
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
