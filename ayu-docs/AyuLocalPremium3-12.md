# Локальный Premium: пункты 3–12

2026-09-27. Рабочая копия: C:/AyuGram-iOS copy for codex. Основной проект не менялся.
Пункты 1–2 и 3–12 опубликованы для новой сборки в ветке codex/local-premium-20260927, поверх успешного коммита сохранения медиа.
Результат новой компиляции ожидается; работа на телефоне НЕ ПРОВЕРЕНА. Предыдущий успешный IPA медиа не содержит локальный Premium.

## Результат по пунктам

| № | Функция | Реализация и пределы |
|---|---|---|
| 3 | Premium-стикеры | Открыты клавиатура, поиск, наборы, предпросмотр, отправка и добавление в избранные в пределах обычного лимита. Используется обычный файл стикера; эффект зависит от наличия ресурса и настроек получателя. |
| 4 | Иконки | Открыты доступные alternate icons, уже включённые в приложение. Добавлять отсутствующие иконки в сборку не стали. Иконка меняется для всего приложения на устройстве. |
| 5 | Четвёртый аккаунт | Лимит авторизации — четыре, когда локальный Premium включён хотя бы у одного активного аккаунта. Лимит тестового окружения и обычная авторизация сохранены. |
| 6 | Перемещение «Все чаты» | Позиция хранится отдельно на устройстве; серверу передаётся допустимый порядок с «Все чаты» в начале. Остальные папки синхронизируются штатно, их количество и лимиты не увеличены. |
| 7 | Перевод чата | Открыты настройка и панель перевода. Для неоплаченного аккаунта вместо Premium-перевода по message id используется обычный перевод текстов, с сохранением результата по сообщениям. Доступный системный перевод iOS имеет приоритет. Сохраняются ошибки/квоты сервиса; успешность обычного API без подписки в этой версии нужно проверить. Пустые подписи исключены; rich-message документы не переводятся новым путём. |
| 8 | Недавние стикеры | При включённом режиме новые стикеры не обрезаются до 20. Серверное обновление добавляет свой список и сохраняет более старые локальные элементы без дубликатов. Это история устройства; избранные стикеры и GIF сохраняют настоящие лимиты. |
| 9 | Статус и цвета | Обычный эмодзи-статус, цвет имени, фоновые эмодзи и цвет профиля сохраняются локально. Серверные обновления проходят через отдельный снимок настоящего оформления; при выключении режима оно восстанавливается. Таймер статуса использует штатный механизм истечения. Коллекционные подарки не выдаются и серверное владение ими не меняется. |
| 10 | Реакции и теги «Избранного» | Реализованы локальные теги: назначение/снятие, название, счётчики и фильтрация загруженных сообщений, включая темы источников в «Избранном». Теги не отправляются как реакции, сохраняются в настройках аккаунта и защищены от серверных обновлений. Обычные Premium-реакции в чужих чатах, платные Stars и их лимиты остаются серверными. |
| 11 | Отправка от имени канала с premium_required | Не разблокирована: сервер проверяет право выбранного отправителя. Настоящая проверка подписки сохранена. Локальный Premium не позволяет обещать успешную отправку от такого канала. |
| 12 | HD stories | Открыт переключатель HD и предпочтение основного варианта видео при просмотре, предварительной загрузке и ожидании медиа. Работает при наличии доступного варианта, описанного сервером. Если сервер предоставляет только SD, локальная настройка не создаёт HD. |

## Как устроено

- AccountContext.ayuLocalPremium хранит отдельный признак UI. AccountContext.isPremium, TelegramUser.flags и userLimits остаются настоящими.
- AyuSettings содержит совместимые optional Codable-ключи для локальной позиции вкладки, оформления и тегов.
- Новые AyuLocalProfile / AyuLocalSavedTags — внутренние типы TelegramCore, входят в существующий Sources/**/*.swift glob. Секретные чаты не подключены к виртуальным эмодзи и тегам «Избранного».
- При выключении режима сохраняется выбор локального оформления и тегов для повторного включения, а отображение переключается на серверное. При сбросе Ayu-настроек серверные атрибуты также восстанавливаются.
- Фильтр локальных тегов использует индекс Postbox по реакциям, не обращается к серверному поиску тегов и показывает только уже загруженные сообщения. При выключении режима восстанавливаются серверные диапазоны загрузки для известных тегов.
- Список тегов и история стикеров растут вместе с использованием. Для большой истории требуется проверка производительности: локальные теги сейчас хранятся в одной записи настроек, а переключение режима обновляет все помеченные сообщения.
- Публичный Bool AyuSettings.localPremium из пунктов 1–2 и новое свойство протокола AccountContext расширяют пересборку Core/UI и зависимостей; следующая сборка может быть долгой.
- Workflow, bundle ID, sideload, .bazelrc и секреты не менялись. Публикация изменений для новой сборки разрешена пользователем 2026-09-27: «Пробуй билдить новую сборку уже со сделанными функциями». Используется отдельная ветка codex/local-premium-20260927.

## Проверки

- precheck.py: все изменённые и новые Swift-файлы, 44 записи настроек; порядок stableId, строки и скобки проверены.
- git diff --check: без ошибок.
- Сверены сигнатуры Transaction (updateMessage, updatePreferencesEntry, addHole/removeHole), StoreMessage, TelegramUser, PeerNameColor, PeerEmojiStatus, ReactionsMessageAttribute, MessageReaction, SavedMessageTags, API перевода и константы лимитов аккаунтов.
- Основная рабочая копия C:/AyuGram-iOS: чистый git status.
- Это статические проверки, они не заменяют компиляцию Swift, реальные ответы Telegram и тестирование UI.

## Проверить на телефоне

1. Без купленного Premium: включить локальный режим, открыть новый Premium-набор стикеров, искать по эмодзи, отправить стикер другому аккаунту и проверить эффект.
2. Переключить каждую доступную иконку. Добавить четвёртый аккаунт и убедиться, что пятый не разрешён. Проверить переключение между аккаунтами с разными Ayu-настройками.
3. Переместить «Все чаты», перезапустить, изменить другие папки со второго клиента. Выключить режим: вкладка возвращается в начало. Включить: локальная позиция восстановлена.
4. Включить перевод чатов в настройках языка; переводить текст, подписи, опрос и уже имеющуюся расшифровку. Проверить системный перевод iOS 18+, ответ обычного API и восстановление после ошибки/лимита. Новая расшифровка Premium-аудио не выполняется.
5. Отправить более 20 разных стикеров, перезапустить и дождаться серверного обновления недавних. Старые локальные элементы сохраняются.
6. Установить цвет имени/профиля, фоновые эмодзи, временный и постоянный статус; перезапустить, обновить свой профиль с сервера, дождаться истечения временного статуса. Другой клиент показывает реальный профиль. Проверить off/on и сброс настроек.
7. Назначить/снять/переименовать обычные и кастомные теги сообщениям и альбомам в «Избранном»; фильтровать глобально и внутри источника. Перезапустить, получить edit/reactions/full-message обновление с сервера; локальные теги остаются. Удалить сообщение/очистить историю и проверить счётчики. Off/on возвращает соответствующий набор тегов.
8. Другому аккаунту не приходят локальные теги; настоящие реакции в чужих чатах сохраняют обычные ограничения. Коллекционные подарки и premium_required send-as не становятся доступными от одного переключателя.
9. Переключить SD/HD story, проверить предварительную загрузку и качество на аккаунте без подписки. Story с единственным SD-ресурсом остаётся SD.
10. Большая история локальных тегов/стикеров: измерить время открытия, переключения режима и объём настроек. Проверить штатный оплаченный Premium с включённым и выключенным локальным режимом.

## Сборка сохранения медиа

Отдельная сборка успешно завершилась:
[GitHub Actions 36315717451](https://github.com/littleboy1941/dyaaufgyh/actions/runs/36315717451),
коммит 63112caf4a79a8e3667ca67bc4877690e9f76209, ветка codex/media-export-20260927.
[Зашифрованный артефакт ipa-encrypted](https://github.com/littleboy1941/dyaaufgyh/actions/runs/36315717451/artifacts/10932604322).
Наблюдение предыдущей сборки завершено. Пункты 1–12 в этот старый IPA не входят; новая сборка запускается из codex/local-premium-20260927.

## Изменённые файлы

Ниже полный набор Swift-изменений новой сборки вместе с пунктами 1–2; сохранение медиа входит в родительский коммит.

- [submodules/AccountContext/Sources/AccountContext.swift](<C:/AyuGram-iOS copy for codex/submodules/AccountContext/Sources/AccountContext.swift>)
- [submodules/ChatListUI/Sources/ChatListController.swift](<C:/AyuGram-iOS copy for codex/submodules/ChatListUI/Sources/ChatListController.swift>)
- [submodules/ChatListUI/Sources/ChatListFilterPresetListController.swift](<C:/AyuGram-iOS copy for codex/submodules/ChatListUI/Sources/ChatListFilterPresetListController.swift>)
- [submodules/SettingsUI/Sources/AyuSettingsController.swift](<C:/AyuGram-iOS copy for codex/submodules/SettingsUI/Sources/AyuSettingsController.swift>)
- [submodules/SettingsUI/Sources/DeleteAccountOptionsController.swift](<C:/AyuGram-iOS copy for codex/submodules/SettingsUI/Sources/DeleteAccountOptionsController.swift>)
- [submodules/SettingsUI/Sources/Language Selection/LocalizationListControllerNode.swift](<C:/AyuGram-iOS copy for codex/submodules/SettingsUI/Sources/Language Selection/LocalizationListControllerNode.swift>)
- [submodules/SettingsUI/Sources/Search/SettingsSearchableItems.swift](<C:/AyuGram-iOS copy for codex/submodules/SettingsUI/Sources/Search/SettingsSearchableItems.swift>)
- [submodules/SettingsUI/Sources/Themes/ThemeSettingsController.swift](<C:/AyuGram-iOS copy for codex/submodules/SettingsUI/Sources/Themes/ThemeSettingsController.swift>)
- [submodules/StickerPackPreviewUI/Sources/StickerPackScreen.swift](<C:/AyuGram-iOS copy for codex/submodules/StickerPackPreviewUI/Sources/StickerPackScreen.swift>)
- [submodules/TelegramCore/Sources/ApiUtils/AyuLocalPremiumEmoji.swift](<C:/AyuGram-iOS copy for codex/submodules/TelegramCore/Sources/ApiUtils/AyuLocalPremiumEmoji.swift>)
- [submodules/TelegramCore/Sources/ApiUtils/StoreMessage_Telegram.swift](<C:/AyuGram-iOS copy for codex/submodules/TelegramCore/Sources/ApiUtils/StoreMessage_Telegram.swift>)
- [submodules/TelegramCore/Sources/ApiUtils/TextEntitiesMessageAttribute.swift](<C:/AyuGram-iOS copy for codex/submodules/TelegramCore/Sources/ApiUtils/TextEntitiesMessageAttribute.swift>)
- [submodules/TelegramCore/Sources/PendingMessages/RequestEditMessage.swift](<C:/AyuGram-iOS copy for codex/submodules/TelegramCore/Sources/PendingMessages/RequestEditMessage.swift>)
- [submodules/TelegramCore/Sources/Settings/AyuLocalProfile.swift](<C:/AyuGram-iOS copy for codex/submodules/TelegramCore/Sources/Settings/AyuLocalProfile.swift>)
- [submodules/TelegramCore/Sources/Settings/AyuLocalSavedTags.swift](<C:/AyuGram-iOS copy for codex/submodules/TelegramCore/Sources/Settings/AyuLocalSavedTags.swift>)
- [submodules/TelegramCore/Sources/Settings/AyuSettings.swift](<C:/AyuGram-iOS copy for codex/submodules/TelegramCore/Sources/Settings/AyuSettings.swift>)
- [submodules/TelegramCore/Sources/State/AccountStateManagementUtils.swift](<C:/AyuGram-iOS copy for codex/submodules/TelegramCore/Sources/State/AccountStateManagementUtils.swift>)
- [submodules/TelegramCore/Sources/State/ApplyUpdateMessage.swift](<C:/AyuGram-iOS copy for codex/submodules/TelegramCore/Sources/State/ApplyUpdateMessage.swift>)
- [submodules/TelegramCore/Sources/State/AyuSelfDestructingMedia.swift](<C:/AyuGram-iOS copy for codex/submodules/TelegramCore/Sources/State/AyuSelfDestructingMedia.swift>)
- [submodules/TelegramCore/Sources/State/Holes.swift](<C:/AyuGram-iOS copy for codex/submodules/TelegramCore/Sources/State/Holes.swift>)
- [submodules/TelegramCore/Sources/State/ManagedConsumePersonalMessagesActions.swift](<C:/AyuGram-iOS copy for codex/submodules/TelegramCore/Sources/State/ManagedConsumePersonalMessagesActions.swift>)
- [submodules/TelegramCore/Sources/State/ManagedRecentStickers.swift](<C:/AyuGram-iOS copy for codex/submodules/TelegramCore/Sources/State/ManagedRecentStickers.swift>)
- [submodules/TelegramCore/Sources/State/MessageReactions.swift](<C:/AyuGram-iOS copy for codex/submodules/TelegramCore/Sources/State/MessageReactions.swift>)
- [submodules/TelegramCore/Sources/State/PendingMessageManager.swift](<C:/AyuGram-iOS copy for codex/submodules/TelegramCore/Sources/State/PendingMessageManager.swift>)
- [submodules/TelegramCore/Sources/State/RestoreFetchedDrafts.swift](<C:/AyuGram-iOS copy for codex/submodules/TelegramCore/Sources/State/RestoreFetchedDrafts.swift>)
- [submodules/TelegramCore/Sources/State/SavedMessageTags.swift](<C:/AyuGram-iOS copy for codex/submodules/TelegramCore/Sources/State/SavedMessageTags.swift>)
- [submodules/TelegramCore/Sources/TelegramEngine/AccountData/TelegramEngineAccountData.swift](<C:/AyuGram-iOS copy for codex/submodules/TelegramCore/Sources/TelegramEngine/AccountData/TelegramEngineAccountData.swift>)
- [submodules/TelegramCore/Sources/TelegramEngine/AccountData/UpdateAccountPeerName.swift](<C:/AyuGram-iOS copy for codex/submodules/TelegramCore/Sources/TelegramEngine/AccountData/UpdateAccountPeerName.swift>)
- [submodules/TelegramCore/Sources/TelegramEngine/Messages/DeleteMessages.swift](<C:/AyuGram-iOS copy for codex/submodules/TelegramCore/Sources/TelegramEngine/Messages/DeleteMessages.swift>)
- [submodules/TelegramCore/Sources/TelegramEngine/Messages/Translate.swift](<C:/AyuGram-iOS copy for codex/submodules/TelegramCore/Sources/TelegramEngine/Messages/Translate.swift>)
- [submodules/TelegramCore/Sources/TelegramEngine/Peers/ChatListFiltering.swift](<C:/AyuGram-iOS copy for codex/submodules/TelegramCore/Sources/TelegramEngine/Peers/ChatListFiltering.swift>)
- [submodules/TelegramCore/Sources/TelegramEngine/Stickers/SearchStickers.swift](<C:/AyuGram-iOS copy for codex/submodules/TelegramCore/Sources/TelegramEngine/Stickers/SearchStickers.swift>)
- [submodules/TelegramCore/Sources/UpdatePeers.swift](<C:/AyuGram-iOS copy for codex/submodules/TelegramCore/Sources/UpdatePeers.swift>)
- [submodules/TelegramUI/Components/Chat/ChatTextInputPanelNode/Sources/ChatTextInputPanelNode.swift](<C:/AyuGram-iOS copy for codex/submodules/TelegramUI/Components/Chat/ChatTextInputPanelNode/Sources/ChatTextInputPanelNode.swift>)
- [submodules/TelegramUI/Components/ChatEntityKeyboardInputNode/Sources/ChatEntityKeyboardInputNode.swift](<C:/AyuGram-iOS copy for codex/submodules/TelegramUI/Components/ChatEntityKeyboardInputNode/Sources/ChatEntityKeyboardInputNode.swift>)
- [submodules/TelegramUI/Components/EmojiStatusSelectionComponent/Sources/EmojiStatusSelectionComponent.swift](<C:/AyuGram-iOS copy for codex/submodules/TelegramUI/Components/EmojiStatusSelectionComponent/Sources/EmojiStatusSelectionComponent.swift>)
- [submodules/TelegramUI/Components/EmojiSuggestionsComponent/Sources/EmojiSuggestionsComponent.swift](<C:/AyuGram-iOS copy for codex/submodules/TelegramUI/Components/EmojiSuggestionsComponent/Sources/EmojiSuggestionsComponent.swift>)
- [submodules/TelegramUI/Components/EntityKeyboard/Sources/EmojiPagerContentSignals.swift](<C:/AyuGram-iOS copy for codex/submodules/TelegramUI/Components/EntityKeyboard/Sources/EmojiPagerContentSignals.swift>)
- [submodules/TelegramUI/Components/EntityKeyboard/Sources/EmojiSearchContent.swift](<C:/AyuGram-iOS copy for codex/submodules/TelegramUI/Components/EntityKeyboard/Sources/EmojiSearchContent.swift>)
- [submodules/TelegramUI/Components/MessageInputPanelComponent/Sources/InputContextQueries.swift](<C:/AyuGram-iOS copy for codex/submodules/TelegramUI/Components/MessageInputPanelComponent/Sources/InputContextQueries.swift>)
- [submodules/TelegramUI/Components/MessageInputPanelComponent/Sources/MessageInputPanelComponent.swift](<C:/AyuGram-iOS copy for codex/submodules/TelegramUI/Components/MessageInputPanelComponent/Sources/MessageInputPanelComponent.swift>)
- [submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoHeaderNode.swift](<C:/AyuGram-iOS copy for codex/submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoHeaderNode.swift>)
- [submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoScreen.swift](<C:/AyuGram-iOS copy for codex/submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoScreen.swift>)
- [submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoScreenSettingsActions.swift](<C:/AyuGram-iOS copy for codex/submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoScreenSettingsActions.swift>)
- [submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoSettingsItems.swift](<C:/AyuGram-iOS copy for codex/submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoSettingsItems.swift>)
- [submodules/TelegramUI/Components/Settings/PeerNameColorScreen/Sources/UserApperanceScreen.swift](<C:/AyuGram-iOS copy for codex/submodules/TelegramUI/Components/Settings/PeerNameColorScreen/Sources/UserApperanceScreen.swift>)
- [submodules/TelegramUI/Components/Stories/StoryContainerScreen/Sources/StoryChatContent.swift](<C:/AyuGram-iOS copy for codex/submodules/TelegramUI/Components/Stories/StoryContainerScreen/Sources/StoryChatContent.swift>)
- [submodules/TelegramUI/Components/Stories/StoryContainerScreen/Sources/StoryItemSetContainerComponent.swift](<C:/AyuGram-iOS copy for codex/submodules/TelegramUI/Components/Stories/StoryContainerScreen/Sources/StoryItemSetContainerComponent.swift>)
- [submodules/TelegramUI/Components/TranslateHeaderPanelComponent/Sources/ChatTranslationPanelNode.swift](<C:/AyuGram-iOS copy for codex/submodules/TelegramUI/Components/TranslateHeaderPanelComponent/Sources/ChatTranslationPanelNode.swift>)
- [submodules/TelegramUI/Sources/AccountContext.swift](<C:/AyuGram-iOS copy for codex/submodules/TelegramUI/Sources/AccountContext.swift>)
- [submodules/TelegramUI/Sources/Chat/ChatControllerLoadDisplayNode.swift](<C:/AyuGram-iOS copy for codex/submodules/TelegramUI/Sources/Chat/ChatControllerLoadDisplayNode.swift>)
- [submodules/TelegramUI/Sources/Chat/ChatControllerOpenMessageContextMenu.swift](<C:/AyuGram-iOS copy for codex/submodules/TelegramUI/Sources/Chat/ChatControllerOpenMessageContextMenu.swift>)
- [submodules/TelegramUI/Sources/ChatController.swift](<C:/AyuGram-iOS copy for codex/submodules/TelegramUI/Sources/ChatController.swift>)
- [submodules/TelegramUI/Sources/ChatControllerContentData.swift](<C:/AyuGram-iOS copy for codex/submodules/TelegramUI/Sources/ChatControllerContentData.swift>)
- [submodules/TelegramUI/Sources/ChatControllerNode.swift](<C:/AyuGram-iOS copy for codex/submodules/TelegramUI/Sources/ChatControllerNode.swift>)
- [submodules/TelegramUI/Sources/ChatControllerOpenAttachmentMenu.swift](<C:/AyuGram-iOS copy for codex/submodules/TelegramUI/Sources/ChatControllerOpenAttachmentMenu.swift>)
- [submodules/TelegramUI/Sources/ChatControllerOpenMessageReactionContextMenu.swift](<C:/AyuGram-iOS copy for codex/submodules/TelegramUI/Sources/ChatControllerOpenMessageReactionContextMenu.swift>)
- [submodules/TelegramUI/Sources/ChatInterfaceStateContextMenus.swift](<C:/AyuGram-iOS copy for codex/submodules/TelegramUI/Sources/ChatInterfaceStateContextMenus.swift>)
- [submodules/TelegramUI/Sources/ChatInterfaceStateContextQueries.swift](<C:/AyuGram-iOS copy for codex/submodules/TelegramUI/Sources/ChatInterfaceStateContextQueries.swift>)
- [submodules/TelegramUI/Sources/ChatSearchTitleAccessoryPanelNode.swift](<C:/AyuGram-iOS copy for codex/submodules/TelegramUI/Sources/ChatSearchTitleAccessoryPanelNode.swift>)
- [submodules/TelegramUI/Sources/EmojisChatInputContextPanelNode.swift](<C:/AyuGram-iOS copy for codex/submodules/TelegramUI/Sources/EmojisChatInputContextPanelNode.swift>)
- [submodules/TranslateUI/Sources/Translate.swift](<C:/AyuGram-iOS copy for codex/submodules/TranslateUI/Sources/Translate.swift>)

Документация: ayu-docs/PROJECT_NOTES.md, ayu-docs/AyuLocalPremiumImplementation.md, ayu-docs/AyuLocalPremium3-12.md.
