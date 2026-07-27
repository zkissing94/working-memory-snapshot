import Foundation

struct Project: Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var rootPath: String
    var isPinned: Bool = false
    var sortOrder: Int = 0
    var createdAt: Date
    var updatedAt: Date
}
