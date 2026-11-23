package fbcrypt.examples;

import java.nio.charset.StandardCharsets;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.Base64;
import java.util.Map;
import java.util.Properties;

/**
 * Scenarios S1 and S2: connect to an encrypted database with Jaybird (pure Java protocol).
 *
 * Key transfer method D: the driver sends the key as a static value.
 * The server must have UnsafeClient = true in plugins/KeyHolder.conf and WireCrypt = Required.
 *
 * Standard output is the same on each run (see expected-output.txt).
 * Full error texts go to standard error.
 */
public final class Main {

    public static void main(String[] args) throws Exception {
        Map<String, byte[]> keys = Common.readKeys();
        String red = Common.staticReply("Red", keys.get("Red"));
        String green = Common.staticReply("Green", keys.get("Green"));

        // S1, form 1: the value as text in a connection property
        System.out.println("S1 key Red, text property: " + queryNote(Common.url("crypt_red"), properties(red)));

        // S1, form 2: base64 in a connection property
        String base64 = "base64:" + Base64.getEncoder().encodeToString(green.getBytes(StandardCharsets.US_ASCII));
        System.out.println("S1 key Green, base64 property: " + queryNote(Common.url("crypt_green"), properties(base64)));

        // S1, form 3: the value in the URL. Use base64url: plain base64 can have '+' and '/'.
        String base64url = "base64url:" + Base64.getUrlEncoder().withoutPadding()
                .encodeToString(red.getBytes(StandardCharsets.US_ASCII));
        String url = Common.url("crypt_red") + "?wireCrypt=REQUIRED&dbCryptConfig=" + base64url;
        System.out.println("S1 key Red, base64url in the URL: " + queryNote(url, properties(null)));

        // S2: errors
        expectError("S2 no key", Common.url("crypt_red"), properties(null));
        expectError("S2 wrong key value", Common.url("crypt_red"),
                properties(Common.staticReply("Red", keys.get("Green"))));
        expectError("S2 wrong key name", Common.url("crypt_red"),
                properties(Common.staticReply("Blue", keys.get("Red"))));

        // A database that is not encrypted needs no key.
        System.out.println("Plain database without a key: " + queryNote(Common.url("plain"), properties(null)));
    }

    private static Properties properties(String dbCryptConfig) {
        Properties props = new Properties();
        props.setProperty("user", Common.user());
        props.setProperty("password", Common.password());
        // The key is sent as a static value. Never allow a connection without wire encryption.
        props.setProperty("wireCrypt", "REQUIRED");
        if (dbCryptConfig != null) {
            props.setProperty("dbCryptConfig", dbCryptConfig);
        }
        return props;
    }

    private static String queryNote(String url, Properties props) throws SQLException {
        try (Connection connection = DriverManager.getConnection(url, props);
             Statement statement = connection.createStatement();
             ResultSet rs = statement.executeQuery("select note from demo where id = 1")) {
            rs.next();
            return rs.getString(1);
        }
    }

    private static void expectError(String title, String url, Properties props) {
        try {
            queryNote(url, props);
            System.out.println(title + ": NO ERROR - this is wrong");
        } catch (SQLException e) {
            System.out.println(title + ": error, as expected");
            System.err.println("--- " + title + "\n" + e.getMessage() + "\n");
        }
    }
}
