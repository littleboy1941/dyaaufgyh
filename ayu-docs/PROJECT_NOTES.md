# AyuGram iOS — рабочие заметки

Состояние на 2026-09-17 (вечер). Это форк официального Telegram-iOS с фичами AyuGram, который собирается без Mac на GitHub Actions и ставится на iPhone через SideStore с бесплатным Apple ID.

## База

- Официальный Telegram-iOS **12.9.2**, залит одним коммитом без истории (upstream `6ad963e5`).
- Требования upstream: Xcode 26.2, Bazel 8.4.2 (`versions.json`).
- Bundle ID: **`com.ayugram.client`**. **Не менять**, иначе тратятся App ID бесплатного аккаунта (10 в неделю).
- Все app extensions выключены в `.bazelrc` (`--//Telegram:disableExtensions`), приложение занимает 1 App ID.
- Push-уведомления на бесплатной подписи не работают, это ожидаемо.
- `.gitmodules`: у rlottie и tgcalls относительные URL upstream заменены на абсолютные.

## Сборка (`.github/workflows/build.yml`)

Запуск вручную: `gh workflow run build.yml -R littleboy1941/dyaaufgyh --ref master -f configuration=sideload -f mode=debug`.

Параметры запуска:
- `configuration`:
  - `sideload` (по умолчанию) — наш bundle ID и ключи из секретов;
  - `official` — контрольная сборка со стоковым конфигом.
- `mode`:
  - `debug` (по умолчанию);
  - `release`.

Раннер `macos-26-intel` (стандартный, бесплатный для публичного репо).

Шаги и особенности:
- Checkout shallow (`fetch-depth: 1`) вместе с сабмодулями. Номер сборки = `run_number + 4000`.
- Metal Toolchain на части образов отсутствует и докачивается (`xcodebuild -downloadComponent MetalToolchain`).
- Bazel: `versions.json` пинит sha только для arm64. На Intel качаем официальный x86_64-бинарник и сверяем с `.sha256` релиза.
- Троттлинг в `.bazelrc` (дописывается в CI): `--jobs=2`, `--worker_max_instances=1`, `local_resources`. Без него раннер терял связь или зависал.
- Дисковый кэш Bazel (`--cacheDir`) хранится в `actions/cache`:
  - ключ `bazel-<mode>-<configuration>-<hash pins>-<run_id>`, restore по префиксу;
  - после успешной сборки файлы кэша, не использованные этой сборкой, удаляются (по mtime, с защитой: удаление только если использовано больше 1000 файлов);
  - сохраняется, только если содержимое изменилось, и только если меньше 9 ГБ;
  - ~6,5 ГБ на диске, ~1,5 ГБ в хранилище GitHub.
- Подпись: `build-system/sideload/prepare.sh` генерирует `configuration.json` из секретов и переподписывает фейковый профиль upstream под наш bundle ID. `aps-environment` в профиле обязателен для `Make.py`.
- IPA публикуется **только** как `Telegram.ipa.7z` с AES-256 и паролем `IPA_PASSWORD`: артефакты публичного репо может скачать кто угодно, а в IPA вшиты `api_id` и `api_hash`.
- `reencrypt.yml` перешифровывает артефакт готовой сборки паролем `IPA_PASSWORD_NEW` (если пароль потерян). Пересборка не нужна.

Секреты: `TELEGRAM_API_ID`, `TELEGRAM_API_HASH`, `IPA_PASSWORD`. Значения никому не показывать и в логи не выводить.

Безопасность репо:
- workflow из fork-PR требуют одобрения (кэш содержит скомпилированные ключи);
- права `GITHUB_TOKEN` по умолчанию только на чтение.

### Замеры

| Сборка | Время |
|---|---|
| Полная release | ~99 мин Bazel |
| Полная debug | ~96 мин (debug почти не ускоряет) |
| Без изменений, из кэша | ~8 мин всего |
| С изменением публичного API `TelegramCore` | ~62 мин всего (пересобираются все зависимые модули) |

- Debug IPA ~550 МБ, release ~70 МБ.
- Изменения только внутри функций `TelegramCore` + правка в `TelegramUI` (без нового public API): шаг Build ~10,5 мин (замер 2026-09-17, run 35201730979). С новым public API в `TelegramCore` — Build ~1 ч 20 мин (run 35194019169). Но run 35204846653 (тоже только внутренние правки `TelegramCore`, сразу после сборки с новым API) шёл ~62 мин — причина не выяснена (возможно, кэш предыдущей сборки не подхватился).

### Известные проблемы и TODO по CI

- Раннеры macOS 26 случайно зависают или «lost communication» (actions/runner-images#13882, жалобы до сентября 2026). У нас одна сборка зависла на 5643/5763, монитор замолчал, помогла только force-cancel, кэш не сохранился.
- Сделано: `timeout-minutes: 240` на шаге Build (job — 360), чтобы при зависании успел сохраниться кэш.
- **TODO:** расширенный монитор (`memory_pressure`, `df`, top по RSS) в файл и выгрузка при падении.
- Запасной вариант при повторных зависаниях — `macos-15-intel` (там тоже есть Xcode 26.2), ценой одной полной пересборки кэша.
- Сравнить инкрементальную сборку в release и debug. Если разницы нет, вернуть release по умолчанию.

## Установка на телефон

1. Скачать артефакт: `gh run download <run_id> -R littleboy1941/dyaaufgyh -n ipa-encrypted`.
2. Распаковать 7-Zip с паролем.
3. Перекинуть `Telegram.ipa` на iPhone. Удобно через LocalSend; файл окажется в «Файлы → На iPhone → LocalSend». При медленной передаче выключить VPN.
4. SideStore → My Apps → «+» → файл. Ставится поверх, данные сохраняются.

## Ключи api_id

- Созданы 2026-09-16 на **чужом** аккаунте. Если владелец удалит приложение на my.telegram.org, ключи перестанут работать.
- Из России сработало: VPN с сервером в Казахстане, режим инкогнито, номер +7.
- Не сработало:
  - hosts;
  - WARP;
  - мобильный МТС;
  - шведский и канадский VPN.

## Фичи

### ✅ Сохранение удалённых сообщений v1 (2026-09-17, проверено на телефоне)

- Личные чаты, не боты, не 777000, только сообщения с текстом (подпись к медиа и ссылки тоже считаются).
- При `updateDeleteMessages` (`.DeleteMessagesWithGlobalIds` в `AccountStateManagementUtils.swift`) сообщение не удаляется: получает `AyuDeletedMessageAttribute`. У времени показывается `🗑`.
- Global id сопоставляется поштучно: `messageIdsForGlobalIds` пропускает отсутствующие локально. В ghostgram здесь баг со сдвигом индексов.
- Удаление с этого устройства идёт локальным путём и стирает сообщение как обычно. Удаление с другого своего устройства сохранится (отличить нельзя).
- Не сохраняется то, что пришло и удалилось, пока приложение было выгружено. Идея на потом: круглосуточный «помощник»-логгер.

Идеи дальше:
- защита скачанного медиа удалённых сообщений от очистки кэша (копия + лимит);
- группы и каналы;
- экран настроек;
- история правок.

### ✅ Удалённые сообщения v2 (2026-09-17, собрано run 35221748150, базово работает на телефоне)

Одна пачка коммитов после `6525467d`, собирается одной сборкой.

- Логика в `TelegramCore/Sources/State/AyuDeletedMessages.swift`: `ayuMarkMessageDeleted` решает по `AyuSettings` и ставит `AyuDeletedMessageAttribute`. Вызывается из:
  - `.DeleteMessagesWithGlobalIds` (личные чаты и обычные группы, `updateDeleteMessages`);
  - `.DeleteMessages` (супергруппы и каналы, `updateDeleteChannelMessages`, в т.ч. из channel difference);
  - `HistoryViewStateValidation` (сверка истории с сервером удаляла пропавшие сообщения).
- Не сохраняются: сервисные сообщения, `TelegramMediaExpiredContent`, сообщения с `AutoremoveTimeoutMessageAttribute`/`AutoclearTimeoutMessageAttribute` (TTL, одноразовые), 777000, секретные чаты.
- Своё удаление с этого устройства стирает сразу локально, поэтому пришедший потом update сообщение уже не находит.
- Настройки: `TelegramCore/Sources/Settings/AyuSettings.swift` — per-account Postbox preference `PreferencesKeys.ayuSettings` (значение 500, далеко от upstream). Поля декодируются с дефолтами, новые поля добавлять так же. Экран `SettingsUI/Sources/AyuSettingsController.swift`, пункт «AyuGram» в настройках (`PeerInfoSettingsSection.ayuGram`).
- UI: `ChatMessageItemView.setupItem` делает удалённые полупрозрачными (`ayuDeletedMessageTargetAlpha`, 0.65); фото, видео и стикеры остаются непрозрачными — только 🗑 (просьба пользователя: полупрозрачная картинка выглядит как фильтр). В анимации пыли конечная прозрачность — `ayuDeletedContentAlpha` (атрибута на старом item ещё нет). `ChatHistoryListNode.ayuAnimateNewlyDeletedMessages`: если у видимого сообщения появился атрибут — DustEffect со снимка и проявление через 1 с.
- Меню: для сохранённого удалённого только «удалить у себя»; `deleteMessagesInteractively` не отправляет для них запрос на сервер.
- Кэш (`Utils/AyuCacheProtection.swift`): автоочистка по срокам (`AutomaticCacheEviction`, по умолчанию группы 31 день, каналы 7) и ручная очистка (`_internal_clearStorage`) пропускают ресурсы, на которые StorageBox ссылается из удалённых сообщений.

Известные ограничения и риски:
- Лимит размера кэша (`TimeBasedCleanup` в Postbox) стирает файлы в обход StorageBox — не защищено (по умолчанию лимита нет).
- Медиа, скачанное без контекста сообщения (reference peerId 0), не защищено.
- `updateChannelAvailableMessages` / `minAvailableMessageId` (очистка истории админом) стирает диапазон — не сохраняется, сознательно.
- Непрочитанное удалённое сообщение остаётся в счётчике непрочитанных.
- Сверка истории может повторно запрашивать у сервера сохранённые сообщения (не проверено, смотреть трафик/логи `HistoryValidation`).
- Ответить/отреагировать на удалённое сообщение меню не запрещает — сервер вернёт ошибку.

Что проверить на телефоне:
1. Личный чат: собеседник удаляет текст, фото, голосовое при открытом чате → пыль, затем полупрозрачный пузырь с 🗑. Переоткрыть чат → без анимации.
2. Группа и супергруппа (другой участник удаляет своё) и канал, где ты подписчик.
3. Настройки ▸ AyuGram: выключить «В группах» → удаление в группе стирает сообщение.
4. Удалить у себя сохранённое сообщение → исчезает, ошибок нет.
5. Хранилище ▸ очистить кэш → фото удалённого сообщения остаётся.

### ✅ История правок v1 (2026-09-17, собрано run 35221748150, базово работает на телефоне)

- `TelegramCore/Sources/State/AyuEditHistory.swift`: перед применением правки старый текст входящего сообщения пишется в item cache коллекцию `Namespaces.CachedItemCollection.ayuEditHistory` (100), ключ — id сообщения, максимум 50 версий. Не в атрибутах: серверная копия сообщения их затирает.
- Точки записи: `.EditMessage` в `replayFinalState`, а также полные серверные копии (`ayuRecordEdits`): `AddMessages` в replay (difference), дыры истории и загрузка чатов в `Holes.swift`, сверка в `HistoryViewStateValidation`. Не покрыты: поиск, `AccountViewTracker`, `ReplyThreadHistory`, `SparseMessageList` и др. полные перезапросы.
- Свои сообщения не пишутся (только `Incoming`). Настройка `saveEditHistory`.
- UI: меню сообщения ▸ «История правок» (для входящих с `EditedMessageAttribute`, не для альбомов) → `SettingsUI/Sources/AyuEditHistoryController.swift`. Открытый экран не обновляется при новой правке (переоткрыть).
- Проверить: собеседник правит сообщение 2–3 раза → в меню «История правок» все версии с датами; свои правки не пишутся; выключенная настройка — не пишется.
- Записи не удаляются при удалении сообщения (мелкий мусор в базе).

### ✅ Одноразовые медиа v1 (2026-09-17, собрано run 35221748150, базово работает на телефоне)

Облачные чаты (не секретные): фото/видео с таймером, «просмотр один раз», view-once голосовые и кружки.

Поведение:
- при открытии собеседнику уходит обычное «просмотрено» (`messages.readMessageContents` / `channels.readMessageContents`);
- у нас медиа не помечается просмотренным: нет `countdownBeginTime`, нет замены на `TelegramMediaExpiredContent`, выглядит неоткрытым (размытие, значок) и открывается сколько угодно раз, переживает перезапуск;
- удалённая собеседником одноразка сохраняется как удалённая (🗑);
- файл защищён от очистки кэша;
- настройка `AyuSettings.keepSelfDestructingMedia` (по умолчанию вкл), экран AyuGram ▸ «Одноразовые медиа».

Почему это вообще возможно: сервер отдаёт файл телефону целиком, «один раз» — это только локальная логика клиента (атрибуты `AutoclearTimeoutMessageAttribute`/`AutoremoveTimeoutMessageAttribute` + `ManagedAutoremoveMessageOperations`). Серверные данные, которые не приходят на телефон (например точный last seen при скрытом статусе), так получить нельзя.

Код (`TelegramCore/Sources/State/AyuSelfDestructingMedia.swift`):
- `ayuShouldPreserveSelfDestructingMedia(message:settings:)` — входящее, Cloud, не секретный чат, `containsSecretMedia`, ещё не expired, настройка включена. Единый предикат для всех мест ниже.
- `ayuConsumeSelfDestructingMediaRemotely` — ждёт `mediaBox.resourceData(...).complete` главного ресурса (largest image representation / file.resource), затем `addSynchronizeConsumeMessageContentsOperation`. Сам не качает: загрузку делает просмотрщик. Если файл не докачался — отметка не уйдёт, пока не откроют снова.
- `ayuPreservingSelfDestructingMedia(transaction:incoming:)` — серверная копия сообщения: для сохраняемого всегда возвращает локальные `ConsumableContent`/timeout/`AyuDeleted` атрибуты; медиа подменяет локальным, только если серверная копия expired или без медиа. `getMessage` делается только если у входящего есть timeout-атрибут или expired.

Точки врезки:
- `MarkMessageContentAsConsumedInteractively.swift`: для сохраняемых — только упоминание (`ConsumablePersonalMention` → pending) + удалённая отметка; остальное — прежний путь `markMessageContentAsConsumedLocallyInteractively`. В `markMessageContentAsConsumedRemotely` (наш же read-update с сервера) для сохраняемых не трогаются consumed и таймеры, упоминания обрабатываются.
- `ManagedAutoremoveMessageOperations.swift`: сообщения с `AyuDeletedMessageAttribute` и сохраняемые одноразки не удаляются/не expire; обязательно `clearTimestampBasedAttribute`, иначе запись остаётся головой очереди.
- Серверные копии через `ayuPreservingSelfDestructingMedia`: replay `AddMessages` и `.EditMessage` (AccountStateManagementUtils), `resolveAssociatedMessages` (там же), `Holes.swift` (дыры, загрузка чатов, additionalMessages), `HistoryViewStateValidation` (обе ветки, `ayuMessage`), `ResetState.swift`, `ManagedSynchronizePinnedChatsOperations.swift`.
- `AyuDeletedMessages.swift`: timeout-атрибуты больше не мешают сохранению удалённого, если одноразка сохраняется.
- `AyuCacheProtection.swift`: защищены ресурсы и удалённых, и сохраняемых одноразок.
- UI не менялся: при нетронутых атрибутах штатный UI сам показывает «неоткрыто», `SecretMediaPreviewController` без `countdownBeginTime` не запускает таймер, view-once голосовые/кружки открываются через `ChatControllerOpenViewOnceMediaMessage`.

Известные ограничения / не проверено:
- Не покрыты редкие пути перезаписи сообщений: поиск (`SearchMessages`), `AccountViewTracker`, `ReplyThreadHistory`, `SparseMessageList`, `LoadMessagesIfNecessary`.
- Можно ли скачать файл после серверной отметки — не проверено; поэтому отметка только после полной загрузки.
- Каждое открытие ставит новую read-операцию (без дедупликации) — лишние запросы, не цикл.
- Сохранение в галерею, пересылка, скриншоты — по-прежнему запрещены штатно (не трогали).
- Медиа, открытое до этой сборки, уже стёрто.
- Секретные чаты не поддержаны.

Чек-лист теста:
1. Фото «один раз»: открыть, закрыть → снова размыто, открывается повторно.
2. У собеседника — «просмотрено».
3. Голосовое и кружок «один раз», фото/видео с таймером.
4. Перезапуск приложения — одноразки на месте.
5. Собеседник удалил одноразку — осталась с 🗑.
6. Выключить настройку — одноразки ведут себя штатно.
7. Настройки ▸ Данные и память ▸ Использование памяти ▸ очистить кэш — одноразки открываются.

### ✅ Снятие ограничений на скриншоты, запись и пересылку v1 (2026-09-18, написано, на телефоне не проверено)

Повод: попытка заснять фичу с одноразовыми медиа — на видео пустой экран.

В Telegram это **три независимых механизма** скрытия контента плюс отдельные уведомления и отдельный запрет пересылки — одной точки нет:

1. `setLayerDisableScreenshots` (`UIKitRuntimeUtils/.../UIKitUtils.m`) — подсовывает `CALayer` внутрь `UITextField` с `isSecureTextEntry`. Обслуживает секретные чаты, copy-protected пиров, одноразки, галерею, профиль, закреплённое, context menu и pinch.
2. `MediaPlayerNode.swift` — `AVSampleBufferDisplayLayer.preventsCapture` для видео (системный iOS-механизм, с п.1 никак не связан).
3. `StoryItemImageView.swift` — у историй своя копия трюка с `UITextField`.

Настройки (все в `AyuSettings`, раздел «СНЯТИЕ ОГРАНИЧЕНИЙ»):

- `allowScreenCapture` (вкл) — гасит все три механизма выше + две помехи записи: отказ открывать view-once при активной записи (`ChatControllerOpenViewOnceMediaMessage.swift`) и паузу view-once голосового (`ChatController.swift`, ветка CloudUser).
- `dontNotifyScreenshots` (вкл) — не отправлять `historyScreenshot` в облачных чатах (`SecretMediaPreviewController.swift`) — именно это палит при скрине одноразки.
- `dontNotifyScreenshotsInSecretChats` (выкл по умолчанию) — то же для секретных (3 точки: `ChatController`, `GalleryController`, `SecretMediaPreviewController`). Выключено, потому что в секретном чате собеседник этого уведомления ждёт.
- `ignoreCopyRestrictions` (вкл) — снимает noforwards: сохранение, копирование текста, выделение, «Поделиться», кнопка «Переслать», автосохранение в галерею.

**Новая инфраструктура: синхронный снапшот настроек.** `TelegramCore/Sources/Settings/AyuSettingsSnapshot.swift` — `ayuSettingsSnapshot` / `ayuSetSettingsSnapshot` (`Atomic<AyuSettings>`). Нужен там, где нет ни транзакции, ни аккаунта: чистые предикаты `Message.isCopyProtected()` / `Peer.isCopyProtectionEnabled` и ObjC-слой `UIKitRuntimeUtils`. Обновляется подпиской в `SharedAccountContextImpl.init` (только `isMainApp`) по **primary-аккаунту**; с несколькими аккаунтами побеждает основной. Этот же снапшот пригодится для режима призрака.

`ignoreCopyRestrictions` пришлось ставить не только в предикаты (`Message.isCopyProtected()`, `Peer.isCopyProtectionEnabled`, EngineData `CopyProtectionEnabled` и `MyCopyProtectionEnabled`), но и в **пять мест, где флаги читаются напрямую** в обход предикатов: `ChatHistoryListNode.swift` (питает `associatedData.isCopyProtectionEnabled` — без этого не работает выделение и копирование текста), `ChatControllerContentData.swift`, `GalleryController.swift`, `PeerInfoData.swift` + `PeerInfoScreen.swift`, `StoreDownloadedMedia.swift`.

Отдельно важно: в `ChatControllerContentData.swift` гасится **и** `myCopyProtectionEnabled` (моя собственная защита в личном чате). Он доезжает до `OpenChatMessage` как `copyProtected` и запрещает «Поделиться» документом; настоящее значение по-прежнему читается из `CachedUserData` для экрана управления в профиле. Побочно исчезает подсказка «вы запретили сохранение» в меню сообщения.

`Peer.ayuRawIsCopyProtectionEnabled` — неискажённое значение флага для логики, которая **не** является presentation-решением. Используется в `AccountStateManagementUtils` (пополнение недавних стикеров/GIF исходящими из защищённых чатов): там подмена предиката меняла бы локальные данные, а не только UI. Правило: всё, что не про отображение, читает raw-версию.

Не трогали сознательно: `ChannelVisibilityController` и `PeerInfoScreenPerformButtonAction` (там флаги читаются для admin-UI «запретить пересылку» — нужно показывать настоящее значение); чат Telegram Notifications (скриншот там инвалидирует коды входа — это защита нас, не ограничение).

Грабли, найденные по ходу (важно для любого теста записи экрана):

- `ScreenCaptureDetection.swift` в `#if DEBUG` делает `value = !"".isEmpty`, то есть **в debug-сборке запись экрана всегда считается выключенной**. Поэтому отказ открыть view-once и пауза голосового в debug не воспроизводятся вообще — проверять эти два пункта можно только в release. Уведомление о скриншоте и затемнение слоёв от этого не зависят.
- `ChatControllerNode.swift` в `#if DEBUG` не защищает `historyNodeContainer` вообще (но title accessory panel всё равно защищает).
- `ayuAllowScreenCaptureValue` в ObjC инициализирован `true`, чтобы совпадать с `AyuSettings.default`: иначе до первой эмиссии подписки получался смешанный режим (видео и истории уже разрешены, а `setLayerDisableScreenshots` ещё защищает). Плата: если настройку выключить, в app extensions (у нас отключены) флаг останется `true` — им понадобится своя загрузка настройки, если extensions когда-нибудь включим.
- Переключение настройки применяется к заново созданным слоям — надо переоткрыть чат.
- `allowScreenCapture` — **глобальный** выключатель, он снимает затемнение и в чате с кодами входа Telegram (`isVerificationCodes`). Это сознательно: точка перехвата в ObjC не знает контекста. Инвалидация кодов входа при скриншоте при этом работает как раньше (не трогали).

Ограничения:

- **Сама пересылка из noforwards-чата всё равно упрётся в сервер** (`CHAT_FORWARDS_RESTRICTED`). Локально работают сохранение, копирование, внешний share и скриншот. Настоящая пересылка = AyuForward (скачать + перезалить), отдельная большая фича.
- У историй закрыты только скриншот и запись. Кнопки Save/Forward/Share у story живут на своём флаге `EngineStoryItem.isForwardingDisabled` (не трогал: гейт в месте разбора флага сломает prefill приватности моих собственных stories).
- Сохранение одноразового медиа в галерею всё ещё недоступно: оно запрещено не через copy protection, а через `containsSecretMedia`, и `SecretMediaPreviewController` показывает урезанный footer без кнопки share. Нужна отдельная UI-работа.
- Снапшот настроек один на все аккаунты (primary).

Чек-лист теста:

1. Одноразовое фото: открыть и записать видео экрана → на записи видно фото, собеседнику не приходит «сделал скриншот».
2. Скриншот одноразки → картинка на скрине есть, уведомления нет.
3. Одноразовое видео и кружок при записи экрана (проверяет `preventsCapture`).
4. Канал с запретом пересылки: текст выделяется и копируется, фото сохраняется в галерею, скриншот не чёрный.
5. Секретный чат: скриншот виден, но уведомление собеседнику УХОДИТ (подпункт выключен по умолчанию). Включить подпункт → не уходит.
6. Выключить «Разрешить скриншоты», переоткрыть чат → затемнение вернулось.

### Сборки 2026-09-17

- run 35194019169 — удалённые v2 (первая сборка с новым public API, ~1 ч 20 мин Build).
- run 35201730979 — фиксы альбомов/общих ресурсов (~10,5 мин).
- run 35203975869 / 35204846653 — история правок и фикс полных копий.
- run 35221748150 — одноразовые медиа + непрозрачные удалённые фото + фиксы ревью. Упала только загрузка артефакта (таймаут GitHub), `gh run rerun --failed` прошёл за ~10 мин. **Актуальная сборка.**

### План

1. Режим призрака. Перехват нужен во всех путях:
   - `readHistory` и `readDiscussion`;
   - `readMessageContents`;
   - `getMessagesViews` с `increment`;
   - `stories.readStories` и `incrementStoryViews`;
   - `setTyping`;
   - `updateStatus` с отправкой offline после отправки сообщения.
2. Название «AyuGram» и иконка (пользователь решил делать вместе с одной из первых фич).
3. Фильтры, мелочи UI, медиа удалённых.
4. Кнопка «Сохранить в галерею» для одноразовых медиа и Save/Forward для stories.
5. Идея пользователя: бегущие слоны поверх чата (хромакей-мем, конвертировать в WebM VP9 с альфой и играть через пайплайн видео-стикеров; оверлей по образцу `ConfettiView`).

## Референсы (локальные shallow-клоны в `C:\ayu-ref`)

- `AyuGramDesktop` (dev `db3b989`, актуальный, C++) — основной источник логики.
- `AyuGram4A` (Android, открытый код только до 2023, часть `proprietary` закрыта).
- `ghostgram` — форк Telegram-iOS 12.2.3 с ghost mode и anti-delete, GPL-2.0. Годится для поиска точек перехвата; хранение у него в `UserDefaults`, так делать не надо.
- Полный разбор фич AyuGram: `ayu-docs/ayugram-features-research.md`.

## Процесс

- Codex (`codex exec`, модель Sol) делает исследования и черновой код. Claude ставит задачи, проверяет по коду, собирает, коммитит.
- Собрать локально нельзя (Windows). Каждая проверка — это сборка в CI, поэтому изменения лучше копить пачкой.
