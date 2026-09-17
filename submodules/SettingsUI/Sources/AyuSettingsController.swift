import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext

// AyuGram: settings screen (Settings ▸ AyuGram)

private final class AyuSettingsControllerArguments {
    let update: (AyuSettingsToggle, Bool) -> Void

    init(update: @escaping (AyuSettingsToggle, Bool) -> Void) {
        self.update = update
    }
}

private enum AyuSettingsToggle: Int32 {
    case saveDeletedMessages
    case saveDeletedInPrivateChats
    case saveDeletedInGroups
    case saveDeletedInChannels
    case saveDeletedFromBots
    case saveDeletedMedia

    var keyPath: WritableKeyPath<AyuSettings, Bool> {
        switch self {
        case .saveDeletedMessages:
            return \.saveDeletedMessages
        case .saveDeletedInPrivateChats:
            return \.saveDeletedInPrivateChats
        case .saveDeletedInGroups:
            return \.saveDeletedInGroups
        case .saveDeletedInChannels:
            return \.saveDeletedInChannels
        case .saveDeletedFromBots:
            return \.saveDeletedFromBots
        case .saveDeletedMedia:
            return \.saveDeletedMedia
        }
    }

    var title: String {
        switch self {
        case .saveDeletedMessages:
            return "Сохранять удалённые"
        case .saveDeletedInPrivateChats:
            return "В личных чатах"
        case .saveDeletedInGroups:
            return "В группах"
        case .saveDeletedInChannels:
            return "В каналах"
        case .saveDeletedFromBots:
            return "В чатах с ботами"
        case .saveDeletedMedia:
            return "Сохранять медиа"
        }
    }
}

private enum AyuSettingsSection: Int32 {
    case deleted
    case deletedScope
}

private enum AyuSettingsEntry: ItemListNodeEntry {
    case deletedHeader
    case toggle(AyuSettingsToggle, Bool)
    case deletedFooter
    case scopeFooter

    var section: ItemListSectionId {
        switch self {
        case .deletedHeader, .deletedFooter:
            return AyuSettingsSection.deleted.rawValue
        case let .toggle(toggle, _):
            return toggle == .saveDeletedMessages ? AyuSettingsSection.deleted.rawValue : AyuSettingsSection.deletedScope.rawValue
        case .scopeFooter:
            return AyuSettingsSection.deletedScope.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .deletedHeader:
            return 0
        case let .toggle(toggle, _):
            // saveDeletedMessages sits between the header and the footer of the first section
            return toggle == .saveDeletedMessages ? 1 : 100 + toggle.rawValue
        case .deletedFooter:
            return 2
        case .scopeFooter:
            return 200
        }
    }

    static func <(lhs: AyuSettingsEntry, rhs: AyuSettingsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! AyuSettingsControllerArguments
        switch self {
        case .deletedHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "УДАЛЁННЫЕ СООБЩЕНИЯ", sectionId: self.section)
        case let .toggle(toggle, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: toggle.title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.update(toggle, value)
            })
        case .deletedFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Сообщения, которые удалил собеседник, остаются в чате с пометкой 🗑. Сохраняется только то, что уже было загружено на это устройство."), sectionId: self.section)
        case .scopeFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Медиа удалённых сообщений не стирается ни ручной очисткой кэша, ни автоудалением по сроку хранения. Исключение — лимит размера кэша: при нём старые файлы могут удалиться."), sectionId: self.section)
        }
    }
}

private func ayuSettingsEntries(settings: AyuSettings) -> [AyuSettingsEntry] {
    var entries: [AyuSettingsEntry] = []

    entries.append(.deletedHeader)
    entries.append(.toggle(.saveDeletedMessages, settings.saveDeletedMessages))
    entries.append(.deletedFooter)

    if settings.saveDeletedMessages {
        let scopeToggles: [AyuSettingsToggle] = [.saveDeletedInPrivateChats, .saveDeletedInGroups, .saveDeletedInChannels, .saveDeletedFromBots, .saveDeletedMedia]
        for toggle in scopeToggles {
            entries.append(.toggle(toggle, settings[keyPath: toggle.keyPath]))
        }
        entries.append(.scopeFooter)
    }

    return entries
}

public func ayuSettingsController(context: AccountContext) -> ViewController {
    let arguments = AyuSettingsControllerArguments(update: { toggle, value in
        let _ = context.engine.ayuUpdateSettings({ settings in
            var settings = settings
            settings[keyPath: toggle.keyPath] = value
            return settings
        }).startStandalone()
    })

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        context.engine.data.subscribe(TelegramEngine.EngineData.Item.Configuration.Ayu())
    )
    |> deliverOnMainQueue
    |> map { presentationData, settings -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("AyuGram"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: ayuSettingsEntries(settings: settings), style: .blocks, animateChanges: true)

        return (controllerState, (listState, arguments))
    }

    return ItemListController(context: context, state: signal)
}
