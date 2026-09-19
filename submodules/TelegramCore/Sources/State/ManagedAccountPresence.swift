import Foundation
import TelegramApi
import Postbox
import SwiftSignalKit
import MtProtoKit

private typealias SignalKitTimer = SwiftSignalKit.Timer


private final class AccountPresenceManagerImpl {
    private let queue: Queue
    private let network: Network
    let isPerformingUpdate = ValuePromise<Bool>(false, ignoreRepeated: true)
    
    private var shouldKeepOnlinePresenceDisposable: Disposable?
    private let currentRequestDisposable = MetaDisposable()
    private var onlineTimer: SignalKitTimer?
    
    // The raw inputs are tracked, never the value derived from them. With ghost mode on the derived value is
    // permanently false, so comparing against it would make the subscription below stop calling updatePresence
    // altogether -- and since the server marks us online on its own activity, nothing would ever push us back
    // offline.
    private var wasKeepingOnlinePresence: Bool = false
    private var wasHidingOnline: Bool = false

    private var ayuServerMarkedUsOnlineDisposable: Disposable?
    private var ayuLastForcedOfflineTimestamp: Double = 0.0

    init(queue: Queue, accountPeerId: PeerId, shouldKeepOnlinePresence: Signal<Bool, NoError>, network: Network) {
        self.queue = queue
        self.network = network

        // AyuGram ghost mode: suppressing our own presence packets leaves one hole open -- the server marks
        // the account online by itself after meaningful actions and reports it back with an updateUserStatus
        // about ourselves. Every such report is answered with an offline status, which is what keeps us dark
        // while the app stays open. Without this the account only went dark when the app was closed.
        self.ayuServerMarkedUsOnlineDisposable = (ayuServerMarkedUsOnlineSignal(accountPeerId: accountPeerId)
        |> deliverOn(self.queue)).start(next: { [weak self] in
            guard let `self` = self else {
                return
            }
            if !ayuSettingsSnapshot.ghostHidesOnline {
                return
            }
            // The server answers our offline status with another update, so a burst of activity must not turn
            // into a request per update.
            let timestamp = CFAbsoluteTimeGetCurrent()
            if timestamp < self.ayuLastForcedOfflineTimestamp + 1.0 {
                return
            }
            self.ayuLastForcedOfflineTimestamp = timestamp
            self.updatePresence(false)
        })

        // AyuGram ghost mode is an input here, not a check inside updatePresence: this manager only contacts
        // the server when its inputs change, so turning the mode on has to push an offline status right away
        // instead of waiting for the app to be backgrounded.
        let ayuHidesOnline = ayuSettingsSnapshotSignal
        |> map { settings -> Bool in
            return settings.ghostHidesOnline
        }
        |> distinctUntilChanged
        
        self.shouldKeepOnlinePresenceDisposable = (combineLatest(shouldKeepOnlinePresence |> distinctUntilChanged, ayuHidesOnline)
        |> deliverOn(self.queue)).start(next: { [weak self] shouldKeepOnline, hidesOnline in
            guard let `self` = self else {
                return
            }
            if self.wasKeepingOnlinePresence != shouldKeepOnline || self.wasHidingOnline != hidesOnline {
                self.wasKeepingOnlinePresence = shouldKeepOnline
                self.wasHidingOnline = hidesOnline
                // updatePresence is the single place that applies ghost mode, so the raw value goes in and
                // comes out as an offline status while the mode is on.
                self.updatePresence(shouldKeepOnline)
            }
        })
    }
    
    deinit {
        assert(self.queue.isCurrent())
        self.shouldKeepOnlinePresenceDisposable?.dispose()
        self.ayuServerMarkedUsOnlineDisposable?.dispose()
        self.currentRequestDisposable.dispose()
        self.onlineTimer?.invalidate()
    }
    
    private func updatePresence(_ isOnline: Bool) {
        // AyuGram ghost mode: never announce ourselves as online. Going offline stays allowed, so the
        // status still flips back after the server marks us online on its own (for example after a send).
        var isOnline = isOnline
        if ayuSettingsSnapshot.ghostHidesOnline {
            isOnline = false
        }

        let request: Signal<Api.Bool, MTRpcError>
        if isOnline {
            let timer = SignalKitTimer(timeout: 30.0, repeat: false, completion: { [weak self] in
                guard let strongSelf = self else {
                    return
                }
                strongSelf.updatePresence(true)
            }, queue: self.queue)
            self.onlineTimer = timer
            timer.start()
            request = self.network.request(Api.functions.account.updateStatus(offline: .boolFalse))
        } else {
            self.onlineTimer?.invalidate()
            self.onlineTimer = nil
            request = self.network.request(Api.functions.account.updateStatus(offline: .boolTrue))
        }
        self.isPerformingUpdate.set(true)
        self.currentRequestDisposable.set((request
        |> `catch` { _ -> Signal<Api.Bool, NoError> in
            return .single(.boolFalse)
        }
        |> deliverOn(self.queue)).start(completed: { [weak self] in
            guard let strongSelf = self else {
                return
            }
            strongSelf.isPerformingUpdate.set(false)
        }))
    }
}

final class AccountPresenceManager {
    private let queue = Queue()
    private let impl: QueueLocalObject<AccountPresenceManagerImpl>
    
    init(accountPeerId: PeerId, shouldKeepOnlinePresence: Signal<Bool, NoError>, network: Network) {
        let queue = self.queue
        self.impl = QueueLocalObject(queue: self.queue, generate: {
            return AccountPresenceManagerImpl(queue: queue, accountPeerId: accountPeerId, shouldKeepOnlinePresence: shouldKeepOnlinePresence, network: network)
        })
    }
    
    func isPerformingUpdate() -> Signal<Bool, NoError> {
        return Signal { subscriber in
            let disposable = MetaDisposable()
            self.impl.with { impl in
                disposable.set(impl.isPerformingUpdate.get().start(next: { value in
                    subscriber.putNext(value)
                }))
            }
            return disposable
        }
    }
}
