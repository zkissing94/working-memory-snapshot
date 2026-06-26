import Foundation

struct GitService: Sendable {
    private let gitExecutableURL: URL
    private let processRunner: any ProcessRunning
    private let configuration: GitServiceConfiguration

    init(
        gitExecutableURL: URL = URL(fileURLWithPath: "/usr/bin/git"),
        processRunner: any ProcessRunning = ProcessRunner(),
        configuration: GitServiceConfiguration = .default
    ) {
        self.gitExecutableURL = gitExecutableURL
        self.processRunner = processRunner
        self.configuration = configuration
    }

    func captureInitialState(projectURL: URL) async throws -> GitInitialEvidence {
        guard let context = try await repositoryContext(for: projectURL) else {
            return .notRepository
        }

        async let branchName = currentBranchName(in: context)
        async let headSHA = currentHeadSHA(in: context)
        async let status = statusSummary(in: context)

        return try await .repository(
            GitRepositorySnapshot(
                branchName: branchName,
                headSHA: headSHA,
                status: status
            )
        )
    }

    func captureFinalSummary(
        projectURL: URL,
        startHead: String?,
        observedRelativePaths: Set<String>
    ) async throws -> GitFinalEvidence {
        guard let context = try await repositoryContext(for: projectURL) else {
            return .notRepository
        }

        async let branchName = currentBranchName(in: context)
        async let headSHA = currentHeadSHA(in: context)
        async let status = statusSummary(in: context)

        let resolvedBranchName = try await branchName
        let resolvedHeadSHA = try await headSHA
        let resolvedStatus = try await status
        let observedPaths = normalizedObservedPaths(observedRelativePaths)
        let changedPaths = Set(resolvedStatus.changedPaths)
        let sessionObservedChangedPaths = resolvedStatus.changedPaths.filter { observedPaths.contains($0) }
        let unobservedChangedPaths = resolvedStatus.changedPaths.filter { !observedPaths.contains($0) }
        let evidencePathspecs = pathspecs(for: observedPaths, context: context)

        async let diffStat = diffStat(
            in: context,
            currentHead: resolvedHeadSHA,
            pathspecs: evidencePathspecs
        )
        async let commitsAfterStart = commitsAfterStart(
            startHead: startHead,
            context: context,
            pathspecs: evidencePathspecs
        )

        return try await .repository(
            GitRepositoryFinalSummary(
                branchName: resolvedBranchName,
                headSHA: resolvedHeadSHA,
                status: resolvedStatus,
                sessionObservedChangedPaths: bounded(sessionObservedChangedPaths, limit: configuration.maxChangedPaths),
                unobservedChangedPaths: bounded(unobservedChangedPaths, limit: configuration.maxChangedPaths),
                diffStat: diffStat,
                commitsAfterStart: commitsAfterStart,
                hasSessionObservedChanges: !changedPaths.isDisjoint(with: observedPaths)
            )
        )
    }

    private func repositoryContext(for projectURL: URL) async throws -> GitRepositoryContext? {
        let standardizedProjectURL = projectURL.standardizedFileURL
        let result = try await runGit(
            arguments: ["rev-parse", "--show-toplevel"],
            currentDirectoryURL: standardizedProjectURL,
            allowNonZeroExit: true
        )

        guard result.terminationStatus == 0 else {
            let stderr = string(from: result.stderr)
            if stderr.localizedCaseInsensitiveContains("not a git repository") {
                return nil
            }

            throw GitServiceError.commandFailed(
                GitCommandFailure(
                    arguments: ["rev-parse", "--show-toplevel"],
                    terminationStatus: result.terminationStatus,
                    stderr: boundedErrorText(stderr)
                )
            )
        }

        guard let rootPath = firstOutputLine(result.stdout) else {
            throw GitServiceError.invalidGitOutput("Missing repository root.")
        }

        let repositoryRootURL = URL(fileURLWithPath: rootPath).standardizedFileURL
        let projectPathspec = try projectPathspec(
            projectURL: standardizedProjectURL,
            repositoryRootURL: repositoryRootURL
        )

        return GitRepositoryContext(
            repositoryRootURL: repositoryRootURL,
            projectPathspec: projectPathspec
        )
    }

    private func currentBranchName(in context: GitRepositoryContext) async throws -> String? {
        let result = try await runGit(
            arguments: ["branch", "--show-current"],
            currentDirectoryURL: context.repositoryRootURL,
            allowNonZeroExit: true
        )

        guard result.terminationStatus == 0 else {
            return nil
        }

        return trimmedNonEmptyString(from: result.stdout)
    }

    private func currentHeadSHA(in context: GitRepositoryContext) async throws -> String? {
        let result = try await runGit(
            arguments: ["rev-parse", "--verify", "HEAD"],
            currentDirectoryURL: context.repositoryRootURL,
            allowNonZeroExit: true
        )

        guard result.terminationStatus == 0 else {
            return nil
        }

        return trimmedNonEmptyString(from: result.stdout)
    }

    private func statusSummary(in context: GitRepositoryContext) async throws -> GitStatusSummary {
        let result = try await runGit(
            arguments: [
                "status",
                "--porcelain=v1",
                "-z",
                "--untracked-files=all",
                "--",
                context.projectPathspec
            ],
            currentDirectoryURL: context.repositoryRootURL
        )

        let parsed = parseStatusEntries(result.stdout, context: context)
        let boundedEntries = bounded(parsed.entries, limit: configuration.maxStatusEntries)
        return GitStatusSummary(
            entries: boundedEntries,
            isOutputTruncated: result.didTruncateStdout || parsed.didDropEntries
        )
    }

    private func diffStat(
        in context: GitRepositoryContext,
        currentHead: String?,
        pathspecs: [String]
    ) async throws -> GitDiffStat {
        var arguments = ["diff"]
        if context.projectPathspec != "." {
            arguments.append("--relative=\(context.projectPathspec)")
        }
        arguments.append("--stat")
        if currentHead != nil {
            arguments.append("HEAD")
        } else {
            arguments.append("--cached")
        }
        arguments.append("--")
        arguments.append(contentsOf: pathspecs)

        let result = try await runGit(
            arguments: arguments,
            currentDirectoryURL: context.repositoryRootURL
        )

        let lines = nonEmptyLines(result.stdout)
        return GitDiffStat(
            lines: bounded(lines, limit: configuration.maxDiffStatLines),
            isOutputTruncated: result.didTruncateStdout || lines.count > configuration.maxDiffStatLines
        )
    }

    private func commitsAfterStart(
        startHead: String?,
        context: GitRepositoryContext,
        pathspecs: [String]
    ) async throws -> [GitCommitSummary] {
        guard let startHead = startHead?.trimmingCharacters(in: .whitespacesAndNewlines),
              !startHead.isEmpty
        else {
            return []
        }

        var arguments = [
            "log",
            "--format=%H%x09%s",
            "-n",
            "\(configuration.maxCommits)",
            "\(startHead)..HEAD",
            "--"
        ]
        arguments.append(contentsOf: pathspecs)

        let result = try await runGit(
            arguments: arguments,
            currentDirectoryURL: context.repositoryRootURL,
            allowNonZeroExit: true
        )

        guard result.terminationStatus == 0 else {
            throw GitServiceError.commandFailed(
                GitCommandFailure(
                    arguments: arguments,
                    terminationStatus: result.terminationStatus,
                    stderr: boundedErrorText(string(from: result.stderr))
                )
            )
        }

        return nonEmptyLines(result.stdout)
            .compactMap { line -> GitCommitSummary? in
                let parts = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
                guard let hash = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !hash.isEmpty
                else {
                    return nil
                }

                let subject = parts.count > 1 ? String(parts[1]) : ""
                return GitCommitSummary(
                    hash: hash,
                    subject: boundedSubject(subject)
                )
            }
    }

    private func runGit(
        arguments: [String],
        currentDirectoryURL: URL,
        allowNonZeroExit: Bool = false
    ) async throws -> ProcessResult {
        let request = ProcessRequest(
            executableURL: gitExecutableURL,
            arguments: arguments,
            currentDirectoryURL: currentDirectoryURL,
            timeout: configuration.commandTimeout,
            maxOutputBytes: configuration.maxOutputBytes
        )

        let result: ProcessResult
        do {
            result = try await processRunner.run(request)
        } catch let error as ProcessRunnerError {
            throw GitServiceError.processFailed(error)
        } catch {
            throw GitServiceError.unexpectedProcessFailure(String(describing: error))
        }

        if !allowNonZeroExit && result.terminationStatus != 0 {
            throw GitServiceError.commandFailed(
                GitCommandFailure(
                    arguments: arguments,
                    terminationStatus: result.terminationStatus,
                    stderr: boundedErrorText(string(from: result.stderr))
                )
            )
        }

        return result
    }

    private func parseStatusEntries(
        _ data: Data,
        context: GitRepositoryContext
    ) -> (entries: [GitStatusEntry], didDropEntries: Bool) {
        let records = string(from: data).split(separator: "\0", omittingEmptySubsequences: true)
        var entries: [GitStatusEntry] = []
        var index = 0
        var didDropEntries = false

        while index < records.count {
            let record = String(records[index])
            guard record.count >= 4 else {
                index += 1
                continue
            }

            let indexStatus = String(record.prefix(1))
            let workTreeStatus = String(record.dropFirst().prefix(1))
            let rawPath = String(record.dropFirst(3))
            var originalPath: String?

            if indexStatus == "R" || indexStatus == "C" {
                index += 1
                if index < records.count {
                    originalPath = projectRelativePath(fromRepositoryRelativePath: String(records[index]), context: context)
                }
            }

            if let path = projectRelativePath(fromRepositoryRelativePath: rawPath, context: context) {
                if entries.count < configuration.maxStatusEntries {
                    entries.append(
                        GitStatusEntry(
                            indexStatus: indexStatus,
                            workTreeStatus: workTreeStatus,
                            path: path,
                            originalPath: originalPath
                        )
                    )
                } else {
                    didDropEntries = true
                }
            }

            index += 1
        }

        return (entries, didDropEntries)
    }

    private func projectPathspec(projectURL: URL, repositoryRootURL: URL) throws -> String {
        let projectPath = projectURL.standardizedFileURL.path
        let repositoryRootPath = repositoryRootURL.standardizedFileURL.path

        if projectPath == repositoryRootPath {
            return "."
        }

        let prefix = repositoryRootPath + "/"
        guard projectPath.hasPrefix(prefix) else {
            throw GitServiceError.projectOutsideRepository
        }

        return String(projectPath.dropFirst(prefix.count))
    }

    private func projectRelativePath(
        fromRepositoryRelativePath path: String,
        context: GitRepositoryContext
    ) -> String? {
        guard let normalizedPath = normalizedRelativePath(path) else {
            return nil
        }

        guard context.projectPathspec != "." else {
            return normalizedPath
        }

        if normalizedPath == context.projectPathspec {
            return nil
        }

        let prefix = context.projectPathspec + "/"
        guard normalizedPath.hasPrefix(prefix) else {
            return nil
        }

        return String(normalizedPath.dropFirst(prefix.count))
    }

    private func pathspecs(for observedPaths: Set<String>, context: GitRepositoryContext) -> [String] {
        let sortedObservedPaths = observedPaths.sorted()
        guard !sortedObservedPaths.isEmpty else {
            return [context.projectPathspec]
        }

        return bounded(sortedObservedPaths, limit: configuration.maxChangedPaths).map { path in
            guard context.projectPathspec != "." else {
                return path
            }

            return "\(context.projectPathspec)/\(path)"
        }
    }

    private func normalizedObservedPaths(_ paths: Set<String>) -> Set<String> {
        Set(paths.compactMap(normalizedRelativePath))
    }

    private func normalizedRelativePath(_ path: String) -> String? {
        let unixPath = path.replacingOccurrences(of: "\\", with: "/")
        guard !unixPath.isEmpty, !unixPath.hasPrefix("/") else {
            return nil
        }

        var components: [String] = []
        for component in unixPath.split(separator: "/", omittingEmptySubsequences: true) {
            switch component {
            case ".":
                continue
            case "..":
                return nil
            default:
                components.append(String(component))
            }
        }

        guard !components.isEmpty else {
            return nil
        }

        return components.joined(separator: "/")
    }

    private func firstOutputLine(_ data: Data) -> String? {
        nonEmptyLines(data).first
    }

    private func trimmedNonEmptyString(from data: Data) -> String? {
        let value = string(from: data).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func nonEmptyLines(_ data: Data) -> [String] {
        string(from: data)
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func string(from data: Data) -> String {
        String(decoding: data, as: UTF8.self)
    }

    private func boundedErrorText(_ text: String) -> String {
        String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(configuration.maxErrorCharacters))
    }

    private func boundedSubject(_ subject: String) -> String {
        String(subject.trimmingCharacters(in: .whitespacesAndNewlines).prefix(configuration.maxCommitSubjectCharacters))
    }

    private func bounded<Value>(_ values: [Value], limit: Int) -> [Value] {
        Array(values.prefix(max(0, limit)))
    }
}

struct GitServiceConfiguration: Equatable, Sendable {
    let commandTimeout: TimeInterval
    let maxOutputBytes: Int
    let maxStatusEntries: Int
    let maxChangedPaths: Int
    let maxDiffStatLines: Int
    let maxCommits: Int
    let maxCommitSubjectCharacters: Int
    let maxErrorCharacters: Int

    static let `default` = GitServiceConfiguration(
        commandTimeout: 5,
        maxOutputBytes: 64_000,
        maxStatusEntries: 200,
        maxChangedPaths: 200,
        maxDiffStatLines: 60,
        maxCommits: 20,
        maxCommitSubjectCharacters: 160,
        maxErrorCharacters: 1_000
    )
}

enum GitInitialEvidence: Equatable, Sendable {
    case notRepository
    case repository(GitRepositorySnapshot)
}

enum GitFinalEvidence: Equatable, Sendable {
    case notRepository
    case repository(GitRepositoryFinalSummary)
}

struct GitRepositorySnapshot: Equatable, Sendable {
    let branchName: String?
    let headSHA: String?
    let status: GitStatusSummary
}

struct GitRepositoryFinalSummary: Equatable, Sendable {
    let branchName: String?
    let headSHA: String?
    let status: GitStatusSummary
    let sessionObservedChangedPaths: [String]
    let unobservedChangedPaths: [String]
    let diffStat: GitDiffStat
    let commitsAfterStart: [GitCommitSummary]
    let hasSessionObservedChanges: Bool
}

struct GitStatusSummary: Equatable, Sendable {
    let entries: [GitStatusEntry]
    let isOutputTruncated: Bool

    var changedPaths: [String] {
        var seenPaths = Set<String>()
        var paths: [String] = []

        for entry in entries where !seenPaths.contains(entry.path) {
            seenPaths.insert(entry.path)
            paths.append(entry.path)
        }

        return paths
    }
}

struct GitStatusEntry: Equatable, Sendable {
    let indexStatus: String
    let workTreeStatus: String
    let path: String
    let originalPath: String?
}

struct GitDiffStat: Equatable, Sendable {
    let lines: [String]
    let isOutputTruncated: Bool
}

struct GitCommitSummary: Equatable, Sendable {
    let hash: String
    let subject: String
}

enum GitServiceError: Error, Equatable, LocalizedError, Sendable {
    case commandFailed(GitCommandFailure)
    case processFailed(ProcessRunnerError)
    case unexpectedProcessFailure(String)
    case invalidGitOutput(String)
    case projectOutsideRepository

    var errorDescription: String? {
        switch self {
        case .commandFailed(let failure):
            "Git command failed: \(failure.arguments.joined(separator: " "))"
        case .processFailed(let error):
            error.localizedDescription
        case .unexpectedProcessFailure(let message):
            "Git process failed unexpectedly: \(message)"
        case .invalidGitOutput(let message):
            "Git returned invalid output: \(message)"
        case .projectOutsideRepository:
            "The selected project folder is outside the detected Git repository."
        }
    }
}

struct GitCommandFailure: Equatable, Sendable {
    let arguments: [String]
    let terminationStatus: Int32
    let stderr: String
}

private struct GitRepositoryContext: Sendable {
    let repositoryRootURL: URL
    let projectPathspec: String
}
