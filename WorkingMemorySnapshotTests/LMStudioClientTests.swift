import XCTest
@testable import WorkingMemorySnapshot

final class LMStudioClientTests: XCTestCase {
    func testListModelsUsesV1ModelsEndpoint() async throws {
        let transport = MockLMStudioHTTPTransport.success(body: #"{"data":[{"id":"model-a"}]}"#)
        let client = try LMStudioClient(
            baseURLString: "http://localhost:1234/v1/",
            apiToken: nil,
            transport: transport
        )

        let models = try await client.listModels()

        XCTAssertEqual(models, [LMStudioModel(id: "model-a")])
        let requests = await transport.capturedRequests()
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url?.absoluteString, "http://localhost:1234/v1/models")
    }

    func testEmptyTokenOmitsAuthorizationHeader() async throws {
        let transport = MockLMStudioHTTPTransport.success(body: #"{"data":[{"id":"model-a"}]}"#)
        let client = try LMStudioClient(
            baseURLString: LMStudioSettings.defaultBaseURLString,
            apiToken: "  ",
            transport: transport
        )

        _ = try await client.listModels()

        let requests = await transport.capturedRequests()
        let request = try XCTUnwrap(requests.first)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }

    func testBearerTokenIsSentWhenPresent() async throws {
        let token = "test-token"
        let transport = MockLMStudioHTTPTransport.success(body: #"{"data":[{"id":"model-a"}]}"#)
        let client = try LMStudioClient(
            baseURLString: LMStudioSettings.defaultBaseURLString,
            apiToken: token,
            transport: transport
        )

        _ = try await client.listModels()

        let requests = await transport.capturedRequests()
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(token)")
    }

    func testUnauthorizedResponseIsDistinct() async throws {
        let client = try LMStudioClient(
            baseURLString: LMStudioSettings.defaultBaseURLString,
            apiToken: "bad-token",
            transport: MockLMStudioHTTPTransport.response(statusCode: 401, body: "{}")
        )

        await XCTAssertThrowsAsyncError({ try await client.listModels() }) { error in
            XCTAssertEqual(error as? LMStudioClientError, .unauthorized)
        }
    }

    func testNoModelsResponseIsDistinct() async throws {
        let client = try LMStudioClient(
            baseURLString: LMStudioSettings.defaultBaseURLString,
            apiToken: nil,
            transport: MockLMStudioHTTPTransport.success(body: #"{"data":[]}"#)
        )

        await XCTAssertThrowsAsyncError({ try await client.listModels() }) { error in
            XCTAssertEqual(error as? LMStudioClientError, .noModels)
        }
    }

    func testInvalidResponseIsDistinct() async throws {
        let client = try LMStudioClient(
            baseURLString: LMStudioSettings.defaultBaseURLString,
            apiToken: nil,
            transport: MockLMStudioHTTPTransport.success(body: #"{"unexpected":true}"#)
        )

        await XCTAssertThrowsAsyncError({ try await client.listModels() }) { error in
            XCTAssertEqual(error as? LMStudioClientError, .invalidResponse)
        }
    }

    func testServerFailureIsDistinct() async throws {
        let client = try LMStudioClient(
            baseURLString: LMStudioSettings.defaultBaseURLString,
            apiToken: nil,
            transport: MockLMStudioHTTPTransport.failure(URLError(.timedOut))
        )

        await XCTAssertThrowsAsyncError({ try await client.listModels() }) { error in
            XCTAssertEqual(error as? LMStudioClientError, .serverUnreachable)
        }
    }

    func testSelectedModelUnavailableIsDistinct() async throws {
        let client = try LMStudioClient(
            baseURLString: LMStudioSettings.defaultBaseURLString,
            apiToken: nil,
            transport: MockLMStudioHTTPTransport.success(body: #"{"data":[{"id":"model-a"}]}"#)
        )

        await XCTAssertThrowsAsyncError({ try await client.listModels(selectedModelID: "model-b") }) { error in
            XCTAssertEqual(error as? LMStudioClientError, .selectedModelUnavailable("model-b"))
        }
    }
}

actor MockLMStudioHTTPTransport: LMStudioHTTPTransport {
    typealias Handler = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    private var requests: [URLRequest] = []
    private let handler: Handler

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        return try await handler(request)
    }

    func capturedRequests() -> [URLRequest] {
        requests
    }

    static func success(body: String) -> MockLMStudioHTTPTransport {
        response(statusCode: 200, body: body)
    }

    static func response(statusCode: Int, body: String) -> MockLMStudioHTTPTransport {
        MockLMStudioHTTPTransport { request in
            (
                Data(body.utf8),
                HTTPURLResponse(
                    url: request.url ?? URL(string: LMStudioSettings.defaultBaseURLString)!,
                    statusCode: statusCode,
                    httpVersion: nil,
                    headerFields: nil
                )!
            )
        }
    }

    static func failure(_ error: Error) -> MockLMStudioHTTPTransport {
        MockLMStudioHTTPTransport { _ in
            throw error
        }
    }
}
