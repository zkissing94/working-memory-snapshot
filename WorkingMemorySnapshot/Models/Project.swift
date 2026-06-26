import Foundation

struct Project: Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var rootPath: String
    var createdAt: Date
    var updatedAt: Date
}
