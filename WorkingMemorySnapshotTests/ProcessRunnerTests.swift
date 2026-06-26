import XCTest
@testable import WorkingMemorySnapshot

final class ProcessRunnerTests: XCTestCase {
    func testCapturesBoundedOutput() async throws {
        let runner = ProcessRunner()
        let result = try await runner.run(
            ProcessRequest(
                executableURL: URL(fileURLWithPath: "/usr/bin/printf"),
                arguments: [String(repeating: "x", count: 32)],
                timeout: 2,
                maxOutputBytes: 8
            )
        )

        XCTAssertEqual(result.terminationStatus, 0)
        XCTAssertEqual(String(decoding: result.stdout, as: UTF8.self), "xxxxxxxx")
        XCTAssertTrue(result.didTruncateStdout)
        XCTAssertFalse(result.didTruncateStderr)
    }

    func testReturnsNonzeroTerminationStatusWithoutThrowing() async throws {
        let runner = ProcessRunner()
        let result = try await runner.run(
            ProcessRequest(
                executableURL: URL(fileURLWithPath: "/usr/bin/false"),
                timeout: 2,
                maxOutputBytes: 128
            )
        )

        XCTAssertNotEqual(result.terminationStatus, 0)
    }

    func testTimesOutLongRunningProcess() async {
        let runner = ProcessRunner()

        await XCTAssertThrowsAsyncError({
            try await runner.run(
                ProcessRequest(
                    executableURL: URL(fileURLWithPath: "/bin/sleep"),
                    arguments: ["2"],
                    timeout: 0.05,
                    maxOutputBytes: 128
                )
            )
        }) { error in
            guard case .timedOut(let executablePath, let arguments, _) = error as? ProcessRunnerError else {
                XCTFail("Expected timedOut error, got \(error).")
                return
            }

            XCTAssertEqual(executablePath, "/bin/sleep")
            XCTAssertEqual(arguments, ["2"])
        }
    }
}
