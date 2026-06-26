import AppKit
import Foundation

struct ActiveAppIdentity: Equatable, Sendable {
    let displayName: String
    let bundleIdentifier: String?

    init?(displayName: String?, bundleIdentifier: String?) {
        let normalizedDisplayName = (displayName ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedDisplayName.isEmpty else {
            return nil
        }

        let normalizedBundleIdentifier = (bundleIdentifier ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        self.displayName = normalizedDisplayName
        self.bundleIdentifier = normalizedBundleIdentifier.isEmpty ? nil : normalizedBundleIdentifier
    }
}

struct ActiveAppObservationEvent: Equatable, Sendable {
    struct Payload: Codable, Equatable, Sendable {
        let displayName: String
        let bundleIdentifier: String?
    }

    static let eventSource = "active_app"
    static let eventKind = "app_activated"

    let occurredAt: Date
    let application: ActiveAppIdentity

    var title: String {
        application.displayName
    }

    var body: String? {
        nil
    }

    var payload: Payload {
        Payload(
            displayName: application.displayName,
            bundleIdentifier: application.bundleIdentifier
        )
    }
}

protocol ActiveAppObservationToken: AnyObject {
    func cancel()
}

protocol ActiveAppObservationSource: AnyObject {
    var frontmostApplication: ActiveAppIdentity? { get }

    func addActivationObserver(
        _ handler: @escaping (ActiveAppIdentity) -> Void
    ) -> ActiveAppObservationToken
}

final class ActiveAppObservationService {
    typealias EventHandler = (ActiveAppObservationEvent) -> Void

    private let source: ActiveAppObservationSource
    private let dateProvider: () -> Date
    private var observationToken: ActiveAppObservationToken?
    private var lastApplication: ActiveAppIdentity?

    init(
        source: ActiveAppObservationSource = NSWorkspaceActiveAppObservationSource(),
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.source = source
        self.dateProvider = dateProvider
    }

    deinit {
        stop()
    }

    var isObserving: Bool {
        observationToken != nil
    }

    func start(eventHandler: @escaping EventHandler) {
        guard observationToken == nil else {
            return
        }

        if let frontmostApplication = source.frontmostApplication {
            emit(frontmostApplication, to: eventHandler)
        }

        observationToken = source.addActivationObserver { [weak self] application in
            self?.emit(application, to: eventHandler)
        }
    }

    func stop() {
        observationToken?.cancel()
        observationToken = nil
        lastApplication = nil
    }

    private func emit(_ application: ActiveAppIdentity, to eventHandler: EventHandler) {
        guard application != lastApplication else {
            return
        }

        lastApplication = application
        eventHandler(
            ActiveAppObservationEvent(
                occurredAt: dateProvider(),
                application: application
            )
        )
    }
}

final class NSWorkspaceActiveAppObservationSource: ActiveAppObservationSource {
    private let workspace: NSWorkspace
    private let notificationCenter: NotificationCenter

    init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
        self.notificationCenter = workspace.notificationCenter
    }

    var frontmostApplication: ActiveAppIdentity? {
        workspace.frontmostApplication.flatMap(Self.identity)
    }

    func addActivationObserver(
        _ handler: @escaping (ActiveAppIdentity) -> Void
    ) -> ActiveAppObservationToken {
        let observer = notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let runningApplication = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let identity = Self.identity(from: runningApplication) else {
                return
            }

            handler(identity)
        }

        return NotificationActiveAppObservationToken(
            notificationCenter: notificationCenter,
            observer: observer
        )
    }

    private static func identity(from application: NSRunningApplication) -> ActiveAppIdentity? {
        ActiveAppIdentity(
            displayName: application.localizedName,
            bundleIdentifier: application.bundleIdentifier
        )
    }
}

private final class NotificationActiveAppObservationToken: ActiveAppObservationToken {
    private let notificationCenter: NotificationCenter
    private var observer: NSObjectProtocol?

    init(notificationCenter: NotificationCenter, observer: NSObjectProtocol) {
        self.notificationCenter = notificationCenter
        self.observer = observer
    }

    deinit {
        cancel()
    }

    func cancel() {
        guard let observer else {
            return
        }

        notificationCenter.removeObserver(observer)
        self.observer = nil
    }
}
