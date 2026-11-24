# Библиотека KeyChecker

Плагин `KeyHolder` при запуске ищет библиотеку с именем `KeyChecker` и вызывает её функцию `CheckKey` для ключей, которые он загрузил.
Описание: руководство, раздел «Библиотека KeyChecker».

```cpp
void CheckKey(const char* keyName, const char* exeName, unsigned keyLen, void* keyValue);
```

Функция ничего не возвращает и не может отклонить ключ. Она может записать сведения о ключе в свой журнал или изменить значение ключа на месте.

## Примеры

| Каталог | Язык | Сборка |
|---|---|---|
| [cpp](cpp) | C++ | Windows: `cl /LD /EHsc /O2 KeyChecker.cpp /Fe:KeyChecker.dll`; Linux: `g++ -shared -fPIC -O2 -o libKeyChecker.so KeyChecker.cpp` |
| [lazarus](lazarus) | Free Pascal | `fpc KeyChecker.lpr` |

Оба примера записывают одну строку для каждого ключа в файл из переменной окружения `FBCRYPT_KEYCHECKER_LOG`:

```
2026-11-24 09:49:13 key=Red length=32 program=C:\app\gbak.exe
```

Значение ключа примеры не записывают. Если переменная не задана, примеры ничего не делают.

## Куда положить библиотеку

| Система | Место | Имя файла |
|---|---|---|
| Windows, сервер | рядом с `firebird.exe` | `KeyChecker.dll` |
| Windows, клиент | рядом с `fbclient.dll` | `KeyChecker.dll` |
| Linux | каталог `lib` | `libKeyChecker.so` |

Разрядность библиотеки должна совпадать с разрядностью Firebird. После замены библиотеки на сервере перезапустите Firebird.

## Когда вызывается CheckKey

| Где работает плагин | Откуда получен ключ | Вызов |
|---|---|---|
| Сервер, `KeyHolder` | `KeyHolder.conf` или `KeySource` | да |
| Сервер, `KeyHolder` | статическое значение от клиента (`UnsafeClient = true`) | да |
| Сервер, `KeyHolder` | защищённый обмен ключом (`fbcrypt`, клиентский `KeyHolder`, `KeyHolderStdin`) | нет |
| Клиент, `KeyHolder` | `KeyHolder.conf` или `KeySource` на клиенте | да, для каждого ключа при каждом подключении |
| Утилита, `KeyHolderStdin` | входной поток | да |
| Приложение, `fbcrypt` | `fbcrypt_key` | нет |

## Как проверить

1. Соберите библиотеку.
2. Положите её рядом с `fbclient.dll` в каталоге `client-keysource` тестового окружения (см. [../common/README.md](../common/README.md)).
3. Задайте переменную и запустите пример с `KeySource`:

```powershell
$env:FBCRYPT_KEYCHECKER_LOG = "$env:TEMP\keychecker.log"
```

```powershell
python ..\python\driver-keysource\main.py
```

4. Откройте файл журнала. В нём по одной строке для каждого ключа библиотеки `KeySource` на каждое подключение.

Так проверены обе библиотеки на Firebird 5.0 (Windows x64). Библиотека на C++ проверена также на сервере и с утилитой `gbak`. Автоматического теста нет: для него нужен компилятор.
