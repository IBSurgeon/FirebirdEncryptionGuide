# Примеры для Java

Драйвер: [Jaybird](https://firebirdsql.org/en/jdbc-driver/) 6 (проверено с версией 6.0.7).

Jaybird имеет два протокола:

- **Чистый Java-протокол** (`jdbc:firebird://...`). Драйвер отправляет ключ статическим значением из свойства `dbCryptConfig` (способ D). Сервер должен иметь `UnsafeClient = true` и `WireCrypt = Required`. См. [../common/server-unsafe-client.md](../common/server-unsafe-client.md).
- **Протокол native** (`jdbc:firebird:native://...`). Драйвер работает через `fbclient`. Свойство `dbCryptConfig` здесь не действует. Ключ передаёт клиентская библиотека с защищённым обменом (способы C и E).

## Что нужно

- JDK 17 или новее, Maven 3.9. Переменная `JAVA_HOME` и команда `mvn` в `PATH`.
- Тестовый сервер: см. [../common/README.md](../common/README.md). Перед запуском загрузите `test-env.ps1`.

## Примеры

| Каталог | Протокол | Способ | Что показывает |
|---|---|---|---|
| [jdbc-basic](jdbc-basic) | Java | D | `dbCryptConfig`: текст, `base64:`, `base64url:` в URL. Ошибки ключа. |
| [jdbc-native-fbcrypt](jdbc-native-fbcrypt) | native | E | Библиотека `fbcrypt` через JNA. Один ключ, два ключа, замена ключей, ошибки. |
| [jdbc-native-keysource](jdbc-native-keysource) | native | C | В программе нет кода для ключа. Ключи отдаёт библиотека `KeySource`. |
| [gbak-stdin](gbak-stdin) | — | — | Запуск `gbak` из программы. Ключ передаётся в стандартный ввод процесса. |

Сборка всех примеров (один раз, в каталоге `java`):

```powershell
mvn -q -DskipTests install
```

Запуск одного примера:

```powershell
mvn -q -pl jdbc-basic exec:java
```

Проверка: `.\run-test.ps1` в каталоге примера.

## Свойство dbCryptConfig (способ D)

Значение — строка `<имя>:0x..,0x..,`.

| Вид значения | Где использовать |
|---|---|
| текст как есть | `Properties`, свойства `DataSource` |
| `base64:<значение>` | `Properties`, свойства `DataSource` |
| `base64url:<значение>` | URL подключения. Обычный base64 содержит `+` и `/`, в URL их нужно экранировать. |

Всегда задавайте `wireCrypt=REQUIRED`. Тогда драйвер не подключится без шифрования протокола.

Для пула (HikariCP и другие) задайте `dbCryptConfig` в свойствах источника данных. Вызовы в потоках не нужны.

## Протокол native и fbcrypt (способ E)

Класс `FbCrypt` в примере `jdbc-native-fbcrypt` загружает `fbcrypt` через JNA.

Правила:

- Вызывайте `registerForThread()` в том потоке, который открывает подключение, перед `DriverManager.getConnection`.
- Jaybird и `fbcrypt` должны использовать один `fbclient`. Пример задаёт `jna.library.path` до первого подключения.
- Для пула подключений нужна обёртка `DataSource`, которая вызывает `registerForThread()` перед `getConnection`. Пул сам создаёт подключения в своих потоках.
- Не используйте виртуальные потоки: виртуальный поток может перейти на другой поток ОС.
- Пример проверен на 64-битной JVM в Windows. Для 32-битной JVM в Windows нужен `StdCallLibrary`.

## Протокол native и KeySource (способ C)

1. Соберите библиотеку `KeySource` (см. [../keysource](../keysource)).
2. Создайте клиентский каталог: `..\common\new-keysource-client.ps1 -KeySourceDll <файл>`.
3. Задайте `jna.library.path` на этот каталог.

## gbak и версия Firebird

- Firebird 4.0 и 5.0: `gbak -KeyHolder KeyHolderStdin`, ключ в стандартном вводе.
- Firebird 3.0: пример создаёт временный файл ключа и вызывает `gbak -KEYFILE`. Этот вариант на сервере 3.0 не проверен.

## Что не сделано

Примеры `jdbc-datasource` (пул), `spring-boot` и `services-backup` из плана пока не написаны.
