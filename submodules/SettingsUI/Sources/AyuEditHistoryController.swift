import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import TelegramStringFormatting

// AyuGram: previous versions of an edited message (message context menu ▸ Edit history)

private enum AyuEditHistoryListEntry: ItemListNodeEntry {
    case versionHeader(index: Int32, title: String)
    case versionText(index: Int32, text: String)
    case empty

    var section: ItemListSectionId {
        switch self {
        case let .versionHeader(index, _), let .versionText(index, _):
            return index
        case .empty:
            return 0
        }
    }

    var stableId: Int32 {
        switch self {
        case let .versionHeader(index, _):
            return index * 2
        case let .versionText(index, _):
            return index * 2 + 1
        case .empty:
            return 0
        }
    }

    static func <(lhs: AyuEditHistoryListEntry, rhs: AyuEditHistoryListEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        switch self {
        case let .versionHeader(_, title):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: title, sectionId: self.section)
        case let .versionText(_, text):
            return ItemListMultilineTextItem(presentationData: presentationData, text: text.isEmpty ? "(без текста)" : text, enabledEntityTypes: [], sectionId: self.section, style: .blocks)
        case .empty:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Сохранённых версий нет. История записывается только для правок, полученных после установки AyuGram, пока включена настройка «Сохранять историю правок»."), sectionId: self.section)
        }
    }
}

private func ayuEditHistoryEntries(presentationData: PresentationData, history: [AyuEditHistoryEntry], currentMessage: EngineMessage?) -> [AyuEditHistoryListEntry] {
    if history.isEmpty {
        return [.empty]
    }

    var entries: [AyuEditHistoryListEntry] = []
    // Newest first: the current text, then previous versions
    var index: Int32 = 1
    if let currentMessage {
        var date = currentMessage.timestamp
        if let edited = currentMessage.attributes.first(where: { $0 is EditedMessageAttribute }) as? EditedMessageAttribute {
            date = edited.date
        }
        let dateString = stringForFullDate(timestamp: date, strings: presentationData.strings, dateTimeFormat: presentationData.dateTimeFormat)
        entries.append(.versionHeader(index: index, title: "СЕЙЧАС · \(dateString)".uppercased()))
        entries.append(.versionText(index: index, text: currentMessage.text))
        index += 1
    }
    for version in history.reversed() {
        let dateString = stringForFullDate(timestamp: version.date, strings: presentationData.strings, dateTimeFormat: presentationData.dateTimeFormat)
        entries.append(.versionHeader(index: index, title: dateString.uppercased()))
        entries.append(.versionText(index: index, text: version.text))
        index += 1
    }
    return entries
}

public func ayuEditHistoryController(context: AccountContext, messageId: EngineMessage.Id) -> ViewController {
    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        context.engine.ayuEditHistory(messageId: messageId),
        context.engine.data.subscribe(TelegramEngine.EngineData.Item.Messages.Message(id: messageId))
    )
    |> map { presentationData, history, currentMessage -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("История правок"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: ayuEditHistoryEntries(presentationData: presentationData, history: history, currentMessage: currentMessage), style: .blocks, animateChanges: false)

        return (controllerState, (listState, Void()))
    }

    return ItemListController(context: context, state: signal)
}
