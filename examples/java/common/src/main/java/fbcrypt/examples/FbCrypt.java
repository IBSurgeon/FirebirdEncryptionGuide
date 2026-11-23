package fbcrypt.examples;

import com.sun.jna.Library;
import com.sun.jna.Native;
import com.sun.jna.NativeLibrary;
import com.sun.jna.Pointer;

import java.io.IOException;
import java.nio.file.DirectoryStream;
import java.nio.file.Files;
import java.nio.file.Path;

/**
 * JNA wrapper of the fbcrypt library from the client package of the encryption plugin.
 * fbcrypt sends the key with the protected key exchange. The server does not need
 * UnsafeClient = true.
 *
 * Checked on 64-bit Windows. A 32-bit JVM on Windows needs StdCallLibrary.
 */
public final class FbCrypt {

    private interface FbCryptLibrary extends Library {
        int fbcrypt_init(String clientPathName);

        int fbcrypt_key(String name, byte[] data, int dl);

        int fbcrypt_callback(Pointer provider);
    }

    private final FbCryptLibrary library;

    /**
     * @param clientDir folder with fbcrypt, fbclient and libcrypto
     */
    public FbCrypt(Path clientDir) throws IOException {
        boolean windows = System.getProperty("os.name").startsWith("Windows");
        Path libDir = windows ? clientDir : clientDir.resolve("lib");

        // Jaybird loads fbclient by name through JNA. Give JNA the folder before the first connection.
        System.setProperty("jna.library.path", libDir.toString());

        if (windows) {
            // fbcrypt loads libcrypto by name. Load it by the full path first:
            // Windows then finds the loaded module.
            try (DirectoryStream<Path> files = Files.newDirectoryStream(libDir, "libcrypto-*.dll")) {
                for (Path file : files) {
                    NativeLibrary.getInstance(file.toString());
                }
            }
        }
        library = Native.load(libDir.resolve(windows ? "fbcrypt.dll" : "libfbcrypt.so").toString(),
                FbCryptLibrary.class);

        // The same fbclient that Jaybird loads.
        Path client = libDir.resolve(windows ? "fbclient.dll" : "libfbclient.so");
        int rc = library.fbcrypt_init(client.toString());
        if (rc < 0) {
            throw new IllegalStateException("fbcrypt_init = " + rc + ": cannot load " + client
                    + ". Check the path and the bitness. Another reason: fbcrypt_init was called before with another path.");
        }
    }

    /** Adds a key to the key list of fbcrypt. The list is global for the process. */
    public void addKey(String name, byte[] key) {
        int rc = library.fbcrypt_key(name, key, key.length);
        if (rc < 0) {
            throw new IllegalStateException("fbcrypt_key = " + rc);
        }
    }

    /** Removes all keys from the key list. */
    public void clearKeys() {
        library.fbcrypt_init(null);
    }

    /**
     * Registers the key callback for the current thread.
     * Call it in the thread that opens the connection, before DriverManager.getConnection.
     * Do not use virtual threads: a virtual thread can move to another platform thread.
     */
    public void registerForThread() {
        int rc = library.fbcrypt_callback(null);
        if (rc >= 0) {
            return;
        }
        String reason = switch (rc) {
            case -1 -> "cannot register the keys";
            case -5 -> "the loaded fbclient is older than 3.0";
            case -10 -> "fbcrypt_init was not called";
            default -> "unknown error";
        };
        throw new IllegalStateException("fbcrypt_callback = " + rc + ": " + reason);
    }
}
