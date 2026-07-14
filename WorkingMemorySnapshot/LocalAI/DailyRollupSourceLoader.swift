import CryptoKit
import Foundation

protocol DailyRollupSourceLoading: Sendable {
    func load(for date: Date, calendar: Calendar) async throws -> DailyRollupEligibility
}

extension DailyRollupSourceLoading {
    func load(for date: Date) async throws -> DailyRollupEligibility {
        try await load(for: date, calendar: .autoupdatingCurrent)
    }
}

struct DailyRollupSourceLoader: DailyRollupSourceLoading {
    let projectRepository: ProjectRepository
    let sessionRepository: SessionRepository
    let snapshotRepository: SnapshotRepository
    let pomodoroBlockRepository: PomodoroBlockRepository
    let workIncrementRepository: WorkIncrementRepository

    func load(
        for date: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) async throws -> DailyRollupEligibility {
        let bounds = DailyRollupDay.bounds(containing: date, calendar: calendar)
        let projects = try await projectRepository.listProjects()
        let activeSession = try await sessionRepository.activeSession()
        var evidence: [DailyRollupSessionEvidence] = []

        for project in projects {
            let sessions = try await sessionRepository.listSessions(for: project.id)
            for session in sessions where isEligible(session, bounds: bounds) {
                let snapshot = try await snapshotRepository.snapshot(for: session.id)
                let fallbackText: String
                if snapshot == nil {
                    fallbackText = try await fallbackCapture(for: session)
                } else {
                    fallbackText = ""
                }
                evidence.append(
                    DailyRollupSessionEvidence(
                        project: project,
                        session: session,
                        snapshot: snapshot,
                        fallbackCapture: fallbackText
                    )
                )
            }
        }

        evidence.sort {
            ($0.session.endedAt ?? $0.session.startedAt) < ($1.session.endedAt ?? $1.session.startedAt)
        }
        let participatingIDs = Set(evidence.map(\.project.id))
        let participatingProjects = projects
            .filter { participatingIDs.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        return DailyRollupEligibility(
            rollupDate: DailyRollupDay.key(for: date, calendar: calendar),
            timezoneIdentifier: calendar.timeZone.identifier,
            dayStart: bounds.start,
            dayEnd: bounds.end,
            projects: participatingProjects,
            sessions: evidence,
            sourceFingerprint: fingerprint(for: evidence),
            hasActiveSession: activeSession != nil
        )
    }

    private func isEligible(
        _ session: WorkSession,
        bounds: (start: Date, end: Date)
    ) -> Bool {
        guard session.status == .completed, let endedAt = session.endedAt else {
            return false
        }
        return endedAt >= bounds.start && endedAt < bounds.end
    }

    private func fallbackCapture(for session: WorkSession) async throws -> String {
        let blocks = try await pomodoroBlockRepository.listBlocks(for: session.id)
        let increments = try await workIncrementRepository.listIncrementsForSession(session.id)
        let incrementsByBlock = Dictionary(grouping: increments, by: \.blockID)
        var lines: [String] = [
            "Mission: \(session.mission)",
            "Brain dump: \(normalized(session.brainDump) ?? "(none provided)")"
        ]

        for block in blocks.prefix(8) {
            let intention = normalized(block.intention)
            let summary = normalized(block.summary)
            if intention != nil || summary != nil {
                lines.append("Block \(block.blockIndex): \(intention ?? "(no intention)") | \(summary ?? "(no summary)")")
            }
            for increment in (incrementsByBlock[block.id] ?? []).prefix(8) {
                let detail = normalized(increment.detail).map { " — \($0)" } ?? ""
                lines.append("\(increment.kind.displayName): \(increment.title)\(detail)")
            }
        }
        return bounded(lines.joined(separator: "\n"), maximumCharacters: 2_400)
    }

    private func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func bounded(_ value: String, maximumCharacters: Int) -> String {
        guard value.count > maximumCharacters else { return value }
        return String(value.prefix(maximumCharacters)) + "\n[additional saved capture omitted]"
    }

    private func fingerprint(for evidence: [DailyRollupSessionEvidence]) -> String {
        let source = evidence.map { item in
            [
                item.project.id.uuidString,
                DateCoding.string(from: item.project.updatedAt),
                item.session.id.uuidString,
                DateCoding.string(from: item.session.updatedAt),
                item.snapshot.map { DateCoding.string(from: $0.updatedAt) } ?? "no-snapshot"
            ].joined(separator: "|")
        }
        .joined(separator: "\n")
        return SHA256.hash(data: Data(source.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
