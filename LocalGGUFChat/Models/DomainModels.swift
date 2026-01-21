
import Foundation
import CoreData

enum MessageRole: Int16, Codable {
    case user = 0
    case assistant = 1
}

struct ModelReference: Identifiable, Hashable {
    let id: UUID
    let displayName: String
    let originalPath: String?
    let fileSize: Int64
    let bookmark: Data
    let createdAt: Date
}

struct Chat: Identifiable, Hashable {
    let id: UUID
    let title: String
    let createdAt: Date
    let updatedAt: Date
    let model: ModelReference?
}

struct Message: Identifiable, Hashable {
    let id: UUID
    let role: MessageRole
    let text: String
    let createdAt: Date
    let editedAt: Date?
    let isOutdated: Bool
}

// MARK: - Mapping

extension ModelReference {
    init(_ entity: ModelReferenceEntity) {
        self.id = entity.id ?? UUID()
        self.displayName = entity.displayName ?? "Model"
        self.originalPath = entity.originalPath
        self.fileSize = entity.fileSize
        self.bookmark = entity.bookmark ?? Data()
        self.createdAt = entity.createdAt ?? Date()
    }
}

extension Chat {
    init(_ entity: ChatEntity) {
        self.id = entity.id ?? UUID()
        self.title = (entity.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? (entity.title ?? "Chat") : "Chat"
        self.createdAt = entity.createdAt ?? Date()
        self.updatedAt = entity.updatedAt ?? Date()
        self.model = entity.model.map(ModelReference.init)
    }
}

extension Message {
    init(_ entity: MessageEntity) {
        self.id = entity.id ?? UUID()
        self.role = MessageRole(rawValue: entity.role) ?? .user
        self.text = entity.text ?? ""
        self.createdAt = entity.createdAt ?? Date()
        self.editedAt = entity.editedAt
        self.isOutdated = entity.isOutdated
    }
}
