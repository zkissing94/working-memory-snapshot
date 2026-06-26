import XCTest
@testable import WorkingMemorySnapshot

final class LMStudioURLPolicyTests: XCTestCase {
    func testNormalizesTrailingSlash() throws {
        let normalized = try LMStudioURLPolicy.normalizedBaseURLString(
            from: " http://localhost:1234/v1/// "
        )

        XCTAssertEqual(normalized, "http://localhost:1234/v1")
    }

    func testRejectsInvalidBaseURL() {
        XCTAssertThrowsError(try LMStudioURLPolicy.normalizedBaseURL(from: "localhost:1234/v1")) { error in
            XCTAssertEqual(error as? LMStudioURLPolicyError, .unsupportedScheme)
        }
    }

    func testDetectsLoopbackHosts() throws {
        let localhost = try LMStudioURLPolicy.normalizedBaseURL(from: "http://localhost:1234/v1")
        let ipv4 = try LMStudioURLPolicy.normalizedBaseURL(from: "http://127.0.0.1:1234/v1")
        let ipv6 = try LMStudioURLPolicy.normalizedBaseURL(from: "http://[::1]:1234/v1")

        XCTAssertTrue(LMStudioURLPolicy.isLoopback(localhost))
        XCTAssertTrue(LMStudioURLPolicy.isLoopback(ipv4))
        XCTAssertTrue(LMStudioURLPolicy.isLoopback(ipv6))
    }

    func testNonLoopbackRequiresWarning() {
        XCTAssertTrue(
            LMStudioURLPolicy.requiresNonLoopbackWarning(for: "http://192.168.1.25:1234/v1")
        )
        XCTAssertFalse(
            LMStudioURLPolicy.requiresNonLoopbackWarning(for: "http://localhost:1234/v1")
        )
    }
}
