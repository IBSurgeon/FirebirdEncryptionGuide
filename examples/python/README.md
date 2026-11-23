# Примеры для Python

Драйвер: [`firebird-driver`](https://pypi.org/project/firebird-driver/). Он работает через `fbclient` и объектно-ориентированный API Firebird.

## Что нужно

- Python 3.11 или новее.
- Пакет `firebird-driver` (проверено с версией 2.0.3):

```powershell
python -m pip install firebird-driver
```

- Тестовый сервер: см. [../common/README.md](../common/README.md). Перед запуском загрузите `test-env.ps1`.

## Примеры

| Каталог | Способ | Что показывает |
|---|---|---|
| [driver-fbcrypt](driver-fbcrypt) | B | Библиотека `fbcrypt` через `ctypes`. Защищённый обмен ключом. Один ключ, два ключа, замена ключей, ошибки. |
| [driver-keysource](driver-keysource) | C | В программе нет кода для ключа. Ключи отдаёт библиотека `KeySource`. |
| [driver-callback](driver-callback) | D | Свой класс обратного вызова отправляет ключ статическим значением. Нужен `UnsafeClient = true`. |
| [gbak-stdin](gbak-stdin) | — | Запуск `gbak` из программы. Ключ передаётся в стандартный ввод процесса. |

Запуск одного примера:

```powershell
python driver-fbcrypt\main.py
```

Проверка примера:

```powershell
.\driver-fbcrypt\run-test.ps1
```

Тексты ошибок сервера пример пишет в стандартный поток ошибок.

## Какой способ выбрать

- **B (`driver-fbcrypt`)** — если приложение само получает ключ (от пользователя, из хранилища секретов).
- **C (`driver-keysource`)** — если код приложения менять нельзя.
- **D (`driver-callback`)** — только если нельзя установить `fbcrypt` на клиенте. См. [../common/server-unsafe-client.md](../common/server-unsafe-client.md).

## Общие модули

| Файл | Назначение |
|---|---|
| `fbcrypt_common.py` | Переменные окружения, чтение файла ключей, запись ключа `0x..,0x..,`. |
| `fbcrypt_api.py` | Обёртка `fbcrypt` для `ctypes` и подключение её к `firebird-driver`. |

## Особенности firebird-driver

- **`fbcrypt_callback(nil)` не работает.** Драйвер использует объектно-ориентированный API. Нужен вызов `fbcrypt_callback(provider)`. Драйвер создаёт `IProvider` внутри `connect`, поэтому `fbcrypt_api.install_firebird_driver_hook()` заменяет метод `iProvider.set_dbcrypt_callback`.
- **Ошибка в классе `iCryptKeyCallbackImpl` (версия 2.0.3).** Встроенная функция обратного вызова завершается с `TypeError`, и подключение аварийно прерывается. Пример `driver-callback` устанавливает свою функцию в таблицу интерфейса.
- **Параметр `keyhoder`.** В методах `backup` и `restore` сервисов параметр назван с опечаткой: `keyhoder`.

## gbak и версия Firebird

- Firebird 4.0 и 5.0: `gbak -KeyHolder KeyHolderStdin`, ключ в стандартном вводе.
- Firebird 3.0: переключателя `-KeyHolder` нет. Пример создаёт временный файл ключа и вызывает `gbak -KEYFILE`. Этот вариант написан по исходным кодам и на сервере 3.0 не проверен.

Версию задаёт переменная `FBCRYPT_FB_MAJOR`.

## Другие драйверы

- `fdb` (устарел): параметра для ключа нет. Не проверялся.
- `firebirdsql` (чистый Python): поддержки ключа шифрования в исходных кодах не найдено. Не проверялся.
