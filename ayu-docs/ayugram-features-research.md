Исследован текущий `AyuGramDesktop` ветки `dev` (`db3b989`), старый Android-форк и документация. Изменений в файлы не вносил.

Сокращения путей:

- `D:` = `C:\ayu-ref\AyuGramDesktop\Telegram\SourceFiles`
- `A:` = `C:\ayu-ref\AyuGram4A\TMessagesProj\src\main\java`
- `Docs:` = `C:\ayu-ref\AyuGramDocs`

Настройки Desktop хранятся в `tdata/ayu_settings.json`; полный сериализуемый список находится в `D:\ayu\ayu_settings.cpp:1072-1169`. Ghost-настройки могут быть глобальными или отдельными для каждого аккаунта: `D:\ayu\ayu_settings.cpp:367-416`, `D:\ayu\ayu_settings.h:715-716`.

---

# 1. Режим призрака

## 1.1. Общая модель

Главный переключатель не является отдельным сетевым режимом. Он одновременно изменяет пять флагов:

- не читать сообщения;
- не читать истории;
- не отправлять online;
- не отправлять typing/upload progress;
- автоматически отправлять offline.

Каждый из них можно «заблокировать» Shift-кликом, чтобы общий переключатель его не менял: `D:\ayu\ui\settings\settings_ayu.cpp:387-430`, `D:\ayu\ayu_settings.cpp:138-152`.

Тонкость: `isGhostModeActive()` считает заблокированную опцию удовлетворённой независимо от её фактического значения: `D:\ayu\ayu_settings.cpp:46-68`. Поэтому «активный Ghost Mode» может иметь намеренно оставленное исключение.

Сложность iOS: **низкая** для модели настроек, **средняя** для корректной интеграции со всеми сетевыми путями.

## 1.2. Не читать сообщения

Что видит пользователь: чат локально становится прочитанным, но read receipt по возможности не уходит на сервер.

Перехваты:

| Механизм | Когда | Реализация |
|---|---|---|
| `messages.readHistory` | Перед фактической отправкой накопленной очереди read-запросов | Очередь просто очищается: `D:\data\data_histories.cpp:695-704`; штатные методы создаются в `D:\data\data_histories.cpp:764-772` |
| `channels.readHistory` | Там же | Те же строки |
| `messages.readDiscussion` | Перед отправкой read в discussion/topic | `D:\data\data_replies_list.cpp:1005-1024` |
| `messages.readMessageContents` | После локального `markContentsRead`, до запроса | `D:\apiwrap.cpp:1450-1515` |
| `channels.readMessageContents` | Аналогично | `D:\apiwrap.cpp:1470-1487`, `1503-1508` |
| `messages.getMessagesViews` | Запрос всё равно отправляется, но `increment=false` | `D:\api\api_views.cpp:89-113` |

Важная тонкость: для unread mention/reaction без unread media `readMessageContents` пропускается даже в Ghost Mode, чтобы сервер очистил mention/reaction: `D:\apiwrap.cpp:1460-1467`, `1491-1500`.

Голосовые и видеосообщения локально отмечаются просмотренными, но `readMessageContents` блокируется. Premium speech-to-text может выдать просмотр серверными путями — это заявлено в `Docs:\shared\ghost.md`, но отдельного перехвата транскрибации в Desktop нет.

Сложность iOS: **средняя**. Нужны отдельные проверки для history, topic/discussion, media content и view counters. Глобальной блокировки одного метода недостаточно.

## 1.3. Прочитать конкретное сообщение

Когда Ghost Mode блокирует read, в контекстном меню появляется «Read Message». Оно принудительно отправляет:

- `messages.readHistory` или `channels.readHistory` до выбранного сообщения;
- затем `messages.readMessageContents` или `channels.readMessageContents`, если это непротухшее входящее media.

Код: `D:\ayu\ui\context_menu\context_menu.cpp:904-950`; helper истории: `D:\ayu\utils\telegram_helpers.cpp:412-447`.

Сложность iOS: **низкая** после реализации базового блокирования read.

## 1.4. Локально прочитать все / прочитать на сервере все

Два опциональных пункта drawer:

- **Read on Local**: временно блокирует read-пакеты и локально помечает все диалоги прочитанными.
- **Read on Server**: временно разрешает пакеты, помечает всё прочитанным, затем через 200 мс восстанавливает Ghost-настройку.

`D:\window\window_main_menu.cpp:767-812`, обход всех диалогов — `D:\ayu\utils\telegram_helpers.cpp:304-312`.

Сложность iOS: **средняя**: массовые транзакции Postbox плюс корректный read state для форумов.

## 1.5. Не читать stories

Перехватываются оба серверных сигнала просмотра:

- `stories.readStories`;
- `stories.incrementStoryViews`.

Проверка стоит как в момент локальной постановки просмотра в очередь, так и непосредственно перед запросом:

- `D:\data\data_stories.cpp:1239-1268`;
- `D:\data\data_stories.cpp:1404-1427`;
- `D:\data\data_stories.cpp:1461-1501`.

При выключенном read-story локальный `readTill` тоже не повышается.

Реакция или ответ на story могут раскрыть просмотр серверу независимо от `stories.readStories`; специального обхода этого ограничения нет.

Сложность iOS: **средняя**.

## 1.6. Предупреждение перед открытием story

Если Ghost Mode не активен, read stories разрешён, соответствующая опция не заблокирована и включён alert, перед открытием показывается диалог:

- «Yes» временно включает Ghost Mode и открывает story;
- после закрытия viewer Ghost Mode возвращается;
- «No» открывает без Ghost Mode.

`D:\window\window_controller.cpp:594-627`, состояние — `D:\ayu\ayu_state.cpp:36-47`, восстановление — `D:\media\view\media_view_overlay_widget.cpp:8581`.

Состояние привязано к одной session. Ответ/реакция всё равно остаются серверной утечкой.

Сложность iOS: **низкая–средняя**.

## 1.7. Не отправлять online

Штатное вычисление online изменено на:

```text
isOnline = sendOnlinePackets && hasActiveWindow
```

Затем уходит `account.updateStatus(offline: !isOnline)`:

`D:\api\api_updates.cpp:994-1063`.

Грабля: `_lastWasOnline` записывается из исходного `isOnlineOrig`, а не из замаскированного значения: `D:\api\api_updates.cpp:1024-1034`. Это может влиять на повторную отправку статуса.

Кроме того, сервер может сам считать пользователя online после значимых действий. Поэтому после успешной отправки сообщения код помечает аккаунт как «возможно засветившийся»: `D:\data\data_histories.cpp:1161-1182`.

Сложность iOS: **средняя**. Важно не только подавить periodic presence, но и учитывать lifecycle приложения и сетевые reconnect.

## 1.8. Автоматически уйти offline

Раз в три секунды worker проверяет аккаунты. Если аккаунт недавно был замечен online, отправляет:

```text
account.updateStatus(offline=true)
```

`D:\ayu\ayu_worker.cpp:24-87`.

Worker повторно вооружается после:

- входящего `updateUserStatus` для самого пользователя: `D:\api\api_updates.cpp:2072-2084`;
- успешной отправки сообщения: `D:\data\data_histories.cpp:1161-1174`;
- запуска бота: `D:\apiwrap.cpp:5015-5029`;
- принудительного чтения: `D:\ayu\utils\telegram_helpers.cpp:412-445`.

Грабля: если параллельно открыт обычный Telegram, получится online/offline blinking.

Сложность iOS: **средняя**, с учётом ограничений background execution iOS. Гарантировать трёхсекундный worker в фоне нельзя.

## 1.9. Не отправлять typing/upload progress

До построения запроса прекращается вся обработка `messages.setTyping`:

- typing;
- record/upload video;
- record/upload voice;
- record/upload round video;
- upload photo/file;
- choosing location/contact/sticker;
- game play;
- speaking in group call.

`D:\api\api_send_progress.cpp:115-158`.

То есть настройка «Don’t Send Typing» фактически блокирует и upload progress.

Сложность iOS: **низкая–средняя**. Надо найти все producers активности, а не только текстовый typing.

## 1.10. Read on Interact

Работает только когда обычное чтение заблокировано. После действия принудительно читает историю до `lastServerMessage`, то есть не только сообщение, на которое ответили:

`D:\ayu\utils\telegram_helpers.cpp:449-456`.

Точки вызова:

- отправка любого подготовленного сообщения: `D:\data\data_histories.cpp:1126-1134`;
- успешный `messages.sendReaction`: `D:\data\data_message_reactions.cpp:1524-1541`;
- успешный `messages.sendVote`: `D:\api\api_polls.cpp:376-395`;
- bot actions: `D:\api_bot.cpp:457`, `611`, `D:\apiwrap.cpp:4405`;
- отправка scheduled message вручную: `D:\window\window_peer_menu.cpp:3778`.

Это также запускает offline worker.

Сложность iOS: **средняя**. Главная опасность — пропустить альтернативные send/reaction/poll пути.

## 1.11. Scheduled Messages для скрытой отправки

Работает только при «полном» активном Ghost Mode и если пользователь сам уже не выбрал schedule date:

`D:\ayu\ayu_settings.h:100`, `D:\ayu\utils\telegram_helpers.cpp:1575-1585`.

Добавляет `schedule_date` к обычным outgoing RPC (`messages.sendMessage`, `messages.sendMedia`, `messages.sendMultiMedia` и связанным путям).

Задержки:

- текст: 12 секунд;
- media в актуальном коде:  
  `12 + ceil(max(6, ceil(sizeMiB * 0.7))) + 1`;
- при включённом proxy задержка умножается на 1.2 с округлением вверх.

`D:\ayu\utils\telegram_helpers.cpp:708-711`, `1575-1585`.

Документация устарела: там указано `sizeMiB * 4.5`. Код является более надёжным источником.

Опция взаимоисключающая с Read on Interact: `D:\ayu\ui\settings\settings_ayu.cpp:438-501`.

Точки применения включают `D:\api\api_sending.cpp:190`, `D:\apiwrap.cpp:4190`, `4659`, `5256`, `5529`, `D:\boxes\send_files_box.cpp:2479`.

Риски:

- плохая сеть может задержать upload дольше schedule date;
- scheduled-message API имеет отличия для разных типов вложений;
- клиент специально не переводит пользователя в раздел scheduled messages после такой отправки.

Сложность iOS: **высокая** из-за количества send-путей и media upload pipeline.

## 1.12. Send without sound по умолчанию

Режимы:

- Never;
- только при активном Ghost Mode;
- Always.

`D:\ayu\ayu_settings.cpp:113-129`, UI — `D:\ayu\ui\settings\settings_ayu.cpp:503-544`.

Флаг `silent` инвертируется для явного пункта «Send With Sound»: `D:\history\history_item_helpers.cpp:626-639`, меню — `D:\menu\menu_send.cpp:750-758`.

Сложность iOS: **низкая**.

---

# 2. Anti-recall: удалённые и изменённые сообщения

## 2.1. Сохранение удалённых сообщений

Перехват выполняется при приёме updates:

- `updateDeleteMessages` → `processNonChannelMessagesDeleted`;
- `updateDeleteChannelMessages` → `processMessagesDeleted`.

`D:\api\api_updates.cpp:1407-1410`, `1457-1462`.

Для каждого ID:

1. Ищется уже загруженный `HistoryItem`.
2. Если включено сохранение и диалог разрешён, item не уничтожается.
3. Item помечается deleted и записывается в Ayu DB.
4. Если item не найден локально, сохранить его нельзя.

`D:\data\data_session.cpp:3150-3213`, проверка bot/settings — `D:\ayu\utils\telegram_helpers.cpp:714-736`.

Следствие: Desktop сохраняет только сообщения, присутствующие в памяти клиента в момент delete update. Он не делает `messages.getMessages` после удаления и не ведёт полную теневую копию Postbox.

### Как отображается

- В текущей сессии сообщение остаётся в истории с флагом deleted.
- После перезапуска оно исчезает из обычного чата.
- Доступно через меню AyuGram → View Deleted.
- Есть Clear Deleted и поиск по тексту.
- Первая страница — 20 записей, далее по 30.

`D:\ayu\ui\context_menu\context_menu.cpp:250-324`, `D:\ayu\ui\message_history\history_inner.cpp:66-68`, `735-857`.

В bubble показывается настраиваемая отметка или иконка; удалённые сообщения могут иметь opacity 0.7 с анимацией 500 мс:

`D:\history\view\history_view_bottom_info.cpp:491-515`, `D:\history\view\history_view_element.cpp:1451-1507`.

Сложность iOS: **высокая**. Нужны перехват update до удаления Postbox-объекта, долговременное хранилище, синтетические UI-items и корректная работа с holes/topics.

## 2.2. История изменений

Перехваты:

- `updateEditMessage`;
- `updateEditChannelMessage`.

`D:\api\api_updates.cpp:1431-1434`, `1447-1450`.

Старое состояние сохраняется **до** применения edition: `D:\data\data_session.cpp:2908-2951`.

Условия:

- старый item должен быть загружен;
- только обычный `message`, не service;
- не local;
- автор не self;
- `editHide` должен быть false;
- новый текст/rich-page должен отличаться;
- старый текст не пустой.

То есть история собственных правок не записывается. `saveForBots` здесь не проверяется — в текущем Desktop он влияет на удалённые сообщения, но не на edit history.

В контекстном меню появляется History; revisions открываются в отдельной истории: `D:\ayu\ui\context_menu\context_menu.cpp:489-513`.

Сложность iOS: **средняя–высокая**. Проще delete, поскольку старая версия обычно ещё находится в Postbox, но важно перехватить update до merge.

## 2.3. Хранилище

Отдельная SQLite БД:

```text
tdata/ayudata.db
```

`D:\ayu\data\ayu_database.cpp:14-15`.

Таблицы:

- `DeletedMessage`;
- `EditedMessage`;
- `DeletedDialog`;
- `RegexFilter`;
- `RegexFilterGlobalExclusion`;
- `SpyMessageRead`;
- `SpyMessageContentsRead`.

Полная схема: `D:\ayu\data\ayu_database.cpp:16-145`.

Поля `DeletedMessage`/`EditedMessage` включают:

- account/user ID, dialog ID, topic ID, message ID;
- grouped ID, peer/from;
- date/edit date/views/flags;
- заготовки forward/reply;
- text и serialized entities;
- media path, thumb, document serialization, MIME.

Но фактический mapper заполняет преимущественно IDs, flags и text/entities. Media помечается TODO, `mediaPath="/"`, `documentType=none`: `D:\ayu\data\messages_storage.cpp:32-85`.

Если текст пустой, запись вообще не создаётся: `D:\ayu\data\messages_storage.cpp:87-95`, `114-123`.

Итого для Desktop:

- текст и подписи сохраняются;
- media-only сообщения после перезапуска не сохраняются;
- файлы и thumbnails в Ayu DB не копируются;
- многие forward/reply поля схемы пока остаются пустыми;
- `DeletedDialog` и обе `SpyMessage*` таблицы в текущем коде фактически не используются;
- автоматического TTL/лимита размера DB не найдено;
- очистка только пользовательская;
- уникального ограничения от дублей нет.

Сложность iOS: **средняя** для text-only аналога; **высокая** для полноценного media archive.

## 2.4. Кто удалил сообщение

Desktop не хранит явный признак «удаление инициировал этот клиент».

При обычном собственном удалении:

1. отправляется `messages.deleteMessages` или `channels.deleteMessages`;
2. item сразу уничтожается локально;
3. поздний delete update уже не находит item и не сохраняет его.

`D:\data\data_histories.cpp:810-831`, `961-1041`.

Это косвенная эвристика, а не надёжное различение сторон. Удаление пользователем с другого своего устройства может попасть в anti-recall.

Отдельный пункт «Delete own messages» ведёт себя иначе: делает `messages.search(from_id=self)` пачками по 100, затем `messages.deleteMessages(revoke)` / `channels.deleteMessages`, обрабатывает flood wait и вручную вызывает delete processing: `D:\ayu\ui\context_menu\context_menu.cpp:81-220`. При включённом сохранении этот путь может оставить собственные удалённые сообщения как deleted.

Для iOS лучше сразу вести короткоживущий набор locallyInitiated `(peerId,messageId)` и исключать его при update, как делает Android.

## 2.5. TTL, one-view media и секретные чаты

Desktop модифицирует TTL UI:

- не очищает expired media при включённом save deleted: `D:\history\history_item.cpp:2728-2756`;
- оставляет возможность повторного открытия документа: `D:\history\view\media\history_view_document.cpp:390-423`;
- меняет подсказки viewer: `D:\chat_helpers\ttl_media_layer_widget.cpp:199-238`;
- пункт Burn вручную отправляет `messages.readMessageContents`: `D:\ayu\ui\context_menu\context_menu.cpp:953-975`.

Это помогает только пока media живёт в текущем кеше/памяти. В Ayu DB файл не копируется.

В Desktop ghost-коде нет перехвата `messages.readEncryptedHistory` или `messages.setEncryptedTyping`. Полноценное покрытие secret chats этим кодом **не подтверждено**. Для Telegram-iOS secret chats надо проектировать отдельно.

---

# 3. Фильтры и скрытие

## 3.1. Regex-фильтры

Виды:

- shared/global;
- отдельные для диалога;
- исключение конкретного shared filter из конкретного диалога;
- enabled;
- case-insensitive;
- reversed: скрывать сообщения, которые **не** совпали;
- разрешать shared filters в обычных чатах отдельно от broadcast.

Схема: `D:\ayu\data\ayu_database.cpp:114-128`.

Matching выполняется ICU regex с `find()` и multiline: `D:\ayu\features\filters\filters_controller.cpp:44-93`.

Текст для проверки содержит не только `message.text`, но и:

- URL и custom URL targets;
- тексты всех сообщений альбома;
- inline keyboard в форме `<button>text data</button>`;
- синтетический `<type>N</type>` для типа media.

`D:\ayu\features\filters\filters_utils.cpp:535-718`.

Исходящие сообщения никогда не фильтруются: `D:\ayu\features\filters\filters_controller.cpp:152-191`.

Regex компилируются в памяти; невалидные/пустые/disabled пропускаются. Результаты кешируются по message и распространяются на весь album: `D:\ayu\features\filters\filters_cache_controller.cpp:43-99`, `182-199`.

Фильтр влияет на:

- message list;
- dialog preview;
- notifications;
- media-info lists.

`D:\history\history_inner_widget.cpp:6013`, `D:\history\view\history_view_list_widget.cpp:1543`, `D:\window\notifications_manager.cpp:455`, `D:\dialogs\dialogs_layout.cpp:471-475`.

Импорт/экспорт — JSON v2, clipboard, URL и публикация на dpaste: `D:\ayu\features\filters\filters_utils.cpp:350-530`, `903-943`.

MTProto не перехватывается: сообщения принимаются и сохраняются штатно, скрывается только клиентское представление.

Сложность iOS: **средняя**. Лучше реализовать как видимость поверх Postbox, не удаляя сообщения из базы.

## 3.2. Hide from Blocked Users

Дополнительный фильтр скрывает:

- сообщения заблокированного автора;
- сообщения через заблокированного бота;
- forwarded сообщения, чей исходный автор заблокирован.

В прямом диалоге с самим заблокированным пользователем сообщения не прячутся: `D:\ayu\features\filters\filters_controller.cpp:100-150`.

Также подавляются typing/send-action и связанные визуальные элементы: `D:\history\view\history_view_send_action.cpp:62-73`.

Сложность iOS: **средняя**.

## 3.3. Shadow Ban

Хранится список dialog/user IDs в `ayu_settings.json`, не в SQLite: `D:\ayu\ayu_settings.cpp:1084`, `D:\ayu\ayu_settings.h:630`.

Скрывает сообщения выбранного пользователя или broadcast source через общий `FiltersController`. Быстрый toggle есть в peer menu: `D:\ayu\ui\context_menu\context_menu.cpp:432-462`.

Это только локальное скрытие; MTProto ban/restrict запросов нет.

Сложность iOS: **низкая–средняя**.

## 3.4. Показать отфильтрованные

Для каждого peer можно временно переключить Show/Hide Filtered. Состояние находится в памяти и не сохраняется: `D:\ayu\ui\context_menu\context_menu.cpp:288-301`.

Сложность iOS: **низкая**.

## 3.5. Hide одного сообщения

Контекстный пункт кладёт ID в `AyuState` и удаляет view. После перезапуска состояние пропадает: `D:\ayu\ayu_state.cpp:13-34`, `D:\ayu\ui\context_menu\context_menu.cpp:516-541`.

Никакого server delete или изменения Postbox нет.

Сложность iOS: **низкая**.

---

# 4. UI-мелочи и локальные фичи

Все следующие функции не перехватывают MTProto, если явно не указано обратное.

| Фича | Что делает / настройки | Основные точки | Сложность iOS |
|---|---|---|---|
| Message Shot | Рендер выбранных сообщений в одно изображение; фон, дата, реакции, header decorations, colorful replies, spoilers, тема; copy/save | `D:\ayu\features\message_shot\message_shot.cpp:462-508`, `D:\ayu\ui\boxes\message_shot_box.cpp:298-416` | **Высокая** |
| Простые replies/quotes | Убирает цветные фоны и background emoji у replies, quotes, previews | `D:\history\view\history_view_reply.cpp:854`, `D:\history\view\media\history_view_web_page.cpp:1045` | **Низкая** |
| Метки deleted/edited | Иконки либо собственные строки; отдельные настройки | `D:\ayu\ui\settings\settings_chats.cpp:150-190`, `D:\history\view\history_view_bottom_info.cpp:491-515` | **Низкая** |
| Прозрачные deleted | Opacity 0.7, 500 ms animation | `D:\history\view\history_view_element.cpp:1451-1507` | **Низкая** |
| Bubble geometry | Радиус 0–16, убрать хвост, единый avatar radius, width multiplier 1–4 | `D:\ayu\ui\settings\settings_chats.cpp:195-290`, `D:\ayu\ui\settings\settings_appearance.cpp:139-190` | **Низкая–средняя** |
| Hide fast share | Убирает боковую кнопку share | `D:\history\view\history_view_message.cpp:5872` | **Низкая** |
| Реакции | Отдельно скрывать в личных чатах, группах, каналах | `D:\ayu\ui\settings\settings_chats.cpp:56-78` | **Низкая** |
| Emoji/stickers | Показывать только добавленные; unlimited recent stickers | `D:\chat_helpers\emoji_list_widget.cpp:3526`, `D:\chat_helpers\stickers_list_widget.cpp:879`, `3334` | **Низкая–средняя** |
| Channel bottom button | Hide / Mute / Discuss with fallback | `D:\history\history_widget.cpp:6027`, `6687` | **Низкая** |
| Quick admin shortcuts | Дополнительные быстрые действия в top bar | `D:\history\view\history_view_top_bar_widget.cpp:1444-1465` | **Низкая** |
| Disable greeting sticker | Скрывает greeting sticker/intro | `D:\history\view\history_view_about_view.cpp:276`, `766` | **Низкая** |
| Context-menu visibility | Для reactions panel, views, Hide, User Messages, Details, Repeat, Add Filter: hidden/shown/только с Ctrl/Shift | `D:\ayu\ui\settings\settings_chats.cpp:291-370`, проверка `D:\ayu\ui\context_menu\context_menu.cpp:245-248` | **Низкая** |
| User Messages | Открывает поиск сообщений конкретного автора в текущем чате | `D:\ayu\ui\context_menu\context_menu.cpp:544-570` | **Низкая** |
| Message Details | ID, views, shares, даты, размер/имя/MIME/path/resolution/DC, данные sticker pack | `D:\ayu\ui\context_menu\context_menu.cpp:573-781` | **Средняя** |
| Repeat Message | Повторно отправляет выбранное сообщение/media, может сохранить reply, применяет ghost schedule | `D:\ayu\ui\context_menu\context_menu.cpp:784-901` | **Средняя–высокая** |
| Message field | Отдельно скрывать Attach, Commands, TTL, Emoji, Microphone, Gift, AI editor; Attach/Emoji popups | `D:\ayu\ui\settings\settings_chats.cpp:377-446` | **Низкая** |
| App icon | Набор альтернативных иконок, на Windows также custom `.ico` | `D:\ayu\ui\components\icon_picker.cpp`, `D:\ayu\ui\settings\settings_appearance.cpp:55-67` | **Низкая** |
| Counters | Скрыть folder counters и badge приложения | `D:\ayu\ui\settings\settings_appearance.cpp:70-76`, `239-250` | **Низкая** |
| Hide All Chats | Убирает системную вкладку All Chats | `D:\ayu\ui\settings\settings_appearance.cpp:246-252` | **Низкая** |
| Drawer/tray | Настраиваемые пункты My Profile, Bots, New Group/Channel, Contacts, Calls, Saved, local/server read, night, ghost, streamer | `D:\ayu\ui\settings\settings_appearance.cpp:260-370` | **Низкая** |
| Hide premium statuses | Не рисует premium badge | `D:\history\view\history_view_message.cpp:2537`, `D:\ui\unread_badge.cpp:247` | **Низкая** |
| Custom backgrounds | Может отключить пользовательские chat backgrounds | `D:\ayu\ui\settings\settings_appearance.cpp:201-207` | **Низкая** |
| MD3 switches | Альтернативный стиль переключателей | `D:\ayu\ui\settings\settings_appearance.cpp:194-200` | **Низкая** |
| Mono font | Пользовательский monospace font | `D:\ayu\ui\settings\settings_appearance.cpp:216-231` | **Низкая** |
| Показывать секунды | Время сообщения с секундами | `D:\ayu\ui\settings\settings_general.cpp:265-271` | **Низкая** |
| Peer ID | Hide / Telegram API / Bot API формат; каналы `-100…` | `D:\ayu\ui\utils\ayu_profile_values.cpp:14-50` | **Низкая** |
| Filter Zalgo | Чистит combining characters в именах и тексте | `D:\ayu\utils\telegram_helpers.cpp:1267`, применения `D:\data\data_user.cpp:380-382`, `D:\history\history_item.cpp:4430-4431` | **Низкая** |
| Send confirmations | Подтверждение sticker/GIF/voice/round video | `D:\chat_helpers\gifs_list_widget.cpp:543`, `D:\chat_helpers\stickers_list_widget.cpp:2846`, `D:\history\view\controls\history_view_voice_record_bar.cpp:3030-3181` | **Низкая** |
| Webview | Представляться `android` вместо `tdesktop`; увеличить окно по ширине/высоте | `D:\inline_bots\bot_attach_web_view.cpp:829`, `D:\ui\chat\attach\attach_bot_webview.cpp:1218-1223` | **Средняя** |
| Adaptive music cover | Включать/выключать вычисление цвета UI из обложки saved music | `D:\ayu\ui\components\saved_music.cpp:276-342`, `D:\info\saved\info_saved_music_common.cpp:104-139` | **Низкая–средняя** |

---

# 5. Прочие функциональные возможности

## 5.1. AyuForward

Автоматически используется для:

- deleted messages;
- no-forwards сообщений/чатов;
- TTL/one-view media.

Условие: `D:\ayu\features\forward\ayu_forward.cpp:228-245`.

Поток:

1. Выделение делится на обычные и AyuForward chunks.
2. Media скачивается.
3. Сообщение пересоздаётся без исходного автора.
4. Media загружается заново.
5. Внизу показывается progress и возможность отмены.

Используемые RPC включают:

- `messages.uploadMedia`: `D:\ayu\features\forward\ayu_sync.cpp:721-726`;
- `messages.getRichMessage`: `D:\ayu\features\forward\ayu_sync.cpp:789-800`;
- `messages.sendMessage`: `D:\ayu\features\forward\ayu_sync.cpp:878-890`;
- остальные media send идут через штатные send APIs.

Ограничения:

- это не настоящий forward, а reupload/re-send;
- авторство и часть metadata теряются;
- нужны локально доступные media;
- deleted text-only из DB можно переслать, media после перезапуска — нет;
- albums, rich pages, captions и progress требуют отдельной логики.

Сложность iOS: **очень высокая**. Делать после anti-recall и стабильного media pipeline.

## 5.2. Disable Ads

Для обычных sponsored messages отключается eligibility/request path: `D:\data\components\sponsored_messages.cpp:245-272`, promo suggestions — `D:\data\components\promo_suggestions.cpp:138`.

Но `contacts.getSponsoredPeers` в поиске всё ещё может отправляться; результат затем отбрасывается: `D:\api\api_peer_search.cpp:95-105`.

Сложность iOS: **низкая–средняя**, но надо перечислить отдельно все рекламные surfaces.

## 5.3. Disable Stories

Не загружает initial stories и скрывает story UI в dialogs/profile: первая проверка `D:\data\data_session.cpp:343-347`. Настройка требует restart.

Это не тотальная блокировка всех story RPC; точное отсутствие любого фонового story traffic **не проверено**.

Сложность iOS: **средняя**, потому что story UI распределён по нескольким модулям.

## 5.4. Local Telegram Premium

Принудительно возвращает premium status/availability на клиенте: `D:\main\main_session.cpp:389-425`, `D:\data\data_peer_values.cpp:410-417`.

Серверные лимиты, отправка premium-only сущностей и отображение другими пользователями не меняются.

Сложность iOS: **низкая**, но результат заведомо косметический.

## 5.5. Similar Channels

- Collapse Similar Channels после вступления: `D:\apiwrap.cpp:1972-1978`.
- Hide Similar Channels Tab: скрывает profile/info tab.

Запросы similar peers полностью не блокируются; это преимущественно UI.

Сложность iOS: **низкая**.

## 5.6. Disable notification delay

Штатный Telegram откладывает локальное уведомление, когда другой клиент online. AyuGram игнорирует cloud/default delay и использует минимальную задержку: `D:\window\notifications_manager.cpp:396-421`.

Сложность iOS: **средняя**, особенно из-за APNs и Notification Service Extension.

## 5.7. Improve Link Previews

До получения preview переписывает host:

- `twitter.com`, `x.com` → `fixupx.com`;
- TikTok → `kktiktok`;
- Reddit → `vxreddit`;
- Instagram → `kkclip`;
- Pixiv → `phixiv`.

`D:\ayu\utils\telegram_helpers.cpp:1544-1572`.

Это не новый MTProto-метод: меняется URL перед штатным web-page preview pipeline.

Сложность iOS: **низкая**.

## 5.8. Translation provider

Выбор:

- Telegram;
- Google;
- Yandex;
- native OS provider, если доступен.

UI: `D:\ayu\ui\settings\settings_general.cpp:36-115`; adapters — `D:\ayu\features\translator\`.

Google/Yandex используют отдельные HTTP-реализации, не MTProto. Для iOS логичнее сначала оставить Telegram/native translation.

Сложность: **низкая** для выбора уже имеющихся providers, **средняя** для Google/Yandex.

## 5.9. Streamer Mode

На Desktop помечает все top-level окна как недоступные для capture:

- Windows: `SetWindowDisplayAffinity(WDA_EXCLUDEFROMCAPTURE)` — `D:\ayu\features\streamer_mode\platform\win\streamer_mode_win.cpp:16-23`;
- macOS: `NSWindowSharingNone` — `D:\ayu\features\streamer_mode\platform\mac\streamer_mode_mac.mm:16-23`;
- Linux: no-op.

Общий обход окон: `D:\ayu\features\streamer_mode\streamer_mode.cpp:22-61`.

На iOS точного аналога нет: приложение может обнаружить `UIScreen.isCaptured` и закрыть/замаскировать UI, но не гарантированно скрыть окно только от внешней записи. Полный parity: **не реализуем/очень высокая**.

## 5.10. Open profile/search by ID

Для `tg://user?id=...` сначала ищется локально загруженный peer: `D:\ayu\ayu_url_handlers.cpp:41-60`.

Документация утверждает fallback через bot. В коде действительно есть схема:

- `messages.getInlineBotResults`;
- затем `contacts.resolveUsername`.

`D:\ayu\utils\telegram_helpers.cpp:739-908`.

Но вызов bot fallback сейчас закомментирован, а `searchPeer()` сразу возвращает `nullptr`: `D:\ayu\utils\telegram_helpers.cpp:911-929`. Поэтому в текущем Desktop реально работает только локально известный пользователь. Документация здесь устарела.

Сложность iOS: **низкая** для local lookup, **средняя** для безопасного внешнего resolver.

## 5.11. Дата регистрации/вступления

Для пользователя делает inline query:

```text
messages.getInlineBotResults(query="regdate <id>")
```

и разбирает JSON-ответ: `D:\ayu\utils\telegram_helpers.cpp:1296-1455`.

Для каналов/чатов часть данных берётся локально из invite/create date: `D:\ayu\utils\telegram_helpers.cpp:1480-1507`, UI — `D:\info\profile\info_profile_actions.cpp:1402-1445`.

Сложность iOS: **средняя**; bot-dependent часть ненадёжна.

## 5.12. Jump to Beginning

Пункт peer menu вызывает штатный `resolveJumpToDate` с датой `2013-08-01`; для удалённого первого service message заменяет полученный ID 0 на ID 2: `D:\ayu\ui\context_menu\context_menu.cpp:327-408`.

Конкретный underlying TL внутри штатного resolver здесь **не проверен**.

Сложность iOS: **низкая**.

## 5.13. Delete own messages

Для администраторов megagroup использует штатный delete-all-from-participant. Иначе:

1. `messages.search(from_id=self)` по 100;
2. `messages.deleteMessages(revoke)` или `channels.deleteMessages`;
3. задержка 500–999 мс между пачками;
4. отдельная обработка `FLOOD_WAIT`.

`D:\ayu\ui\context_menu\context_menu.cpp:81-220`.

Сложность iOS: **средняя–высокая** и высокий риск flood/rate-limit.

## 5.14. Register URL Scheme, crash reporting, reset settings

- Register URL Scheme вызывает платформенную регистрацию: `D:\ayu\ui\settings\settings_other.cpp:196-207`.
- Crash reporting включает предложение отправить отчёт после crash: `D:\ayu\ui\settings\settings_other.cpp:178-193`.
- Reset удаляет логическое состояние настроек, записывая defaults: `D:\ayu\ui\settings\settings_other.cpp:209-224`.

Сложность iOS: **низкая**, но URL schemes задаются в bundle/Info.plist, а не регистрируются динамически.

---

# 6. Существенные грабли

1. **Delete update содержит ID, а не старое содержимое.** Сохранять надо до удаления объекта из Postbox. Если item уже выгружен, Desktop теряет его.

2. **Read receipt — не один RPC.** Нужны history, discussion, content read, story read, story view increment и view counters.

3. **Read on Interact читает до последнего серверного сообщения**, а не только reply target. Это может раскрыть больше сообщений, чем ожидает пользователь.

4. **Отправка может сделать пользователя online серверно**, даже если periodic `account.updateStatus(offline=false)` подавлен. Desktop после send лишь пытается быстро вернуть offline.

5. **Schedule date должен рассчитываться после понимания media size**, но до финального send. Если upload длится слишком долго, дата становится плохой.

6. **Собственное удаление Desktop различает лишь косвенно.** Для iOS нужен явный locally-initiated deletion registry.

7. **Media anti-recall в Desktop фактически отсутствует после restart.** Поля есть, mapper не реализован.

8. **Нет лимитов Ayu DB.** При долгой работе история edits/deletes растёт без автоматического retention.

9. **`saveForBots` не применяется к edits** в текущем Desktop.

10. **Secret chats требуют отдельного покрытия.** Android перехватывает encrypted read/typing, Desktop — нет.

11. **Фильтры должны скрывать, но не удалять данные.** Иначе отключение фильтра не восстановит сообщения и сломает unread state.

12. **Документация не всегда соответствует `dev`:**
    - media schedule formula устарела;
    - bot fallback для поиска по ID сейчас отключён;
    - Desktop действительно сохраняет только текст;
    - строки/таблицы Spy, Peek Online, read dates присутствуют, но рабочей реализации в текущем Desktop не найдено.

---

# 7. Отличия Android 2023

## Ghost Mode

Android ставит единый hook прямо перед сериализацией любого запроса: `A:\org\telegram\tgnet\ConnectionsManager.java:302-396`.

Он:

- отбрасывает `messages.setTyping` и `messages.setEncryptedTyping`;
- переписывает `account.updateStatus` в `offline=true`;
- подменяет успешным пустым ответом:
  - `messages.readHistory`;
  - `messages.readEncryptedHistory`;
  - `messages.readDiscussion`;
  - `messages.readMessageContents`;
  - `channels.readHistory`;
  - `channels.readMessageContents`.

То есть Android покрывает secret chats лучше, но в версии 2023 нет блокировки `stories.readStories`.

Read-after-send обёртывает completion `messages.sendMessage`, `sendMedia`, `sendMultiMedia`, затем отправляет `messages.readHistory`: `ConnectionsManager.java:361-391`. Для channel peer это выглядит подозрительно, поскольку всегда создаётся `messages.readHistory`, а не `channels.readHistory`.

`sendOfflinePacketAfterOnline` в Android практически не используется вне settings; отдельного Desktop-подобного worker нет.

## Anti-recall

Android заметно полноценнее:

- Room DB version 21: `A:\com\radolyn\ayugram\database\AyuDatabase.java:20-25`;
- сохраняет media и реакции;
- копирует вложения в `Downloads/AyuGram/Saved Attachments`;
- имеет лимиты и категории сохранения для private/public chats/groups/channels;
- сравнивает не только text, но и photo/document IDs при edits;
- хранит deleted reactions.

`A:\com\radolyn\ayugram\messages\AyuMessagesController.java:70-198`.

Отличие удаления:

- Android ведёт `deletePermitted` по `(dialogId,messageId)`: `A:\com\radolyn\ayugram\utils\AyuState.java:50-76`;
- диалог удаления имеет «Keep locally»: `A:\org\telegram\ui\Components\AlertsCreator.java:5648-5715`;
- явно обрабатывает encrypted/TTL сообщения и при необходимости читает старую запись из Telegram DB: `A:\org\telegram\messenger\MessagesController.java:6095-6172`.

Часть media mapper находится за отсутствующим proprietary-компонентом, поэтому точный формат сериализации файлов **не проверен**.

## Фильтры

Android 2023 имеет существенно более простой фильтр:

- глобальный список regex;
- один общий case-insensitive флаг;
- Java `Pattern.find()`;
- кеш по dialog/message;
- album propagation.

`A:\com\radolyn\ayugram\AyuFilter.java:21-98`.

Нет Desktop-возможностей per-dialog filter, reversed, индивидуальной case sensitivity, global exclusions, blocked-source и shadow-ban в этой реализации.

## Scheduled sends

Android добавляет примерно:

- +11 секунд обычным сообщениям/forward;
- дополнительные константы для photo/document;
- исключает secret chats.

`A:\org\telegram\messenger\SendMessagesHelper.java:1678-1693`, `3378-3405`.

Формула также не совпадает с текущим Desktop.

## Android-only/неподтверждённое

Документация описывает Peek Online, FCM/foreground push service и DB sync. Полная открытая реализация Peek Online в данном shallow clone не найдена — **не проверено**.

---

# 8. Рекомендуемый порядок переноса на Telegram-iOS

1. **Инфраструктура настроек и тестовые hooks**  
   Per-account settings, feature flags, журнал перехваченных RPC. Сложность: низкая.

2. **Ghost: typing + ordinary read history + online**  
   `messages/channels.readHistory`, `messages.setTyping`, `account.updateStatus`. Быстрый пользовательский эффект, нет новой БД. Сложность: средняя.

3. **Ghost: content read, discussion, views и stories**  
   Добавить `readMessageContents`, `readDiscussion`, `getMessagesViews(increment=false)`, `stories.readStories`, `incrementStoryViews`. Сложность: средняя.

4. **Низкорисковые UI-фичи**  
   Peer ID, seconds, simple replies, confirmations, hide buttons/reactions/share, counters, bubble styling. Сложность: низкая.

5. **Edit history text-only**  
   Перехватить `updateEditMessage`/`updateEditChannelMessage` до merge и хранить revisions в отдельном Postbox namespace. Сложность: средняя.

6. **Deleted messages text-only**  
   Сначала обеспечить capture старой Postbox-записи, locally-initiated deletion set, View Deleted и Clear. Сложность: высокая.

7. **Regex filters / blocked / shadow ban**  
   Отдельный слой видимости для chat list, message list и notifications. Сложность: средняя.

8. **Read on Interact, local/server read и story alert**  
   Делать после того, как базовая read-модель уже покрыта тестами. Сложность: средняя.

9. **Media anti-recall**  
   Сразу проектировать retention, quota, cleanup, thumbnails, encrypted media и файловую защиту; не копировать недоделанную Desktop-схему. Сложность: высокая.

10. **Scheduled Ghost Send**  
    После стабилизации всех sendMedia/sendMessage путей. Сложность: высокая.

11. **Message Shot**  
    Независимая, но большая UI/rendering задача. Сложность: высокая.

12. **AyuForward**  
    Последним: download/reupload, albums, progress, cancel, TTL/no-forward/deleted sources. Сложность: очень высокая.

Главный архитектурный совет для iOS: anti-recall лучше строить внутри Postbox-транзакции, до применения delete/edit update, а не как последующий UI-патч. Для media стоит сразу заложить отдельный managed storage с quota и ссылкой на snapshot записи; иначе получится то же ограничение, что у Desktop — «видно до перезапуска, потом остаётся только текст».