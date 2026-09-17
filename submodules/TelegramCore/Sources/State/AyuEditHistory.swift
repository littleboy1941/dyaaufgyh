import Foundation
import Postbox
import SwiftSignalKit

// AyuGram: history of edits of incoming messages.
// Previous versions are kept in a separate item cache collection keyed by message id, not in message
// attributes: a message re-fetched from the server replaces its attributes.

public struct AyuEditHistoryEntry: Codable, Equatable {
    public let text: String
    // When this version appeared: the message date or the date of the edit that produced it
    public let date: Int32

    public init(text: String, date: Int32) {
        self.text = text
        self.date = date
    }
}

private struct AyuEditHistory: Codable {
    var entries: [AyuEditHistoryEntry]
}

private func ayuEditHistoryEntryId(_ id: MessageId) -> ItemCacheEntryId {
    let key = ValueBoxKey(length: 8 + 4 + 4)
    key.setInt64(0, value: id.peerId.toInt64())
    key.setInt32(8, value: id.namespace)
    key.setInt32(12, value: id.id)
    return ItemCacheEntryId(collectionId: Namespaces.CachedItemCollection.ayuEditHistory, key: key)
}

private func ayuStoredEditHistory(transaction: Transaction, id: MessageId) -> [AyuEditHistoryEntry] {
    return transaction.retrieveItemCacheEntry(id: ayuEditHistoryEntryId(id))?.get(AyuEditHistory.self)?.entries ?? []
}

// Called before an edit from the server is applied
func ayuRecordEdit(transaction: Transaction, id: MessageId, updatedText: String) {
    guard id.namespace == Namespaces.Message.Cloud, ayuSettings(transaction: transaction).saveEditHistory else {
        return
    }
    guard let previousMessage = transaction.getMessage(id), previousMessage.flags.contains(.Incoming), previousMessage.text != updatedText else {
        return
    }
    guard let peer = transaction.getPeer(id.peerId), peer is TelegramUser || peer is TelegramGroup || peer is TelegramChannel else {
        return
    }

    var previousDate = previousMessage.timestamp
    if let edited = previousMessage.attributes.first(where: { $0 is EditedMessageAttribute }) as? EditedMessageAttribute {
        previousDate = edited.date
    }

    var entries = ayuStoredEditHistory(transaction: transaction, id: id)
    if entries.last?.text == previousMessage.text {
        return
    }
    entries.append(AyuEditHistoryEntry(text: previousMessage.text, date: previousDate))
    if let entry = CodableEntry(AyuEditHistory(entries: entries)) {
        transaction.putItemCacheEntry(id: ayuEditHistoryEntryId(id), entry: entry)
    }
}

public extension TelegramEngine {
    // Previous versions of a message, oldest first (the current text is not included)
    func ayuEditHistory(messageId: EngineMessage.Id) -> Signal<[AyuEditHistoryEntry], NoError> {
        return self.account.postbox.transaction { transaction -> [AyuEditHistoryEntry] in
            return ayuStoredEditHistory(transaction: transaction, id: messageId)
        }
    }
}
