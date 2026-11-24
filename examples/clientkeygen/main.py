"""Scenario S9: individual client keys (Firebird 5.0 only).

The utility ClientKeygen makes a separate key for each client from one database key.
The server unpacks a client key with its license and gets the database key and the
number of the client key. With Logger = true in DbCrypt.conf the server writes the
number to firebird.log.

The example:
  1. runs ClientKeygen and makes 3 client keys for the database key Red;
  2. connects with each client key (fbcrypt, protected key exchange);
  3. finds the records in firebird.log of the test server;
  4. shows that a damaged client key is rejected.

Environment: FBCRYPT_CLIENTKEYGEN = full path of ClientKeygen.
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "python"))

from firebird.driver import DatabaseError, connect, driver_config

import fbcrypt_common as common
from fbcrypt_api import FbCrypt, UseFbCrypt, install_firebird_driver_hook

KEY_NAME = "Red"
KEY_COUNT = 3


def make_client_keys(folder: Path) -> list[bytes]:
    """Runs ClientKeygen in a folder with KeyHolder.conf and DbCrypt.conf."""
    keygen = Path(common.env("FBCRYPT_CLIENTKEYGEN"))
    server_plugins = Path(common.env("FBCRYPT_WORK")) / "server" / "plugins"

    # ClientKeygen reads the database key from KeyHolder.conf and the license from DbCrypt.conf.
    # The license must be the license of the server that will get the client keys.
    key = common.read_keys()[KEY_NAME]
    (folder / "KeyHolder.conf").write_text(f"Key={KEY_NAME} {common.key_text(key)}\n", encoding="ascii")
    shutil.copy(server_plugins / "DbCrypt.conf", folder / "DbCrypt.conf")

    # ClientKeygen needs libcrypto: add the client folder of the plugin to PATH.
    env = dict(os.environ)
    env["PATH"] = str(common.client_dir()) + os.pathsep + env.get("PATH", "")
    result = subprocess.run([str(keygen), KEY_NAME, str(KEY_COUNT)], cwd=folder, env=env,
                            capture_output=True, text=True)
    if result.returncode != 0:
        sys.exit(f"ERROR: ClientKeygen failed: {result.stdout}{result.stderr}")

    keys = []
    for number in range(1, KEY_COUNT + 1):
        # File KeyHolder.conf.<number> has one line: Key=<name> 0x..,0x..,  (64 bytes)
        text = (folder / f"KeyHolder.conf.{number}").read_text(encoding="ascii")
        value = re.match(r"\s*Key\s*=\s*\S+\s+(\S+)", text).group(1)
        keys.append(bytes(int(part, 16) for part in value.split(",") if part))
    return keys


def query_note(fbcrypt: FbCrypt) -> str:
    with connect(common.dsn("crypt_red"), user=common.env("FBCRYPT_USER"),
                 password=common.env("FBCRYPT_PASSWORD"), crypt_callback=UseFbCrypt(fbcrypt)) as con:
        cur = con.cursor()
        cur.execute("select note from demo where id = 1")
        return cur.fetchone()[0]


def main() -> None:
    if os.environ.get("FBCRYPT_FB_MAJOR", "5") != "5":
        sys.exit("ERROR: individual client keys need the plugin for Firebird 5.0")

    driver_config.fb_client_library.value = str(common.client_library())
    fbcrypt = FbCrypt(common.client_dir(), common.client_library())
    install_firebird_driver_hook()

    log_file = Path(common.env("FBCRYPT_WORK")) / "server" / "firebird.log"
    log_start = log_file.stat().st_size if log_file.exists() else 0

    # Client keys are secrets. Keep them in a temporary folder and delete it at the end.
    folder = Path(tempfile.mkdtemp(prefix="fbclientkeys-"))
    try:
        keys = make_client_keys(folder)
        print(f"ClientKeygen: {len(keys)} client keys, {len(keys[0])} bytes each")

        for number, key in enumerate(keys, start=1):
            fbcrypt.clear_keys()
            # The client key has the name of the database key.
            fbcrypt.add_key(KEY_NAME, key)
            print(f"Client key {number}:", query_note(fbcrypt))

        # Records of the server: "DbCrypt login from <address> using key <number>"
        with open(log_file, "r", encoding="ascii", errors="replace") as f:
            f.seek(log_start)
            numbers = sorted({int(n) for n in re.findall(r"DbCrypt login from \S+ using key (\d+)", f.read())})
        if numbers:
            print("Log records for the client keys:", ", ".join(str(n) for n in numbers))
        else:
            print("Log records for the client keys: NOT FOUND (set Logger = true in DbCrypt.conf of the server)")

        # A damaged client key does not open the database.
        damaged = bytearray(keys[0])
        damaged[40] ^= 0xFF
        fbcrypt.clear_keys()
        fbcrypt.add_key(KEY_NAME, bytes(damaged))
        try:
            query_note(fbcrypt)
            print("Damaged client key: NO ERROR - this is wrong")
        except DatabaseError as e:
            print("Damaged client key: error, as expected")
            print(f"--- Damaged client key\n{e}\n", file=sys.stderr)
    finally:
        shutil.rmtree(folder, ignore_errors=True)


if __name__ == "__main__":
    main()
