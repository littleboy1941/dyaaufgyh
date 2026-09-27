import Foundation
import Postbox

// Ayu: only visual appearance is overlaid; flags, identity and permissions remain real.
struct AyuLocalProfile: Equatable, Codable {
    var peerId: Int64
    var serverUserData: Data
    var hasColors: Bool = false
    var nameColor: Int32 = 0
    var backgroundEmojiId: Int64?
    var profileColor: Int32?
    var profileBackgroundEmojiId: Int64?
    var hasStatus: Bool = false
    var emojiStatus: PeerEmojiStatus?

    init(user: TelegramUser) {
        self.peerId = user.id.toInt64()
        let encoder = PostboxEncoder()
        encoder.encodeRootObject(user)
        self.serverUserData = encoder.makeData()
    }

    var serverUser: TelegramUser? {
        return PostboxDecoder(buffer: MemoryBuffer(data: self.serverUserData)).decodeRootObject() as? TelegramUser
    }

    mutating func updateServerUser(_ user: TelegramUser) {
        let encoder = PostboxEncoder()
        encoder.encodeRootObject(user)
        self.serverUserData = encoder.makeData()
    }
}

func ayuUserWithAppearance(_ user: TelegramUser, source: TelegramUser, colors: Bool, status: Bool) -> TelegramUser {
    return TelegramUser(id: user.id, accessHash: user.accessHash, firstName: user.firstName, lastName: user.lastName, username: user.username, phone: user.phone, photo: user.photo, botInfo: user.botInfo, restrictionInfo: user.restrictionInfo, flags: user.flags, emojiStatus: status ? source.emojiStatus : user.emojiStatus, usernames: user.usernames, storiesHidden: user.storiesHidden, nameColor: colors ? source.nameColor : user.nameColor, backgroundEmojiId: colors ? source.backgroundEmojiId : user.backgroundEmojiId, profileColor: colors ? source.profileColor : user.profileColor, profileBackgroundEmojiId: colors ? source.profileBackgroundEmojiId : user.profileBackgroundEmojiId, subscriberCount: user.subscriberCount, verificationIconFileId: user.verificationIconFileId, linkedCommunityId: user.linkedCommunityId)
}

func ayuApplyLocalProfile(transaction: Transaction, user: TelegramUser) -> TelegramUser {
    let settings = ayuSettings(transaction: transaction)
    guard settings.localPremium, !user.flags.contains(.isPremium),
          let profile = settings.ayuLocalProfile, profile.peerId == user.id.toInt64() else { return user }
    var result = user
    if profile.hasColors {
        result = result.withUpdatedNameColor(.preset(PeerNameColor(rawValue: profile.nameColor)))
            .withUpdatedBackgroundEmojiId(profile.backgroundEmojiId)
            .withUpdatedProfileColor(profile.profileColor.map { PeerNameColor(rawValue: $0) })
            .withUpdatedProfileBackgroundEmojiId(profile.profileBackgroundEmojiId)
    }
    if profile.hasStatus {
        var status = profile.emojiStatus
        if let expirationDate = status?.expirationDate, expirationDate <= Int32(Date().timeIntervalSince1970) {
            status = nil
        }
        result = result.withUpdatedEmojiStatus(status)
    }
    return result
}

func ayuUpdateLocalProfileBaseline(transaction: Transaction, user: TelegramUser) {
    var settings = ayuSettings(transaction: transaction)
    guard var profile = settings.ayuLocalProfile, profile.peerId == user.id.toInt64() else { return }
    profile.updateServerUser(user)
    if profile != settings.ayuLocalProfile {
        settings.ayuLocalProfile = profile
        transaction.updatePreferencesEntry(key: PreferencesKeys.ayuSettings, { _ in PreferencesEntry(settings) })
    }
}
