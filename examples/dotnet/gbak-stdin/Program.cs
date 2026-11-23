// Scenario S6: encrypted backup and restore from a program.
//
// Firebird 4.0 and 5.0: gbak -KeyHolder KeyHolderStdin, the key goes to the standard input of gbak.
// Firebird 3.0: gbak has no -KeyHolder switch. The program writes the key to a temporary file
// in the profile of the current user and runs gbak -KEYFILE.
//
// The key is never put on the command line: other users can see the command line.

using System.Diagnostics;
using System.Text;
using FbCryptExamples;

const string KeyName = "Red";
var marker = Encoding.ASCII.GetBytes("Hello from crypt_red");

var fbMajor = int.Parse(Environment.GetEnvironmentVariable("FBCRYPT_FB_MAJOR") ?? "5");
var key = Common.ReadKeys()[KeyName];
var gbak = Path.Combine(Common.ClientDir, OperatingSystem.IsWindows() ? "gbak.exe" : "bin/gbak");
var backupFile = Path.Combine(Common.WorkDir, "tmp", "dotnet-crypt_red.fbk");
var restoredDb = Path.Combine(Common.WorkDir, "db", "dotnet-restored.fdb");
var server = $"{Common.Host}/{Common.Port}:";

try
{
    // 1. Backup without a key must fail: the database is encrypted.
    Report("Backup without a key", RunGbak(["-b", server + "crypt_red", backupFile], null), mustFail: true);

    // 2. Backup with the key. The backup file is encrypted too.
    if (!Report("Backup with the key", GbakWithKey(["-b", server + "crypt_red", backupFile])))
        return 1;
    var encrypted = File.ReadAllBytes(backupFile).AsSpan().IndexOf(marker) < 0;
    Console.WriteLine("Backup file is encrypted: " + (encrypted ? "yes" : "NO - this is wrong"));

    // 3. Restore without a key must fail: gbak cannot read the encrypted backup file.
    Report("Restore without a key", RunGbak(["-rep", backupFile, server + restoredDb], null), mustFail: true);

    // 4. Restore with the key. gbak encrypts the new database with the same key.
    Report("Restore with the key", GbakWithKey(["-rep", backupFile, server + restoredDb]));
    return 0;
}
finally
{
    File.Delete(backupFile);
    File.Delete(restoredDb);
}

(int ExitCode, string Errors) GbakWithKey(string[] args)
{
    var keyLine = $"Key={KeyName} {Common.KeyText(key)}";
    if (fbMajor >= 4)
        return RunGbak([.. args, "-keyholder", "KeyHolderStdin"], keyLine);

    // Firebird 3.0: a temporary key file in the profile of the current user.
    var keyFile = Path.Combine(Path.GetTempPath(), $"fbkey-{Guid.NewGuid():N}.conf");
    try
    {
        File.WriteAllText(keyFile, keyLine + "\n", Encoding.ASCII);
        if (!OperatingSystem.IsWindows())
            File.SetUnixFileMode(keyFile, UnixFileMode.UserRead | UnixFileMode.UserWrite);
        return RunGbak([.. args, "-keyfile", keyFile, "-keyname", KeyName], null);
    }
    finally
    {
        File.Delete(keyFile);
    }
}

// Runs gbak. The line with the key goes to the standard input of the process.
(int ExitCode, string Errors) RunGbak(string[] args, string? keyLine)
{
    var info = new ProcessStartInfo(gbak)
    {
        UseShellExecute = false,
        RedirectStandardInput = true,
        RedirectStandardOutput = true,
        RedirectStandardError = true,
    };
    info.ArgumentList.Add("-user");
    info.ArgumentList.Add(Common.User);
    info.ArgumentList.Add("-password");
    info.ArgumentList.Add(Common.Password);
    foreach (var arg in args)
        info.ArgumentList.Add(arg);

    using var process = Process.Start(info)!;
    // Write bytes to the base stream: a StreamWriter can add a byte order mark before the key.
    if (keyLine != null)
        process.StandardInput.BaseStream.Write(Encoding.ASCII.GetBytes(keyLine));
    process.StandardInput.Close();

    var errors = process.StandardError.ReadToEnd();
    process.StandardOutput.ReadToEnd();
    process.WaitForExit();
    return (process.ExitCode, errors);
}

bool Report(string title, (int ExitCode, string Errors) result, bool mustFail = false)
{
    var failed = result.ExitCode != 0;
    if (failed == mustFail)
        Console.WriteLine($"{title}: {(mustFail ? "error, as expected" : "OK")}");
    else
        Console.WriteLine($"{title}: {(mustFail ? "NO ERROR - this is wrong" : "FAILED")}");
    if (failed)
        Console.Error.WriteLine($"--- {title}\n{result.Errors}");
    return failed == mustFail;
}
