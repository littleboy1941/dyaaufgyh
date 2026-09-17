import Foundation
import Postbox
import SwiftSignalKit

// AyuGram: media of kept deleted messages can't be downloaded again, so cache cleanup skips it.
// A resource is protected if StorageBox references it from a message with AyuDeletedMessageAttribute.

private func ayuProtectedIds(transaction: Transaction, entries: [StorageBox.Entry]) -> Set<Data> {
    let settings = ayuSettings(transaction: transaction)
    var result = Set<Data>()
    var checkedMessages: [MessageId: Bool] = [:]
    for entry in entries {
        for reference in entry.references {
            if reference.peerId == 0 {
                continue
            }
            let messageId = MessageId(peerId: PeerId(reference.peerId), namespace: Int32(reference.messageNamespace), id: reference.messageId)
            let isDeleted: Bool
            if let value = checkedMessages[messageId] {
                isDeleted = value
            } else {
                if let message = transaction.getMessage(messageId) {
                    isDeleted = message.ayuDeletedDate != nil || ayuShouldPreserveSelfDestructingMedia(message: message, settings: settings)
                } else {
                    isDeleted = false
                }
                checkedMessages[messageId] = isDeleted
            }
            if isDeleted {
                result.insert(entry.id)
                break
            }
        }
    }
    return result
}

// Protected ids among the given resource ids
func ayuProtectedResourceIds(postbox: Postbox, ids: [Data]) -> Signal<Set<Data>, NoError> {
    if ids.isEmpty {
        return .single(Set())
    }
    return postbox.mediaBox.storageBox.get(ids: ids)
    |> mapToSignal { entries -> Signal<Set<Data>, NoError> in
        return postbox.transaction { transaction -> Set<Data> in
            return ayuProtectedIds(transaction: transaction, entries: entries)
        }
    }
}

// All protected ids known to StorageBox
func ayuAllProtectedResourceIds(postbox: Postbox) -> Signal<Set<Data>, NoError> {
    return postbox.mediaBox.storageBox.all()
    |> mapToSignal { entries -> Signal<Set<Data>, NoError> in
        return postbox.transaction { transaction -> Set<Data> in
            return ayuProtectedIds(transaction: transaction, entries: entries)
        }
    }
}
