# План разработки примеров шифрования (Delphi, Java, Pascal)

Дата: 23.11.2026. Статус: предложение.

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

## 5. Delphi

Каталог `examples/delphi`. Версии: Delphi 10.4 и новее, Win32 и Win64.

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
| `jdbc-native` | S1, S4 | Jaybird native (JNA) + `fbcrypt` через JNA. Сначала исследование: см. открытый вопрос 1. |
| `server-setup` | — | README: `UnsafeClient = true`, `WireCrypt = Required`, аутентификация `Srp256`. Проверка, что без `WireCrypt` ключ виден в трафике. |

Особенность Java: чистый Java-драйвер не выполняет защищённый обмен ключом.
Каждый README должен начинаться с требований к серверу из `server-setup`.

## 8. Этапы

| Этап | Содержание | Оценка |
|---|---|---|
| 0 | `examples/common`, исправление IBX-примера, README для существующих примеров | 2 дня |
| 1 | Консольные примеры S1–S3: Delphi FireDAC, Lazarus SQLdb, Java `jdbc-basic` | 4 дня |
| 2 | S6 (gbak из программы) для трёх языков; `keysource` для Linux | 3 дня |
| 3 | S4 (потоки и пул) для трёх языков | 3 дня |
| 4 | GUI Delphi (VCL), `spring-boot`, S5 и S8 | 4 дня |
| 5 | Объектно-ориентированный API (Delphi, fbintf), `jdbc-native`, ZeosLib, IBX Delphi | 4 дня |
| 6 | Сборка в CI, архивы в Releases, ссылки из руководства | 2 дня |

Этапы 0–2 закрывают самые частые вопросы поддержки. Их стоит выпустить первыми.

## 9. Проверка

Матрица: Firebird 3.0, 4.0, 5.0 и HQbird; Windows x86 и x64; Linux x64 (Lazarus, Java).

Критерии готовности примера:

1. Собирается по README на чистой машине.
2. Сценарий проходит на всех версиях Firebird из матрицы.
3. Без ключа подключение завершается ожидаемой ошибкой.
4. В коде и в истории git нет рабочих ключей.
5. На пример есть ссылка из руководства (`doc/ru`).

## 10. Открытые вопросы

1. Jaybird native: поддерживает ли текущая версия `dbCryptConfig` для JNA, и можно ли зарегистрировать обратный вызов `fbcrypt` в потоке пула. Нужна проверка до этапа 5.
2. Лицензия для CI: пробная лицензия имеет срок действия. Нужна постоянная тестовая лицензия.
3. Публиковать ли в руководстве `ClientKeygen` и `KeyChecker`. Сейчас они описаны кратко.
4. Минимальная версия Delphi для примеров (10.4 или старше).
5. Нужны ли примеры для .NET, Python и PHP в следующей очереди.
