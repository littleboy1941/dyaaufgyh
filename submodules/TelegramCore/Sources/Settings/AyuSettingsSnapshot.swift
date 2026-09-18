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
private let ayuSettingsSnapshotPromise = ValuePromise<AyuSettings>(AyuSettings.default, ignoreRepeated: true)

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
}
