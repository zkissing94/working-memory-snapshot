import Foundation

protocol LMStudioHTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionLMStudioHTTPTransport: LMStudioHTTPTransport {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LMStudioClientError.invalidResponse
        }

        return (data, httpResponse)
    }
}

struct LMStudioClient: Sendable {
    private let baseURL: URL
    private let apiToken: String?
    private let transport: any LMStudioHTTPTransport
    private let chatCompletionTimeout: TimeInterval = 60

    init(
        baseURLString: String,
        apiToken: String?,
        transport: any LMStudioHTTPTransport = URLSessionLMStudioHTTPTransport()
    ) throws {
        do {
            self.baseURL = try LMStudioURLPolicy.normalizedBaseURL(from: baseURLString)
        } catch {
            throw LMStudioClientError.invalidBaseURL
        }
        self.apiToken = apiToken?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.transport = transport
    }

    func listModels(selectedModelID: String? = nil) async throws -> [LMStudioModel] {
        var request = URLRequest(url: baseURL.appendingPathComponent("models"))
        request.httpMethod = "GET"
        request.timeoutInterval = 10

        if let apiToken, !apiToken.isEmpty {
            request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.data(for: request)
        } catch let error as LMStudioClientError {
            throw error
        } catch {
            throw LMStudioClientError.serverUnreachable
        }

        switch response.statusCode {
        case 200:
            break
        case 401, 403:
            throw LMStudioClientError.unauthorized
        default:
            throw LMStudioClientError.serverError(statusCode: response.statusCode)
        }

        let decodedResponse: ModelsResponse
        do {
            decodedResponse = try JSONDecoder().decode(ModelsResponse.self, from: data)
        } catch {
            throw LMStudioClientError.invalidResponse
        }

        let models = decodedResponse.data
            .map { $0.id.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map(LMStudioModel.init(id:))

        guard !models.isEmpty else {
            throw LMStudioClientError.noModels
        }

        let selectedModelID = selectedModelID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !selectedModelID.isEmpty && !models.contains(where: { $0.id == selectedModelID }) {
            throw LMStudioClientError.selectedModelUnavailable(selectedModelID)
        }

        return models
    }

    func generateSnapshot(
        modelID: String,
        systemPrompt: String,
        userPrompt: String
    ) async throws -> SnapshotGenerationResult {
        let trimmedModelID = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModelID.isEmpty else {
            throw LMStudioGenerationError.noModelSelected
        }

        let messages = [
            ChatCompletionMessage(role: "system", content: systemPrompt),
            ChatCompletionMessage(role: "user", content: userPrompt)
        ]

        let initialContent = try await requestChatCompletion(
            modelID: trimmedModelID,
            messages: messages
        )

        do {
            return try SnapshotSchema.validateJSONContent(initialContent)
        } catch let validationError as SnapshotGenerationValidationError {
            let repairMessages = messages + [
                ChatCompletionMessage(
                    role: "user",
                    content: repairInstruction(for: validationError)
                )
            ]
            let repairedContent = try await requestChatCompletion(
                modelID: trimmedModelID,
                messages: repairMessages
            )

            do {
                return try SnapshotSchema.validateJSONContent(repairedContent)
            } catch let repairedValidationError as SnapshotGenerationValidationError {
                throw LMStudioGenerationError.invalidSnapshotJSON(repairedValidationError)
            }
        }
    }

    private func requestChatCompletion(
        modelID: String,
        messages: [ChatCompletionMessage]
    ) async throws -> String {
        var request = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.timeoutInterval = chatCompletionTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let apiToken, !apiToken.isEmpty {
            request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        }

        let body = ChatCompletionRequest(
            model: modelID,
            messages: messages,
            temperature: 0.1,
            stream: false,
            maxTokens: 700,
            responseFormat: ChatCompletionResponseFormat(
                type: "json_schema",
                jsonSchema: ChatCompletionJSONSchema(
                    name: SnapshotSchema.name,
                    strict: true,
                    schema: SnapshotSchema.schemaObject()
                )
            )
        )

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body.jsonObject(), options: [])
        } catch {
            throw LMStudioGenerationError.invalidRequest
        }

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.data(for: request)
        } catch let error as LMStudioClientError {
            throw error
        } catch {
            throw LMStudioClientError.serverUnreachable
        }

        switch response.statusCode {
        case 200:
            break
        case 401, 403:
            throw LMStudioClientError.unauthorized
        default:
            throw LMStudioClientError.serverError(statusCode: response.statusCode)
        }

        let decodedResponse: ChatCompletionResponse
        do {
            decodedResponse = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        } catch {
            throw LMStudioGenerationError.invalidChatCompletionEnvelope
        }

        guard let content = decodedResponse.choices.first?.message.content,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw LMStudioGenerationError.invalidChatCompletionEnvelope
        }

        return content
    }

    private func repairInstruction(for error: SnapshotGenerationValidationError) -> String {
        """
        Your previous response could not be accepted: \(error).
        Return only valid JSON matching the supplied schema. Do not add prose, Markdown, or extra keys.
        """
    }
}

enum LMStudioClientError: Error, Equatable, LocalizedError {
    case invalidBaseURL
    case serverUnreachable
    case unauthorized
    case noModels
    case selectedModelUnavailable(String)
    case invalidResponse
    case serverError(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            "The LM Studio base URL is invalid."
        case .serverUnreachable:
            "LM Studio could not be reached."
        case .unauthorized:
            "LM Studio rejected the API token."
        case .noModels:
            "LM Studio is reachable, but no models are loaded."
        case .selectedModelUnavailable(let modelID):
            "The selected model is not available: \(modelID)."
        case .invalidResponse:
            "LM Studio returned an invalid model list."
        case .serverError(let statusCode):
            "LM Studio returned HTTP \(statusCode)."
        }
    }
}

enum LMStudioGenerationError: Error, Equatable, LocalizedError {
    case noModelSelected
    case invalidRequest
    case invalidChatCompletionEnvelope
    case invalidSnapshotJSON(SnapshotGenerationValidationError)

    var errorDescription: String? {
        switch self {
        case .noModelSelected:
            "No model is selected."
        case .invalidRequest:
            "The LM Studio snapshot request could not be created."
        case .invalidChatCompletionEnvelope:
            "LM Studio returned an invalid chat completion response."
        case .invalidSnapshotJSON:
            "LM Studio returned snapshot JSON that did not match the required schema."
        }
    }
}

private struct ModelsResponse: Decodable {
    let data: [ModelResponse]
}

private struct ModelResponse: Decodable {
    let id: String
}

private struct ChatCompletionMessage: Equatable {
    let role: String
    let content: String
}

private struct ChatCompletionRequest {
    let model: String
    let messages: [ChatCompletionMessage]
    let temperature: Double
    let stream: Bool
    let maxTokens: Int
    let responseFormat: ChatCompletionResponseFormat

    func jsonObject() -> [String: Any] {
        [
            "model": model,
            "messages": messages.map { message in
                [
                    "role": message.role,
                    "content": message.content
                ]
            },
            "temperature": temperature,
            "stream": stream,
            "max_tokens": maxTokens,
            "response_format": responseFormat.jsonObject()
        ]
    }
}

private struct ChatCompletionResponseFormat {
    let type: String
    let jsonSchema: ChatCompletionJSONSchema

    func jsonObject() -> [String: Any] {
        [
            "type": type,
            "json_schema": jsonSchema.jsonObject()
        ]
    }
}

private struct ChatCompletionJSONSchema {
    let name: String
    let strict: Bool
    let schema: [String: Any]

    func jsonObject() -> [String: Any] {
        [
            "name": name,
            "strict": strict,
            "schema": schema
        ]
    }
}

private struct ChatCompletionResponse: Decodable {
    let choices: [ChatCompletionChoice]
}

private struct ChatCompletionChoice: Decodable {
    let message: ChatCompletionResponseMessage
}

private struct ChatCompletionResponseMessage: Decodable {
    let content: String
}
