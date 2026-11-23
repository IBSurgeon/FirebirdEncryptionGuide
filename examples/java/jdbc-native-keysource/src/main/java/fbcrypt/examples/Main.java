package fbcrypt.examples;

import java.nio.file.Files;
import java.nio.file.Path;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.Statement;

/**
 * Scenarios S1 and S7: Jaybird native protocol with the client-side KeyHolder plugin and KeySource.
 *
 * Key transfer method C. The program has no code for the key:
 *
 *   - firebird.conf next to fbclient has KeyHolderPlugin = KeyHolder;
 *   - the library KeySource next to fbclient returns the keys;
 *   - the KeyHolder plugin of the client sends the key with the protected key exchange.
 *
 * The server does not need UnsafeClient = true.
 * Create the client folder with examples/common/new-keysource-client.ps1.
 */
public final class Main {

    public static void main(String[] args) throws Exception {
        String folder = System.getenv("FBCRYPT_CLIENT_KEYSOURCE");
        Path client = folder != null && !folder.isEmpty()
                ? Path.of(folder)
                : Path.of(Common.env("FBCRYPT_WORK"), "client-keysource");
        if (!Files.isDirectory(client)) {
            System.err.println("ERROR: " + client + " is not found. Run examples/common/new-keysource-client.ps1 first.");
            System.exit(2);
        }
        // Jaybird loads fbclient through JNA. Set the folder before the first connection.
        System.setProperty("jna.library.path", client.toString());

        for (String alias : new String[] {"crypt_red", "crypt_green", "plain"}) {
            // An ordinary connection: no key in the program.
            try (Connection connection = DriverManager.getConnection(
                         Common.nativeUrl(alias), Common.user(), Common.password());
                 Statement statement = connection.createStatement();
                 ResultSet rs = statement.executeQuery("select note from demo where id = 1")) {
                rs.next();
                System.out.println("S7 connect to " + alias + ": " + rs.getString(1));
            }
        }
    }
}
