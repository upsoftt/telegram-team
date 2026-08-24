# Telegram Team

Сборка Telegram для Windows и iPhone из **оригинальных исходников** с несколькими
правками. Нужна там, где официальный клиент упирается в два своих ограничения:

1. **Больше аккаунтов.** Официальный клиент держит 3 аккаунта без подписки и 4–6 с ней.
   Здесь лимит поднят до 50.
2. **Открыть нужное сообщение под нужным аккаунтом.** Ссылка вида
   `tgteam://resolve?domain=<чат>&post=<номер>&account=<user id>` сначала переключает
   клиент на указанный аккаунт, потом открывает сообщение. У Telegram такой возможности
   нет вовсе: `tg://`-ссылка открывается тем аккаунтом, который активен в этот момент.

Всё остальное — обычный Telegram: тот же код, те же серверы, то же шифрование.
Правки занимают около пятисот строк в двадцати шести файлах (сотня из них — описание
набора иконок), их полный текст лежит в `patches/` и читается глазами за один присест.

## Скачать

| Платформа | Где взять |
|---|---|
| Windows 10/11 (64-бит) | [team.bozex.ru](https://team.bozex.ru) и [раздел Releases](../../releases) — архив с готовой программой |
| iPhone | [TestFlight](https://testflight.apple.com/join/DbZ4xJCf) — бета Apple, ставится в один шаг |

Windows-сборка **портативная**: распаковать в любую папку и запустить. Данные аккаунтов
клиент держит рядом с собой, в подпапке `tdata`, — личный Telegram он не трогает вовсе,
и наоборот. Чтобы обновиться, достаточно заменить `.exe` — аккаунты останутся на месте.

**Вход только по QR-коду.** У сборок со своим ключом приложения Telegram придерживает вход
по номеру телефона. QR-код сканируется из уже работающего Telegram на телефоне:
«Настройки → Устройства → Подключить устройство».

**Windows будет ругаться при первом запуске.** Программа не подписана сертификатом
издателя, поэтому SmartScreen показывает «Windows защитила ваш компьютер» — это про
отсутствие подписи, а не про вирус: «Подробнее» → «Выполнить в любом случае». Что скачан
именно опубликованный файл, проверяется контрольной суммой из `.sha256` рядом с архивом:

```powershell
(Get-FileHash TelegramTeam-*-windows-x64.zip -Algorithm SHA256).Hash
```

## Что именно изменено

Подробный разбор — [`docs/changes.md`](docs/changes.md). Коротко:

### Windows (`patches/desktop`, поверх тега `v7.1.1`)

| Файл | Что меняется |
|---|---|
| `main/main_domain.h` | лимит аккаунтов 3/6 → 50 |
| `core/version.h` | своё имя, имя файла и GUID приложения — отдельный каталог данных |
| `core/application.cpp` | схемы `tg://`, `tonsite://`, своя `tgteam://` регистрируются при каждом запуске; параметр `account` переключает аккаунт до открытия чата |
| `core/local_url_handlers.cpp` | текст ответа из ссылки подставляется в поле ввода и в чатах без публичного имени |
| `platform/win/windows_app_user_model_id.cpp` | своя группа в панели задач |
| `Telegram/CMakeLists.txt` | имя выходного файла |
| `config.h`, `Telegram/CMakeLists.txt` и три места использования | ключ приложения попадает в сборку уже перемешанным и не лежит в файле открытым текстом |
| `data_premium_limits.cpp` | закрепление чатов не режется подпиской: клиент всегда берёт больший предел (окончательный предел всё равно ставит сервер) |

### iPhone (`patches/ios`)

| Файл | Что меняется |
|---|---|
| `AccountUtils.swift` и три экрана настроек | лимит аккаунтов 3/4 → 50 |
| `Telegram/BUILD` | своя схема ссылок и свой набор иконок |
| `AppDelegate.swift` | параметр `account` переключает аккаунт — и при холодном старте тоже |
| `UrlHandling.swift`, `OpenUrl.swift` | ссылка несёт номер сообщения и текст ответа сразу |

Правки лежат отдельными коммитами поверх стабильного тега апстрима, поэтому переход на
новую версию Telegram — это `git merge` нового тега, а не перенос изменений руками.

## Чего здесь нет

Это важнее того, что есть, потому что речь о мессенджере:

- **никакой телеметрии, аналитики и «домашних» серверов.** Ни одна правка не добавляет
  сетевых обращений — в этом можно убедиться, прочитав `patches/` целиком;
- **никаких чужих форков в основе.** Только `telegramdesktop/tdesktop` и
  `TelegramMessenger/Telegram-iOS`, стабильные теги. 64Gram, AyuGram, Kotatogram и прочие
  не используются намеренно: чтобы отвечать за то, что происходит с рабочими аккаунтами,
  надо понимать каждую строку отличий от оригинала;
- **никакого автообновления.** Программа не скачивает и не запускает ничего сама.

Готовая сборка не воспроизводима побайтово — Telegram Desktop собирается со своим набором
библиотек, и одинаковые байты у двух разных машин не получатся. Кто не готов доверять
чужому файлу, собирает сам: инструкции ниже полные, ничего скрытого в них нет.

## Собрать самому

Нужен **свой ключ приложения** — пара `api_id` + `api_hash`. Берётся бесплатно на
[my.telegram.org](https://my.telegram.org) → «API development tools». Чужой ключ, ключ из
документации Telegram и ключи официальных клиентов не подойдут: вход просто не сработает.

```powershell
# Windows: полный проход (часы — собираются все библиотеки), потом быстрые пересборки
$env:TELEGRAM_API_ID = '<ваш api_id>'
$env:TELEGRAM_API_HASH = '<ваш api_hash>'
powershell -File scripts\build.ps1 -All
```

```sh
# iPhone: на macOS с Xcode
scripts/mac/run-build.sh <номер сборки>
```

Подробности, требования к машине и разбор типичных сбоев:
[`docs/build-windows.md`](docs/build-windows.md), [`docs/build-ios.md`](docs/build-ios.md).

### Проверить патчи, ничего не собирая

Убедиться, что правки — это ровно то, что здесь написано, можно за пару минут и без
компилятора: патчи должны лечь на чистый тег апстрима без единого конфликта.

```sh
git clone --depth 1 --branch v7.1.1 https://github.com/telegramdesktop/tdesktop.git
cd tdesktop
git am --keep-cr ../telegram-team/patches/desktop/*.patch
git log --oneline -6      # пять наших коммитов поверх «Version 7.1.1»
```

Флаг `--keep-cr` обязателен, а `.gitattributes` в этом репозитории помечает `*.patch`
как двоичные — иначе Windows-переводы строк ломают совпадение контекста.

## Лицензия и правовой статус

Telegram Desktop распространяется под **GPLv3** (с исключением для OpenSSL), Telegram-iOS —
под **GPLv2**. Обе лицензии прямо разрешают изменять программу и распространять изменённую
версию при одном условии: исходный код изменений должен быть открыт. Этот репозиторий и
есть выполнение условия — в нём лежат все правки до последней строки.

Файл [`LICENSE`](LICENSE) — лицензия Telegram Desktop; патчи в `patches/` — производная
работа и распространяются на тех же условиях (`patches/desktop` — GPLv3,
`patches/ios` — GPLv2).

Требования самого Telegram к сторонним клиентам тоже выполнены: собственный `api_id`
([правила](https://core.telegram.org/api/obtaining_api_id)) и открытый исходный код.

**Это не официальный Telegram и проект никак не связан с Telegram FZ-LLC.** Название и
логотип Telegram принадлежат их владельцу; здесь они используются только для того, чтобы
назвать вещи своими именами — какая программа взята за основу.

---

## English summary

An unofficial build of Telegram for Windows and iPhone, made from the original upstream
sources (`telegramdesktop/tdesktop` and `TelegramMessenger/Telegram-iOS`, stable tags) with
two changes: the account limit is raised to 50, and a `tgteam://…&account=<user id>` link
switches to the given account before opening a chat or message.

All modifications are in `patches/` — fewer than 500 lines across 25 files. No telemetry,
no analytics, no auto-update, no third-party fork in the base.

Telegram Desktop is GPLv3 (with the OpenSSL exception), Telegram-iOS is GPLv2; both allow
modification and redistribution provided the modified source is published — which is what
this repository is for. Building requires your own `api_id`/`api_hash` from
[my.telegram.org](https://my.telegram.org).

Not affiliated with or endorsed by Telegram FZ-LLC.
