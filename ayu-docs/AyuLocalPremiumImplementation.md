# Локальный Premium и кастомные эмодзи: пункты 1–2

Состояние на 2026-09-27: код реализован в C:/AyuGram-iOS copy for codex. По запросу пользователя пункты 1–12 публикуются для новой сборки в codex/local-premium-20260927. Основной проект не менялся.

Актуальные изменения пунктов 3–12, полный перечень файлов и ограничения: [AyuLocalPremium3-12.md](AyuLocalPremium3-12.md). Ниже первоначальная реализация пунктов 1–2; утверждения о ещё не открытых возможностях относятся к тому этапу.

## Поведение

- Настройки ▸ Goldagram ▸ Локальный Premium. По умолчанию выключен; сохраняется отдельно для каждого аккаунта.
- Звезда видна у своего имени в настройках/собственном профиле только на этом клиенте. Флаг Premium пользователя на сервере и в Postbox не подменяется.
- Открыты эмодзи-клавиатура, установка наборов из неё, текстовые подсказки, поиск и вставка из меню набора.
- У неоплаченного аккаунта при отправке облачного сообщения, подписи (включая альбомы) или правки платный CustomEmoji превращается в TextUrl с tg://emoji?id=DOCUMENT_ID, сохраняя исходный Unicode-эмодзи и UTF-16 диапазон.
- Оплаченный Premium, бесплатные эмодзи, «Избранное» и известный собственный набор группы используют штатную отправку. Для набора группы нужен известный медиафайл/его packReference.
- При получении точная ссылка на положительный Int64 внутри одного полного эмодзи получает дополнительный локальный CustomEmoji для отображения. Исходная ссылка сохраняется как маркер транспорта; при последующей сериализации дополнительный CustomEmoji не уходит серверу. Это работает независимо от переключателя.
- Учтены полные серверные сообщения, короткие входящие обновления, ответ сервера после отправки, цитаты и восстановление полученных черновиков.
- Совместимый AyuGram отображает кастомный эмодзи; обычный Telegram показывает исходный Unicode-эмодзи со ссылкой.

## Решения и ограничения

- Один новый публичный Bool в AyuSettings. Это изменение публичного API TelegramCore, поэтому следующая сборка может пересобирать почти всё приложение. Новые функции кодека внутренние.
- Исходные флаги TelegramUser и context.isPremium не меняются. Премиум-стикеры, лимиты, реакции, статусы, перевод, аккаунты и другие пункты прежнего списка остаются на штатных проверках.
- Клавиатура рисования получает эмодзи для локально отрисованного текста; результат рисунка — обычное медиа.
- Виртуальный транспорт предназначен для облачных сообщений и подписей. Секретные чаты не подключены к этому способу отправки.
- Poll/Todo-подсказки не получают локальную льготу: новый параметр EmojiSuggestionsComponent по умолчанию выключен, включён в текстовых полях сообщений.
- Не обещается нативный кастомный эмодзи у получателя в обычном Telegram. Входящие ранее закэшированные ссылки перерисуются новым способом после обновления их серверной копии.
- Исходящие облачные черновики не переводятся в виртуальные ссылки этой версией; их отправка как сообщения проходит через кодек. Rich-message документы вне обычных text entities не конвертируются.
- Предусмотрены проверка границ UTF-16, границ графемы, размера Int64, запрет произвольных ссылок и отсутствие повторных render-entities.

## Проверено локально

- precheck.py: баланс скобок/строк во всех 26 изменённых Swift-файлах и строгий порядок 44 записей настроек; чисто.
- git diff --check: чисто.
- Типы Transaction.getMedia/getPeerCachedData, StickerPackReference, MessageTextEntity, TelegramMediaFile и сигналы engine.data сверены с локальным репозиторием.
- Это статические проверки, не компиляция Swift и не проверка поведения на телефоне. Swift/Xcode на Windows отсутствуют.

## Проверить в следующей сборке и на телефоне

1. Два аккаунта без Premium: включить на одном; звезда/эмодзи доступны только там. Выключить и перезапустить: значение сохраняется, реальные лимиты не меняются.
2. Отправить платные эмодзи из установленного и нового набора, поиска и подсказок: текст, фото/видео с подписью, альбом, отложенное сообщение, редактирование.
3. Проверить результат сразу после отправки, после ответа сервера, переоткрытия чата и перезапуска. Приём на AyuGram Desktop/новом Android и обычном Telegram.
4. Скопировать/переслать сообщение со специальной ссылкой; отредактировать его. В запросе остаётся одна TextUrl на соответствующий диапазон.
5. Отправить в «Избранное», эмодзи группы и бесплатный эмодзи. С оплаченной подпиской штатная отправка CustomEmoji сохраняется.
6. Поставить несколько эмодзи рядом с кириллицей, флагом, тоном кожи, ZWJ-семьёй и форматированием: диапазоны не сдвигаются.
7. Ссылки с обычным текстом, двумя эмодзи, неверным/слишком большим id, лишними параметрами или диапазоном внутри графемы остаются ссылками.
8. Локальный Premium не снимает серверную проверку статуса, стикеров, реакций и не выдаёт оплаченную подписку.

## Изменённые файлы

- [submodules/SettingsUI/Sources/AyuSettingsController.swift](<C:/AyuGram-iOS copy for codex/submodules/SettingsUI/Sources/AyuSettingsController.swift>)
- [submodules/StickerPackPreviewUI/Sources/StickerPackScreen.swift](<C:/AyuGram-iOS copy for codex/submodules/StickerPackPreviewUI/Sources/StickerPackScreen.swift>)
- [submodules/TelegramCore/Sources/ApiUtils/AyuLocalPremiumEmoji.swift](<C:/AyuGram-iOS copy for codex/submodules/TelegramCore/Sources/ApiUtils/AyuLocalPremiumEmoji.swift>)
- [submodules/TelegramCore/Sources/ApiUtils/StoreMessage_Telegram.swift](<C:/AyuGram-iOS copy for codex/submodules/TelegramCore/Sources/ApiUtils/StoreMessage_Telegram.swift>)
- [submodules/TelegramCore/Sources/ApiUtils/TextEntitiesMessageAttribute.swift](<C:/AyuGram-iOS copy for codex/submodules/TelegramCore/Sources/ApiUtils/TextEntitiesMessageAttribute.swift>)
- [submodules/TelegramCore/Sources/PendingMessages/RequestEditMessage.swift](<C:/AyuGram-iOS copy for codex/submodules/TelegramCore/Sources/PendingMessages/RequestEditMessage.swift>)
- [submodules/TelegramCore/Sources/Settings/AyuSettings.swift](<C:/AyuGram-iOS copy for codex/submodules/TelegramCore/Sources/Settings/AyuSettings.swift>)
- [submodules/TelegramCore/Sources/State/AccountStateManagementUtils.swift](<C:/AyuGram-iOS copy for codex/submodules/TelegramCore/Sources/State/AccountStateManagementUtils.swift>)
- [submodules/TelegramCore/Sources/State/ApplyUpdateMessage.swift](<C:/AyuGram-iOS copy for codex/submodules/TelegramCore/Sources/State/ApplyUpdateMessage.swift>)
- [submodules/TelegramCore/Sources/State/PendingMessageManager.swift](<C:/AyuGram-iOS copy for codex/submodules/TelegramCore/Sources/State/PendingMessageManager.swift>)
- [submodules/TelegramCore/Sources/State/RestoreFetchedDrafts.swift](<C:/AyuGram-iOS copy for codex/submodules/TelegramCore/Sources/State/RestoreFetchedDrafts.swift>)
- [submodules/TelegramUI/Components/Chat/ChatTextInputPanelNode/Sources/ChatTextInputPanelNode.swift](<C:/AyuGram-iOS copy for codex/submodules/TelegramUI/Components/Chat/ChatTextInputPanelNode/Sources/ChatTextInputPanelNode.swift>)
- [submodules/TelegramUI/Components/ChatEntityKeyboardInputNode/Sources/ChatEntityKeyboardInputNode.swift](<C:/AyuGram-iOS copy for codex/submodules/TelegramUI/Components/ChatEntityKeyboardInputNode/Sources/ChatEntityKeyboardInputNode.swift>)
- [submodules/TelegramUI/Components/EmojiSuggestionsComponent/Sources/EmojiSuggestionsComponent.swift](<C:/AyuGram-iOS copy for codex/submodules/TelegramUI/Components/EmojiSuggestionsComponent/Sources/EmojiSuggestionsComponent.swift>)
- [submodules/TelegramUI/Components/EntityKeyboard/Sources/EmojiPagerContentSignals.swift](<C:/AyuGram-iOS copy for codex/submodules/TelegramUI/Components/EntityKeyboard/Sources/EmojiPagerContentSignals.swift>)
- [submodules/TelegramUI/Components/EntityKeyboard/Sources/EmojiSearchContent.swift](<C:/AyuGram-iOS copy for codex/submodules/TelegramUI/Components/EntityKeyboard/Sources/EmojiSearchContent.swift>)
- [submodules/TelegramUI/Components/MessageInputPanelComponent/Sources/InputContextQueries.swift](<C:/AyuGram-iOS copy for codex/submodules/TelegramUI/Components/MessageInputPanelComponent/Sources/InputContextQueries.swift>)
- [submodules/TelegramUI/Components/MessageInputPanelComponent/Sources/MessageInputPanelComponent.swift](<C:/AyuGram-iOS copy for codex/submodules/TelegramUI/Components/MessageInputPanelComponent/Sources/MessageInputPanelComponent.swift>)
- [submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoHeaderNode.swift](<C:/AyuGram-iOS copy for codex/submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoHeaderNode.swift>)
- [submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoScreen.swift](<C:/AyuGram-iOS copy for codex/submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoScreen.swift>)
- [submodules/TelegramUI/Sources/Chat/ChatControllerLoadDisplayNode.swift](<C:/AyuGram-iOS copy for codex/submodules/TelegramUI/Sources/Chat/ChatControllerLoadDisplayNode.swift>)
- [submodules/TelegramUI/Sources/ChatController.swift](<C:/AyuGram-iOS copy for codex/submodules/TelegramUI/Sources/ChatController.swift>)
- [submodules/TelegramUI/Sources/ChatControllerNode.swift](<C:/AyuGram-iOS copy for codex/submodules/TelegramUI/Sources/ChatControllerNode.swift>)
- [submodules/TelegramUI/Sources/ChatControllerOpenAttachmentMenu.swift](<C:/AyuGram-iOS copy for codex/submodules/TelegramUI/Sources/ChatControllerOpenAttachmentMenu.swift>)
- [submodules/TelegramUI/Sources/ChatInterfaceStateContextQueries.swift](<C:/AyuGram-iOS copy for codex/submodules/TelegramUI/Sources/ChatInterfaceStateContextQueries.swift>)
- [submodules/TelegramUI/Sources/EmojisChatInputContextPanelNode.swift](<C:/AyuGram-iOS copy for codex/submodules/TelegramUI/Sources/EmojisChatInputContextPanelNode.swift>)
- ayu-docs/PROJECT_NOTES.md — статус сборки медиа и новой реализации.
- ayu-docs/AyuLocalPremiumImplementation.md — этот отчёт.

## Текущая отдельная сборка медиа

Ветка codex/media-export-20260927, коммит 63112caf4a79a8e3667ca67bc4877690e9f76209.
[GitHub Actions 36315717451](https://github.com/littleboy1941/dyaaufgyh/actions/runs/36315717451).
Сборка медиа завершилась успешно; [зашифрованный IPA](https://github.com/littleboy1941/dyaaufgyh/actions/runs/36315717451/artifacts/10932604322). Наблюдение ayugram остановлено (PAUSED). Изменения локального Premium не входят в опубликованный коммит.
