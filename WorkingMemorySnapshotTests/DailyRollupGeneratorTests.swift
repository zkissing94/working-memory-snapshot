import XCTest
@testable import WorkingMemorySnapshot

final class DailyRollupGeneratorTests: XCTestCase {
    private var temporaryRoot: URL?

    override func tearDownWithError() throws {
        if let temporaryRoot { try? FileManager.default.removeItem(at: temporaryRoot) }
    }

    func testGeneratorUsesSharedSettingsAndPersistsValidatedMultiProjectRollup() async throws {
        let harness = try makeHarness()
        try await harness.migrator.migrate()
        try await harness.settings.saveLMStudioSettings(
            LMStudioSettings(baseURLString: LMStudioSettings.defaultBaseURLString, selectedModelID: "daily-model")
        )
        let eligibility = makeEligibility(projectCount: 2)
        let content = validJSON(for: eligibility.projects)
        let transport = MockLMStudioHTTPTransport.success(body: completionBody(content))
        let generator = DailyRollupGenerator(
            repository: harness.repository,
            settingsRepository: harness.settings,
            tokenStore: DailyMemoryTokenStore(token: "secret-token"),
            transport: transport
        )

        let rollup = try await generator.generate(from: eligibility)

        XCTAssertEqual(rollup.generatorModel, "daily-model")
        XCTAssertEqual(rollup.promptVersion, "daily-rollup-v1")
        XCTAssertEqual(rollup.projectThreads.count, 2)
        let stored = try await harness.repository.rollup(for: eligibility.rollupDate)
        XCTAssertEqual(stored, rollup)
        let requests = await transport.capturedRequests()
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret-token")
        let body = try requestDictionary(request)
        let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
        XCTAssertTrue(messages.last?["content"]?.contains("No snapshot yet; grounded capture") == true)
    }

    func testFailedRefreshPreservesExistingRollup() async throws {
        let harness = try makeHarness()
        try await harness.migrator.migrate()
        try await harness.settings.saveLMStudioSettings(
            LMStudioSettings(baseURLString: LMStudioSettings.defaultBaseURLString, selectedModelID: "daily-model")
        )
        let eligibility = makeEligibility(projectCount: 1)
        let project = eligibility.projects[0]
        let existing = try await harness.repository.saveOrReplace(
            DailyRollupDraft(
                rollupDate: eligibility.rollupDate, timezoneIdentifier: eligibility.timezoneIdentifier,
                daySummary: "Existing close", projectThreads: [DailyProjectThread(projectID: project.id, projectName: project.name, summary: "Existing thread")],
                carryForwards: [], closureNote: "Existing closure", generatorModel: "old-model",
                promptVersion: "daily-rollup-v1", sourceFingerprint: "old",
                sources: []
            )
        )
        let invalid = completionBody(#"{"day_summary":""}"#)
        let generator = DailyRollupGenerator(
            repository: harness.repository,
            settingsRepository: harness.settings,
            tokenStore: DailyMemoryTokenStore(),
            transport: MockLMStudioHTTPTransport.sequence([.success(body: invalid), .success(body: invalid)])
        )

        await XCTAssertThrowsAsyncError({ try await generator.generate(from: eligibility) }) { error in
            guard case .invalidDailyRollupJSON = error as? LMStudioGenerationError else {
                return XCTFail("Expected daily rollup validation error, got \(error)")
            }
        }

        let preserved = try await harness.repository.rollup(for: eligibility.rollupDate)
        XCTAssertEqual(preserved, existing)
    }

    func testGeneratorRejectsActiveOrEmptyEligibilityBeforeNetwork() async throws {
        let harness = try makeHarness()
        try await harness.migrator.migrate()
        let transport = MockLMStudioHTTPTransport.success(body: "{}")
        let generator = DailyRollupGenerator(
            repository: harness.repository, settingsRepository: harness.settings,
            tokenStore: DailyMemoryTokenStore(), transport: transport
        )
        var active = makeEligibility(projectCount: 1)
        active.hasActiveSession = true
        await XCTAssertThrowsAsyncError({ try await generator.generate(from: active) }) {
            XCTAssertEqual($0 as? DailyRollupGeneratorError, .activeSessionInProgress)
        }
        var empty = makeEligibility(projectCount: 0)
        empty.sessions = []
        await XCTAssertThrowsAsyncError({ try await generator.generate(from: empty) }) {
            XCTAssertEqual($0 as? DailyRollupGeneratorError, .noCompletedSessions)
        }
        let requests = await transport.capturedRequests()
        XCTAssertTrue(requests.isEmpty)
    }

    private func makeHarness() throws -> (
        migrator: DatabaseMigrator, repository: DailyRollupRepository, settings: SettingsRepository
    ) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DailyRollupGeneratorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        temporaryRoot = root
        let database = Database(url: root.appendingPathComponent("working-memory.sqlite3"))
        return (DatabaseMigrator(database: database), DailyRollupRepository(database: database), SettingsRepository(database: database))
    }

    private func makeEligibility(projectCount: Int) -> DailyRollupEligibility {
        let projects = (0..<projectCount).map { index in
            Project(id: UUID(), name: "Project \(index + 1)", rootPath: "/tmp/p\(index)", createdAt: Date(), updatedAt: Date())
        }
        let sessions = projects.map { project in
            let session = WorkSession(
                id: UUID(), projectID: project.id, mission: "Mission for \(project.name)", brainDump: "Saved",
                startedAt: Date().addingTimeInterval(-3_600), endedAt: Date(), status: .completed,
                createdAt: Date(), updatedAt: Date()
            )
            return DailyRollupSessionEvidence(
                project: project, session: session, snapshot: nil,
                fallbackCapture: "No snapshot yet; grounded capture for \(project.name)."
            )
        }
        return DailyRollupEligibility(
            rollupDate: "2026-07-13", timezoneIdentifier: "America/Denver",
            dayStart: Date().addingTimeInterval(-7_200), dayEnd: Date().addingTimeInterval(79_200),
            projects: projects, sessions: sessions, sourceFingerprint: "fingerprint", hasActiveSession: false
        )
    }

    private func validJSON(for projects: [Project]) -> String {
        let object: [String: Any] = [
            "day_summary": "The day established the rollup foundation.",
            "project_threads": projects.map { ["project_id": $0.id.uuidString, "summary": "\($0.name) moved forward with grounded evidence."] },
            "carry_forwards": projects.prefix(1).map { ["project_id": $0.id.uuidString, "text": "Verify the next integration boundary."] },
            "closure_note": "The working threads are saved and ready for a calm return."
        ]
        let data = try! JSONSerialization.data(withJSONObject: object)
        return String(data: data, encoding: .utf8)!
    }

    private func completionBody(_ content: String) -> String {
        let object = ["choices": [["message": ["content": content]]]]
        let data = try! JSONSerialization.data(withJSONObject: object)
        return String(data: data, encoding: .utf8)!
    }

    private func requestDictionary(_ request: URLRequest) throws -> [String: Any] {
        let data = try XCTUnwrap(request.httpBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

private actor DailyMemoryTokenStore: LMStudioTokenStore {
    let token: String?
    init(token: String? = nil) { self.token = token }
    func loadToken() async throws -> String? { token }
    func saveToken(_ token: String?) async throws {}
    func deleteToken() async throws {}
}
