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
