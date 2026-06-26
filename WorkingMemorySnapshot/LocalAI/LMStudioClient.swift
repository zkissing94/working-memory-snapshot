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

private struct ModelsResponse: Decodable {
    let data: [ModelResponse]
}

private struct ModelResponse: Decodable {
    let id: String
}
