import Foundation
import SQLite3

struct ProjectRepository {
    let database: Database

    func createProject(at url: URL) async throws -> Project {
        let rootPath = normalizedPath(for: url)
        let now = try DateCoding.now()
        let project = Project(
            id: UUID(),
            name: displayName(for: url),
            rootPath: rootPath,
            createdAt: now,
            updatedAt: now
        )

        do {
            try await database.execute("""
            INSERT INTO projects(id, name, root_path, created_at, updated_at)
            VALUES(?, ?, ?, ?, ?)
            """) { statement in
                try bind(project, to: statement)
            }
        } catch let error as SQLiteError where error.code == SQLITE_CONSTRAINT {
            throw ProjectRepositoryError.duplicateProject(rootPath: rootPath)
        }

        return project
    }

    func listProjects() async throws -> [Project] {
        try await database.query("""
        SELECT id, name, root_path, created_at, updated_at
        FROM projects
        ORDER BY updated_at DESC, name ASC
        """) { statement in
            try mapProject(from: statement)
        }
    }

    func project(for id: UUID) async throws -> Project? {
        try await database.query("""
        SELECT id, name, root_path, created_at, updated_at
        FROM projects
        WHERE id = ?
        LIMIT 1
        """, bind: { statement in
            try SQLiteValue.bind(id.uuidString, to: statement, at: 1)
        }, map: { statement in
            try mapProject(from: statement)
        })
        .first
    }

    func updateProjectRoot(id: UUID, to url: URL) async throws -> Project {
        let rootPath = normalizedPath(for: url)
        let now = try DateCoding.now()

        do {
            let changedRows = try await database.executeReturningChanges("""
            UPDATE projects
            SET root_path = ?, updated_at = ?
            WHERE id = ?
            """) { statement in
                try SQLiteValue.bind(rootPath, to: statement, at: 1)
                try SQLiteValue.bind(DateCoding.string(from: now), to: statement, at: 2)
                try SQLiteValue.bind(id.uuidString, to: statement, at: 3)
            }

            guard changedRows > 0 else {
                throw ProjectRepositoryError.projectNotFound(id)
            }
        } catch let error as SQLiteError where error.code == SQLITE_CONSTRAINT {
            throw ProjectRepositoryError.duplicateProject(rootPath: rootPath)
        }

        guard let project = try await project(for: id) else {
            throw ProjectRepositoryError.projectNotFound(id)
        }

        return project
    }

    func updateProjectName(id: UUID, to name: String) async throws -> Project {
        let now = try DateCoding.now()

        let changedRows = try await database.executeReturningChanges("""
        UPDATE projects
        SET name = ?, updated_at = ?
        WHERE id = ?
        """) { statement in
            try SQLiteValue.bind(name, to: statement, at: 1)
            try SQLiteValue.bind(DateCoding.string(from: now), to: statement, at: 2)
            try SQLiteValue.bind(id.uuidString, to: statement, at: 3)
        }

        guard changedRows > 0 else {
            throw ProjectRepositoryError.projectNotFound(id)
        }

        guard let project = try await project(for: id) else {
            throw ProjectRepositoryError.projectNotFound(id)
        }

        return project
    }

    func deleteProject(id: UUID) async throws {
        let changedRows = try await database.executeReturningChanges("""
        DELETE FROM projects
        WHERE id = ?
        """) { statement in
            try SQLiteValue.bind(id.uuidString, to: statement, at: 1)
        }

        guard changedRows > 0 else {
            throw ProjectRepositoryError.projectNotFound(id)
        }
    }

    private func bind(_ project: Project, to statement: OpaquePointer) throws {
        try SQLiteValue.bind(project.id.uuidString, to: statement, at: 1)
        try SQLiteValue.bind(project.name, to: statement, at: 2)
        try SQLiteValue.bind(project.rootPath, to: statement, at: 3)
        try SQLiteValue.bind(DateCoding.string(from: project.createdAt), to: statement, at: 4)
        try SQLiteValue.bind(DateCoding.string(from: project.updatedAt), to: statement, at: 5)
    }

    private func mapProject(from statement: OpaquePointer) throws -> Project {
        let idString = SQLiteValue.text(statement, at: 0)
        guard let id = UUID(uuidString: idString) else {
            throw ProjectRepositoryError.invalidStoredProject("Invalid project id: \(idString)")
        }

        return Project(
            id: id,
            name: SQLiteValue.text(statement, at: 1),
            rootPath: SQLiteValue.text(statement, at: 2),
            createdAt: try DateCoding.date(from: SQLiteValue.text(statement, at: 3)),
            updatedAt: try DateCoding.date(from: SQLiteValue.text(statement, at: 4))
        )
    }

    private func normalizedPath(for url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private func displayName(for url: URL) -> String {
        let lastPathComponent = url.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return lastPathComponent.isEmpty ? normalizedPath(for: url) : lastPathComponent
    }
}

enum ProjectRepositoryError: Error, Equatable, LocalizedError {
    case duplicateProject(rootPath: String)
    case invalidStoredProject(String)
    case projectNotFound(UUID)

    var errorDescription: String? {
        switch self {
        case .duplicateProject:
            "That project is already in the list."
        case .invalidStoredProject(let message):
            message
        case .projectNotFound:
            "The project could not be found."
        }
    }
}
