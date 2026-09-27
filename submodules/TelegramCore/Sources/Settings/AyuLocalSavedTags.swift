import Foundation
import Postbox

// Ayu: Saved Messages tags are private local metadata, never sent as reactions.
struct AyuLocalSavedTags: Equatable, Codable {
    struct Entry: Equatable, Codable {
        var reactions: [MessageReaction.Reaction]
        var serverAttributeData: Data
        var threadId: Int64?
        var timestamp: Int32
    }
    var peerId: Int64
    var messages: [Int32: Entry] = [:]
    var titles: [SavedMessageTags.Tag] = []
    var serverTags: SavedMessageTags?

    var tags: SavedMessageTags {
        var counts: [MessageReaction.Reaction: Int] = [:]
        for entry in self.messages.values {
            for reaction in Set(entry.reactions) { counts[reaction, default: 0] += 1 }
        }
        let reactions = Set(counts.keys).union(self.titles.map { $0.reaction }).sorted()
        return SavedMessageTags(hash: 0, tags: reactions.map { reaction in
            SavedMessageTags.Tag(reaction: reaction, title: self.titles.first(where: { $0.reaction == reaction })?.title, count: counts[reaction] ?? 0)
        })
    }
}

func ayuUsesLocalSavedTags(transaction: Transaction, peerId: PeerId) -> Bool {
    guard let state = transaction.getState() as? AuthorizedAccountState, state.peerId == peerId else { return false }
    return ayuSettings(transaction: transaction).localPremium
        && !((transaction.getPeer(peerId) as? TelegramUser)?.isPremium ?? false)
}

private func ayuReactionData(_ attributes: [MessageAttribute]) -> Data {
    guard let value = attributes.first(where: { $0 is ReactionsMessageAttribute }) else { return Data() }
    let encoder = PostboxEncoder()
    encoder.encodeRootObject(value)
    return encoder.makeData()
}

func ayuLocalTagsAttribute(_ reactions: [MessageReaction.Reaction]) -> ReactionsMessageAttribute {
    return ReactionsMessageAttribute(canViewList: false, isTags: true, reactions: reactions.enumerated().map {
        MessageReaction(value: $0.element, count: 1, chosenOrder: $0.offset)
    }, recentPeers: [], topPeers: [])
}

func ayuSetLocalSavedTags(transaction: Transaction, message: Message, reactions: [MessageReaction.Reaction]) {
    var settings = ayuSettings(transaction: transaction)
    var local = settings.ayuLocalSavedTags ?? AyuLocalSavedTags(peerId: message.id.peerId.toInt64(), serverTags: _internal_savedMessageTags(transaction: transaction))
    let previous = local.messages[message.id.id]
    local.messages[message.id.id] = AyuLocalSavedTags.Entry(reactions: reactions, serverAttributeData: previous?.serverAttributeData ?? ayuReactionData(message.attributes), threadId: message.threadId, timestamp: message.timestamp)
    settings.ayuLocalSavedTags = local
    transaction.updatePreferencesEntry(key: PreferencesKeys.ayuSettings, { _ in PreferencesEntry(settings) })
    _internal_setSavedMessageTags(transaction: transaction, savedMessageTags: local.tags)
}

func ayuPreservingLocalSavedTags(transaction: Transaction, incoming: StoreMessage) -> StoreMessage {
    guard case let .Id(id) = incoming.id, id.namespace == Namespaces.Message.Cloud else { return incoming }
    var settings = ayuSettings(transaction: transaction)
    guard var local = settings.ayuLocalSavedTags, local.peerId == id.peerId.toInt64(),
          ayuUsesLocalSavedTags(transaction: transaction, peerId: id.peerId),
          var entry = local.messages[id.id] else { return incoming }
    let serverData = ayuReactionData(incoming.attributes)
    if entry.serverAttributeData != serverData {
        entry.serverAttributeData = serverData
        local.messages[id.id] = entry
        settings.ayuLocalSavedTags = local
        transaction.updatePreferencesEntry(key: PreferencesKeys.ayuSettings, { _ in PreferencesEntry(settings) })
    }
    var attributes = incoming.attributes.filter { !($0 is ReactionsMessageAttribute) && !($0 is PendingReactionsMessageAttribute) }
    attributes.append(ayuLocalTagsAttribute(entry.reactions))
    return incoming.withUpdatedAttributes(attributes)
}

func ayuRestoreLocalSavedTags(transaction: Transaction, accountPeerId: PeerId, enabled: Bool, savedTags: AyuLocalSavedTags?) {
    let settings = ayuSettings(transaction: transaction)
    guard let local = settings.ayuLocalSavedTags ?? savedTags, local.peerId == accountPeerId.toInt64() else { return }
    let useLocal = enabled && ayuUsesLocalSavedTags(transaction: transaction, peerId: accountPeerId)
    for (id, entry) in local.messages {
        let messageId = MessageId(peerId: accountPeerId, namespace: Namespaces.Message.Cloud, id: id)
        transaction.updateMessage(messageId, update: { message in
            var attributes = message.attributes.filter { !($0 is ReactionsMessageAttribute) && !($0 is PendingReactionsMessageAttribute) }
            if useLocal {
                attributes.append(ayuLocalTagsAttribute(entry.reactions))
            } else if !entry.serverAttributeData.isEmpty, let attribute = PostboxDecoder(buffer: MemoryBuffer(data: entry.serverAttributeData)).decodeRootObject() as? ReactionsMessageAttribute {
                attributes.append(attribute)
            }
            return .update(StoreMessage(id: message.id, customStableId: nil, globallyUniqueId: message.globallyUniqueId, groupingKey: message.groupingKey, threadId: message.threadId, timestamp: message.timestamp, flags: StoreMessageFlags(message.flags), tags: message.tags, globalTags: message.globalTags, localTags: message.localTags, forwardInfo: message.forwardInfo.flatMap(StoreMessageForwardInfo.init), authorId: message.author?.id, text: message.text, attributes: attributes, media: message.media))
        })
        if !useLocal {
            for reaction in entry.reactions {
                let space = MessageHistoryHoleOperationSpace.customTag(ReactionsMessageAttribute.messageTag(reaction: reaction), nil)
                transaction.addHole(peerId: accountPeerId, threadId: nil, namespace: Namespaces.Message.Cloud, space: space, range: 1 ... (Int32.max - 1))
                if let threadId = entry.threadId {
                    transaction.addHole(peerId: accountPeerId, threadId: threadId, namespace: Namespaces.Message.Cloud, space: space, range: 1 ... (Int32.max - 1))
                }
            }
        }
    }
    _internal_setSavedMessageTags(transaction: transaction, savedMessageTags: useLocal ? local.tags : (local.serverTags ?? SavedMessageTags(hash: 0, tags: [])))
}

func ayuRemoveLocalSavedTags(transaction: Transaction, ids: [MessageId]) {
    var settings = ayuSettings(transaction: transaction)
    guard var local = settings.ayuLocalSavedTags else { return }
    var changed = false
    for id in ids where id.peerId.toInt64() == local.peerId && id.namespace == Namespaces.Message.Cloud {
        if local.messages.removeValue(forKey: id.id) != nil { changed = true }
    }
    if changed {
        settings.ayuLocalSavedTags = local
        transaction.updatePreferencesEntry(key: PreferencesKeys.ayuSettings, { _ in PreferencesEntry(settings) })
        if ayuUsesLocalSavedTags(transaction: transaction, peerId: PeerId(local.peerId)) {
            _internal_setSavedMessageTags(transaction: transaction, savedMessageTags: local.tags)
        }
    }
}

func ayuRefreshLocalSavedTagsSummaries(transaction: Transaction, peerId: PeerId, threadId: Int64?) {
    let local = ayuSettings(transaction: transaction).ayuLocalSavedTags
    guard local == nil || local?.peerId == peerId.toInt64() else { return }
    var counts: [MessageReaction.Reaction: Int32] = [:]
    if let local {
        for entry in local.messages.values where threadId == nil || entry.threadId == threadId {
            for reaction in Set(entry.reactions) { counts[reaction, default: 0] += 1 }
        }
    }
    let previousTags = transaction.getMessageTagSummaryCustomTags(peerId: peerId, threadId: threadId, tagMask: [], namespace: Namespaces.Message.Cloud)
    let topId = transaction.getTopPeerMessageId(peerId: peerId, namespace: Namespaces.Message.Cloud)?.id ?? 1
    var valid: [MemoryBuffer] = []
    for (reaction, count) in counts {
        let tag = ReactionsMessageAttribute.messageTag(reaction: reaction)
        valid.append(tag)
        transaction.replaceMessageTagSummary(peerId: peerId, threadId: threadId, tagMask: [], namespace: Namespaces.Message.Cloud, customTag: tag, count: count, maxId: topId)
    }
    for tag in previousTags where !valid.contains(tag) {
        transaction.replaceMessageTagSummary(peerId: peerId, threadId: threadId, tagMask: [], namespace: Namespaces.Message.Cloud, customTag: tag, count: 0, maxId: topId)
    }
    transaction.setPreferencesEntry(key: PreferencesKeys.didCacheSavedMessageTags(threadId: threadId), value: PreferencesEntry(data: Data()))
}

func ayuPreserveLocalSavedReactionUpdate(transaction: Transaction, messageId: MessageId, reactions: ReactionsMessageAttribute) -> Bool {
    var settings = ayuSettings(transaction: transaction)
    guard var local = settings.ayuLocalSavedTags, local.peerId == messageId.peerId.toInt64(),
          messageId.namespace == Namespaces.Message.Cloud,
          ayuUsesLocalSavedTags(transaction: transaction, peerId: messageId.peerId),
          var entry = local.messages[messageId.id] else { return false }
    entry.serverAttributeData = ayuReactionData([reactions])
    local.messages[messageId.id] = entry
    settings.ayuLocalSavedTags = local
    transaction.updatePreferencesEntry(key: PreferencesKeys.ayuSettings, { _ in PreferencesEntry(settings) })
    return true
}

func ayuRemoveLocalSavedTagsForHistory(transaction: Transaction, peerId: PeerId, threadId: Int64?, namespaces: MessageIdNamespaces, minTimestamp: Int32? = nil, maxTimestamp: Int32? = nil) {
    guard namespaces.contains(Namespaces.Message.Cloud), let local = ayuSettings(transaction: transaction).ayuLocalSavedTags, local.peerId == peerId.toInt64() else { return }
    let ids = local.messages.compactMap { id, entry -> MessageId? in
        if let threadId, entry.threadId != threadId { return nil }
        if let minTimestamp, entry.timestamp < minTimestamp { return nil }
        if let maxTimestamp, entry.timestamp > maxTimestamp { return nil }
        return MessageId(peerId: peerId, namespace: Namespaces.Message.Cloud, id: id)
    }
    ayuRemoveLocalSavedTags(transaction: transaction, ids: ids)
}
