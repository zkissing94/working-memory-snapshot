import Darwin
import Foundation

protocol ProcessRunning: Sendable {
    func run(_ request: ProcessRequest) async throws -> ProcessResult
}

struct ProcessRequest: Equatable, Sendable {
    let executableURL: URL
    let arguments: [String]
    let currentDirectoryURL: URL?
    let timeout: TimeInterval
    let maxOutputBytes: Int

    init(
        executableURL: URL,
        arguments: [String] = [],
        currentDirectoryURL: URL? = nil,
        timeout: TimeInterval = 5,
        maxOutputBytes: Int = 64_000
    ) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.currentDirectoryURL = currentDirectoryURL
        self.timeout = timeout
        self.maxOutputBytes = maxOutputBytes
    }
}

struct ProcessResult: Equatable, Sendable {
    let terminationStatus: Int32
    let stdout: Data
    let stderr: Data
    let didTruncateStdout: Bool
    let didTruncateStderr: Bool
}

enum ProcessRunnerError: Error, Equatable, LocalizedError, Sendable {
    case invalidTimeout(TimeInterval)
    case invalidOutputLimit(Int)
    case launchFailed(executablePath: String, message: String)
    case timedOut(executablePath: String, arguments: [String], timeout: TimeInterval)

    var errorDescription: String? {
        switch self {
        case .invalidTimeout(let timeout):
            "Process timeout must be positive. Received \(timeout)."
        case .invalidOutputLimit(let limit):
            "Process output limit must be non-negative. Received \(limit)."
        case .launchFailed(let executablePath, let message):
            "Could not launch \(executablePath): \(message)"
        case .timedOut(let executablePath, _, let timeout):
            "\(executablePath) timed out after \(timeout) seconds."
        }
    }
}

struct ProcessRunner: ProcessRunning {
    func run(_ request: ProcessRequest) async throws -> ProcessResult {
        guard request.timeout > 0 else {
            throw ProcessRunnerError.invalidTimeout(request.timeout)
        }

        guard request.maxOutputBytes >= 0 else {
            throw ProcessRunnerError.invalidOutputLimit(request.maxOutputBytes)
        }

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = request.executableURL
            process.arguments = request.arguments
            process.currentDirectoryURL = request.currentDirectoryURL

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            let stdoutBuffer = BoundedOutputBuffer(limit: request.maxOutputBytes)
            let stderrBuffer = BoundedOutputBuffer(limit: request.maxOutputBytes)
            let completion = ProcessCompletion(continuation: continuation)

            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                stdoutBuffer.append(handle.availableData)
            }
            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                stderrBuffer.append(handle.availableData)
            }

            let timeoutItem = DispatchWorkItem {
                let didResume = completion.resume(
                    with: .failure(
                        ProcessRunnerError.timedOut(
                            executablePath: request.executableURL.path,
                            arguments: request.arguments,
                            timeout: request.timeout
                        )
                    )
                )

                guard didResume else {
                    return
                }

                if process.isRunning {
                    process.terminate()

                    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + .milliseconds(250)) {
                        if process.isRunning {
                            kill(process.processIdentifier, SIGKILL)
                        }
                    }
                }
            }

            process.terminationHandler = { terminatedProcess in
                timeoutItem.cancel()
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                stdoutBuffer.append(stdoutPipe.fileHandleForReading.readDataToEndOfFile())
                stderrBuffer.append(stderrPipe.fileHandleForReading.readDataToEndOfFile())

                let stdout = stdoutBuffer.snapshot()
                let stderr = stderrBuffer.snapshot()
                _ = completion.resume(
                    with: .success(
                        ProcessResult(
                            terminationStatus: terminatedProcess.terminationStatus,
                            stdout: stdout.data,
                            stderr: stderr.data,
                            didTruncateStdout: stdout.didTruncate,
                            didTruncateStderr: stderr.didTruncate
                        )
                    )
                )
            }

            do {
                try process.run()
                DispatchQueue.global(qos: .utility).asyncAfter(
                    deadline: .now() + .nanoseconds(Int(request.timeout * 1_000_000_000)),
                    execute: timeoutItem
                )
            } catch {
                timeoutItem.cancel()
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                _ = completion.resume(
                    with: .failure(
                        ProcessRunnerError.launchFailed(
                            executablePath: request.executableURL.path,
                            message: error.localizedDescription
                        )
                    )
                )
            }
        }
    }
}

private final class BoundedOutputBuffer: @unchecked Sendable {
    private let limit: Int
    private let lock = NSLock()
    private var storage = Data()
    private var truncated = false

    init(limit: Int) {
        self.limit = limit
    }

    func append(_ data: Data) {
        guard !data.isEmpty else {
            return
        }

        lock.lock()
        defer {
            lock.unlock()
        }

        let remainingBytes = max(0, limit - storage.count)
        if remainingBytes > 0 {
            storage.append(data.prefix(remainingBytes))
        }

        if data.count > remainingBytes {
            truncated = true
        }
    }

    func snapshot() -> (data: Data, didTruncate: Bool) {
        lock.lock()
        defer {
            lock.unlock()
        }

        return (storage, truncated)
    }
}

private final class ProcessCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false
    private let continuation: CheckedContinuation<ProcessResult, Error>

    init(continuation: CheckedContinuation<ProcessResult, Error>) {
        self.continuation = continuation
    }

    func resume(with result: Result<ProcessResult, Error>) -> Bool {
        lock.lock()
        defer {
            lock.unlock()
        }

        guard !didResume else {
            return false
        }

        didResume = true
        continuation.resume(with: result)
        return true
    }
}
