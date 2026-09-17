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
    case saveEditHistory
    case keepSelfDestructingMedia

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
        case .saveEditHistory:
            return \.saveEditHistory
        case .keepSelfDestructingMedia:
            return \.keepSelfDestructingMedia
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
        case .saveEditHistory:
            return "Сохранять историю правок"
        case .keepSelfDestructingMedia:
            return "Сохранять одноразовые медиа"
        }
    }
}

private enum AyuSettingsSection: Int32 {
    case deleted
    case deletedScope
    case edits
    case selfDestructing
}

private enum AyuSettingsEntry: ItemListNodeEntry {
    case deletedHeader
    case toggle(AyuSettingsToggle, Bool)
    case deletedFooter
    case scopeFooter
    case editsHeader
    case editsFooter
    case selfDestructingHeader
    case selfDestructingFooter

    var section: ItemListSectionId {
        switch self {
        case .deletedHeader, .deletedFooter:
            return AyuSettingsSection.deleted.rawValue
        case let .toggle(toggle, _):
            switch toggle {
            case .saveDeletedMessages:
                return AyuSettingsSection.deleted.rawValue
            case .saveEditHistory:
                return AyuSettingsSection.edits.rawValue
            case .keepSelfDestructingMedia:
                return AyuSettingsSection.selfDestructing.rawValue
            default:
                return AyuSettingsSection.deletedScope.rawValue
            }
        case .scopeFooter:
            return AyuSettingsSection.deletedScope.rawValue
        case .editsHeader, .editsFooter:
            return AyuSettingsSection.edits.rawValue
        case .selfDestructingHeader, .selfDestructingFooter:
            return AyuSettingsSection.selfDestructing.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .deletedHeader:
            return 0
        case let .toggle(toggle, _):
            // saveDeletedMessages sits between the header and the footer of the first section
            switch toggle {
            case .saveDeletedMessages:
                return 1
            case .saveEditHistory:
                return 301
            case .keepSelfDestructingMedia:
                return 401
            default:
                return 100 + toggle.rawValue
            }
        case .deletedFooter:
            return 2
        case .scopeFooter:
            return 200
        case .editsHeader:
            return 300
        case .editsFooter:
            return 302
        case .selfDestructingHeader:
            return 400
        case .selfDestructingFooter:
            return 402
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
        case .editsHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "ИСТОРИЯ ПРАВОК", sectionId: self.section)
        case .editsFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Прежние версии изменённых сообщений собеседников. Открываются через меню сообщения ▸ «История правок»."), sectionId: self.section)
        case .selfDestructingHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "ОДНОРАЗОВЫЕ МЕДИА", sectionId: self.section)
        case .selfDestructingFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Фото, видео, голосовые и кружки с таймером или «просмотр один раз» не исчезают: у вас они выглядят неоткрытыми и открываются сколько угодно раз, а собеседник видит, что медиа просмотрено. Отметка уходит после полной загрузки файла."), sectionId: self.section)
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

    entries.append(.editsHeader)
    entries.append(.toggle(.saveEditHistory, settings.saveEditHistory))
    entries.append(.editsFooter)

    entries.append(.selfDestructingHeader)
    entries.append(.toggle(.keepSelfDestructingMedia, settings.keepSelfDestructingMedia))
    entries.append(.selfDestructingFooter)

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
