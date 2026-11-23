# Примеры для .NET

Провайдер: [`FirebirdSql.Data.FirebirdClient`](https://www.nuget.org/packages/FirebirdSql.Data.FirebirdClient) (проверено с версией 10.3.4).

Провайдер реализует сетевой протокол Firebird сам и отправляет ключ статическим значением (способ D).
Сервер должен иметь `UnsafeClient = true` и `WireCrypt = Required`. См. [../common/server-unsafe-client.md](../common/server-unsafe-client.md).

## Что нужно

- .NET SDK 8 или новее. Проекты собираются для `net8.0` и запускаются на более новой среде выполнения.
- Тестовый сервер: см. [../common/README.md](../common/README.md). Перед запуском загрузите `test-env.ps1`.

## Примеры

| Каталог | Что показывает |
|---|---|
| [ado-basic](ado-basic) | Подключение с ключом через `FbConnectionStringBuilder.CryptKey` и через текст строки подключения. Ошибки ключа. |
| [gbak-stdin](gbak-stdin) | Запуск `gbak` из программы. Ключ передаётся в стандартный ввод процесса. |

Запуск:

```powershell
dotnet run -c Release --project ado-basic
```

Проверка:

```powershell
.\ado-basic\run-test.ps1
```

## Параметр crypt key

Значение параметра — это байты строки `<имя>:0x..,0x..,`.

| Способ задания | Вид значения |
|---|---|
| `FbConnectionStringBuilder.CryptKey` | массив байтов (`byte[]`) |
| текст строки подключения, `crypt key=...` или `cryptkey=...` | base64 от тех же байтов |

Код, который строит значение, находится в `Common/Common.cs` (`StaticReply`).

Всегда задавайте `WireCrypt = FbWireCrypt.Required`. Тогда провайдер не подключится без шифрования протокола.

## Пул подключений

Ключ входит в строку подключения. Пул провайдера (`Pooling=true`) создаёт отдельный набор подключений для каждой строки. Вызовы в потоках не нужны.

## gbak и версия Firebird

- Firebird 4.0 и 5.0: `gbak -KeyHolder KeyHolderStdin`, ключ в стандартном вводе.
- Firebird 3.0: переключателя `-KeyHolder` нет. Пример создаёт временный файл ключа и вызывает `gbak -KEYFILE`. Этот вариант написан по исходным кодам и на сервере 3.0 не проверен.

Ключ записывается в `StandardInput.BaseStream` как байты ASCII. Класс `StreamWriter` может добавить перед ключом метку порядка байтов.

## Режим Embedded и fbcrypt

Способ с `ServerType=Embedded` и библиотекой `fbcrypt` не работает с провайдером 10.3.4:

- в этом режиме провайдер не передаёт пароль в параметрах подключения;
- подключение к удалённому серверу завершается ошибкой `unavailable database`.

Для защищённого обмена ключом в .NET сейчас готового способа нет.
