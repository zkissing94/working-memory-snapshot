import XCTest
@testable import WorkingMemorySnapshot

@MainActor
final class DailyRollupViewModelTests: XCTestCase {
    func testReadyBlockedAndStaleStatesAreDerivedFromEligibility() async {
        let readyEligibility = eligibility(active: false, hasSessions: true, fingerprint: "new")
        let repository = DailyRollupRepositoryFake()
        let viewModel = DailyRollupViewModel(
            sourceLoader: DailyRollupSourceLoaderFake(eligibility: readyEligibility),
            repository: repository,
            generator: DailyRollupGeneratorFake(result: .failure(DailyRollupGeneratorError.noCompletedSessions))
        )
        await viewModel.load()
        guard case .ready(let ready) = viewModel.state else {
            return XCTFail("Expected ready state, got \(viewModel.state)")
        }
        XCTAssertEqual(ready.completedSessionCount, 1)

        let blockedViewModel = DailyRollupViewModel(
            sourceLoader: DailyRollupSourceLoaderFake(eligibility: eligibility(active: true, hasSessions: true, fingerprint: "new")),
            repository: DailyRollupRepositoryFake(),
            generator: DailyRollupGeneratorFake(result: .failure(DailyRollupGeneratorError.activeSessionInProgress))
        )
        await blockedViewModel.load()
        guard case .blocked = blockedViewModel.state else {
            return XCTFail("Expected blocked state")
        }

        let existing = rollup(fingerprint: "old")
        let staleRepository = DailyRollupRepositoryFake(existing: existing)
        let staleViewModel = DailyRollupViewModel(
            sourceLoader: DailyRollupSourceLoaderFake(eligibility: readyEligibility),
            repository: staleRepository,
            generator: DailyRollupGeneratorFake(result: .success(existing))
        )
        await staleViewModel.load()
        XCTAssertEqual(staleViewModel.state, .generated(existing, isStale: true))
    }

    func testGenerationTransitionsToGeneratedAndFailurePreservesExistingArtifact() async {
        let eligibility = eligibility(active: false, hasSessions: true, fingerprint: "new")
        let generated = rollup(fingerprint: "new")
        let repository = DailyRollupRepositoryFake()
        let viewModel = DailyRollupViewModel(
            sourceLoader: DailyRollupSourceLoaderFake(eligibility: eligibility),
            repository: repository,
            generator: DailyRollupGeneratorFake(result: .success(generated))
        )
        await viewModel.load()
        await viewModel.generate()
        XCTAssertEqual(viewModel.state, .generated(generated, isStale: false))

        let preserved = rollup(fingerprint: "old")
        let failureRepository = DailyRollupRepositoryFake(existing: preserved)
        let failureViewModel = DailyRollupViewModel(
            sourceLoader: DailyRollupSourceLoaderFake(eligibility: eligibility),
            repository: failureRepository,
            generator: DailyRollupGeneratorFake(result: .failure(LMStudioClientError.serverUnreachable))
        )
        await failureViewModel.load()
        await failureViewModel.generate()
        guard case .failed(let message, let retained) = failureViewModel.state else {
            return XCTFail("Expected failed state")
        }
        XCTAssertEqual(retained, preserved)
        XCTAssertTrue(message.contains("source sessions remain saved"))
    }

    func testSelectingEarlierSameDayRevisionLoadsThatExactArtifactAndSources() async {
        let eligibility = eligibility(active: false, hasSessions: true, fingerprint: "current")
        let latest = rollup(fingerprint: "current", summary: "Latest run")
        let earlier = rollup(
            fingerprint: "earlier",
            summary: "Earlier run with preserved carry-forwards",
            generatedAt: Date().addingTimeInterval(-120)
        )
        let project = eligibility.projects[0]
        let source = DailyRollupSource(
            rollupID: earlier.id,
            sessionID: UUID(),
            projectID: project.id,
            projectName: project.name,
            mission: "Earlier source",
            endedAt: Date(),
            isAvailable: true
        )
        let repository = DailyRollupRepositoryFake(
            existing: latest,
            history: [latest, earlier],
            sourcesByRollupID: [earlier.id: [source]]
        )
        let viewModel = DailyRollupViewModel(
            sourceLoader: DailyRollupSourceLoaderFake(eligibility: eligibility),
            repository: repository,
            generator: DailyRollupGeneratorFake(result: .success(latest))
        )
        await viewModel.load()

        await viewModel.select(earlier)

        guard case .generated(let selected, let isStale) = viewModel.state else {
            return XCTFail("Expected selected revision")
        }
        XCTAssertEqual(selected.id, earlier.id)
        XCTAssertTrue(isStale)
        XCTAssertEqual(viewModel.sources, [source])
    }

    private func eligibility(active: Bool, hasSessions: Bool, fingerprint: String) -> DailyRollupEligibility {
        let project = Project(id: UUID(), name: "Project", rootPath: "/tmp/project", createdAt: Date(), updatedAt: Date())
        let session = WorkSession(
            id: UUID(), projectID: project.id, mission: "Mission", brainDump: "Saved",
            startedAt: Date().addingTimeInterval(-60), endedAt: Date(), status: .completed,
            createdAt: Date(), updatedAt: Date()
        )
        return DailyRollupEligibility(
            rollupDate: "2026-07-13", timezoneIdentifier: "America/Denver",
            dayStart: Date(), dayEnd: Date().addingTimeInterval(86_400),
            projects: hasSessions ? [project] : [],
            sessions: hasSessions ? [DailyRollupSessionEvidence(project: project, session: session, snapshot: nil, fallbackCapture: "Saved")] : [],
            sourceFingerprint: fingerprint, hasActiveSession: active
        )
    }

    private func rollup(
        fingerprint: String,
        summary: String = "Summary",
        generatedAt: Date = Date()
    ) -> DailyRollup {
        DailyRollup(
            id: UUID(), rollupDate: "2026-07-13", timezoneIdentifier: "America/Denver",
            daySummary: summary, projectThreads: [], carryForwards: [], closureNote: "Closed",
            generatorModel: "model", promptVersion: "daily-rollup-v1", sourceFingerprint: fingerprint,
            generatedAt: generatedAt, updatedAt: generatedAt
        )
    }
}

private struct DailyRollupSourceLoaderFake: DailyRollupSourceLoading {
    let eligibility: DailyRollupEligibility
    func load(for date: Date, calendar: Calendar) async throws -> DailyRollupEligibility { eligibility }
}

private actor DailyRollupRepositoryFake: DailyRollupPersisting {
    private var existing: DailyRollup?
    private var history: [DailyRollup]
    private var sourcesByRollupID: [UUID: [DailyRollupSource]]

    init(
        existing: DailyRollup? = nil,
        history: [DailyRollup]? = nil,
        sourcesByRollupID: [UUID: [DailyRollupSource]] = [:]
    ) {
        self.existing = existing
        self.history = history ?? existing.map { [$0] } ?? []
        self.sourcesByRollupID = sourcesByRollupID
    }

    func saveRevision(_ draft: DailyRollupDraft) async throws -> DailyRollup {
        guard let existing else { throw DailyRollupRepositoryError.invalidJSON }
        return existing
    }
    func rollup(for rollupDate: String) async throws -> DailyRollup? { existing }
    func listRollups() async throws -> [DailyRollup] { history }
    func sources(for rollupID: UUID) async throws -> [DailyRollupSource] {
        sourcesByRollupID[rollupID] ?? []
    }
}

private struct DailyRollupGeneratorFake: DailyRollupGenerating {
    let result: Result<DailyRollup, Error>
    func generate(from eligibility: DailyRollupEligibility) async throws -> DailyRollup { try result.get() }
}
