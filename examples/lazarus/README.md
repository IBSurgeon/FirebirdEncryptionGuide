# Примеры для Free Pascal и Lazarus

Компоненты: SQLdb (`TIBConnection`) из состава Free Pascal. Они работают через `fbclient` (ISC API).
Ключ передаёт библиотека `fbcrypt` с защищённым обменом (способ A). Параметр `UnsafeClient = true` на сервере не нужен.

## Что нужно

- Lazarus 4.x или Free Pascal 3.2.2 (проверено с Lazarus 4.8, FPC 3.2.2, цель `x86_64-win64`).
- Команда `fpc` в `PATH`. В Lazarus для Windows компилятор находится в каталоге `fpc\3.2.2\bin\x86_64-win64`.
- Тестовый сервер: см. [../common/README.md](../common/README.md). Перед запуском загрузите `test-env.ps1`.

Разрядность программы должна совпадать с разрядностью `fbclient` и `fbcrypt`.

## Примеры

| Каталог | Что показывает |
|---|---|
| [console-sqldb](console-sqldb) | Подключение с ключом через SQLdb. Один ключ, два ключа, замена ключей, ошибки. |
| [gbak-stdin](gbak-stdin) | Запуск `gbak` из программы (`TProcess`). Ключ передаётся в стандартный ввод процесса. |
| [threads-sqldb](threads-sqldb) | Потоки: каждый поток вызывает `RegisterForThread`. Поток без вызова получает ошибку. |

Сборка и запуск:

```powershell
cd console-sqldb
```

```powershell
fpc -Fu..\common -FUlib -oconsole_sqldb.exe console_sqldb.lpr
```

```powershell
.\console_sqldb.exe
```

Перед сборкой создайте каталог `lib`. Проверка: `.\run-test.ps1` в каталоге примера (скрипт сам создаёт `lib` и собирает программу).

В Lazarus откройте файл `.lpr` и добавьте каталог `..\common` в пути модулей проекта.

## Общие модули

| Файл | Назначение |
|---|---|
| `common/fbcryptapi.pas` | Класс `TFbCrypt`: загрузка `fbcrypt`, список ключей, регистрация обратного вызова. |
| `common/examplecommon.pas` | Переменные окружения, чтение файла ключей, запись ключа `0x..,0x..,`. |

## Правила работы с fbcrypt

1. Компоненты доступа и `fbcrypt` должны использовать один `fbclient`. Пример задаёт путь через `TSQLDBLibraryLoader` и передаёт тот же каталог в `TFbCrypt.Create`.
2. Вызывайте `TFbCrypt.RegisterForThread` в том потоке, который открывает подключение, перед `Connection.Open`.
3. Список ключей общий для процесса. `ClearKeys` удаляет все ключи.
4. Для кода на объектно-ориентированном API (`fbintf`) используйте `RegisterForProvider`.

Класс `TFbCrypt` сначала загружает `libcrypto` по полному пути. Библиотека `fbcrypt` ищет её по имени, и без этого шага Windows может её не найти.

## gbak и версия Firebird

- Firebird 4.0 и 5.0: `gbak -KeyHolder KeyHolderStdin`, ключ в стандартном вводе.
- Firebird 3.0: пример создаёт временный файл ключа и вызывает `gbak -KEYFILE`. Этот вариант на сервере 3.0 не проверен.

## Существующий пример с IBX

Графический пример находится в каталоге [../app/Example_ForLazarus_IBX](../app/Example_ForLazarus_IBX).
В модуле `dbcrypthelper.pas` исправлены опечатка `cdelc` и имя библиотеки для Linux (`libfbcrypt.so`).

Готовая программа для Windows x64: [AppLazarus-IBX-x86_64-win64.zip](https://github.com/IBSurgeon/FirebirdEncryptionGuide/releases/latest/download/AppLazarus-IBX-x86_64-win64.zip).

Сборка из исходных текстов:

1. Установите в Lazarus пакет `IBX4Lazarus` (вместе с ним `FBIntf` и `IBControls`). Это можно сделать через Online Package Manager.
2. Соберите проект:

```
lazbuild --build-mode=Release FbCryptExample.lpi
```

Программа появится в каталоге `bin\x86_64-win64\Release`.

Проверено 24.11.2026: Lazarus 4.8, FPC 3.2.2, IBX из Online Package Manager, Windows x64, Firebird 5.0. Программа открыла зашифрованную копию базы `employee` с ключом `Red` и показала таблицу `EMPLOYEE`. Кнопки шифрования, расшифровки и `gstat -h` в этой сборке не проверялись.

## Что не сделано

- Сборка и проверка на Linux.
- Примеры `console-fbintf` и `console-zeos` из плана.
