import Foundation

struct Snapshot: Identifiable, Equatable, Sendable {
    let id: UUID
    let sessionID: UUID
    var whatChanged: String
    var decisions: [String]
    var openLoops: [String]
    var nextAction: String
    var resumeBrief: String
    var generatorModel: String?
    var promptVersion: String
    var createdAt: Date
    var updatedAt: Date
}

struct SnapshotDraft: Equatable, Sendable {
    var whatChanged: String
    var decisions: [String]
    var openLoops: [String]
    var nextAction: String
    var resumeBrief: String
    var generatorModel: String?
    var promptVersion: String
}
