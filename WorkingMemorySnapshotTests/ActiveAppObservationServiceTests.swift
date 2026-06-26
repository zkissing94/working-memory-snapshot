import XCTest
@testable import WorkingMemorySnapshot

final class ActiveAppObservationServiceTests: XCTestCase {
    func testStartEmitsInitialFrontmostApplicationOnce() throws {
        let initialApplication = try XCTUnwrap(
            ActiveAppIdentity(
                displayName: "Terminal",
                bundleIdentifier: "com.apple.Terminal"
            )
        )
        let source = FakeActiveAppObservationSource(frontmostApplication: initialApplication)
        let service = ActiveAppObservationService(
            source: source,
            dateProvider: { Date(timeIntervalSince1970: 10) }
        )
        var events: [ActiveAppObservationEvent] = []

        service.start { events.append($0) }
        service.start { _ in XCTFail("A second start should not replace the active observer") }

        XCTAssertEqual(source.addedObserverCount, 1)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.occurredAt, Date(timeIntervalSince1970: 10))
        XCTAssertEqual(events.first?.application, initialApplication)
        XCTAssertEqual(events.first?.title, "Terminal")
        XCTAssertEqual(events.first?.body, nil)
    }

    func testTransitionsEmitOnceAndConsecutiveDuplicatesAreDiscarded() throws {
        let terminal = try XCTUnwrap(
            ActiveAppIdentity(
                displayName: "Terminal",
                bundleIdentifier: "com.apple.Terminal"
            )
        )
        let xcode = try XCTUnwrap(
            ActiveAppIdentity(
                displayName: "Xcode",
                bundleIdentifier: "com.apple.dt.Xcode"
            )
        )
        let safari = try XCTUnwrap(
            ActiveAppIdentity(
                displayName: "Safari",
                bundleIdentifier: "com.apple.Safari"
            )
        )
        var nextTimestamp: TimeInterval = 20
        let source = FakeActiveAppObservationSource(frontmostApplication: terminal)
        let service = ActiveAppObservationService(
            source: source,
            dateProvider: {
                defer { nextTimestamp += 1 }
                return Date(timeIntervalSince1970: nextTimestamp)
            }
        )
        var events: [ActiveAppObservationEvent] = []

        service.start { events.append($0) }
        source.emit(terminal)
        source.emit(xcode)
        source.emit(xcode)
        source.emit(safari)

        XCTAssertEqual(events.map(\.application), [terminal, xcode, safari])
        XCTAssertEqual(
            events.map(\.occurredAt),
            [
                Date(timeIntervalSince1970: 20),
                Date(timeIntervalSince1970: 21),
                Date(timeIntervalSince1970: 22)
            ]
        )
    }

    func testStopRemovesObserverAndSuppressesLaterNotifications() throws {
        let terminal = try XCTUnwrap(
            ActiveAppIdentity(
                displayName: "Terminal",
                bundleIdentifier: "com.apple.Terminal"
            )
        )
        let xcode = try XCTUnwrap(
            ActiveAppIdentity(
                displayName: "Xcode",
                bundleIdentifier: "com.apple.dt.Xcode"
            )
        )
        let source = FakeActiveAppObservationSource(frontmostApplication: terminal)
        let service = ActiveAppObservationService(source: source)
        var events: [ActiveAppObservationEvent] = []

        service.start { events.append($0) }
        service.stop()
        source.emit(xcode)

        XCTAssertFalse(service.isObserving)
        XCTAssertEqual(source.activeObserverCount, 0)
        XCTAssertEqual(source.removedObserverCount, 1)
        XCTAssertEqual(events.map(\.application), [terminal])
    }

    func testStopResetsDeduplicationForNextStart() throws {
        let terminal = try XCTUnwrap(
            ActiveAppIdentity(
                displayName: "Terminal",
                bundleIdentifier: "com.apple.Terminal"
            )
        )
        let source = FakeActiveAppObservationSource(frontmostApplication: terminal)
        let service = ActiveAppObservationService(source: source)
        var events: [ActiveAppObservationEvent] = []

        service.start { events.append($0) }
        service.stop()
        service.start { events.append($0) }

        XCTAssertEqual(events.map(\.application), [terminal, terminal])
        XCTAssertEqual(source.addedObserverCount, 2)
        XCTAssertEqual(source.removedObserverCount, 1)
    }

    func testIdentityRejectsMissingDisplayNameAndNormalizesBundleIdentifier() {
        XCTAssertNil(
            ActiveAppIdentity(
                displayName: "  ",
                bundleIdentifier: "com.example.MissingName"
            )
        )

        let identity = ActiveAppIdentity(
            displayName: "  Xcode  ",
            bundleIdentifier: "  "
        )

        XCTAssertEqual(identity?.displayName, "Xcode")
        XCTAssertNil(identity?.bundleIdentifier)
    }

    func testEventPayloadContainsOnlyApplicationIdentity() throws {
        let identity = try XCTUnwrap(
            ActiveAppIdentity(
                displayName: "Xcode",
                bundleIdentifier: "com.apple.dt.Xcode"
            )
        )
        let event = ActiveAppObservationEvent(
            occurredAt: Date(timeIntervalSince1970: 30),
            application: identity
        )

        XCTAssertEqual(ActiveAppObservationEvent.eventSource, "active_app")
        XCTAssertEqual(ActiveAppObservationEvent.eventKind, "app_activated")
        XCTAssertNil(event.body)
        XCTAssertEqual(event.payload.displayName, "Xcode")
        XCTAssertEqual(event.payload.bundleIdentifier, "com.apple.dt.Xcode")

        let payloadData = try JSONEncoder().encode(event.payload)
        let payloadObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: payloadData) as? [String: Any]
        )

        XCTAssertEqual(Set(payloadObject.keys), ["displayName", "bundleIdentifier"])
    }
}

private final class FakeActiveAppObservationSource: ActiveAppObservationSource {
    var frontmostApplication: ActiveAppIdentity?

    private var handlers: [UUID: (ActiveAppIdentity) -> Void] = [:]
    private(set) var addedObserverCount = 0
    private(set) var removedObserverCount = 0

    init(frontmostApplication: ActiveAppIdentity?) {
        self.frontmostApplication = frontmostApplication
    }

    var activeObserverCount: Int {
        handlers.count
    }

    func addActivationObserver(
        _ handler: @escaping (ActiveAppIdentity) -> Void
    ) -> ActiveAppObservationToken {
        let id = UUID()
        addedObserverCount += 1
        handlers[id] = handler

        return FakeActiveAppObservationToken { [weak self] in
            guard let self else {
                return
            }

            if handlers.removeValue(forKey: id) != nil {
                removedObserverCount += 1
            }
        }
    }

    func emit(_ application: ActiveAppIdentity) {
        for handler in handlers.values {
            handler(application)
        }
    }
}

private final class FakeActiveAppObservationToken: ActiveAppObservationToken {
    private var onCancel: (() -> Void)?

    init(onCancel: @escaping () -> Void) {
        self.onCancel = onCancel
    }

    func cancel() {
        guard let onCancel else {
            return
        }

        self.onCancel = nil
        onCancel()
    }
}
