import Foundation
import Postbox
import SwiftSignalKit

// AyuGram ghost mode: suppressing our own presence packets is not enough, because the server marks the
// account online by itself after meaningful actions -- sending a message above all -- and then tells us about
// it with an updateUserStatus about ourselves.
//
// That update is the only reliable signal that we have been lit up. The client never stores its own presence:
// the account's own row in Postbox is pinned to "online" locally right after login, so watching it says
// nothing about what the server thinks. AyuGram Desktop solves this with a worker that re-arms on the same
// update; this is the event-driven equivalent, which suits iOS better than a three second poll.
//
// The state replay only reports the event here. AccountPresenceManager owns the network and the queue, so it
// does the actual offline push, throttled and only while ghost mode hides our presence.
private let ayuServerMarkedUsOnlinePipe = ValuePipe<PeerId>()

func ayuNoteServerMarkedUsOnline(accountPeerId: PeerId) {
    ayuServerMarkedUsOnlinePipe.putNext(accountPeerId)
}

func ayuServerMarkedUsOnlineSignal(accountPeerId: PeerId) -> Signal<Void, NoError> {
    return ayuServerMarkedUsOnlinePipe.signal()
    |> filter { peerId in
        return peerId == accountPeerId
    }
    |> map { _ -> Void in
        return Void()
    }
}
