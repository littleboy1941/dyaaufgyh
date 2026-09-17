import Foundation
import Postbox
import SwiftSignalKit

// AyuGram: self-destructing and view-once media in cloud chats.
// The sender gets the regular "opened" mark, locally the media is never consumed: no countdown, no
// replacement with TelegramMediaExpiredContent, it looks unopened and can be opened again.

func ayuShouldPreserveSelfDestructingMedia(message: Message, settings: AyuSettings) -> Bool {
    return settings.keepSelfDestructingMedia
        && message.flags.contains(.Incoming)
        && message.id.namespace == Namespaces.Message.Cloud
        && message.id.peerId.namespace != Namespaces.Peer.SecretChat
        && message.containsSecretMedia
        && !message.media.contains(where: { $0 is TelegramMediaExpiredContent })
}

// The main resource that has to be downloaded before the server is told the media was opened:
// after that the server may stop serving the file.
private func ayuSelfDestructingMediaResource(message: Message) -> MediaResource? {
    for media in message.media {
        if let image = media as? TelegramMediaImage, let representation = largestImageRepresentation(image.representations) {
            return representation.resource
        } else if let file = media as? TelegramMediaFile {
            return file.resource
        }
    }
    return nil
}

// Waits until the media is fully downloaded (the viewer fetches it), then sends "opened" to the server
// without touching the local message.
func ayuConsumeSelfDestructingMediaRemotely(postbox: Postbox, message: Message) -> Signal<Void, NoError> {
    let messageId = message.id
    let enqueueOperation: Signal<Void, NoError> = postbox.transaction { transaction -> Void in
        addSynchronizeConsumeMessageContentsOperation(transaction: transaction, messageIds: [messageId])
    }
    guard let resource = ayuSelfDestructingMediaResource(message: message) else {
        return enqueueOperation
    }
    return postbox.mediaBox.resourceData(resource)
    |> filter { data in
        return data.complete
    }
    |> take(1)
    |> mapToSignal { _ -> Signal<Void, NoError> in
        return enqueueOperation
    }
}

// A server copy of the message (difference, holes, validation, edit) comes with the media already expired;
// keep the local media and its unopened state.
func ayuPreservingSelfDestructingMedia(transaction: Transaction, incoming: StoreMessage) -> StoreMessage {
    guard case let .Id(id) = incoming.id else {
        return incoming
    }
    let incomingIsExpired = incoming.media.contains(where: { $0 is TelegramMediaExpiredContent })
    let incomingLacksMedia = !incoming.media.contains(where: { $0 is TelegramMediaImage || $0 is TelegramMediaFile })
    guard incomingIsExpired || incomingLacksMedia else {
        return incoming
    }
    guard let current = transaction.getMessage(id), ayuShouldPreserveSelfDestructingMedia(message: current, settings: ayuSettings(transaction: transaction)) else {
        return incoming
    }

    func isPreservedAttribute(_ attribute: MessageAttribute) -> Bool {
        return attribute is ConsumableContentMessageAttribute || attribute is AutoclearTimeoutMessageAttribute || attribute is AutoremoveTimeoutMessageAttribute || attribute is AyuDeletedMessageAttribute
    }
    var attributes = incoming.attributes.filter { !isPreservedAttribute($0) }
    attributes.append(contentsOf: current.attributes.filter { isPreservedAttribute($0) })

    return incoming.withUpdatedMedia(current.media).withUpdatedAttributes(attributes)
}

func ayuPreservingSelfDestructingMedia(transaction: Transaction, messages: [StoreMessage]) -> [StoreMessage] {
    return messages.map { ayuPreservingSelfDestructingMedia(transaction: transaction, incoming: $0) }
}
