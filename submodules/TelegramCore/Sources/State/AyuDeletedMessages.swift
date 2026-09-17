import Foundation
import Postbox

// AyuGram: keeping messages deleted by the other side.
// Instead of removing such a message from Postbox it gets AyuDeletedMessageAttribute.

func ayuShouldKeepDeletedMessage(transaction: Transaction, message: Message, settings: AyuSettings) -> Bool {
    guard settings.saveDeletedMessages, message.id.namespace == Namespaces.Message.Cloud else {
        return false
    }
    if message.media.contains(where: { $0 is TelegramMediaAction || $0 is TelegramMediaExpiredContent }) {
        return false
    }
    // Self-destructing and view-once content keeps its own semantics
    if message.attributes.contains(where: { $0 is AutoremoveTimeoutMessageAttribute || $0 is AutoclearTimeoutMessageAttribute }) {
        return false
    }

    // A link preview alone isn't media: a text with a link is kept even without saveDeletedMedia
    let hasContentMedia = message.media.contains(where: { !($0 is TelegramMediaWebpage) })
    if message.text.isEmpty && !hasContentMedia {
        return false
    }
    if hasContentMedia && !settings.saveDeletedMedia {
        return false
    }

    guard let peer = transaction.getPeer(message.id.peerId) else {
        return false
    }
    switch peer {
    case let user as TelegramUser:
        if user.id.id._internalGetInt64Value() == 777000 {
            return false
        }
        if user.botInfo != nil {
            return settings.saveDeletedFromBots
        }
        return settings.saveDeletedInPrivateChats
    case is TelegramGroup:
        return settings.saveDeletedInGroups
    case let channel as TelegramChannel:
        if case .group = channel.info {
            return settings.saveDeletedInGroups
        } else {
            return settings.saveDeletedInChannels
        }
    default:
        return false
    }
}

// Returns true if the message is kept (marked as deleted) and must not be removed.
func ayuMarkMessageDeleted(transaction: Transaction, id: MessageId, settings: AyuSettings, timestamp: Int32) -> Bool {
    guard let message = transaction.getMessage(id) else {
        return false
    }
    if message.ayuDeletedDate != nil {
        return true
    }
    guard ayuShouldKeepDeletedMessage(transaction: transaction, message: message, settings: settings) else {
        return false
    }
    transaction.updateMessage(id, update: { currentMessage in
        guard currentMessage.ayuDeletedDate == nil else {
            return .skip
        }
        var attributes = currentMessage.attributes
        attributes.append(AyuDeletedMessageAttribute(date: timestamp))
        return .update(StoreMessage(id: currentMessage.id, customStableId: nil, globallyUniqueId: currentMessage.globallyUniqueId, groupingKey: currentMessage.groupingKey, threadId: currentMessage.threadId, timestamp: currentMessage.timestamp, flags: StoreMessageFlags(currentMessage.flags), tags: currentMessage.tags, globalTags: currentMessage.globalTags, localTags: currentMessage.localTags, forwardInfo: currentMessage.forwardInfo.flatMap(StoreMessageForwardInfo.init), authorId: currentMessage.author?.id, text: currentMessage.text, attributes: attributes, media: currentMessage.media))
    })
    return true
}

func ayuCurrentTimestamp() -> Int32 {
    return Int32(Date().timeIntervalSince1970)
}
