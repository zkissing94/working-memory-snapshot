import Foundation

enum DailyRollupScreenState: Equatable {
    case loading
    case empty(DailyRollupEligibility)
    case ready(DailyRollupEligibility)
    case blocked(DailyRollupEligibility)
    case generating(DailyRollup?)
    case generated(DailyRollup, isStale: Bool)
    case failed(message: String, preservedRollup: DailyRollup?)
}

@MainActor
final class DailyRollupViewModel: ObservableObject {
    @Published private(set) var state: DailyRollupScreenState = .loading
    @Published private(set) var history: [DailyRollup] = []
    @Published private(set) var sources: [DailyRollupSource] = []
    @Published private(set) var selectedDate = Date()

    private let sourceLoader: any DailyRollupSourceLoading
    private let repository: any DailyRollupPersisting
    private let generator: any DailyRollupGenerating
    private var eligibility: DailyRollupEligibility?

    init(
        sourceLoader: any DailyRollupSourceLoading,
        repository: any DailyRollupPersisting,
        generator: any DailyRollupGenerating
    ) {
        self.sourceLoader = sourceLoader
        self.repository = repository
        self.generator = generator
    }

    var displayedRollup: DailyRollup? {
        switch state {
        case .generated(let rollup, _): rollup
        case .generating(let rollup): rollup
        case .failed(_, let rollup): rollup
        default: nil
        }
    }

    var canGenerate: Bool {
        eligibility?.canGenerate == true
    }

    var hasActiveSession: Bool {
        eligibility?.hasActiveSession == true
    }

    func load(date: Date = Date()) async {
        let preserved = displayedRollup
        selectedDate = date
        state = .loading
        do {
            let eligibility = try await sourceLoader.load(for: date, calendar: .autoupdatingCurrent)
            self.eligibility = eligibility
            history = try await repository.listRollups()
            let existing = try await repository.rollup(for: eligibility.rollupDate)
            if let existing {
                sources = try await repository.sources(for: existing.id)
                state = .generated(existing, isStale: existing.sourceFingerprint != eligibility.sourceFingerprint)
            } else {
                sources = []
                state = initialState(for: eligibility)
            }
        } catch {
            eligibility = nil
            sources = []
            state = .failed(message: error.localizedDescription, preservedRollup: preserved)
        }
    }

    func generate() async {
        guard let eligibility, eligibility.canGenerate else { return }
        let preserved = displayedRollup
        state = .generating(preserved)
        do {
            let rollup = try await generator.generate(from: eligibility)
            history = try await repository.listRollups()
            sources = try await repository.sources(for: rollup.id)
            state = .generated(rollup, isStale: false)
        } catch {
            state = .failed(message: recoveryMessage(for: error), preservedRollup: preserved)
        }
    }

    func select(_ rollup: DailyRollup) async {
        let preserved = displayedRollup
        let date = date(for: rollup)
        selectedDate = date
        state = .loading
        do {
            let eligibility = try await sourceLoader.load(for: date, calendar: .autoupdatingCurrent)
            self.eligibility = eligibility
            history = try await repository.listRollups()
            sources = try await repository.sources(for: rollup.id)
            state = .generated(rollup, isStale: rollup.sourceFingerprint != eligibility.sourceFingerprint)
        } catch {
            eligibility = nil
            sources = []
            state = .failed(message: error.localizedDescription, preservedRollup: preserved)
        }
    }

    private func initialState(for eligibility: DailyRollupEligibility) -> DailyRollupScreenState {
        if eligibility.hasActiveSession { return .blocked(eligibility) }
        if eligibility.sessions.isEmpty { return .empty(eligibility) }
        return .ready(eligibility)
    }

    private func recoveryMessage(for error: Error) -> String {
        "\(error.localizedDescription) Your source sessions remain saved."
    }

    private func date(for rollup: DailyRollup) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = .autoupdatingCurrent
        formatter.timeZone = .autoupdatingCurrent
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: rollup.rollupDate) ?? rollup.generatedAt
    }
}
