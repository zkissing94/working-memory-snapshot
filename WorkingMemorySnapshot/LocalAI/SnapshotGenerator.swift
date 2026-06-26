import Foundation

protocol SessionSnapshotGenerating: Sendable {
    func generateSnapshot(for project: Project, session: WorkSession) async throws -> Snapshot
}

struct SnapshotGenerator: SessionSnapshotGenerating {
    private let eventRepository: EventRepository
    private let snapshotRepository: SnapshotRepository
    private let settingsRepository: SettingsRepository
    private let tokenStore: any LMStudioTokenStore
    private let transport: any LMStudioHTTPTransport
    private let evidenceCompactor: EvidenceCompactor
    private let promptBuilder: PromptBuilder

    init(
        eventRepository: EventRepository,
        snapshotRepository: SnapshotRepository,
        settingsRepository: SettingsRepository,
        tokenStore: any LMStudioTokenStore,
        transport: any LMStudioHTTPTransport = URLSessionLMStudioHTTPTransport(),
        evidenceCompactor: EvidenceCompactor = EvidenceCompactor(),
        promptBuilder: PromptBuilder = PromptBuilder()
    ) {
        self.eventRepository = eventRepository
        self.snapshotRepository = snapshotRepository
        self.settingsRepository = settingsRepository
        self.tokenStore = tokenStore
        self.transport = transport
        self.evidenceCompactor = evidenceCompactor
        self.promptBuilder = promptBuilder
    }

    func generateSnapshot(for project: Project, session: WorkSession) async throws -> Snapshot {
        guard session.status == .completed else {
            throw SnapshotGeneratorError.sessionNotCompleted
        }

        let settings = try await settingsRepository.loadLMStudioSettings().normalized()
        guard !settings.selectedModelID.isEmpty else {
            throw LMStudioGenerationError.noModelSelected
        }

        let token = try await tokenStore.loadToken()
        let events = try await eventRepository.listEvents(for: session.id)
        let digest = evidenceCompactor.compact(
            project: project,
            session: session,
            events: events
        )
        let prompt = promptBuilder.makePrompt(from: digest)
        let client = try LMStudioClient(
            baseURLString: settings.baseURLString,
            apiToken: token,
            transport: transport
        )
        let result = try await client.generateSnapshot(
            modelID: settings.selectedModelID,
            systemPrompt: prompt.systemPrompt,
            userPrompt: prompt.userPrompt
        )
        let draft = SnapshotDraft(
            whatChanged: result.whatChanged,
            decisions: result.decisions,
            openLoops: result.openLoops,
            nextAction: result.nextAction,
            resumeBrief: result.resumeBrief,
            generatorModel: settings.selectedModelID,
            promptVersion: prompt.promptVersion
        )

        return try await snapshotRepository.saveOrReplaceSnapshot(draft, for: session.id)
    }
}

enum SnapshotGeneratorError: Error, Equatable, LocalizedError {
    case sessionNotCompleted

    var errorDescription: String? {
        switch self {
        case .sessionNotCompleted:
            "Snapshot generation requires a completed session."
        }
    }
}
