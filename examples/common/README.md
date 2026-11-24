# Тестовый сервер для примеров

Скрипты создают отдельный сервер Firebird с зашифрованными базами данных.
Установленные службы Firebird скрипты не изменяют.

## Что нужно

- Windows, PowerShell 5.1 или новее.
- Каталог Firebird 3.0, 4.0 или 5.0 с плагином шифрования IBSurgeon (или HQbird). В каталоге должны быть `firebird.exe`, `fbclient.dll`, `fbcrypt.dll`, `plugins\dbcrypt.dll`, `plugins\keyholder.dll`, `plugins\keyholderstdin.dll`.
- Файл лицензии `DbCrypt.conf`. Лицензия должна подходить к версии плагина.
- Библиотека OpenSSL (`libcrypto-*.dll`). Если её нет в каталоге Firebird, укажите путь в параметре `-OpenSslDll`.

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

Параметры: `-WorkDir <каталог>`, `-Port <порт>`, `-OpenSslDll <файл>`.

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
| `FBCRYPT_KEYS` | файл с тестовыми ключами |
| `FBCRYPT_WORK` | рабочий каталог |
| `FBCRYPT_FB_MAJOR` | версия Firebird: 3, 4 или 5 |
| `FBCRYPT_CLIENTKEYGEN` | путь к утилите `ClientKeygen`. Задаётся вручную, нужен только примеру `clientkeygen`. |

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
