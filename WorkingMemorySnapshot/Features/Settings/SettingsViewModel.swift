import Foundation
import SwiftUI

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var baseURLString = LMStudioSettings.defaultBaseURLString
    @Published var selectedModelID = ""
    @Published var apiToken = ""
    @Published private(set) var models: [LMStudioModel] = []
    @Published private(set) var connectionState: LMStudioConnectionState = .idle
    @Published private(set) var errorMessage: String?
    @Published private(set) var isBusy = false

    private let repository: SettingsRepository
    private let tokenStore: any LMStudioTokenStore
    private let transport: any LMStudioHTTPTransport
    private var hasLoadedSettings = false

    init(
        repository: SettingsRepository,
        tokenStore: any LMStudioTokenStore,
        transport: any LMStudioHTTPTransport = URLSessionLMStudioHTTPTransport()
    ) {
        self.repository = repository
        self.tokenStore = tokenStore
        self.transport = transport
    }

    var isNonLoopbackWarningVisible: Bool {
        LMStudioURLPolicy.requiresNonLoopbackWarning(for: baseURLString)
    }

    var selectedModelIsUnavailable: Bool {
        !selectedModelID.isEmpty && !models.contains(where: { $0.id == selectedModelID })
    }

    var isShowingError: Binding<Bool> {
        Binding(
            get: { self.errorMessage != nil },
            set: { isShowing in
                if !isShowing {
                    self.errorMessage = nil
                }
            }
        )
    }

    func loadSettings() async {
        guard !hasLoadedSettings else {
            return
        }

        isBusy = true
        defer {
            isBusy = false
        }

        do {
            let settings = try await repository.loadLMStudioSettings()
            baseURLString = settings.baseURLString
            selectedModelID = settings.selectedModelID
            apiToken = try await tokenStore.loadToken() ?? ""
            hasLoadedSettings = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveSettings() async {
        isBusy = true
        defer {
            isBusy = false
        }

        do {
            let settings = LMStudioSettings(
                baseURLString: baseURLString,
                selectedModelID: selectedModelID
            )
            let normalizedSettings = try settings.normalized()
            try await repository.saveLMStudioSettings(normalizedSettings)
            try await tokenStore.saveToken(apiToken)
            baseURLString = normalizedSettings.baseURLString
            selectedModelID = normalizedSettings.selectedModelID
            connectionState = .saved
        } catch is LMStudioURLPolicyError {
            connectionState = .invalidBaseURL
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshModels() async {
        await loadModels(checkSelectedModel: false)
    }

    func testConnection() async {
        await loadModels(checkSelectedModel: true)
    }

    func clearError() {
        errorMessage = nil
    }

    private func loadModels(checkSelectedModel: Bool) async {
        isBusy = true
        connectionState = .testing
        defer {
            isBusy = false
        }

        do {
            let client = try LMStudioClient(
                baseURLString: baseURLString,
                apiToken: apiToken,
                transport: transport
            )
            let selectedModelID = checkSelectedModel ? selectedModelID : nil
            models = try await client.listModels(selectedModelID: selectedModelID)
            connectionState = .success(modelCount: models.count)
        } catch let error as LMStudioClientError {
            connectionState = LMStudioConnectionState(error: error)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

enum LMStudioConnectionState: Equatable {
    case idle
    case testing
    case saved
    case success(modelCount: Int)
    case invalidBaseURL
    case serverUnreachable
    case unauthorized
    case noModels
    case selectedModelUnavailable(String)
    case invalidResponse
    case serverError(Int)

    init(error: LMStudioClientError) {
        switch error {
        case .invalidBaseURL:
            self = .invalidBaseURL
        case .serverUnreachable:
            self = .serverUnreachable
        case .unauthorized:
            self = .unauthorized
        case .noModels:
            self = .noModels
        case .selectedModelUnavailable(let modelID):
            self = .selectedModelUnavailable(modelID)
        case .invalidResponse:
            self = .invalidResponse
        case .serverError(let statusCode):
            self = .serverError(statusCode)
        }
    }

    var message: String? {
        switch self {
        case .idle:
            nil
        case .testing:
            "Testing connection..."
        case .saved:
            "Settings saved."
        case .success(let modelCount):
            modelCount == 1 ? "Connected. 1 model is available." : "Connected. \(modelCount) models are available."
        case .invalidBaseURL:
            "The base URL is invalid."
        case .serverUnreachable:
            "LM Studio could not be reached."
        case .unauthorized:
            "Authentication is required or the token was rejected."
        case .noModels:
            "LM Studio is reachable, but no models are loaded."
        case .selectedModelUnavailable(let modelID):
            "The selected model is unavailable: \(modelID)."
        case .invalidResponse:
            "LM Studio returned an invalid model list."
        case .serverError(let statusCode):
            "LM Studio returned HTTP \(statusCode)."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .idle, .testing, .saved, .success:
            nil
        case .invalidBaseURL:
            "Use a URL like http://localhost:1234/v1."
        case .serverUnreachable:
            "Start the local server, confirm the address in Settings, and try again."
        case .unauthorized:
            "Check the optional API token or disable authentication in LM Studio."
        case .noModels:
            "Load an instruct model in LM Studio, then refresh models."
        case .selectedModelUnavailable:
            "Refresh the model list or choose another synthesizer model."
        case .invalidResponse:
            "Confirm the server exposes LM Studio's OpenAI-compatible /v1/models endpoint."
        case .serverError:
            "Check LM Studio, then try the connection again."
        }
    }

    var systemImageName: String {
        switch self {
        case .idle:
            "circle"
        case .testing:
            "arrow.clockwise"
        case .saved, .success:
            "checkmark.circle"
        case .invalidBaseURL,
             .serverUnreachable,
             .unauthorized,
             .noModels,
             .selectedModelUnavailable,
             .invalidResponse,
             .serverError:
            "exclamationmark.triangle"
        }
    }
}
