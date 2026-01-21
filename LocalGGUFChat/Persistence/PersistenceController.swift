
import CoreData
import Foundation

final class PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentContainer

    var viewContext: NSManagedObjectContext { container.viewContext }

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "LocalGGUFChat")

        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }

        let desc = container.persistentStoreDescriptions.first
        desc?.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        desc?.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        desc?.shouldMigrateStoreAutomatically = true
        desc?.shouldInferMappingModelAutomatically = true

        container.loadPersistentStores { _, error in
            if let error = error as NSError? {
                fatalError("Unresolved Core Data error \(error), \(error.userInfo)")
            }
        }

        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.undoManager = nil
    }

    func save(_ context: NSManagedObjectContext? = nil) {
        let ctx = context ?? viewContext
        guard ctx.hasChanges else { return }
        do {
            try ctx.save()
        } catch {
            assertionFailure("Core Data save failed: \(error)")
        }
    }

    func newBackgroundContext() -> NSManagedObjectContext {
        let ctx = container.newBackgroundContext()
        ctx.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        ctx.undoManager = nil
        return ctx
    }
}

// MARK: - Convenience create/update

extension PersistenceController {
    @discardableResult
    func upsertModel(from bookmark: Data, displayName: String, originalPath: String?, fileSize: Int64) throws -> ModelReferenceEntity {
        let req: NSFetchRequest<ModelReferenceEntity> = ModelReferenceEntity.fetchRequest()
        req.fetchLimit = 1
        req.predicate = NSPredicate(format: "bookmark == %@", bookmark as NSData)

        if let existing = try viewContext.fetch(req).first {
            existing.displayName = displayName
            existing.originalPath = originalPath
            existing.fileSize = fileSize
            save()
            return existing
        }

        let model = ModelReferenceEntity(context: viewContext)
        model.id = UUID()
        model.displayName = displayName
        model.originalPath = originalPath
        model.fileSize = fileSize
        model.bookmark = bookmark
        model.createdAt = Date()
        save()
        return model
    }

    @discardableResult
    func createChat(title: String?, model: ModelReferenceEntity?) -> ChatEntity {
        let chat = ChatEntity(context: viewContext)
        chat.id = UUID()
        chat.title = (title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? title : "New Chat"
        chat.createdAt = Date()
        chat.updatedAt = Date()
        chat.model = model
        save()
        return chat
    }

    @discardableResult
    func appendMessage(chat: ChatEntity, role: MessageRole, text: String) -> MessageEntity {
        let msg = MessageEntity(context: viewContext)
        msg.id = UUID()
        msg.role = role.rawValue
        msg.text = text
        msg.createdAt = Date()
        msg.editedAt = nil
        msg.isOutdated = false
        msg.chat = chat

        // Maintain ordered relationship
        let mutable = chat.mutableOrderedSetValue(forKey: "messages")
        mutable.add(msg)

        chat.updatedAt = Date()
        if role == .user, chat.title == "New Chat" {
            chat.title = Self.suggestTitle(from: text)
        }

        save()
        return msg
    }

    func markOutdatedAfter(message: MessageEntity) {
        guard let chat = message.chat else { return }
        guard let messages = chat.messages?.array as? [MessageEntity],
              let idx = messages.firstIndex(of: message) else { return }

        for m in messages[(idx + 1)...] {
            m.isOutdated = true
        }
        chat.updatedAt = Date()
        save()
    }

    func deleteFromHere(message: MessageEntity) {
        guard let chat = message.chat else { return }
        guard let messages = chat.messages?.array as? [MessageEntity],
              let idx = messages.firstIndex(of: message) else { return }

        for m in messages[idx...] {
            viewContext.delete(m)
        }
        chat.updatedAt = Date()
        save()
    }

    func truncateOutdatedAndContinue(chat: ChatEntity) -> MessageEntity? {
        guard let messages = chat.messages?.array as? [MessageEntity] else { return nil }
        guard let firstOutdated = messages.first(where: { $0.isOutdated }) else { return nil }
        deleteFromHere(message: firstOutdated)
        return nil
    }

    static func suggestTitle(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "New Chat" }
        let words = trimmed.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        return words.prefix(6).joined(separator: " ")
    }
}
