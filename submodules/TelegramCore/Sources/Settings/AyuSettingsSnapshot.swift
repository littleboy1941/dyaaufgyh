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
// several accounts logged in the primary account's settings win. That is acceptable for these two uses:
// both are local presentation decisions, not anything that is sent to the server.
private let ayuSettingsSnapshotValue = Atomic<AyuSettings>(value: AyuSettings.default)

public var ayuSettingsSnapshot: AyuSettings {
    return ayuSettingsSnapshotValue.with({ $0 })
}

public func ayuSetSettingsSnapshot(_ settings: AyuSettings) {
    let _ = ayuSettingsSnapshotValue.swap(settings)
}
