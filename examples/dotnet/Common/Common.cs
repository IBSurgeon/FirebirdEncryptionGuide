using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

namespace FbCryptExamples;

/// <summary>
/// Helpers shared by the .NET examples.
/// The examples read the connection parameters from environment variables.
/// The script examples/common/setup.ps1 creates the file test-env.ps1 that sets them.
/// </summary>
public static class Common
{
    public static string Env(string name)
    {
        var value = Environment.GetEnvironmentVariable(name);
        if (string.IsNullOrEmpty(value))
        {
            Console.Error.WriteLine($"ERROR: environment variable {name} is not set. " +
                "Run examples/common/setup.ps1 and dot-source test-env.ps1.");
            Environment.Exit(2);
        }
        return value!;
    }

    public static string Host => Env("FBCRYPT_HOST");
    public static int Port => int.Parse(Env("FBCRYPT_PORT"), CultureInfo.InvariantCulture);
    public static string User => Env("FBCRYPT_USER");
    public static string Password => Env("FBCRYPT_PASSWORD");
    public static string ClientDir => Env("FBCRYPT_CLIENT");
    public static string WorkDir => Env("FBCRYPT_WORK");

    /// <summary>
    /// Reads keys from a file in KeyHolder.conf format: Key=&lt;name&gt; 0x..,0x..,
    /// Do not keep real keys in the source code or in appsettings.json.
    /// </summary>
    public static Dictionary<string, byte[]> ReadKeys(string? path = null)
    {
        var keys = new Dictionary<string, byte[]>();
        foreach (var line in File.ReadAllLines(path ?? Env("FBCRYPT_KEYS")))
        {
            var m = Regex.Match(line, @"^\s*Key\s*=\s*(\S+)\s+(\S+)\s*$");
            if (!m.Success)
                continue;
            var data = m.Groups[2].Value
                .Split(',', StringSplitOptions.RemoveEmptyEntries)
                .Select(part => Convert.ToByte(part, 16))
                .ToArray();
            if (data.Length is not (16 or 24 or 32))
                throw new InvalidDataException($"Key {m.Groups[1].Value} has {data.Length} bytes, need 16, 24 or 32");
            keys[m.Groups[1].Value] = data;
        }
        return keys;
    }

    /// <summary>Key value in the notation of the plugin: 0x..,0x..,</summary>
    public static string KeyText(byte[] key) =>
        string.Concat(key.Select(b => $"0x{b:x2},"));

    /// <summary>
    /// Value for the "crypt key" connection parameter: &lt;name&gt;:0x..,0x..,
    /// The server accepts it only with UnsafeClient = true in KeyHolder.conf.
    /// </summary>
    public static byte[] StaticReply(string name, byte[] key) =>
        Encoding.ASCII.GetBytes($"{name}:{KeyText(key)}");
}
