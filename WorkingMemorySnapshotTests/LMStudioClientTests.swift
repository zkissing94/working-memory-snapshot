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

    func testGenerateSnapshotPostsStructuredChatCompletionRequest() async throws {
        let token = "test-token"
        let transport = MockLMStudioHTTPTransport.success(body: chatCompletionBody(content: validSnapshotJSON()))
        let client = try LMStudioClient(
            baseURLString: "http://localhost:1234/v1/",
            apiToken: token,
            transport: transport
        )

        let result = try await client.generateSnapshot(
            modelID: "model-a",
            systemPrompt: "system prompt",
            userPrompt: "user prompt"
        )

        XCTAssertEqual(result.whatChanged, "The implementation reached the client boundary.")
        XCTAssertEqual(result.decisions, ["Use structured JSON output."])
        XCTAssertEqual(result.openLoops, ["Wire this through the generator later."])
        XCTAssertEqual(result.nextAction, "Add integration wiring in M6.")
        XCTAssertEqual(result.resumeBrief, "You added a structured generation client and should wire it into snapshot generation later.")

        let requests = await transport.capturedRequests()
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url?.absoluteString, "http://localhost:1234/v1/chat/completions")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.timeoutInterval, 60)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(token)")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try requestBodyDictionary(request)
        XCTAssertEqual(body["model"] as? String, "model-a")
        XCTAssertEqual(body["stream"] as? Bool, false)
        XCTAssertEqual(body["temperature"] as? Double, 0.1)
        XCTAssertEqual(body["max_tokens"] as? Int, 700)

        let responseFormat = try XCTUnwrap(body["response_format"] as? [String: Any])
        XCTAssertEqual(responseFormat["type"] as? String, "json_schema")

        let jsonSchema = try XCTUnwrap(responseFormat["json_schema"] as? [String: Any])
        XCTAssertEqual(jsonSchema["name"] as? String, SnapshotSchema.name)
        XCTAssertEqual(jsonSchema["strict"] as? Bool, true)

        let schema = try XCTUnwrap(jsonSchema["schema"] as? [String: Any])
        XCTAssertEqual(schema["additionalProperties"] as? Bool, false)
        XCTAssertNotNil(schema["required"])
    }

    func testGenerateSnapshotOmitsAuthorizationHeaderForEmptyToken() async throws {
        let transport = MockLMStudioHTTPTransport.success(body: chatCompletionBody(content: validSnapshotJSON()))
        let client = try LMStudioClient(
            baseURLString: LMStudioSettings.defaultBaseURLString,
            apiToken: " ",
            transport: transport
        )

        _ = try await client.generateSnapshot(
            modelID: "model-a",
            systemPrompt: "system",
            userPrompt: "user"
        )

        let requests = await transport.capturedRequests()
        let request = try XCTUnwrap(requests.first)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }

    func testInvalidChatCompletionEnvelopeIsTyped() async throws {
        let client = try LMStudioClient(
            baseURLString: LMStudioSettings.defaultBaseURLString,
            apiToken: nil,
            transport: MockLMStudioHTTPTransport.success(body: #"{"unexpected":true}"#)
        )

        await XCTAssertThrowsAsyncError({
            try await client.generateSnapshot(
                modelID: "model-a",
                systemPrompt: "system",
                userPrompt: "user"
            )
        }) { error in
            XCTAssertEqual(error as? LMStudioGenerationError, .invalidChatCompletionEnvelope)
        }
    }

    func testGenerateSnapshotRejectsMissingModelID() async throws {
        let client = try LMStudioClient(
            baseURLString: LMStudioSettings.defaultBaseURLString,
            apiToken: nil,
            transport: MockLMStudioHTTPTransport.success(body: chatCompletionBody(content: validSnapshotJSON()))
        )

        await XCTAssertThrowsAsyncError({
            try await client.generateSnapshot(
                modelID: " ",
                systemPrompt: "system",
                userPrompt: "user"
            )
        }) { error in
            XCTAssertEqual(error as? LMStudioGenerationError, .noModelSelected)
        }
    }

    func testGenerateSnapshotTransportFailureIsServerUnreachable() async throws {
        let client = try LMStudioClient(
            baseURLString: LMStudioSettings.defaultBaseURLString,
            apiToken: nil,
            transport: MockLMStudioHTTPTransport.failure(URLError(.timedOut))
        )

        await XCTAssertThrowsAsyncError({
            try await client.generateSnapshot(
                modelID: "model-a",
                systemPrompt: "system",
                userPrompt: "user"
            )
        }) { error in
            XCTAssertEqual(error as? LMStudioClientError, .serverUnreachable)
        }
    }

    func testGenerateSnapshotHTTPErrorIsTyped() async throws {
        let client = try LMStudioClient(
            baseURLString: LMStudioSettings.defaultBaseURLString,
            apiToken: nil,
            transport: MockLMStudioHTTPTransport.response(statusCode: 500, body: "{}")
        )

        await XCTAssertThrowsAsyncError({
            try await client.generateSnapshot(
                modelID: "model-a",
                systemPrompt: "system",
                userPrompt: "user"
            )
        }) { error in
            XCTAssertEqual(error as? LMStudioClientError, .serverError(statusCode: 500))
        }
    }

    func testInvalidSnapshotJSONTriggersOneRepairRetry() async throws {
        let transport = MockLMStudioHTTPTransport.sequence([
            .success(body: chatCompletionBody(content: #"{"what_changed":""}"#)),
            .success(body: chatCompletionBody(content: validSnapshotJSON()))
        ])
        let client = try LMStudioClient(
            baseURLString: LMStudioSettings.defaultBaseURLString,
            apiToken: nil,
            transport: transport
        )

        let result = try await client.generateSnapshot(
            modelID: "model-a",
            systemPrompt: "system",
            userPrompt: "user"
        )

        XCTAssertEqual(result.nextAction, "Add integration wiring in M6.")

        let requests = await transport.capturedRequests()
        XCTAssertEqual(requests.count, 2)

        let retryBody = try requestBodyDictionary(try XCTUnwrap(requests.last))
        let messages = try XCTUnwrap(retryBody["messages"] as? [[String: String]])
        XCTAssertEqual(messages.count, 3)
        XCTAssertEqual(messages.last?["role"], "user")
        XCTAssertTrue(messages.last?["content"]?.contains("previous response could not be accepted") == true)
    }

    func testInvalidSnapshotJSONRetriesAtMostOnce() async throws {
        let transport = MockLMStudioHTTPTransport.sequence([
            .success(body: chatCompletionBody(content: #"{"what_changed":""}"#)),
            .success(body: chatCompletionBody(content: #"{"what_changed":""}"#)),
            .success(body: chatCompletionBody(content: validSnapshotJSON()))
        ])
        let client = try LMStudioClient(
            baseURLString: LMStudioSettings.defaultBaseURLString,
            apiToken: nil,
            transport: transport
        )

        await XCTAssertThrowsAsyncError({
            try await client.generateSnapshot(
                modelID: "model-a",
                systemPrompt: "system",
                userPrompt: "user"
            )
        }) { error in
            guard case .invalidSnapshotJSON = error as? LMStudioGenerationError else {
                return XCTFail("Expected invalid snapshot JSON, got \(error)")
            }
        }

        let requests = await transport.capturedRequests()
        XCTAssertEqual(requests.count, 2)
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

    static func sequence(_ responses: [MockLMStudioHTTPResponse]) -> MockLMStudioHTTPTransport {
        let responseQueue = MockLMStudioHTTPResponseQueue(responses)
        return MockLMStudioHTTPTransport { request in
            let response = try await responseQueue.next()
            switch response {
            case .success(let body):
                return (
                    Data(body.utf8),
                    HTTPURLResponse(
                        url: request.url ?? URL(string: LMStudioSettings.defaultBaseURLString)!,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: nil
                    )!
                )
            }
        }
    }
}

private actor MockLMStudioHTTPResponseQueue {
    private var responses: [MockLMStudioHTTPResponse]

    init(_ responses: [MockLMStudioHTTPResponse]) {
        self.responses = responses
    }

    func next() throws -> MockLMStudioHTTPResponse {
        guard !responses.isEmpty else {
            throw LMStudioGenerationError.invalidChatCompletionEnvelope
        }
        return responses.removeFirst()
    }
}

enum MockLMStudioHTTPResponse {
    case success(body: String)
}

private func validSnapshotJSON() -> String {
    """
    {
      "what_changed": " The implementation reached the client boundary. ",
      "decisions": [" Use structured JSON output. "],
      "open_loops": [" Wire this through the generator later. "],
      "next_action": " Add integration wiring in M6. ",
      "resume_brief": " You added a structured generation client and should wire it into snapshot generation later. "
    }
    """
}

private func chatCompletionBody(content: String) -> String {
    let object: [String: Any] = [
        "choices": [
            [
                "message": [
                    "content": content
                ]
            ]
        ]
    ]
    let data = try! JSONSerialization.data(withJSONObject: object)
    return String(data: data, encoding: .utf8)!
}

private func requestBodyDictionary(_ request: URLRequest) throws -> [String: Any] {
    let body = try XCTUnwrap(request.httpBody)
    let object = try JSONSerialization.jsonObject(with: body)
    return try XCTUnwrap(object as? [String: Any])
}
