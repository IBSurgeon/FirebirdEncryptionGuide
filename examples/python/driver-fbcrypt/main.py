"""Scenarios S1, S2 and S3: firebird-driver with the fbcrypt library.

Key transfer method B: fbcrypt_callback(provider), protected key exchange.
The server does not need UnsafeClient = true.

Standard output is the same on each run (see expected-output.txt).
Full error texts go to standard error.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from firebird.driver import DatabaseError, connect, driver_config

import fbcrypt_common as common
from fbcrypt_api import FbCrypt, UseFbCrypt, install_firebird_driver_hook


def query_note(alias: str, fbcrypt: FbCrypt | None) -> str:
    callback = UseFbCrypt(fbcrypt) if fbcrypt else None
    with connect(common.dsn(alias), user=common.env("FBCRYPT_USER"),
                 password=common.env("FBCRYPT_PASSWORD"), crypt_callback=callback) as con:
        cur = con.cursor()
        cur.execute("select note from demo where id = 1")
        return cur.fetchone()[0]


def expect_error(title: str, alias: str, fbcrypt: FbCrypt | None) -> None:
    try:
        query_note(alias, fbcrypt)
    except DatabaseError as e:
        print(f"{title}: error, as expected")
        print(f"--- {title}\n{e}\n", file=sys.stderr)
    else:
        print(f"{title}: NO ERROR - this is wrong")


def main() -> None:
    # The driver and fbcrypt must use the same fbclient.
    driver_config.fb_client_library.value = str(common.client_library())
    fbcrypt = FbCrypt(common.client_dir(), common.client_library())
    install_firebird_driver_hook()
    keys = common.read_keys()

    # S1: one key
    fbcrypt.add_key("Red", keys["Red"])
    print("S1 connect with key Red:", query_note("crypt_red", fbcrypt))

    # S3: two keys in the list, two databases
    fbcrypt.add_key("Green", keys["Green"])
    print("S3 two keys, database crypt_red:", query_note("crypt_red", fbcrypt))
    print("S3 two keys, database crypt_green:", query_note("crypt_green", fbcrypt))

    # S3: replace the keys. fbcrypt_init(NULL) clears the list.
    fbcrypt.clear_keys()
    expect_error("S3 after the key list is cleared", "crypt_red", fbcrypt)

    # S2: errors
    expect_error("S2 no key", "crypt_red", None)
    fbcrypt.add_key("Red", keys["Green"])
    expect_error("S2 wrong key value", "crypt_red", fbcrypt)
    fbcrypt.clear_keys()
    fbcrypt.add_key("Blue", keys["Red"])
    expect_error("S2 wrong key name", "crypt_red", fbcrypt)

    # Back to the right key
    fbcrypt.clear_keys()
    fbcrypt.add_key("Red", keys["Red"])
    print("S1 connect again with key Red:", query_note("crypt_red", fbcrypt))


if __name__ == "__main__":
    main()
