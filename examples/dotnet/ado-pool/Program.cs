// Scenario S4: the connection pool of the Firebird .NET provider and parallel tasks.
//
// Key transfer method D: the key is a part of the connection string.
// The provider keeps a separate pool for each connection string, so each database
// gets its own pool with its own key. No call depends on the thread.
//
// The server must have UnsafeClient = true in plugins/KeyHolder.conf and WireCrypt = Required.

using FbCryptExamples;
using FirebirdSql.Data.FirebirdClient;

const int Tasks = 8;
const int MaxPoolSize = 4;
var keys = Common.ReadKeys();

foreach (var (alias, keyName) in new[] { ("crypt_red", "Red"), ("crypt_green", "Green") })
{
    var connectionString = new FbConnectionStringBuilder
    {
        DataSource = Common.Host,
        Port = Common.Port,
        Database = alias,
        UserID = Common.User,
        Password = Common.Password,
        WireCrypt = FbWireCrypt.Required,
        Pooling = true,
        MaxPoolSize = MaxPoolSize,
        CryptKey = Common.StaticReply(keyName, keys[keyName]),
    }.ToString();

    // The pool of the provider does not wait for a free connection: it throws
    // "Connection pool is full". So the program limits the number of open connections.
    using var limit = new SemaphoreSlim(MaxPoolSize);

    var tasks = Enumerable.Range(0, Tasks).Select(_ => Task.Run(async () =>
    {
        await limit.WaitAsync();
        try
        {
            // "await" can continue in another thread. This is safe for method D.
            await using var connection = new FbConnection(connectionString);
            await connection.OpenAsync();
            await using var command = new FbCommand("select note from demo where id = 1", connection);
            return (string)(await command.ExecuteScalarAsync())!;
        }
        finally
        {
            limit.Release();
        }
    })).ToArray();

    var answers = await Task.WhenAll(tasks);
    var correct = answers.Count(answer => answer == $"Hello from {alias}");
    Console.WriteLine($"Pool for {alias}: {Tasks} tasks, {correct} correct answers");
}

FbConnection.ClearAllPools();
