package fbcrypt.examples;

import com.zaxxer.hikari.HikariConfig;
import com.zaxxer.hikari.HikariDataSource;

import java.nio.file.Path;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import javax.sql.DataSource;

/**
 * Scenario S4: a connection pool (HikariCP) and threads.
 *
 * Part 1, pure Java protocol (method D): the key is a property of the data source.
 * Nothing depends on the thread.
 *
 * Part 2, native protocol with fbcrypt (method E): the pool opens connections in its own
 * threads, so the class FbCryptDataSource registers the key callback in each of them.
 *
 * Part 3 shows the error in a thread that did not register the callback.
 */
public final class Main {

    private static final int TASKS = 8;

    public static void main(String[] args) throws Exception {
        Map<String, byte[]> keys = Common.readKeys();

        // Part 1: pure Java protocol
        HikariConfig javaConfig = new HikariConfig();
        javaConfig.setJdbcUrl(Common.url("crypt_red"));
        javaConfig.setUsername(Common.user());
        javaConfig.setPassword(Common.password());
        javaConfig.setMaximumPoolSize(4);
        javaConfig.addDataSourceProperty("dbCryptConfig", Common.staticReply("Red", keys.get("Red")));
        javaConfig.addDataSourceProperty("wireCrypt", "REQUIRED");
        try (HikariDataSource pool = new HikariDataSource(javaConfig)) {
            System.out.println("Pool, pure Java protocol: " + TASKS + " tasks, " + runTasks(pool) + " correct answers");
        }

        // Part 2: native protocol and fbcrypt
        FbCrypt fbcrypt = new FbCrypt(Path.of(Common.env("FBCRYPT_CLIENT")));
        fbcrypt.addKey("Red", keys.get("Red"));

        HikariConfig nativeConfig = new HikariConfig();
        nativeConfig.setDataSource(new FbCryptDataSource(
                fbcrypt, Common.nativeUrl("crypt_red"), Common.user(), Common.password()));
        nativeConfig.setMaximumPoolSize(4);
        try (HikariDataSource pool = new HikariDataSource(nativeConfig)) {
            System.out.println("Pool, native protocol and fbcrypt: " + TASKS + " tasks, " + runTasks(pool)
                    + " correct answers");
        }

        // Part 3: a new thread opens a native connection without registerForThread().
        // The callback of fbcrypt is not set for this thread, so the server gets no key.
        String[] error = new String[1];
        Thread thread = new Thread(() -> {
            try (Connection connection = DriverManager.getConnection(
                    Common.nativeUrl("crypt_red"), Common.user(), Common.password())) {
                error[0] = null;
            } catch (SQLException e) {
                error[0] = e.getMessage();
            }
        });
        thread.start();
        thread.join();
        if (error[0] == null) {
            System.out.println("Thread without registerForThread: NO ERROR - this is wrong");
        } else {
            System.out.println("Thread without registerForThread: error, as expected");
            System.err.println("--- Thread without registerForThread\n" + error[0] + "\n");
        }
    }

    /** Runs the query in several threads. Returns the number of correct answers. */
    private static int runTasks(DataSource pool) throws Exception {
        ExecutorService executor = Executors.newFixedThreadPool(TASKS);
        try {
            List<Future<String>> results = new ArrayList<>();
            for (int i = 0; i < TASKS; i++) {
                results.add(executor.submit(() -> {
                    try (Connection connection = pool.getConnection();
                         Statement statement = connection.createStatement();
                         ResultSet rs = statement.executeQuery("select note from demo where id = 1")) {
                        rs.next();
                        return rs.getString(1);
                    }
                }));
            }
            int correct = 0;
            for (Future<String> result : results) {
                if ("Hello from crypt_red".equals(result.get())) {
                    correct++;
                }
            }
            return correct;
        } finally {
            executor.shutdown();
        }
    }
}
