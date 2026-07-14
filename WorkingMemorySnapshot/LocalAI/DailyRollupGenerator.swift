import Foundation

protocol DailyRollupGenerating: Sendable {
    func generate(from eligibility: DailyRollupEligibility) async throws -> DailyRollup
}

struct DailyRollupGenerator: DailyRollupGenerating {
    let repository: DailyRollupRepository
    let settingsRepository: SettingsRepository
    let tokenStore: any LMStudioTokenStore
    let transport: any LMStudioHTTPTransport
    let promptBuilder: DailyRollupPromptBuilder

    init(
        repository: DailyRollupRepository,
        settingsRepository: SettingsRepository,
        tokenStore: any LMStudioTokenStore,
        transport: any LMStudioHTTPTransport = URLSessionLMStudioHTTPTransport(),
        promptBuilder: DailyRollupPromptBuilder = DailyRollupPromptBuilder()
    ) {
        self.repository = repository
        self.settingsRepository = settingsRepository
        self.tokenStore = tokenStore
        self.transport = transport
        self.promptBuilder = promptBuilder
    }

    func generate(from eligibility: DailyRollupEligibility) async throws -> DailyRollup {
        guard !eligibility.hasActiveSession else {
            throw DailyRollupGeneratorError.activeSessionInProgress
        }
        guard !eligibility.sessions.isEmpty else {
            throw DailyRollupGeneratorError.noCompletedSessions
        }

        let settings = try await settingsRepository.loadLMStudioSettings().normalized()
        guard !settings.selectedModelID.isEmpty else {
            throw LMStudioGenerationError.noModelSelected
        }
        let token = try await tokenStore.loadToken()
        let prompt = promptBuilder.makePrompt(from: eligibility)
        let expectedProjectIDs = Set(eligibility.projects.map(\.id))
        let client = try LMStudioClient(
            baseURLString: settings.baseURLString,
            apiToken: token,
            transport: transport
        )
        let result = try await client.generateDailyRollup(
            modelID: settings.selectedModelID,
            systemPrompt: prompt.systemPrompt,
            userPrompt: prompt.userPrompt,
            expectedProjectIDs: expectedProjectIDs
        )
        let projectsByID = Dictionary(uniqueKeysWithValues: eligibility.projects.map { ($0.id, $0) })

        let threads = result.projectThreads.compactMap { thread -> DailyProjectThread? in
            guard let project = projectsByID[thread.projectID] else { return nil }
            return DailyProjectThread(
                projectID: project.id,
                projectName: project.name,
                summary: thread.summary
            )
        }
        let carryForwards = result.carryForwards.compactMap { carry -> DailyCarryForward? in
            guard let project = projectsByID[carry.projectID] else { return nil }
            return DailyCarryForward(
                projectID: project.id,
                projectName: project.name,
                text: carry.text
            )
        }
        let placeholderRollupID = UUID()
        let sources = eligibility.sessions.compactMap { item -> DailyRollupSource? in
            guard let endedAt = item.session.endedAt else { return nil }
            return DailyRollupSource(
                rollupID: placeholderRollupID,
                sessionID: item.session.id,
                projectID: item.project.id,
                projectName: item.project.name,
                mission: item.session.mission,
                endedAt: endedAt,
                isAvailable: true
            )
        }

        return try await repository.saveOrReplace(
            DailyRollupDraft(
                rollupDate: eligibility.rollupDate,
                timezoneIdentifier: eligibility.timezoneIdentifier,
                daySummary: result.daySummary,
                projectThreads: threads,
                carryForwards: carryForwards,
                closureNote: result.closureNote,
                generatorModel: settings.selectedModelID,
                promptVersion: prompt.promptVersion,
                sourceFingerprint: eligibility.sourceFingerprint,
                sources: sources
            )
        )
    }
}

enum DailyRollupGeneratorError: Error, Equatable, LocalizedError {
    case activeSessionInProgress
    case noCompletedSessions

    var errorDescription: String? {
        switch self {
        case .activeSessionInProgress:
            "End the active session before generating the Daily Rollup."
        case .noCompletedSessions:
            "There are no completed sessions to roll up for this day."
        }
    }
}
