"""Scenario S11: encrypted backup and restore through the Services API.

Firebird 4.0 and 5.0. gbak runs inside the server process. The client sends the key
through the connection to the service manager (key transfer method B, fbcrypt).

Three things are needed:
  * the key callback for the connection to the service manager;
  * the service parameter "keyholder": the key holder plugin of the server (KeyHolder);
  * the service parameter "keyname": the name of the key.

The backup file is written on the server computer and it is encrypted.

Note: firebird-driver 2.0.3 names the parameter "keyhoder" (a typo in the driver).
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from firebird.driver import DatabaseError, connect, connect_server, driver_config

import fbcrypt_common as common
from fbcrypt_api import FbCrypt, UseFbCrypt, install_firebird_driver_hook

KEY_NAME = "Red"
MARKER = b"Hello from crypt_red"


def main() -> None:
    driver_config.fb_client_library.value = str(common.client_library())
    fbcrypt = FbCrypt(common.client_dir(), common.client_library())
    install_firebird_driver_hook()
    fbcrypt.add_key(KEY_NAME, common.read_keys()[KEY_NAME])

    # firebird-driver takes the address of the service manager from a server configuration.
    driver_config.register_server("fbcrypt-test")
    server = driver_config.get_server("fbcrypt-test")
    server.host.value = common.env("FBCRYPT_HOST")
    server.port.value = common.env("FBCRYPT_PORT")

    work = Path(common.env("FBCRYPT_WORK"))
    backup_file = work / "tmp" / "python-services.fbk"
    restored_db = work / "db" / "python-services-restored.fdb"
    backup_file.unlink(missing_ok=True)

    def open_services():
        return connect_server("fbcrypt-test", user=common.env("FBCRYPT_USER"),
                              password=common.env("FBCRYPT_PASSWORD"), crypt_callback=UseFbCrypt(fbcrypt))

    try:
        # 1. Without the key holder parameter the service cannot open the encrypted database.
        try:
            with open_services() as srv:
                srv.database.backup(database="crypt_red", backup=str(backup_file))
                srv.wait()
            print("Backup without keyholder: NO ERROR - this is wrong")
        except DatabaseError as e:
            print("Backup without keyholder: error, as expected")
            print(f"--- Backup without keyholder\n{e}\n", file=sys.stderr)
        backup_file.unlink(missing_ok=True)

        # 2. Backup with the key holder plugin and the key name.
        with open_services() as srv:
            srv.database.backup(database="crypt_red", backup=str(backup_file),
                                keyhoder="KeyHolder", keyname=KEY_NAME)
            srv.wait()
        print("Backup with keyholder: OK")
        encrypted = MARKER not in backup_file.read_bytes()
        print("Backup file is encrypted:", "yes" if encrypted else "NO - this is wrong")

        # 3. Restore. The service decrypts the backup file and encrypts the new database.
        with open_services() as srv:
            srv.database.restore(backup=str(backup_file), database=str(restored_db),
                                 keyhoder="KeyHolder", keyname=KEY_NAME)
            srv.wait()
        print("Restore with keyholder: OK")

        # 4. The restored database is encrypted with the same key.
        dsn = f"{common.env('FBCRYPT_HOST')}/{common.env('FBCRYPT_PORT')}:{restored_db}"
        with connect(dsn, user=common.env("FBCRYPT_USER"), password=common.env("FBCRYPT_PASSWORD"),
                     crypt_callback=UseFbCrypt(fbcrypt)) as con:
            cur = con.cursor()
            cur.execute("select note from demo where id = 1")
            print("Restored database:", cur.fetchone()[0])
            cur.execute("select mon$crypt_state from mon$database")
            print("Restored database is encrypted:", "yes" if cur.fetchone()[0] == 1 else "NO - this is wrong")
            cur.close()
            con.commit()
            con.drop_database()
    finally:
        backup_file.unlink(missing_ok=True)


if __name__ == "__main__":
    main()
