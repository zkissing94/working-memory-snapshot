import XCTest
@testable import WorkingMemorySnapshot

final class GitServiceTests: XCTestCase {
    func testNonGitProjectIsNormalResult() async throws {
        let directory = try makeTemporaryDirectory()
        defer {
            removeTemporaryDirectory(directory)
        }

        let evidence = try await GitService().captureInitialState(projectURL: directory)

        XCTAssertEqual(evidence, .notRepository)
    }

    func testCleanRepositoryCapturesBranchHeadAndEmptyStatus() async throws {
        let repository = try makeRepository()
        defer {
            removeTemporaryDirectory(repository)
        }

        try writeFile("README.md", contents: "Initial\n", in: repository)
        try commitAll(in: repository, message: "initial commit")

        let evidence = try await GitService().captureInitialState(projectURL: repository)
        let snapshot = try repositorySnapshot(from: evidence)

        XCTAssertNotNil(snapshot.branchName)
        XCTAssertNotNil(snapshot.headSHA)
        XCTAssertTrue(snapshot.status.entries.isEmpty)
        XCTAssertFalse(snapshot.status.isOutputTruncated)
    }

    func testDirtyStateCapturesRelativePathsWithSpaces() async throws {
        let repository = try makeRepository()
        defer {
            removeTemporaryDirectory(repository)
        }

        try writeFile("Tracked File.txt", contents: "Before\n", in: repository)
        try commitAll(in: repository, message: "track spaced path")
        try writeFile("Tracked File.txt", contents: "After\n", in: repository)
        try writeFile("Untracked File.txt", contents: "New\n", in: repository)

        let evidence = try await GitService().captureInitialState(projectURL: repository)
        let snapshot = try repositorySnapshot(from: evidence)
        let changedPaths = Set(snapshot.status.changedPaths)

        XCTAssertEqual(changedPaths, ["Tracked File.txt", "Untracked File.txt"])
        XCTAssertTrue(snapshot.status.entries.contains { entry in
            entry.path == "Tracked File.txt" && entry.workTreeStatus == "M"
        })
        XCTAssertTrue(snapshot.status.entries.contains { entry in
            entry.path == "Untracked File.txt" && entry.indexStatus == "?" && entry.workTreeStatus == "?"
        })
    }

    func testSubdirectoryProjectKeepsGitPathsInsideProject() async throws {
        let repository = try makeRepository()
        defer {
            removeTemporaryDirectory(repository)
        }

        try writeFile("Nested Project/inside.txt", contents: "Before\n", in: repository)
        try writeFile("outside.txt", contents: "Before\n", in: repository)
        try commitAll(in: repository, message: "initial files")
        try writeFile("Nested Project/inside.txt", contents: "After\n", in: repository)
        try writeFile("outside.txt", contents: "After\n", in: repository)

        let projectURL = repository.appendingPathComponent("Nested Project", isDirectory: true)
        let evidence = try await GitService().captureInitialState(projectURL: projectURL)
        let snapshot = try repositorySnapshot(from: evidence)

        XCTAssertEqual(snapshot.status.changedPaths, ["inside.txt"])
    }

    func testFinalSummaryUsesObservedPathsToBoundDiffStat() async throws {
        let repository = try makeRepository()
        defer {
            removeTemporaryDirectory(repository)
        }

        try writeFile("observed.txt", contents: "Before\n", in: repository)
        try writeFile("unobserved.txt", contents: "Before\n", in: repository)
        try commitAll(in: repository, message: "initial files")

        let initialSnapshot = try repositorySnapshot(
            from: try await GitService().captureInitialState(projectURL: repository)
        )
        let startHead = try XCTUnwrap(initialSnapshot.headSHA)

        try writeFile("observed.txt", contents: "After\n", in: repository)
        try writeFile("unobserved.txt", contents: "After\n", in: repository)

        let finalEvidence = try await GitService().captureFinalSummary(
            projectURL: repository,
            startHead: startHead,
            observedRelativePaths: ["observed.txt"]
        )
        let summary = try finalSummary(from: finalEvidence)
        let diffText = summary.diffStat.lines.joined(separator: "\n")

        XCTAssertEqual(Set(summary.status.changedPaths), ["observed.txt", "unobserved.txt"])
        XCTAssertEqual(summary.sessionObservedChangedPaths, ["observed.txt"])
        XCTAssertEqual(summary.unobservedChangedPaths, ["unobserved.txt"])
        XCTAssertTrue(summary.hasSessionObservedChanges)
        XCTAssertTrue(diffText.contains("observed.txt"))
        XCTAssertFalse(diffText.contains("unobserved.txt"))
    }

    func testCommitsAfterStartHeadAreCapturedForObservedPaths() async throws {
        let repository = try makeRepository()
        defer {
            removeTemporaryDirectory(repository)
        }

        try writeFile("observed.txt", contents: "Before\n", in: repository)
        try writeFile("other.txt", contents: "Before\n", in: repository)
        try commitAll(in: repository, message: "initial files")

        let initialSnapshot = try repositorySnapshot(
            from: try await GitService().captureInitialState(projectURL: repository)
        )
        let startHead = try XCTUnwrap(initialSnapshot.headSHA)

        try writeFile("observed.txt", contents: "After\n", in: repository)
        try commitAll(in: repository, message: "update observed path")

        let finalEvidence = try await GitService().captureFinalSummary(
            projectURL: repository,
            startHead: startHead,
            observedRelativePaths: ["observed.txt"]
        )
        let summary = try finalSummary(from: finalEvidence)

        XCTAssertTrue(summary.status.entries.isEmpty)
        XCTAssertEqual(summary.commitsAfterStart.count, 1)
        XCTAssertEqual(summary.commitsAfterStart.first?.subject, "update observed path")
    }

    func testGitCommandFailureIsTyped() async throws {
        let directory = try makeTemporaryDirectory()
        defer {
            removeTemporaryDirectory(directory)
        }

        let service = GitService(gitExecutableURL: URL(fileURLWithPath: "/usr/bin/false"))

        await XCTAssertThrowsAsyncError({
            try await service.captureInitialState(projectURL: directory)
        }) { error in
            guard case .commandFailed(let failure) = error as? GitServiceError else {
                XCTFail("Expected commandFailed error, got \(error).")
                return
            }

            XCTAssertEqual(failure.arguments, ["rev-parse", "--show-toplevel"])
            XCTAssertNotEqual(failure.terminationStatus, 0)
        }
    }

    func testProcessTimeoutIsTyped() async {
        let service = GitService(processRunner: TimeoutProcessRunner())

        await XCTAssertThrowsAsyncError({
            try await service.captureInitialState(projectURL: URL(fileURLWithPath: "/tmp"))
        }) { error in
            guard case .processFailed(.timedOut(let executablePath, let arguments, _)) = error as? GitServiceError else {
                XCTFail("Expected processFailed timeout, got \(error).")
                return
            }

            XCTAssertEqual(executablePath, "/usr/bin/git")
            XCTAssertEqual(arguments, ["rev-parse", "--show-toplevel"])
        }
    }

    func testStatusOutputTruncationIsReported() async throws {
        let repository = try makeRepository()
        defer {
            removeTemporaryDirectory(repository)
        }

        for index in 0..<120 {
            try writeFile("long-untracked-file-name-\(index).txt", contents: "New\n", in: repository)
        }

        let service = GitService(
            configuration: GitServiceConfiguration(
                commandTimeout: 5,
                maxOutputBytes: 512,
                maxStatusEntries: 100,
                maxChangedPaths: 100,
                maxDiffStatLines: 20,
                maxCommits: 10,
                maxCommitSubjectCharacters: 80,
                maxErrorCharacters: 200
            )
        )

        let evidence = try await service.captureInitialState(projectURL: repository)
        let snapshot = try repositorySnapshot(from: evidence)

        XCTAssertTrue(snapshot.status.isOutputTruncated)
    }

    private func makeRepository() throws -> URL {
        let repository = try makeTemporaryDirectory()
        try runGit(["init"], in: repository)
        try runGit(["config", "user.email", "test@example.com"], in: repository)
        try runGit(["config", "user.name", "Test User"], in: repository)
        return repository
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkingMemorySnapshot-GitServiceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func removeTemporaryDirectory(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }

    private func writeFile(_ relativePath: String, contents: String, in directory: URL) throws {
        let fileURL = directory.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private func commitAll(in repository: URL, message: String) throws {
        try runGit(["add", "."], in: repository)
        try runGit(["commit", "-m", message], in: repository)
    }

    @discardableResult
    private func runGit(_ arguments: [String], in directory: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let stdoutText = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let stderrText = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)

        guard process.terminationStatus == 0 else {
            throw GitServiceTestError.commandFailed(arguments: arguments, stderr: stderrText)
        }

        return stdoutText
    }

    private func repositorySnapshot(from evidence: GitInitialEvidence) throws -> GitRepositorySnapshot {
        guard case .repository(let snapshot) = evidence else {
            throw GitServiceTestError.expectedRepositoryEvidence
        }

        return snapshot
    }

    private func finalSummary(from evidence: GitFinalEvidence) throws -> GitRepositoryFinalSummary {
        guard case .repository(let summary) = evidence else {
            throw GitServiceTestError.expectedRepositoryEvidence
        }

        return summary
    }
}

private struct TimeoutProcessRunner: ProcessRunning {
    func run(_ request: ProcessRequest) async throws -> ProcessResult {
        throw ProcessRunnerError.timedOut(
            executablePath: request.executableURL.path,
            arguments: request.arguments,
            timeout: request.timeout
        )
    }
}

private enum GitServiceTestError: Error, LocalizedError {
    case commandFailed(arguments: [String], stderr: String)
    case expectedRepositoryEvidence

    var errorDescription: String? {
        switch self {
        case .commandFailed(let arguments, let stderr):
            "git \(arguments.joined(separator: " ")) failed: \(stderr)"
        case .expectedRepositoryEvidence:
            "Expected repository evidence."
        }
    }
}
