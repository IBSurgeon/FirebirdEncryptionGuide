# Тестовый сервер для примеров

Скрипты создают отдельный сервер Firebird с зашифрованными базами данных.
Установленные службы Firebird скрипты не изменяют.

## Что нужно

- Windows, PowerShell 5.1 или новее.
- Каталог Firebird 3.0, 4.0 или 5.0 с плагином шифрования IBSurgeon (или HQbird). В каталоге должны быть `firebird.exe`, `fbclient.dll`, `fbcrypt.dll`, `plugins\dbcrypt.dll`, `plugins\keyholder.dll`, `plugins\keyholderstdin.dll`.
- Файл лицензии `DbCrypt.conf`. Лицензия должна подходить к версии плагина.
- Библиотека OpenSSL (`libcrypto-*.dll`). Если её нет в каталоге Firebird, укажите путь в параметре `-OpenSslDll`. Для клиентского каталога имя библиотеки имеет значение, см. [OpenSSL в клиентском каталоге](#openssl-в-клиентском-каталоге).
- Для проверки 32-битных примеров: каталог с 32-битными клиентскими файлами (`fbclient.dll`, `fbcrypt.dll`, `plugins\`). Необязательный параметр `-ClientDir32`.

Двоичных файлов плагина в репозитории нет.

## Создание сервера

```powershell
.\setup.ps1 -FirebirdDir C:\HQbird\Firebird50 -LicenseFile C:\lic\DbCrypt.conf
```

Скрипт выполняет следующие действия:

1. Копирует сервер в рабочий каталог (по умолчанию `%TEMP%\fbcrypt-examples`).
2. Создаёт базы данных `crypt_red` (ключ `Red`), `crypt_green` (ключ `Green`), `plain` и `work` (без шифрования). Базу `work` примеры шифруют и расшифровывают.
3. Удаляет ключи с сервера. После этого ключ должно передать каждое подключение.
4. Создаёт каталог `client` с клиентскими библиотеками и утилитами.
5. Запускает сервер на порту 3070.
6. Создаёт файл `test-env.ps1` с переменными окружения.

Параметры: `-WorkDir <каталог>`, `-Port <порт>`, `-OpenSslDll <файл>`, `-OpenSslDir <каталог>`, `-ClientDir32 <каталог>`, `-OpenSslDir32 <каталог>`.

Перед запуском примера загрузите переменные окружения:

```powershell
. "$env:TEMP\fbcrypt-examples\test-env.ps1"
```

## Переменные окружения

| Переменная | Значение |
|---|---|
| `FBCRYPT_HOST`, `FBCRYPT_PORT` | адрес тестового сервера |
| `FBCRYPT_USER`, `FBCRYPT_PASSWORD` | `SYSDBA` и `masterkey` |
| `FBCRYPT_CLIENT` | каталог с `fbclient`, `fbcrypt` и утилитами |
| `FBCRYPT_CLIENT32` | то же для 32 бит. Пустая, если `setup.ps1` запущен без `-ClientDir32` |
| `FBCRYPT_KEYS` | файл с тестовыми ключами |
| `FBCRYPT_WORK` | рабочий каталог |
| `FBCRYPT_FB_MAJOR` | версия Firebird: 3, 4 или 5 |
| `FBCRYPT_CLIENTKEYGEN` | путь к утилите `ClientKeygen`. Задаётся вручную, нужен только примеру `clientkeygen`. |

## OpenSSL в клиентском каталоге

Библиотека `fbcrypt.dll` загружает OpenSSL по имени, а имя зависит от версии Firebird и от разрядности:

| Firebird | 64 бита | 32 бита |
|---|---|---|
| 3.0, 4.0 | `libcrypto-1_1-x64.dll` | `libcrypto-1_1.dll` |
| 5.0 | `libcrypto-3-x64.dll` или `libcrypto-1_1-x64.dll` | `libcrypto-3.dll` или `libcrypto-1_1.dll` |

Если в клиентском каталоге нет библиотеки с таким именем, `fbcrypt_init` и `fbcrypt_key` возвращают успех, но каждое подключение к зашифрованной базе заканчивается ошибкой `Key not set`.

Скрипт `setup.ps1` читает имена из самого `fbcrypt.dll` и проверяет клиентский каталог. Если в каталоге есть та же версия OpenSSL под другим именем (например, `libcrypto-1_1.dll` вместо `libcrypto-1_1-x64.dll`), скрипт копирует её под нужным именем. Если подходящей библиотеки нет, скрипт останавливается с сообщением. Тогда укажите `-OpenSslDir <каталог с libcrypto-*.dll>`.

Не держите библиотеки с именами `libcrypto-1_1*.dll` в переменной `PATH` вне клиентского каталога (например, из Git for Windows): на машине разработчика ошибка будет замаскирована, а на другой машине примеры не пройдут.

## 32-битный клиент

Проверка примеров в 32 битах (сейчас только `delphi/console-firedac -Platform win32`) требует 32-битные `fbclient`, `fbcrypt` и OpenSSL той же версии Firebird:

```powershell
.\setup.ps1 -FirebirdDir C:\HQbird\Firebird50 -LicenseFile C:\lic\DbCrypt.conf -ClientDir32 C:\FB50x32 -OpenSslDir32 C:\OpenSSL-Win32\bin
```

Скрипт создаёт каталог `client32` и задаёт переменную `FBCRYPT_CLIENT32`.

## Проверка примеров

Каждый пример имеет файл `expected-output.txt` и скрипт `run-test.ps1`.
Скрипт запускает пример и сравнивает стандартный вывод с файлом.

```powershell
.\run-all-tests.ps1
```

Для примеров со способом C сначала создайте клиентский каталог с библиотекой `KeySource`:

```powershell
.\new-keysource-client.ps1 -KeySourceDll C:\build\KeySource.dll
```

## Остановка и удаление

| Действие | Команда |
|---|---|
| Остановить сервер | `.\stop-server.ps1` |
| Запустить сервер снова | `.\start-server.ps1` |
| Остановить сервер и удалить рабочий каталог | `.\cleanup.ps1` |

## Настройка сервера

Для Firebird 5.0 скрипт добавляет в `plugins\DbCrypt.conf` сервера строку `Logger = true` (журнал клиентских ключей).

Файл `plugins\KeyHolder.conf` тестового сервера содержит одну строку: `UnsafeClient = true`.
Она нужна только примерам со способом D. См. [server-unsafe-client.md](server-unsafe-client.md).

Для второго сервера (другая версия Firebird) задайте другие `-WorkDir` и `-Port`.

Скрипта для Linux пока нет.
