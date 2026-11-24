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
| E. `fbcrypt` из Java (JNA) или PHP (FFI), вызов `fbcrypt_callback(nil)` | да | ничего |

Используйте способ D только с шифрованием сетевого протокола. Подробности: [common/server-unsafe-client.md](common/server-unsafe-client.md).

## Готовые примеры

| Каталог | Язык | Сценарии | Способ |
|---|---|---|---|
| [python/driver-fbcrypt](python/driver-fbcrypt) | Python, `firebird-driver` | подключение, ошибки ключа, несколько ключей | B |
| [python/driver-keysource](python/driver-keysource) | Python, `firebird-driver` | подключение без кода для ключа | C |
| [python/driver-callback](python/driver-callback) | Python, `firebird-driver` | подключение, ошибки ключа | D |
| [python/gbak-stdin](python/gbak-stdin) | Python | резервная копия и восстановление из программы | — |
| [python/encrypt-monitor](python/encrypt-monitor) | Python, `firebird-driver` | шифрование, смена ключа, мониторинг | B |
| [python/services-backup](python/services-backup) | Python, `firebird-driver` | резервная копия через Services API | B |
| [java/jdbc-basic](java/jdbc-basic) | Java, Jaybird | подключение, ошибки ключа | D |
| [java/jdbc-native-fbcrypt](java/jdbc-native-fbcrypt) | Java, Jaybird native | подключение, ошибки ключа, несколько ключей | E |
| [java/jdbc-native-keysource](java/jdbc-native-keysource) | Java, Jaybird native | подключение без кода для ключа | C |
| [java/gbak-stdin](java/gbak-stdin) | Java | резервная копия и восстановление из программы | — |
| [java/jdbc-datasource](java/jdbc-datasource) | Java, HikariCP | пул подключений и потоки | D, E |
| [java/spring-boot](java/spring-boot) | Java, Spring Boot | ключ из переменной окружения | D |
| [php/pdo-ffi-fbcrypt](php/pdo-ffi-fbcrypt) | PHP, PDO | подключение, ошибки ключа, несколько ключей | E |
| [php/pdo-keysource](php/pdo-keysource) | PHP, PDO | подключение без кода для ключа | C |
| [php/gbak-stdin](php/gbak-stdin) | PHP | резервная копия и восстановление из скрипта | — |
| [dotnet/ado-basic](dotnet/ado-basic) | C#, ADO.NET | подключение, ошибки ключа | D |
| [dotnet/gbak-stdin](dotnet/gbak-stdin) | C# | резервная копия и восстановление из программы | — |
| [dotnet/ado-pool](dotnet/ado-pool) | C#, ADO.NET | пул подключений и параллельные задачи | D |
| [dotnet/efcore](dotnet/efcore) | C#, EF Core | ключ из переменной окружения | D |
| [lazarus/console-sqldb](lazarus/console-sqldb) | Free Pascal, SQLdb | подключение, ошибки ключа, несколько ключей | A |
| [lazarus/gbak-stdin](lazarus/gbak-stdin) | Free Pascal | резервная копия и восстановление из программы | — |
| [lazarus/threads-sqldb](lazarus/threads-sqldb) | Free Pascal, SQLdb | потоки | A |
| [keysource](keysource) | C++, Delphi, Lazarus | библиотека `KeySource` | C |
| [closed-gui](closed-gui) | Lazarus, Free Pascal, PowerShell | полный пример для приложения без исходных кодов: приложение, четыре варианта `KeySource`, поставщик ключа, служба REST, скрипты развёртывания; Firebird 3.0, 4.0, 5.0 | C |
| [clientkeygen](clientkeygen) | Python | индивидуальные ключи клиентов, журнал сервера (только Firebird 5.0) | B |
| [keychecker](keychecker) | C++, Free Pascal | библиотека `KeyChecker` | — |
| [app/Example_ForLazarus_IBX](app/Example_ForLazarus_IBX) | Lazarus, IBX | подключение, шифрование, мониторинг | A |

Примеры Python, Java, PHP, .NET и Free Pascal проверены на Firebird 4.0 и 5.0 (Windows x64). У каждого есть скрипт `run-test.ps1`.
Способы B, C и E проверены и при `UnsafeClient = false` (Firebird 4.0).

## Как запустить

1. Создайте тестовый сервер: [common/README.md](common/README.md).
2. Откройте каталог примера и следуйте его README.

Тестовые ключи `Red` и `Green` из файла [common/test-keys.conf](common/test-keys.conf) опубликованы. Не используйте их для рабочих данных.
