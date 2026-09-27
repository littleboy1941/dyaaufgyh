import Foundation
import Postbox
import Emoji

// Ayu: wire-compatible with AyuGram Desktop/Android. Never change TelegramUser.flags.
private let ayuEmojiUrlPrefix = "tg://emoji?id="

func ayuLocalPremiumEmojiFileId(url: String) -> Int64? {
    guard url.hasPrefix(ayuEmojiUrlPrefix) else {
        return nil
    }
    let value = url.dropFirst(ayuEmojiUrlPrefix.count)
    guard !value.isEmpty, value.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
          let fileId = Int64(value), fileId > 0 else {
        return nil
    }
    return fileId
}

private func ayuIsSingleEmoji(text: String, range: Range<Int>) -> Bool {
    guard range.lowerBound >= 0, range.upperBound <= text.utf16.count, !range.isEmpty,
          let stringRange = Range(NSRange(location: range.lowerBound, length: range.count), in: text),
          text.indices.contains(stringRange.lowerBound),
          stringRange.upperBound == text.endIndex || text.indices.contains(stringRange.upperBound) else {
        return false
    }
    return String(text[stringRange]).isSingleEmoji
}

func ayuLocalPremiumEmojiHasMarker(_ entity: MessageTextEntity, entities: [MessageTextEntity]) -> Bool {
    guard case let .CustomEmoji(_, fileId) = entity.type else {
        return false
    }
    return entities.contains { other in
        guard other.range == entity.range, case let .TextUrl(url) = other.type else {
            return false
        }
        return ayuLocalPremiumEmojiFileId(url: url) == fileId
    }
}

func ayuDecodeLocalPremiumEmoji(text: String, entities: [MessageTextEntity]) -> [MessageTextEntity] {
    var ayuRenderedRanges = Set<Range<Int>>()
    for entity in entities {
        if case .CustomEmoji = entity.type {
            ayuRenderedRanges.insert(entity.range)
        }
    }
    var result: [MessageTextEntity] = []
    for entity in entities {
        result.append(entity)
        if case let .TextUrl(url) = entity.type,
           let fileId = ayuLocalPremiumEmojiFileId(url: url),
           ayuIsSingleEmoji(text: text, range: entity.range),
           ayuRenderedRanges.insert(entity.range).inserted {
            result.append(MessageTextEntity(range: entity.range, type: .CustomEmoji(stickerPack: nil, fileId: fileId)))
        }
    }
    return result
}

func ayuOutgoingEmojiEntities(transaction: Transaction, accountPeerId: PeerId, peerId: PeerId, text: String, entities: [MessageTextEntity]) -> [MessageTextEntity] {
    // Saved Messages already accepts native custom emoji. Paid accounts keep native transport.
    guard peerId != accountPeerId, ayuSettings(transaction: transaction).localPremium,
          let user = transaction.getPeer(accountPeerId) as? TelegramUser,
          !user.flags.contains(.isPremium) else {
        return entities
    }
    return entities.compactMap { entity in
        guard case let .CustomEmoji(stickerPack, fileId) = entity.type else {
            return entity
        }
        if ayuLocalPremiumEmojiHasMarker(entity, entities: entities) {
            return nil
        }
        guard fileId > 0, ayuIsSingleEmoji(text: text, range: entity.range) else {
            return entity
        }
        // Free emoji and the group's own emoji pack remain native when the file is known.
        if let file = transaction.getMedia(MediaId(namespace: Namespaces.Media.CloudFile, id: fileId)) as? TelegramMediaFile {
            if !file.isPremiumEmoji {
                return entity
            }
            if let pack = (transaction.getPeerCachedData(peerId: peerId) as? CachedChannelData)?.emojiPack {
                let reference = StickerPackReference.id(id: pack.id.id, accessHash: pack.accessHash)
                if stickerPack == reference || file.attributes.contains(where: { attribute in
                    if case let .CustomEmoji(_, _, _, packReference) = attribute {
                        return packReference == reference
                    }
                    return false
                }) {
                    return entity
                }
            }
        }
        return MessageTextEntity(range: entity.range, type: .TextUrl(url: ayuEmojiUrlPrefix + String(fileId)))
    }
}
