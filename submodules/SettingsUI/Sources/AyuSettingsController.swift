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
    case allowScreenCapture
    case dontNotifyScreenshots
    case dontNotifyScreenshotsInSecretChats
    case ignoreCopyRestrictions
    case disableAds
    case hideSimilarChannels
    case improveLinkPreviews
    case showMessageSeconds
    case ghostMode
    case ghostDontReadMessages
    case ghostDontReadMedia
    case ghostDontCountViews
    case ghostDontReadStories
    case ghostDontSendTyping
    case ghostDontSendOnline
    case ghostOfflineAfterSend

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
        case .allowScreenCapture:
            return \.allowScreenCapture
        case .dontNotifyScreenshots:
            return \.dontNotifyScreenshots
        case .dontNotifyScreenshotsInSecretChats:
            return \.dontNotifyScreenshotsInSecretChats
        case .ignoreCopyRestrictions:
            return \.ignoreCopyRestrictions
        case .disableAds:
            return \.disableAds
        case .hideSimilarChannels:
            return \.hideSimilarChannels
        case .improveLinkPreviews:
            return \.improveLinkPreviews
        case .showMessageSeconds:
            return \.showMessageSeconds
        case .ghostMode:
            return \.ghostMode
        case .ghostDontReadMessages:
            return \.ghostDontReadMessages
        case .ghostDontReadMedia:
            return \.ghostDontReadMedia
        case .ghostDontCountViews:
            return \.ghostDontCountViews
        case .ghostDontReadStories:
            return \.ghostDontReadStories
        case .ghostDontSendTyping:
            return \.ghostDontSendTyping
        case .ghostDontSendOnline:
            return \.ghostDontSendOnline
        case .ghostOfflineAfterSend:
            return \.ghostOfflineAfterSend
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
        case .allowScreenCapture:
            return "Разрешить скриншоты и запись"
        case .dontNotifyScreenshots:
            return "Не уведомлять о скриншотах"
        case .dontNotifyScreenshotsInSecretChats:
            return "Не уведомлять в секретных чатах"
        case .ignoreCopyRestrictions:
            return "Игнорировать запрет пересылки"
        case .disableAds:
            return "Убрать рекламу"
        case .hideSimilarChannels:
            return "Скрыть похожие каналы"
        case .improveLinkPreviews:
            return "Улучшать превью ссылок"
        case .showMessageSeconds:
            return "Секунды у времени сообщений"
        case .ghostMode:
            return "Режим призрака"
        case .ghostDontReadMessages:
            return "Не отмечать прочитанным"
        case .ghostDontReadMedia:
            return "Не отмечать медиа просмотренным"
        case .ghostDontCountViews:
            return "Не считать просмотр в каналах"
        case .ghostDontReadStories:
            return "Не отмечать истории"
        case .ghostDontSendTyping:
            return "Не показывать «печатает»"
        case .ghostDontSendOnline:
            return "Не показывать себя в сети"
        case .ghostOfflineAfterSend:
            return "Уходить офлайн после отправки"
        }
    }
}

private enum AyuSettingsSection: Int32 {
    case deleted
    case deletedScope
    case edits
    case selfDestructing
    case restrictions
    case ads
    case links
    case misc
    case ghost
    case ghostOptions
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
    case restrictionsHeader
    case restrictionsFooter
    case adsHeader
    case adsFooter
    case linksHeader
    case linksFooter
    case miscHeader
    case ghostHeader
    case ghostFooter
    case ghostOptionsFooter

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
            case .allowScreenCapture, .dontNotifyScreenshots, .dontNotifyScreenshotsInSecretChats, .ignoreCopyRestrictions:
                return AyuSettingsSection.restrictions.rawValue
            case .disableAds, .hideSimilarChannels:
                return AyuSettingsSection.ads.rawValue
            case .improveLinkPreviews:
                return AyuSettingsSection.links.rawValue
            case .showMessageSeconds:
                return AyuSettingsSection.misc.rawValue
            case .ghostMode:
                return AyuSettingsSection.ghost.rawValue
            case .ghostDontReadMessages, .ghostDontReadMedia, .ghostDontCountViews, .ghostDontReadStories, .ghostDontSendTyping, .ghostDontSendOnline, .ghostOfflineAfterSend:
                return AyuSettingsSection.ghostOptions.rawValue
            default:
                return AyuSettingsSection.deletedScope.rawValue
            }
        case .scopeFooter:
            return AyuSettingsSection.deletedScope.rawValue
        case .editsHeader, .editsFooter:
            return AyuSettingsSection.edits.rawValue
        case .selfDestructingHeader, .selfDestructingFooter:
            return AyuSettingsSection.selfDestructing.rawValue
        case .restrictionsHeader, .restrictionsFooter:
            return AyuSettingsSection.restrictions.rawValue
        case .adsHeader, .adsFooter:
            return AyuSettingsSection.ads.rawValue
        case .linksHeader, .linksFooter:
            return AyuSettingsSection.links.rawValue
        case .miscHeader:
            return AyuSettingsSection.misc.rawValue
        case .ghostHeader, .ghostFooter:
            return AyuSettingsSection.ghost.rawValue
        case .ghostOptionsFooter:
            return AyuSettingsSection.ghostOptions.rawValue
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
            case .allowScreenCapture:
                return 501
            case .dontNotifyScreenshots:
                return 502
            case .dontNotifyScreenshotsInSecretChats:
                return 503
            case .ignoreCopyRestrictions:
                return 504
            case .disableAds:
                return 901
            case .hideSimilarChannels:
                return 902
            case .improveLinkPreviews:
                return 1001
            case .showMessageSeconds:
                return 1101
            case .ghostMode:
                return 601
            case .ghostDontReadMessages:
                return 701
            case .ghostDontReadMedia:
                return 702
            case .ghostDontCountViews:
                return 703
            case .ghostDontReadStories:
                return 704
            case .ghostDontSendTyping:
                return 705
            case .ghostDontSendOnline:
                return 706
            case .ghostOfflineAfterSend:
                return 707
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
        case .restrictionsHeader:
            return 500
        case .restrictionsFooter:
            return 505
        case .adsHeader:
            return 900
        case .adsFooter:
            return 903
        case .miscHeader:
            return 1100
        case .linksHeader:
            return 1000
        case .linksFooter:
            return 1002
        case .ghostHeader:
            return 600
        case .ghostFooter:
            return 602
        case .ghostOptionsFooter:
            return 800
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
        case .ghostHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "РЕЖИМ ПРИЗРАКА", sectionId: self.section)
        case .ghostFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Пока режим включён, сервер не узнаёт, что вы прочитали чат, открыли медиа, посмотрели историю, печатаете или находитесь в сети. Локально всё выглядит как обычно: чаты становятся прочитанными, медиа открывается."), sectionId: self.section)
        case .ghostOptionsFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Полностью невидимым режим не делает. Отправка сообщения помечает вас в сети на стороне сервера — «Уходить офлайн после отправки» возвращает статус обратно через секунду, но само мелькание убрать нельзя. Ответ или реакция на историю тоже раскрывают просмотр. Непрочитанные упоминания и реакции отмечаются всегда, иначе их счётчик не сбросится.\n\nЕсли параллельно открыт обычный Telegram на другом устройстве, он честно сообщит, что вы в сети."), sectionId: self.section)
        case .restrictionsHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "СНЯТИЕ ОГРАНИЧЕНИЙ", sectionId: self.section)
        case .restrictionsFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Скриншоты и запись экрана больше не затемняются, а собеседник не получает уведомление о скриншоте. В чатах с запретом пересылки снова доступны сохранение, копирование и «Переслать» — но сама пересылка на сервере всё равно будет отклонена.\n\nУведомление в секретных чатах собеседник обычно ожидает, поэтому этот пункт выключен по умолчанию. Новые значения применяются к заново открытым чатам."), sectionId: self.section)
        case .adsHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "РЕКЛАМА И ЛИШНЕЕ", sectionId: self.section)
        case .adsFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Спонсорские посты в каналах и в полноэкранном видео, спонсорские результаты в поиске и рекламная строка над списком чатов не запрашиваются у сервера и не показываются. Блок «похожие каналы» тоже скрывается.

Уже показанные объявления исчезнут после переоткрытия чата."), sectionId: self.section)
        case .miscHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "МЕЛОЧИ", sectionId: self.section)
        case .linksHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "ССЫЛКИ", sectionId: self.section)
        case .linksFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Telegram не умеет разворачивать превью для x.com, Reddit, TikTok, Instagram и Pixiv. Превью запрашивается через зеркало (fixupx.com, vxreddit.com и подобные), поэтому картинка и текст появляются и у вас, и у собеседника. Текст самого сообщения не меняется: адрес остаётся тот, который вы написали."), sectionId: self.section)
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

    entries.append(.restrictionsHeader)
    let restrictionToggles: [AyuSettingsToggle] = [.allowScreenCapture, .dontNotifyScreenshots, .dontNotifyScreenshotsInSecretChats, .ignoreCopyRestrictions]
    for toggle in restrictionToggles {
        entries.append(.toggle(toggle, settings[keyPath: toggle.keyPath]))
    }
    entries.append(.restrictionsFooter)

    entries.append(.adsHeader)
    for toggle in [AyuSettingsToggle.disableAds, .hideSimilarChannels] {
        entries.append(.toggle(toggle, settings[keyPath: toggle.keyPath]))
    }
    entries.append(.adsFooter)

    entries.append(.linksHeader)
    entries.append(.toggle(.improveLinkPreviews, settings.improveLinkPreviews))
    entries.append(.linksFooter)

    entries.append(.miscHeader)
    entries.append(.toggle(.showMessageSeconds, settings.showMessageSeconds))

    entries.append(.ghostHeader)
    entries.append(.toggle(.ghostMode, settings.ghostMode))
    entries.append(.ghostFooter)

    if settings.ghostMode {
        let ghostToggles: [AyuSettingsToggle] = [.ghostDontReadMessages, .ghostDontReadMedia, .ghostDontCountViews, .ghostDontReadStories, .ghostDontSendTyping, .ghostDontSendOnline, .ghostOfflineAfterSend]
        for toggle in ghostToggles {
            entries.append(.toggle(toggle, settings[keyPath: toggle.keyPath]))
        }
        entries.append(.ghostOptionsFooter)
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
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Goldagram"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: ayuSettingsEntries(settings: settings), style: .blocks, animateChanges: true)

        return (controllerState, (listState, arguments))
    }

    return ItemListController(context: context, state: signal)
}
