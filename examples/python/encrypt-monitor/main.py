"""Scenario S5: encrypt a database, watch the progress, change the key, decrypt.

The example works with the database "work" of the test server.
Key transfer method B (fbcrypt). The connection that runs ALTER DATABASE ENCRYPT
must send the key: the server keeps no keys.

Firebird 4.0 and 5.0: the state is in MON$DATABASE.MON$CRYPT_STATE.
Firebird 3.0 has no such column (see the encryption guide, chapter "Monitoring").

Rules that the example shows:
  * the encryption thread works only while a connection to the database is open;
  * to change the key, decrypt the database and encrypt it with the new key.
"""
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from firebird.driver import connect, driver_config

import fbcrypt_common as common
from fbcrypt_api import FbCrypt, UseFbCrypt, install_firebird_driver_hook

STATES = {0: "not encrypted", 1: "encrypted", 2: "decryption in progress", 3: "encryption in progress"}
TIMEOUT_SECONDS = 120


def crypt_state(con) -> tuple[int, int]:
    """Returns (MON$CRYPT_STATE, MON$CRYPT_PAGE). Monitoring data is fixed inside
    a transaction, so each call uses a new transaction."""
    cur = con.cursor()
    cur.execute("select mon$crypt_state, mon$crypt_page from mon$database")
    state, page = cur.fetchone()
    cur.close()
    con.commit()
    return state, page


def wait_for(con, wanted: int) -> str:
    """Keeps the connection open until the crypt thread finishes."""
    deadline = time.monotonic() + TIMEOUT_SECONDS
    while True:
        state, page = crypt_state(con)
        if state == wanted:
            return STATES[state]
        if time.monotonic() > deadline:
            sys.exit(f"ERROR: timeout, state = {STATES.get(state, state)}, page = {page}")
        # Progress goes to standard error: it is different on each run.
        print(f"   {STATES.get(state, state)}, page {page}", file=sys.stderr)
        time.sleep(0.2)


def alter(con, statement: str) -> None:
    con.execute_immediate(statement)
    con.commit()


def main() -> None:
    driver_config.fb_client_library.value = str(common.client_library())
    fbcrypt = FbCrypt(common.client_dir(), common.client_library())
    install_firebird_driver_hook()
    keys = common.read_keys()
    fbcrypt.add_key("Red", keys["Red"])
    fbcrypt.add_key("Green", keys["Green"])

    def open_connection():
        return connect(common.dsn("work"), user=common.env("FBCRYPT_USER"),
                       password=common.env("FBCRYPT_PASSWORD"), crypt_callback=UseFbCrypt(fbcrypt))

    with open_connection() as con:
        # A previous run could stop in the middle. Return the database to the start state.
        if crypt_state(con)[0] != 0:
            alter(con, "alter database decrypt")
            wait_for(con, 0)
        print("State at start:", STATES[crypt_state(con)[0]])

        # Write the plugin name in double quotes: on Linux the name is case-sensitive.
        alter(con, 'alter database encrypt with "DbCrypt" key Red')
        print("Encrypt with key Red:", wait_for(con, 1))

    # A new connection reads the encrypted database with the key Red.
    with open_connection() as con:
        cur = con.cursor()
        cur.execute("select note from demo where id = 1")
        print("Read data:", cur.fetchone()[0])
        cur.close()
        con.commit()

        # Change the key: decrypt, then encrypt with the new key.
        alter(con, "alter database decrypt")
        wait_for(con, 0)
        alter(con, 'alter database encrypt with "DbCrypt" key Green')
        print("Change key to Green:", wait_for(con, 1))

        alter(con, "alter database decrypt")
        print("Decrypt:", wait_for(con, 0))


if __name__ == "__main__":
    main()
