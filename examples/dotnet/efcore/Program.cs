// Scenarios S1 and S8: Entity Framework Core with an encrypted database.
//
// Key transfer method D: the key is a part of the connection string.
// The key is NOT in the source code and NOT in appsettings.json. The program takes it
// from the environment variable FBCRYPT_DB_KEY. Other safe places:
//   * development: "dotnet user-secrets";
//   * Windows service: a file protected with DPAPI (ProtectedData);
//   * containers: Docker or Kubernetes secrets.
// Format of the value: <name>:0x..,0x..,
//
// The server must have UnsafeClient = true in plugins/KeyHolder.conf and WireCrypt = Required.

using System.ComponentModel.DataAnnotations.Schema;
using System.Text;
using FbCryptExamples;
using FirebirdSql.Data.FirebirdClient;
using Microsoft.EntityFrameworkCore;

var connectionString = new FbConnectionStringBuilder
{
    DataSource = Common.Host,
    Port = Common.Port,
    Database = "crypt_red",
    UserID = Common.User,
    Password = Common.Password,
    WireCrypt = FbWireCrypt.Required,
    CryptKey = Encoding.ASCII.GetBytes(Common.Env("FBCRYPT_DB_KEY")),
}.ToString();

using (var db = new DemoContext(connectionString))
{
    var row = db.Demo.Single(d => d.Id == 1);
    Console.WriteLine("S1 EF Core, key from the environment: " + row.Note);
    Console.WriteLine("Rows in the table: " + db.Demo.Count());
}
FbConnection.ClearAllPools();

[Table("DEMO")]
public class DemoRow
{
    [Column("ID")]
    public int Id { get; set; }

    [Column("NOTE")]
    public string? Note { get; set; }
}

public class DemoContext(string connectionString) : DbContext
{
    public DbSet<DemoRow> Demo => Set<DemoRow>();

    protected override void OnConfiguring(DbContextOptionsBuilder options) =>
        options.UseFirebird(connectionString);
}
