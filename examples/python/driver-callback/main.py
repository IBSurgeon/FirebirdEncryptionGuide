"""Scenarios S1 and S2: connect to an encrypted database with firebird-driver.

Key transfer method D: the driver sends the key as a static value.
The server must have UnsafeClient = true in plugins/KeyHolder.conf and WireCrypt = Required.

Standard output is the same on each run (see expected-output.txt).
Full error texts go to standard error.
"""
import ctypes
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from firebird.driver import DatabaseError, connect, driver_config, fbapi
from firebird.driver.interfaces import iCryptKeyCallbackImpl

import fbcrypt_common as common


class StaticKeyCallback(iCryptKeyCallbackImpl):
    """Answers the request of the server with a fixed value.

    firebird-driver 2.0.3: the built-in wrapper of the callback fails with TypeError
    (it slices a raw pointer), and the connection attempt crashes. This class installs
    its own callback function into the interface table instead.
    """

    def __init__(self, reply: bytes):
        super().__init__()
        self._reply = reply
        # Keep a reference to the C function: ctypes does not keep it.
        self._c_callback = fbapi.ICryptKeyCallback_callback(self._callback)
        self.vtable.callback = self._c_callback

    def _callback(self, this, data_length, data, buffer_length, buffer) -> int:
        # The function returns the length of the reply. It copies the reply only if
        # the buffer of the caller is big enough.
        try:
            reply = self._reply
            if buffer and buffer_length >= len(reply):
                ctypes.memmove(buffer, reply, len(reply))
            return len(reply)
        except Exception:  # an exception must not leave a C callback
            return 0


def query_note(alias: str, callback: iCryptKeyCallbackImpl | None) -> str:
    with connect(common.dsn(alias), user=common.env("FBCRYPT_USER"),
                 password=common.env("FBCRYPT_PASSWORD"), crypt_callback=callback) as con:
        cur = con.cursor()
        cur.execute("select note from demo where id = 1")
        return cur.fetchone()[0]


def expect_error(title: str, alias: str, callback: iCryptKeyCallbackImpl | None) -> None:
    try:
        query_note(alias, callback)
    except DatabaseError as e:
        print(f"{title}: error, as expected")
        print(f"--- {title}\n{e}\n", file=sys.stderr)
    else:
        print(f"{title}: NO ERROR - this is wrong")


def main() -> None:
    # Use fbclient from the client package of the plugin.
    driver_config.fb_client_library.value = str(common.client_library())
    keys = common.read_keys()

    # S1: the right key
    red = StaticKeyCallback(common.static_reply("Red", keys["Red"]))
    print("S1 connect with key Red:", query_note("crypt_red", red))

    green = StaticKeyCallback(common.static_reply("Green", keys["Green"]))
    print("S1 connect with key Green:", query_note("crypt_green", green))

    # S2: errors
    expect_error("S2 no key", "crypt_red", None)
    expect_error("S2 wrong key value", "crypt_red",
                 StaticKeyCallback(common.static_reply("Red", keys["Green"])))
    expect_error("S2 wrong key name", "crypt_red",
                 StaticKeyCallback(common.static_reply("Blue", keys["Red"])))

    # A database that is not encrypted needs no key.
    print("Plain database without a key:", query_note("plain", None))


if __name__ == "__main__":
    main()
