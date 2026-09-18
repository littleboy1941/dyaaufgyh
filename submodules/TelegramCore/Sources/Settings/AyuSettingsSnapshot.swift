import Foundation
import SwiftSignalKit

// A synchronously readable copy of the active account's AyuSettings.
//
// The settings themselves live in Postbox preferences (AyuSettings.swift), which can only be read
// inside a transaction or through a signal. Some enforcement points have neither: `Message.isCopyProtected()`
// and `Peer.isCopyProtectionEnabled` are pure predicates called from layout code, and the capture-protection
// layer is plain Objective-C in UIKitRuntimeUtils with no account in reach.
//
// The snapshot is written from the app side (SharedAccountContextImpl) for the primary account, so with
// several accounts logged in the primary account's settings win.
//
// KNOWN LIMITATION: ghost mode reads this snapshot to decide whether to send read receipts, view counts,
// typing and presence, which are per-account network calls. With several accounts logged in, the primary
// account's ghost setting therefore governs all of them. Fixing this means reading the setting per account
// at each call site (most have a Transaction in reach, ManagedAccountPresence does not).

// A cold start reads the real settings out of the account's Postbox, which takes long enough that presence
// could announce us online before ghost mode was known. The last pushed value is therefore mirrored into
// UserDefaults and used to seed the snapshot at process start.
//
// Postbox stays the source of truth: this copy is overwritten the moment the account's settings load, and a
// missing or unreadable copy just falls back to the defaults. It exists only to make the first instant after
// launch behave like the rest of the session.
private let ayuSettingsCacheKey = "ayu_settings_snapshot_cache"

private func ayuCachedSettings() -> AyuSettings {
    guard let data = UserDefaults.standard.data(forKey: ayuSettingsCacheKey) else {
        return AyuSettings.default
    }
    guard let settings = try? JSONDecoder().decode(AyuSettings.self, from: data) else {
        return AyuSettings.default
    }
    return settings
}

private func ayuStoreCachedSettings(_ settings: AyuSettings) {
    guard let data = try? JSONEncoder().encode(settings) else {
        return
    }
    UserDefaults.standard.set(data, forKey: ayuSettingsCacheKey)
}

private let ayuSettingsSnapshotValue = Atomic<AyuSettings>(value: ayuCachedSettings())
private let ayuSettingsSnapshotPromise = ValuePromise<AyuSettings>(ayuCachedSettings(), ignoreRepeated: true)

public var ayuSettingsSnapshot: AyuSettings {
    return ayuSettingsSnapshotValue.with({ $0 })
}

// For code that has to react to a change rather than read the value at one moment. AccountPresenceManager
// needs this: it only talks to the server when its inputs change, so without a signal, switching ghost mode
// on would not take effect until the app was backgrounded or its 30 second refresh fired.
public var ayuSettingsSnapshotSignal: Signal<AyuSettings, NoError> {
    return ayuSettingsSnapshotPromise.get()
}

public func ayuSetSettingsSnapshot(_ settings: AyuSettings) {
    let _ = ayuSettingsSnapshotValue.swap(settings)
    ayuSettingsSnapshotPromise.set(settings)
    ayuStoreCachedSettings(settings)
}
