# План разработки примеров шифрования (Delphi, Pascal, Java, .NET, Python, PHP)

Дата: 23.11.2026. Статус: вопросы 1, 3, 4, 5 решены (раздел 14). Лицензия для CI отложена.

## 1. Цель

Дать разработчику готовый код для каждого способа передачи ключа.
Каждый пример должен собираться и запускаться за 10 минут по файлу README.

## 2. Что уже есть

| Пример | Путь | Состояние |
|---|---|---|
| Lazarus + IBX (GUI) | `examples/app/Example_ForLazarus_IBX` | Работает на Windows. В `dbcrypthelper.pas` опечатка `cdelc` (ветка не-Windows не компилируется). Ключ только 32 байта. |
| KeySource: C++, Delphi, Lazarus | `examples/keysource` | Работает. Нет README и сборки для Linux. |
| gbak + KeyHolderStdin на Delphi и C | в исходниках HQbird (`src/plugins/crypt/db/stdin/sample`) | В репозитории руководства нет. |

## 3. Общие правила для всех примеров

- Один набор сценариев для всех языков (раздел 4). Одинаковые имена и одинаковый вывод.
- Общий каталог `examples/common`: тестовая база, тестовые ключи `Red` и `Green`, скрипты `setup` и `cleanup`.
- Общий файл `examples/common/server-unsafe-client.md`: настройка сервера для драйверов, которые отправляют ключ статическим значением (Java, .NET, Python с обратным вызовом).
- В коде нет рабочих ключей. Ключ читается из файла или переменной окружения. В README есть предупреждение о ключе-константе.
- Каждый пример проверяет коды возврата `fbcrypt_*` и показывает текст ошибки.
- README в каждом каталоге: что нужно установить, как собрать, как запустить, ожидаемый вывод.
- Языки README: русский и английский.

## 4. Сценарии

| № | Сценарий | Что показывает |
|---|---|---|
| S1 | Подключение с ключом | `fbcrypt_init`, `fbcrypt_key`, `fbcrypt_callback`, обычный запрос |
| S2 | Ошибки ключа | нет ключа, неверное значение, неверное имя; разбор текста ошибки |
| S3 | Несколько ключей и баз | два ключа в списке, две базы; замена ключей через `fbcrypt_init(nil)` |
| S4 | Потоки и пул | `fbcrypt_callback(nil)` в каждом потоке; пул подключений |
| S5 | Шифрование и мониторинг | `ALTER DATABASE ENCRYPT/DECRYPT`, процент из `MON$DATABASE` |
| S6 | Резервная копия из программы | запуск `gbak` с `-KeyHolder KeyHolderStdin`, ключ в stdin процесса |
| S7 | KeySource | библиотека с `MakeKeys` для приложения без исходного кода |
| S8 | Хранение ключа | ключ из файла с правами доступа, из DPAPI (Windows), ввод пользователем |
| S9 | Индивидуальные ключи клиентов | `ClientKeygen`, параметр `Logger`, запись в `firebird.log`. Только Firebird 5.0 |
| S10 | KeyChecker | библиотека с функцией `CheckKey` |

## 5. Delphi

Каталог `examples/delphi`. Минимальная версия: Delphi 10.4 Sydney. Проекты сохраняются в формате 10.4. Платформы: Win32 и Win64.

| Пример | Сценарии | Замечания |
|---|---|---|
| `FbCryptApi.pas` | — | Общий модуль: объявления `fbcrypt_*`, класс-обёртка, разбор hex-ключа. Позднее связывание (`LoadLibrary`). |
| `console-firedac` | S1, S2, S3 | FireDAC использует ISC API: `fbcrypt_callback(nil)`. Путь к `fbclient.dll` берётся из `TFDPhysFBDriverLink.VendorLib` и передаётся в `fbcrypt_init`. |
| `threads-firedac` | S4 | Рабочие потоки и пул FireDAC (`Pooled=True`). Показать ошибку без вызова в потоке и исправление. |
| `vcl-firedac` | S1, S5, S8 | Форма: параметры подключения, шифрование, полоса прогресса. Аналог примера Lazarus. |
| `console-ooapi` | S1, S3 | `Firebird.pas`, `IProvider`, `fbcrypt_callback(provider)`. |
| `console-ibx` | S1 | IBX для Delphi (ISC API). Короткий пример. |
| `gbak-stdin` | S6 | `CreateProcess` с каналом для stdin. За основу взять `gbakrun.pas` из исходников HQbird. Backup, restore, nbackup. |
| `keysource` | S7 | Уже есть. Добавить README, проект для Win64, вариант со сборкой ключа во время работы. |

## 6. Pascal (Lazarus / Free Pascal)

Каталог `examples/lazarus`. Версии: Lazarus 3.x, FPC 3.2.2. Платформы: Windows и Linux.

| Пример | Сценарии | Замечания |
|---|---|---|
| Исправить существующий IBX-пример | S1, S5 | Исправить `cdelc` на `cdecl`. Ключи 16, 24 и 32 байта. Собрать и проверить на Linux (`libfbcrypt.so`). Вынести `dbcrypthelper.pas` в общий каталог. |
| `console-sqldb` | S1, S2, S3 | SQLdb (`TIBConnection`) использует ISC API: `fbcrypt_callback(nil)`. Без сторонних пакетов. |
| `console-fbintf` | S1, S3 | Пакет `fbintf` (объектно-ориентированный API), `fbcrypt_callback(provider)`. |
| `threads-sqldb` | S4 | `TThread`, отдельное подключение в каждом потоке. |
| `console-zeos` | S1 | ZeosLib. Короткий пример. По запросу пользователей. |
| `gbak-stdin` | S6 | `TProcess` с каналом `Input`. Windows и Linux. |
| `keysource` | S7 | Уже есть. Добавить сборку `libKeySource.so` и README с каталогом установки на Linux. |

## 7. Java

Каталог `examples/java`. Версии: Java 17, Maven, Jaybird 5 и 6.

| Пример | Сценарии | Замечания |
|---|---|---|
| `jdbc-basic` | S1, S2 | `dbCryptConfig` через `Properties` и через URL. Форма `base64:`. Экранирование `+` как `%2B` в URL. |
| `jdbc-datasource` | S1, S4 | `FBSimpleDataSource` и пул HikariCP: ключ в свойствах источника данных. |
| `spring-boot` | S1, S8 | Ключ из переменной окружения или хранилища секретов, а не из `application.properties`. |
| `encrypt-monitor` | S5 | `ALTER DATABASE ENCRYPT`, опрос `MON$DATABASE`. |
| `gbak-stdin` | S6 | `ProcessBuilder`, запись ключа в `OutputStream` процесса. |
| `jdbc-native-keysource` | S1, S7 | Jaybird native (JNA) без кода для ключа: клиентский `firebird.conf` с `KeyHolderPlugin = KeyHolder` и библиотека `KeySource`. См. решение 1. |
| `jdbc-native-fbcrypt` | S1, S4 | Jaybird native (JNA) и `fbcrypt` через собственный интерфейс JNA. Сначала практическая проверка. См. решение 1. |
| `server-setup` | — | README: `UnsafeClient = true`, `WireCrypt = Required`, аутентификация `Srp256`. Проверка, что без `WireCrypt` ключ виден в трафике. |

Особенность Java: чистый Java-драйвер не выполняет защищённый обмен ключом.
Каждый README должен начинаться с требований к серверу из `server-setup`.

## 8. .NET

Каталог `examples/dotnet`. Версии: .NET 8, `FirebirdSql.Data.FirebirdClient` (актуальная версия). Платформы: Windows и Linux.

| Пример | Сценарии | Замечания |
|---|---|---|
| `ado-basic` | S1, S2 | Параметр `cryptkey` в строке подключения. Значение: base64 от строки `<имя>:0x..,0x..,`. Показать код, который строит это значение. |
| `ado-pool` | S1, S4 | Пул провайдера (`Pooling=true`). Ключ входит в строку подключения, отдельных вызовов в потоках нет. |
| `efcore` | S1, S8 | EF Core. Ключ из переменной окружения, `user-secrets` или DPAPI, а не из `appsettings.json`. |
| `encrypt-monitor` | S5 | `ALTER DATABASE ENCRYPT`, опрос `MON$DATABASE`. |
| `gbak-stdin` | S6 | `Process` с `RedirectStandardInput`. |
| `embedded-fbcrypt` | S1 | Исследование: режим `ServerType=Embedded` загружает нативную библиотеку. Проверить, работает ли `fbcrypt` через P/Invoke. |

Особенность .NET: провайдер отправляет ключ статическим значением, как Jaybird.
Требования к серверу те же: `UnsafeClient = true` и `WireCrypt = Required`.

## 9. Python

Каталог `examples/python`. Версии: Python 3.11 и новее, пакет `firebird-driver` (актуальная версия). Платформы: Windows и Linux.

Драйвер `firebird-driver` работает через `fbclient` и объектно-ориентированный API.

| Пример | Сценарии | Замечания |
|---|---|---|
| `driver-keysource` | S1, S7 | Без кода для ключа: клиентский `firebird.conf` с `KeyHolderPlugin = KeyHolder` и библиотека `KeySource`. Защищённый обмен ключом сохраняется. Основной способ. |
| `driver-callback` | S1, S2 | Параметр `crypt_callback` функции `connect` (проверено по исходникам драйвера). Класс на основе `iCryptKeyCallbackImpl` возвращает строку `<имя>:0x..,0x..,`. Нужен `UnsafeClient = true` на сервере. |
| `driver-fbcrypt` | S1, S4 | Исследование: `fbcrypt` через `ctypes`. Драйвер создаёт `IProvider` внутри `connect`, поэтому `fbcrypt_callback(nil)` может не подойти. Найти способ передать обратный вызов `fbcrypt` в `crypt_callback`. |
| `encrypt-monitor` | S5 | `ALTER DATABASE ENCRYPT`, опрос `MON$DATABASE`. |
| `gbak-stdin` | S6 | `subprocess.run(..., input=...)`. |

Другие драйверы: `fdb` (устарел) и `firebirdsql` (чистый Python). Проверить поддержку ключа и записать результат в README. Отдельных примеров для них нет.

## 10. PHP

Каталог `examples/php`. Версии: PHP 8.2 и новее, расширения `pdo_firebird` и `php-firebird` (`ibase_*`). Платформы: Windows и Linux.

Оба расширения работают через `fbclient` (ISC API). В PHP нет параметра подключения для ключа.

| Пример | Сценарии | Замечания |
|---|---|---|
| `pdo-keysource` | S1, S7 | Без кода для ключа: клиентский `firebird.conf` с `KeyHolderPlugin = KeyHolder` и библиотека `KeySource` на веб-сервере. Основной способ. |
| `pdo-ffi-fbcrypt` | S1, S2 | Исследование: расширение FFI загружает `fbcrypt`. Вызовы `fbcrypt_init`, `fbcrypt_key`, `fbcrypt_callback(NULL)` перед `new PDO`. Проверить: тот же экземпляр `fbclient`, тот же поток, постоянные подключения. |
| `ibase-keysource` | S1 | Тот же способ для `ibase_connect`. Короткий пример. |
| `gbak-stdin` | S6 | `proc_open` с каналом для stdin. |

README должен описать, где хранить ключ на веб-сервере и какие права доступа нужны для `php-fpm` и Apache.

## 11. ClientKeygen и KeyChecker

Решение 3: обе возможности публикуются в руководстве и получают примеры.

| Задача | Сценарии | Замечания |
|---|---|---|
| Расширить раздел «Индивидуальные ключи клиентов» в `doc/ru/_fbcrypt-keygen.adoc` | S9 | Полный порядок действий: создание ключей, выдача клиентам, включение `Logger`, пример строки в `firebird.log`, замена ключа клиента. Только Firebird 5.0. |
| Расширить раздел `KeyChecker` в `doc/ru/_fbcrypt-config.adoc` | S10 | Когда вызывается `CheckKey` (ключи из `KeyHolder.conf`, из `KeySource`, от клиента, в `KeyHolderStdin`). Что функция может делать с ключом: уточнить по исходникам. |
| `examples/clientkeygen` | S9 | Скрипты для Windows и Linux: создать 3 клиентских ключа, подключиться с каждым, показать записи журнала. |
| `examples/keychecker` | S10 | Библиотека на C++, Delphi и Lazarus. Пример: запись имени ключа и имени программы в журнал. Сборка для Windows и Linux. |

Перед публикацией проверить, что утилита `ClientKeygen` входит в пакет плагина для Firebird 5.0.

## 12. Этапы

| Этап | Содержание | Оценка |
|---|---|---|
| 0 | `examples/common`, исправление IBX-примера, README для существующих примеров | 2 дня |
| 1 | Консольные примеры S1–S3: Delphi FireDAC, Lazarus SQLdb, Java `jdbc-basic` | 4 дня |
| 2 | S6 (gbak из программы) для Delphi, Lazarus, Java; `keysource` для Linux | 3 дня |
| 3 | S4 (потоки и пул) для Delphi, Lazarus, Java | 3 дня |
| 4 | GUI Delphi (VCL), `spring-boot`, S5 и S8 | 4 дня |
| 5 | Объектно-ориентированный API (Delphi, fbintf), `jdbc-native-*`, ZeosLib, IBX Delphi | 4 дня |
| 6 | .NET: `ado-basic`, `ado-pool`, `efcore`, `encrypt-monitor`, `gbak-stdin` | 3 дня |
| 7 | Python и PHP: способ с `KeySource`, `driver-callback`, `gbak-stdin`; исследования `ctypes` и FFI | 4 дня |
| 8 | `ClientKeygen` и `KeyChecker`: разделы руководства, примеры S9 и S10 | 3 дня |
| 9 | Сборка в CI, архивы в Releases, ссылки из руководства | 2 дня |

Этапы 0–2 закрывают самые частые вопросы поддержки. Их стоит выпустить первыми.
Этап 9 зависит от тестовой лицензии (раздел 14). До её появления CI только собирает примеры, запуск выполняется вручную.

## 13. Проверка

Матрица: Firebird 3.0, 4.0, 5.0 и HQbird; Windows x86 и x64; Linux x64 (Lazarus, Java, .NET, Python, PHP).

Критерии готовности примера:

1. Собирается по README на чистой машине.
2. Сценарий проходит на всех версиях Firebird из матрицы (S9 — только на 5.0).
3. Без ключа подключение завершается ожидаемой ошибкой.
4. В коде и в истории git нет рабочих ключей.
5. На пример есть ссылка из руководства (`doc/ru`).

## 14. Решения и открытые вопросы

Решения от 23.11.2026:

1. **Jaybird native.** Свойство `dbCryptConfig` в режимах native и embedded не работает. Руководство Jaybird 6 (раздел 9.4) говорит, что обратный вызов поддержан только в чистом Java-протоколе. В исходниках Jaybird нет вызова `fb_database_crypt_callback`. Остаются два способа:
   - A. Клиентский плагин `KeyHolder` и библиотека `KeySource`. Java-код не меняется.
   - B. Библиотека `fbcrypt` через собственный интерфейс JNA: `fbcrypt_init` с путём к тому же `fbclient`, `fbcrypt_key`, затем `fbcrypt_callback(null)` в потоке, который открывает подключение. Для пула нужна обёртка `DataSource`, которая делает этот вызов перед `getConnection`. Виртуальные потоки использовать нельзя. Способ B на практике не проверен.
2. **Лицензия для CI.** Отложено. Постоянную тестовую лицензию добавим позже.
3. **`ClientKeygen` и `KeyChecker`.** Публикуем. Работы описаны в разделе 11.
4. **Минимальная версия Delphi.** Delphi 10.4.
5. **.NET, Python, PHP.** Примеры нужны. Они описаны в разделах 8–10.

Открытые вопросы:

1. Тестовая лицензия для CI (отложено, см. решение 2).
2. Практические проверки до начала кода: `jdbc-native-fbcrypt` (Java), `embedded-fbcrypt` (.NET), `driver-fbcrypt` (Python), `pdo-ffi-fbcrypt` (PHP). Если способ не работает, пример заменяется абзацем в README.
3. Поддержка ключа шифрования в драйверах `fdb` и `firebirdsql` (Python).
