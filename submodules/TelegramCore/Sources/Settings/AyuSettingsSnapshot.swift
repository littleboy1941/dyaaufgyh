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
private let ayuSettingsSnapshotValue = Atomic<AyuSettings>(value: AyuSettings.default)

public var ayuSettingsSnapshot: AyuSettings {
    return ayuSettingsSnapshotValue.with({ $0 })
}

public func ayuSetSettingsSnapshot(_ settings: AyuSettings) {
    let _ = ayuSettingsSnapshotValue.swap(settings)
}
