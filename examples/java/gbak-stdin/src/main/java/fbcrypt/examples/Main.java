package fbcrypt.examples;

import java.io.IOException;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

/**
 * Scenario S6: encrypted backup and restore from a program.
 *
 * Firebird 4.0 and 5.0: gbak -KeyHolder KeyHolderStdin, the key goes to the standard input of gbak.
 * Firebird 3.0: gbak has no -KeyHolder switch. The program writes the key to a temporary file
 * in the profile of the current user and runs gbak -KEYFILE.
 *
 * The key is never put on the command line: other users can see the command line.
 */
public final class Main {

    private static final String KEY_NAME = "Red";

    private record Result(int exitCode, String errors) {
    }

    private static int fbMajor;
    private static byte[] key;

    public static void main(String[] args) throws Exception {
        String major = System.getenv("FBCRYPT_FB_MAJOR");
        fbMajor = major == null || major.isEmpty() ? 5 : Integer.parseInt(major);
        key = Common.readKeys().get(KEY_NAME);

        Path work = Path.of(Common.env("FBCRYPT_WORK"));
        String backupFile = work.resolve("tmp").resolve("java-crypt_red.fbk").toString();
        String restoredDb = work.resolve("db").resolve("java-restored.fdb").toString();
        String server = Common.env("FBCRYPT_HOST") + "/" + Common.env("FBCRYPT_PORT") + ":";

        try {
            // 1. Backup without a key must fail: the database is encrypted.
            report("Backup without a key", runGbak(List.of("-b", server + "crypt_red", backupFile), null), true);

            // 2. Backup with the key. The backup file is encrypted too.
            if (!report("Backup with the key", gbakWithKey(List.of("-b", server + "crypt_red", backupFile)), false)) {
                System.exit(1);
            }
            String content = new String(Files.readAllBytes(Path.of(backupFile)), StandardCharsets.ISO_8859_1);
            System.out.println("Backup file is encrypted: "
                    + (content.contains("Hello from crypt_red") ? "NO - this is wrong" : "yes"));

            // 3. Restore without a key must fail: gbak cannot read the encrypted backup file.
            report("Restore without a key", runGbak(List.of("-rep", backupFile, server + restoredDb), null), true);

            // 4. Restore with the key. gbak encrypts the new database with the same key.
            report("Restore with the key", gbakWithKey(List.of("-rep", backupFile, server + restoredDb)), false);
        } finally {
            Files.deleteIfExists(Path.of(backupFile));
            Files.deleteIfExists(Path.of(restoredDb));
        }
    }

    private static Result gbakWithKey(List<String> args) throws IOException, InterruptedException {
        String keyLine = "Key=" + KEY_NAME + " " + Common.keyText(key);
        List<String> all = new ArrayList<>(args);
        if (fbMajor >= 4) {
            all.addAll(List.of("-keyholder", "KeyHolderStdin"));
            return runGbak(all, keyLine);
        }

        // Firebird 3.0: a temporary key file in the profile of the current user.
        Path keyFile = Files.createTempFile("fbkey-", ".conf");
        try {
            Files.writeString(keyFile, keyLine + "\n", StandardCharsets.US_ASCII);
            all.addAll(List.of("-keyfile", keyFile.toString(), "-keyname", KEY_NAME));
            return runGbak(all, null);
        } finally {
            Files.deleteIfExists(keyFile);
        }
    }

    /** Runs gbak. The line with the key goes to the standard input of the process. */
    private static Result runGbak(List<String> args, String keyLine) throws IOException, InterruptedException {
        boolean windows = System.getProperty("os.name").startsWith("Windows");
        Path gbak = Path.of(Common.env("FBCRYPT_CLIENT"), windows ? "gbak.exe" : "bin/gbak");

        List<String> command = new ArrayList<>(Arrays.asList(
                gbak.toString(), "-user", Common.user(), "-password", Common.password()));
        command.addAll(args);

        ProcessBuilder builder = new ProcessBuilder(command);
        builder.redirectOutput(ProcessBuilder.Redirect.DISCARD);
        Process process = builder.start();
        try (OutputStream stdin = process.getOutputStream()) {
            if (keyLine != null) {
                stdin.write(keyLine.getBytes(StandardCharsets.US_ASCII));
            }
        }
        String errors = new String(process.getErrorStream().readAllBytes(), StandardCharsets.UTF_8);
        return new Result(process.waitFor(), errors);
    }

    private static boolean report(String title, Result result, boolean mustFail) {
        boolean failed = result.exitCode() != 0;
        if (failed == mustFail) {
            System.out.println(title + ": " + (mustFail ? "error, as expected" : "OK"));
        } else {
            System.out.println(title + ": " + (mustFail ? "NO ERROR - this is wrong" : "FAILED"));
        }
        if (failed) {
            System.err.println("--- " + title + "\n" + result.errors());
        }
        return failed == mustFail;
    }
}
