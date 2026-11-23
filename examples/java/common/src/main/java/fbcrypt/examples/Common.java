package fbcrypt.examples;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Helpers shared by the Java examples.
 * The examples read the connection parameters from environment variables.
 * The script examples/common/setup.ps1 creates the file test-env.ps1 that sets them.
 */
public final class Common {

    private static final Pattern KEY_LINE = Pattern.compile("^\\s*Key\\s*=\\s*(\\S+)\\s+(\\S+)\\s*$");

    private Common() {
    }

    public static String env(String name) {
        String value = System.getenv(name);
        if (value == null || value.isEmpty()) {
            System.err.println("ERROR: environment variable " + name + " is not set. "
                    + "Run examples/common/setup.ps1 and dot-source test-env.ps1.");
            System.exit(2);
        }
        return value;
    }

    public static String user() {
        return env("FBCRYPT_USER");
    }

    public static String password() {
        return env("FBCRYPT_PASSWORD");
    }

    /** JDBC URL of the pure Java protocol. */
    public static String url(String alias) {
        return "jdbc:firebird://" + env("FBCRYPT_HOST") + ":" + env("FBCRYPT_PORT") + "/" + alias;
    }

    /** JDBC URL of the native protocol (Jaybird works through fbclient). */
    public static String nativeUrl(String alias) {
        return "jdbc:firebird:native://" + env("FBCRYPT_HOST") + ":" + env("FBCRYPT_PORT") + "/" + alias;
    }

    /**
     * Reads keys from a file in KeyHolder.conf format: Key=&lt;name&gt; 0x..,0x..,
     * Do not keep real keys in the source code or in application.properties.
     */
    public static Map<String, byte[]> readKeys() throws IOException {
        Map<String, byte[]> keys = new LinkedHashMap<>();
        for (String line : Files.readAllLines(Path.of(env("FBCRYPT_KEYS")), StandardCharsets.US_ASCII)) {
            Matcher m = KEY_LINE.matcher(line);
            if (!m.matches()) {
                continue;
            }
            String[] parts = m.group(2).split(",");
            byte[] data = new byte[parts.length];
            for (int i = 0; i < parts.length; i++) {
                data[i] = (byte) Integer.decode(parts[i]).intValue();
            }
            if (data.length != 16 && data.length != 24 && data.length != 32) {
                throw new IOException("Key " + m.group(1) + " has " + data.length + " bytes, need 16, 24 or 32");
            }
            keys.put(m.group(1), data);
        }
        return keys;
    }

    /** Key value in the notation of the plugin: 0x..,0x.., */
    public static String keyText(byte[] key) {
        StringBuilder sb = new StringBuilder();
        for (byte b : key) {
            sb.append(String.format("0x%02x,", b & 0xff));
        }
        return sb.toString();
    }

    /**
     * Value for the dbCryptConfig property of Jaybird: &lt;name&gt;:0x..,0x..,
     * The server accepts it only with UnsafeClient = true in KeyHolder.conf.
     */
    public static String staticReply(String name, byte[] key) {
        return name + ":" + keyText(key);
    }
}
