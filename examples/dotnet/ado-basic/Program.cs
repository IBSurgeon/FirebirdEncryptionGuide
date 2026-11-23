// Scenarios S1 and S2: connect to an encrypted database with the Firebird .NET provider.
//
// Key transfer method D: the provider sends the key as a static value.
// The server must have UnsafeClient = true in plugins/KeyHolder.conf and WireCrypt = Required.
//
// Standard output is the same on each run (see expected-output.txt).
// Full error texts go to standard error.

using FbCryptExamples;
using FirebirdSql.Data.FirebirdClient;

var keys = Common.ReadKeys();

// S1: the key in a property of the connection string builder
var red = Common.StaticReply("Red", keys["Red"]);
Console.WriteLine("S1 connect with key Red (builder): " + QueryNote(BuildConnectionString("crypt_red", red)));

// S1: the key as text in the connection string. The value is base64 of "<name>:0x..,0x..,"
var green = Common.StaticReply("Green", keys["Green"]);
var text = BuildConnectionString("crypt_green", null) + ";crypt key=" + Convert.ToBase64String(green);
Console.WriteLine("S1 connect with key Green (text): " + QueryNote(text));

// S2: errors
ExpectError("S2 no key", BuildConnectionString("crypt_red", null));
ExpectError("S2 wrong key value", BuildConnectionString("crypt_red", Common.StaticReply("Red", keys["Green"])));
ExpectError("S2 wrong key name", BuildConnectionString("crypt_red", Common.StaticReply("Blue", keys["Red"])));

// A database that is not encrypted needs no key.
Console.WriteLine("Plain database without a key: " + QueryNote(BuildConnectionString("plain", null)));

static string BuildConnectionString(string alias, byte[]? cryptKey)
{
    var builder = new FbConnectionStringBuilder
    {
        DataSource = Common.Host,
        Port = Common.Port,
        Database = alias,
        UserID = Common.User,
        Password = Common.Password,
        // The key is sent as a static value. Never allow a connection without wire encryption.
        WireCrypt = FbWireCrypt.Required,
        // Each scenario must open a new connection, so the pool is off in this example.
        Pooling = false,
    };
    if (cryptKey != null)
        builder.CryptKey = cryptKey;
    return builder.ToString();
}

static string QueryNote(string connectionString)
{
    using var connection = new FbConnection(connectionString);
    connection.Open();
    using var command = new FbCommand("select note from demo where id = 1", connection);
    return (string)command.ExecuteScalar()!;
}

static void ExpectError(string title, string connectionString)
{
    try
    {
        QueryNote(connectionString);
        Console.WriteLine($"{title}: NO ERROR - this is wrong");
    }
    catch (FbException e)
    {
        Console.WriteLine($"{title}: error, as expected");
        Console.Error.WriteLine($"--- {title}\n{e.Message}\n");
    }
}
