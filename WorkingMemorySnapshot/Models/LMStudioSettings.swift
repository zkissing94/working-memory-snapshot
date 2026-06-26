import Foundation

struct LMStudioSettings: Equatable, Sendable {
    static let defaultBaseURLString = "http://localhost:1234/v1"

    var baseURLString: String
    var selectedModelID: String

    static var defaults: LMStudioSettings {
        LMStudioSettings(
            baseURLString: defaultBaseURLString,
            selectedModelID: ""
        )
    }

    func normalized() throws -> LMStudioSettings {
        LMStudioSettings(
            baseURLString: try LMStudioURLPolicy.normalizedBaseURLString(from: baseURLString),
            selectedModelID: selectedModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

struct LMStudioModel: Identifiable, Equatable, Sendable {
    let id: String
}

enum LMStudioURLPolicy {
    static func normalizedBaseURLString(from input: String) throws -> String {
        try normalizedBaseURL(from: input).absoluteString
    }

    static func normalizedBaseURL(from input: String) throws -> URL {
        let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else {
            throw LMStudioURLPolicyError.emptyBaseURL
        }

        guard var components = URLComponents(string: trimmedInput) else {
            throw LMStudioURLPolicyError.invalidBaseURL
        }

        guard let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else {
            throw LMStudioURLPolicyError.unsupportedScheme
        }

        guard let host = components.host,
              !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw LMStudioURLPolicyError.missingHost
        }

        guard components.query == nil,
              components.fragment == nil
        else {
            throw LMStudioURLPolicyError.invalidBaseURL
        }

        components.scheme = scheme
        components.host = host.lowercased()

        var path = components.percentEncodedPath
        while path.count > 1 && path.hasSuffix("/") {
            path.removeLast()
        }
        if path == "/" {
            path = ""
        }
        components.percentEncodedPath = path

        guard let url = components.url else {
            throw LMStudioURLPolicyError.invalidBaseURL
        }

        return url
    }

    static func isLoopback(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else {
            return false
        }

        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }

    static func requiresNonLoopbackWarning(for input: String) -> Bool {
        guard let url = try? normalizedBaseURL(from: input) else {
            return false
        }

        return !isLoopback(url)
    }
}

enum LMStudioURLPolicyError: Error, Equatable, LocalizedError {
    case emptyBaseURL
    case unsupportedScheme
    case missingHost
    case invalidBaseURL

    var errorDescription: String? {
        switch self {
        case .emptyBaseURL:
            "Enter an LM Studio base URL."
        case .unsupportedScheme:
            "Use an HTTP or HTTPS base URL."
        case .missingHost:
            "The LM Studio base URL needs a host."
        case .invalidBaseURL:
            "The LM Studio base URL is invalid."
        }
    }
}
