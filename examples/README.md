# Примеры работы с зашифрованной базой данных Firebird

Примеры показывают, как приложение передаёт ключ шифрования плагину IBSurgeon.
План работ и состояние: [PLAN-ru.md](PLAN-ru.md).

## Способы передачи ключа

| Способ | Защищённый обмен | Что нужно на сервере |
|---|---|---|
| A. `fbcrypt` + `fbcrypt_callback(nil)` (драйверы на ISC API) | да | ничего |
| B. `fbcrypt` + `fbcrypt_callback(provider)` (объектно-ориентированный API) | да | ничего |
| C. Клиентский плагин `KeyHolder` + библиотека `KeySource` | да | ничего |
| D. Статическое значение в параметре драйвера | нет | `UnsafeClient = true` и `WireCrypt = Required` |

Используйте способ D только с шифрованием сетевого протокола. Подробности: [common/server-unsafe-client.md](common/server-unsafe-client.md).

## Готовые примеры

| Каталог | Язык | Сценарии | Способ |
|---|---|---|---|
| [python/driver-fbcrypt](python/driver-fbcrypt) | Python, `firebird-driver` | подключение, ошибки ключа, несколько ключей | B |
| [python/driver-keysource](python/driver-keysource) | Python, `firebird-driver` | подключение без кода для ключа | C |
| [python/driver-callback](python/driver-callback) | Python, `firebird-driver` | подключение, ошибки ключа | D |
| [python/gbak-stdin](python/gbak-stdin) | Python | резервная копия и восстановление из программы | — |
| [dotnet/ado-basic](dotnet/ado-basic) | C#, ADO.NET | подключение, ошибки ключа | D |
| [dotnet/gbak-stdin](dotnet/gbak-stdin) | C# | резервная копия и восстановление из программы | — |
| [keysource](keysource) | C++, Delphi, Lazarus | библиотека `KeySource` | C |
| [app/Example_ForLazarus_IBX](app/Example_ForLazarus_IBX) | Lazarus, IBX | подключение, шифрование, мониторинг | A |

Примеры Python и .NET проверены на Firebird 4.0 (Windows x64). У каждого есть скрипт `run-test.ps1`.

## Как запустить

1. Создайте тестовый сервер: [common/README.md](common/README.md).
2. Откройте каталог примера и следуйте его README.

Тестовые ключи `Red` и `Green` из файла [common/test-keys.conf](common/test-keys.conf) опубликованы. Не используйте их для рабочих данных.
