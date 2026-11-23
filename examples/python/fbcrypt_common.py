"""Helpers shared by the Python examples.

The examples read the connection parameters from environment variables.
The script examples/common/setup.ps1 creates the file test-env.ps1 that sets them.
"""
import os
import re
import sys
from pathlib import Path


def env(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        sys.exit(f"ERROR: environment variable {name} is not set. "
                 "Run examples/common/setup.ps1 and dot-source test-env.ps1.")
    return value


def dsn(alias: str) -> str:
    """Connection string for a database alias on the test server."""
    return f"{env('FBCRYPT_HOST')}/{env('FBCRYPT_PORT')}:{alias}"


def client_dir() -> Path:
    return Path(env("FBCRYPT_CLIENT"))


def client_library() -> Path:
    """Path of fbclient from the client package of the encryption plugin."""
    if os.name == "nt":
        return client_dir() / "fbclient.dll"
    return client_dir() / "lib" / "libfbclient.so"


def read_keys(path: str | None = None) -> dict[str, bytes]:
    """Reads keys from a file in KeyHolder.conf format: Key=<name> 0x..,0x..,

    Do not keep real keys in the source code. Read them from a protected file,
    from an environment variable or from a secret store.
    """
    keys: dict[str, bytes] = {}
    text = Path(path or env("FBCRYPT_KEYS")).read_text(encoding="ascii")
    for line in text.splitlines():
        m = re.match(r"\s*Key\s*=\s*(\S+)\s+(\S+)\s*$", line)
        if not m:
            continue
        name, value = m.group(1), m.group(2)
        data = bytes(int(part, 16) for part in value.split(",") if part)
        if len(data) not in (16, 24, 32):
            sys.exit(f"ERROR: key {name} has {len(data)} bytes, need 16, 24 or 32")
        keys[name] = data
    return keys


def key_text(key: bytes) -> str:
    """Key value in the notation of the plugin: 0x..,0x..,"""
    return "".join(f"0x{b:02x}," for b in key)


def static_reply(name: str, key: bytes) -> bytes:
    """Reply for drivers that send the key as a static value: <name>:0x..,0x..,

    The server accepts it only with UnsafeClient = true in KeyHolder.conf.
    """
    return f"{name}:{key_text(key)}".encode("ascii")
