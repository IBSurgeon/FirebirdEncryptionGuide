package fbcrypt.examples;

import java.io.PrintWriter;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.SQLException;
import java.sql.SQLFeatureNotSupportedException;
import java.util.logging.Logger;
import javax.sql.DataSource;

/**
 * Data source for the native protocol of Jaybird with the fbcrypt library.
 *
 * A connection pool opens connections in its own threads. The key callback of fbcrypt
 * is registered for a thread. So this class registers the callback in the thread that
 * asks for a new connection, and then opens the connection in the same thread.
 */
public final class FbCryptDataSource implements DataSource {

    private final FbCrypt fbcrypt;
    private final String url;
    private final String user;
    private final String password;

    public FbCryptDataSource(FbCrypt fbcrypt, String url, String user, String password) {
        this.fbcrypt = fbcrypt;
        this.url = url;
        this.user = user;
        this.password = password;
    }

    @Override
    public Connection getConnection() throws SQLException {
        return getConnection(user, password);
    }

    @Override
    public Connection getConnection(String username, String pass) throws SQLException {
        fbcrypt.registerForThread();
        return DriverManager.getConnection(url, username, pass);
    }

    @Override
    public PrintWriter getLogWriter() {
        return null;
    }

    @Override
    public void setLogWriter(PrintWriter out) {
    }

    @Override
    public void setLoginTimeout(int seconds) {
    }

    @Override
    public int getLoginTimeout() {
        return 0;
    }

    @Override
    public Logger getParentLogger() throws SQLFeatureNotSupportedException {
        throw new SQLFeatureNotSupportedException();
    }

    @Override
    public <T> T unwrap(Class<T> iface) throws SQLException {
        throw new SQLException("Not a wrapper");
    }

    @Override
    public boolean isWrapperFor(Class<?> iface) {
        return false;
    }
}
