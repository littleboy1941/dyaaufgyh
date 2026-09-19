import Foundation
import Postbox
import SwiftSignalKit

// AyuGram settings, stored per account in Postbox preferences so that state replay
// (AccountStateManagementUtils) can read them inside the same transaction.
public struct AyuSettings: Equatable, Codable {
    public static let `default` = AyuSettings()

    // Keep messages deleted by the other side
    public var saveDeletedMessages: Bool = true
    public var saveDeletedInPrivateChats: Bool = true
    public var saveDeletedInGroups: Bool = true
    public var saveDeletedInChannels: Bool = true
    public var saveDeletedFromBots: Bool = false
    public var saveDeletedMedia: Bool = true

    // Keep previous versions of edited incoming messages
    public var saveEditHistory: Bool = true

    // Self-destructing and view-once media stays in the chat and can be opened again
    public var keepSelfDestructingMedia: Bool = true

    // Screenshots and screen recording are not blacked out, and view-once playback is not paused
    public var allowScreenCapture: Bool = true
    // Taking a screenshot does not notify the other side (cloud chats: view-once media)
    public var dontNotifyScreenshots: Bool = true
    // The same for secret chats, where the notification is normally expected: off by default
    public var dontNotifyScreenshotsInSecretChats: Bool = false
    // Saving, copying and the Forward button are available in chats that restrict them
    public var ignoreCopyRestrictions: Bool = true

    // Sponsored posts in channels and sponsored results in search are neither requested nor shown
    public var disableAds: Bool = true
    // The "similar channels" block is neither requested nor shown
    public var hideSimilarChannels: Bool = true
    // Message timestamps include seconds
    public var showMessageSeconds: Bool = false
    // Link previews are requested through a mirror host that renders them properly (x.com, Reddit, ...)
    public var improveLinkPreviews: Bool = true

    // Ghost mode: the master switch. Every ghost* toggle below only applies while this is on, so the
    // individual choices survive turning the mode off and back on.
    public var ghostMode: Bool = false
    // Reading a chat, a topic or a discussion does not send a read receipt
    public var ghostDontReadMessages: Bool = true
    // Opening media, voice messages and round videos does not mark them as viewed
    public var ghostDontReadMedia: Bool = true
    // Channel posts are fetched without incrementing the view counter
    public var ghostDontCountViews: Bool = true
    // Watching a story neither marks it read nor increments its view counter
    public var ghostDontReadStories: Bool = true
    // Typing, and the upload progress that shares the same request, are not reported
    public var ghostDontSendTyping: Bool = true
    // The periodic online status is not sent
    public var ghostDontSendOnline: Bool = true
    // Sending a message makes the server consider you online, so push an offline status right after
    public var ghostOfflineAfterSend: Bool = true

    public init() {
    }

    private enum CodingKeys: String, CodingKey {
        case saveDeletedMessages
        case saveDeletedInPrivateChats
        case saveDeletedInGroups
        case saveDeletedInChannels
        case saveDeletedFromBots
        case saveDeletedMedia
        case saveEditHistory
        case keepSelfDestructingMedia
        case allowScreenCapture
        case dontNotifyScreenshots
        case dontNotifyScreenshotsInSecretChats
        case ignoreCopyRestrictions
        case disableAds
        case hideSimilarChannels
        case showMessageSeconds
        case improveLinkPreviews
        case ghostMode
        case ghostDontReadMessages
        case ghostDontReadMedia
        case ghostDontCountViews
        case ghostDontReadStories
        case ghostDontSendTyping
        case ghostDontSendOnline
        case ghostOfflineAfterSend
    }

    // Every key is optional so that settings saved by an older build decode with defaults
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AyuSettings()
        self.saveDeletedMessages = try container.decodeIfPresent(Bool.self, forKey: .saveDeletedMessages) ?? defaults.saveDeletedMessages
        self.saveDeletedInPrivateChats = try container.decodeIfPresent(Bool.self, forKey: .saveDeletedInPrivateChats) ?? defaults.saveDeletedInPrivateChats
        self.saveDeletedInGroups = try container.decodeIfPresent(Bool.self, forKey: .saveDeletedInGroups) ?? defaults.saveDeletedInGroups
        self.saveDeletedInChannels = try container.decodeIfPresent(Bool.self, forKey: .saveDeletedInChannels) ?? defaults.saveDeletedInChannels
        self.saveDeletedFromBots = try container.decodeIfPresent(Bool.self, forKey: .saveDeletedFromBots) ?? defaults.saveDeletedFromBots
        self.saveDeletedMedia = try container.decodeIfPresent(Bool.self, forKey: .saveDeletedMedia) ?? defaults.saveDeletedMedia
        self.saveEditHistory = try container.decodeIfPresent(Bool.self, forKey: .saveEditHistory) ?? defaults.saveEditHistory
        self.keepSelfDestructingMedia = try container.decodeIfPresent(Bool.self, forKey: .keepSelfDestructingMedia) ?? defaults.keepSelfDestructingMedia
        self.allowScreenCapture = try container.decodeIfPresent(Bool.self, forKey: .allowScreenCapture) ?? defaults.allowScreenCapture
        self.dontNotifyScreenshots = try container.decodeIfPresent(Bool.self, forKey: .dontNotifyScreenshots) ?? defaults.dontNotifyScreenshots
        self.dontNotifyScreenshotsInSecretChats = try container.decodeIfPresent(Bool.self, forKey: .dontNotifyScreenshotsInSecretChats) ?? defaults.dontNotifyScreenshotsInSecretChats
        self.ignoreCopyRestrictions = try container.decodeIfPresent(Bool.self, forKey: .ignoreCopyRestrictions) ?? defaults.ignoreCopyRestrictions
        self.disableAds = try container.decodeIfPresent(Bool.self, forKey: .disableAds) ?? defaults.disableAds
        self.hideSimilarChannels = try container.decodeIfPresent(Bool.self, forKey: .hideSimilarChannels) ?? defaults.hideSimilarChannels
        self.showMessageSeconds = try container.decodeIfPresent(Bool.self, forKey: .showMessageSeconds) ?? defaults.showMessageSeconds
        self.improveLinkPreviews = try container.decodeIfPresent(Bool.self, forKey: .improveLinkPreviews) ?? defaults.improveLinkPreviews
        self.ghostMode = try container.decodeIfPresent(Bool.self, forKey: .ghostMode) ?? defaults.ghostMode
        self.ghostDontReadMessages = try container.decodeIfPresent(Bool.self, forKey: .ghostDontReadMessages) ?? defaults.ghostDontReadMessages
        self.ghostDontReadMedia = try container.decodeIfPresent(Bool.self, forKey: .ghostDontReadMedia) ?? defaults.ghostDontReadMedia
        self.ghostDontCountViews = try container.decodeIfPresent(Bool.self, forKey: .ghostDontCountViews) ?? defaults.ghostDontCountViews
        self.ghostDontReadStories = try container.decodeIfPresent(Bool.self, forKey: .ghostDontReadStories) ?? defaults.ghostDontReadStories
        self.ghostDontSendTyping = try container.decodeIfPresent(Bool.self, forKey: .ghostDontSendTyping) ?? defaults.ghostDontSendTyping
        self.ghostDontSendOnline = try container.decodeIfPresent(Bool.self, forKey: .ghostDontSendOnline) ?? defaults.ghostDontSendOnline
        self.ghostOfflineAfterSend = try container.decodeIfPresent(Bool.self, forKey: .ghostOfflineAfterSend) ?? defaults.ghostOfflineAfterSend
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.saveDeletedMessages, forKey: .saveDeletedMessages)
        try container.encode(self.saveDeletedInPrivateChats, forKey: .saveDeletedInPrivateChats)
        try container.encode(self.saveDeletedInGroups, forKey: .saveDeletedInGroups)
        try container.encode(self.saveDeletedInChannels, forKey: .saveDeletedInChannels)
        try container.encode(self.saveDeletedFromBots, forKey: .saveDeletedFromBots)
        try container.encode(self.saveDeletedMedia, forKey: .saveDeletedMedia)
        try container.encode(self.saveEditHistory, forKey: .saveEditHistory)
        try container.encode(self.keepSelfDestructingMedia, forKey: .keepSelfDestructingMedia)
        try container.encode(self.allowScreenCapture, forKey: .allowScreenCapture)
        try container.encode(self.dontNotifyScreenshots, forKey: .dontNotifyScreenshots)
        try container.encode(self.dontNotifyScreenshotsInSecretChats, forKey: .dontNotifyScreenshotsInSecretChats)
        try container.encode(self.ignoreCopyRestrictions, forKey: .ignoreCopyRestrictions)
        try container.encode(self.disableAds, forKey: .disableAds)
        try container.encode(self.hideSimilarChannels, forKey: .hideSimilarChannels)
        try container.encode(self.showMessageSeconds, forKey: .showMessageSeconds)
        try container.encode(self.improveLinkPreviews, forKey: .improveLinkPreviews)
        try container.encode(self.ghostMode, forKey: .ghostMode)
        try container.encode(self.ghostDontReadMessages, forKey: .ghostDontReadMessages)
        try container.encode(self.ghostDontReadMedia, forKey: .ghostDontReadMedia)
        try container.encode(self.ghostDontCountViews, forKey: .ghostDontCountViews)
        try container.encode(self.ghostDontReadStories, forKey: .ghostDontReadStories)
        try container.encode(self.ghostDontSendTyping, forKey: .ghostDontSendTyping)
        try container.encode(self.ghostDontSendOnline, forKey: .ghostDontSendOnline)
        try container.encode(self.ghostOfflineAfterSend, forKey: .ghostOfflineAfterSend)
    }
}

// The master switch folded in, so a call site reads one flag and cannot forget `ghostMode`.
public extension AyuSettings {
    var ghostHidesReading: Bool {
        return self.ghostMode && self.ghostDontReadMessages
    }

    var ghostHidesMediaViews: Bool {
        return self.ghostMode && self.ghostDontReadMedia
    }

    var ghostHidesChannelViews: Bool {
        return self.ghostMode && self.ghostDontCountViews
    }

    var ghostHidesStoryViews: Bool {
        return self.ghostMode && self.ghostDontReadStories
    }

    var ghostHidesTyping: Bool {
        return self.ghostMode && self.ghostDontSendTyping
    }

    var ghostHidesOnline: Bool {
        return self.ghostMode && self.ghostDontSendOnline
    }

    var ghostGoesOfflineAfterSend: Bool {
        return self.ghostMode && self.ghostOfflineAfterSend
    }
}

func ayuSettings(transaction: Transaction) -> AyuSettings {
    return transaction.getPreferencesEntry(key: PreferencesKeys.ayuSettings)?.get(AyuSettings.self) ?? AyuSettings.default
}

public extension TelegramEngine {
    func ayuUpdateSettings(_ f: @escaping (AyuSettings) -> AyuSettings) -> Signal<Never, NoError> {
        return self.account.postbox.transaction { transaction -> Void in
            transaction.updatePreferencesEntry(key: PreferencesKeys.ayuSettings, { current in
                let previous = current?.get(AyuSettings.self) ?? AyuSettings.default
                return PreferencesEntry(f(previous))
            })
        }
        |> ignoreValues
    }
}

public extension TelegramEngine.EngineData.Item.Configuration {
    struct Ayu: TelegramEngineDataItem, PostboxViewDataItem {
        public typealias Result = AyuSettings

        public init() {
        }

        var key: PostboxViewKey {
            return .preferences(keys: Set([PreferencesKeys.ayuSettings]))
        }

        func extract(view: PostboxView) -> Result {
            guard let view = view as? PreferencesView else {
                preconditionFailure()
            }
            return view.values[PreferencesKeys.ayuSettings]?.get(AyuSettings.self) ?? AyuSettings.default
        }
    }
}
