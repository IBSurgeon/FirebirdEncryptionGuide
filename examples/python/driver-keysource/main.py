"""Scenarios S1 and S7: firebird-driver with the client-side KeyHolder plugin and KeySource.

Key transfer method C. The program has no code for the key:

  * firebird.conf next to fbclient has KeyHolderPlugin = KeyHolder;
  * the library KeySource next to fbclient returns the keys;
  * the KeyHolder plugin of the client sends the key with the protected key exchange.

The server does not need UnsafeClient = true.
Create the client folder with examples/common/new-keysource-client.ps1.
"""
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from firebird.driver import connect, driver_config

import fbcrypt_common as common


def main() -> None:
    client = Path(os.environ.get("FBCRYPT_CLIENT_KEYSOURCE")
                  or Path(common.env("FBCRYPT_WORK")) / "client-keysource")
    library = client / ("fbclient.dll" if os.name == "nt" else "lib/libfbclient.so")
    if not library.exists():
        sys.exit(f"ERROR: {library} is not found. Run examples/common/new-keysource-client.ps1 first.")
    driver_config.fb_client_library.value = str(library)

    for alias in ("crypt_red", "crypt_green", "plain"):
        # An ordinary connection: no key in the program.
        with connect(common.dsn(alias), user=common.env("FBCRYPT_USER"),
                     password=common.env("FBCRYPT_PASSWORD")) as con:
            cur = con.cursor()
            cur.execute("select note from demo where id = 1")
            print(f"S7 connect to {alias}:", cur.fetchone()[0])


if __name__ == "__main__":
    main()
