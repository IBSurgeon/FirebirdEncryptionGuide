package fbcrypt.examples;

import java.nio.file.Path;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.Map;

/**
 * Scenarios S1, S2 and S3: Jaybird native protocol with the fbcrypt library.
 *
 * Key transfer method E: Jaybird works through fbclient (ISC API), and fbcrypt registers
 * the key callback for the current thread. The key exchange is protected.
 * The server does not need UnsafeClient = true.
 *
 * Standard output is the same on each run (see expected-output.txt).
 * Full error texts go to standard error.
 */
public final class Main {

    private static FbCrypt fbcrypt;

    public static void main(String[] args) throws Exception {
        fbcrypt = new FbCrypt(Path.of(Common.env("FBCRYPT_CLIENT")));
        Map<String, byte[]> keys = Common.readKeys();

        // S1: one key
        fbcrypt.addKey("Red", keys.get("Red"));
        System.out.println("S1 connect with key Red: " + queryNote("crypt_red"));

        // S3: two keys in the list, two databases
        fbcrypt.addKey("Green", keys.get("Green"));
        System.out.println("S3 two keys, database crypt_red: " + queryNote("crypt_red"));
        System.out.println("S3 two keys, database crypt_green: " + queryNote("crypt_green"));

        // S2: errors. clearKeys() removes all keys from the list.
        fbcrypt.clearKeys();
        expectError("S2 no key", "crypt_red");
        fbcrypt.addKey("Red", keys.get("Green"));
        expectError("S2 wrong key value", "crypt_red");
        fbcrypt.clearKeys();
        fbcrypt.addKey("Blue", keys.get("Red"));
        expectError("S2 wrong key name", "crypt_red");

        // Back to the right key
        fbcrypt.clearKeys();
        fbcrypt.addKey("Red", keys.get("Red"));
        System.out.println("S1 connect again with key Red: " + queryNote("crypt_red"));
    }

    private static String queryNote(String alias) throws SQLException {
        // The callback must be registered in the thread that opens the connection.
        fbcrypt.registerForThread();
        try (Connection connection = DriverManager.getConnection(
                     Common.nativeUrl(alias), Common.user(), Common.password());
             Statement statement = connection.createStatement();
             ResultSet rs = statement.executeQuery("select note from demo where id = 1")) {
            rs.next();
            return rs.getString(1);
        }
    }

    private static void expectError(String title, String alias) {
        try {
            queryNote(alias);
            System.out.println(title + ": NO ERROR - this is wrong");
        } catch (SQLException e) {
            System.out.println(title + ": error, as expected");
            System.err.println("--- " + title + "\n" + e.getMessage() + "\n");
        }
    }
}
