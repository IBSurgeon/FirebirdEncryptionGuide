"""ctypes wrapper of the fbcrypt library from the client package of the encryption plugin.

fbcrypt sends the key with the protected key exchange. The server does not need
UnsafeClient = true.
"""
import ctypes
import os
from pathlib import Path


class FbCryptError(Exception):
    pass


class FbCrypt:
    def __init__(self, client_dir: Path, client_library: Path):
        """client_library: the same fbclient that the database driver loads."""
        if os.name == "nt":
            # libcrypto is next to fbcrypt.dll
            os.add_dll_directory(str(client_dir))
            self._lib = ctypes.WinDLL(str(client_dir / "fbcrypt.dll"))
        else:
            self._lib = ctypes.CDLL(str(client_dir / "lib" / "libfbcrypt.so"))

        self._lib.fbcrypt_init.argtypes = [ctypes.c_char_p]
        self._lib.fbcrypt_init.restype = ctypes.c_int
        self._lib.fbcrypt_key.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint]
        self._lib.fbcrypt_key.restype = ctypes.c_int
        self._lib.fbcrypt_callback.argtypes = [ctypes.c_void_p]
        self._lib.fbcrypt_callback.restype = ctypes.c_int

        rc = self._lib.fbcrypt_init(str(client_library).encode())
        if rc < 0:
            raise FbCryptError(
                f"fbcrypt_init = {rc}: cannot load {client_library}. Check the path and the bitness. "
                "Another reason: fbcrypt_init was called before with another path.")

    def add_key(self, name: str, key: bytes) -> None:
        """Adds a key to the key list of fbcrypt. The list is global for the process."""
        rc = self._lib.fbcrypt_key(name.encode("ascii"), key, len(key))
        if rc < 0:
            raise FbCryptError(f"fbcrypt_key = {rc}")

    def clear_keys(self) -> None:
        """Removes all keys from the key list."""
        self._lib.fbcrypt_init(None)

    def register_for_thread(self) -> None:
        """For drivers on the ISC API. Call it in the thread that opens the connection."""
        self._check_callback(self._lib.fbcrypt_callback(None))

    def register_for_provider(self, provider_pointer) -> None:
        """For drivers on the object-oriented API: pass the pointer to IProvider."""
        self._check_callback(self._lib.fbcrypt_callback(provider_pointer))

    @staticmethod
    def _check_callback(rc: int) -> None:
        if rc >= 0:
            return
        reasons = {
            -1: "cannot register the keys",
            -5: "the loaded fbclient is older than 3.0",
            -10: "fbcrypt_init was not called",
        }
        raise FbCryptError(f"fbcrypt_callback = {rc}: {reasons.get(rc, 'unknown error')}")


class UseFbCrypt:
    """Marker object. Pass it as crypt_callback= to firebird.driver.connect()."""

    def __init__(self, fbcrypt: FbCrypt):
        self.fbcrypt = fbcrypt


def install_firebird_driver_hook() -> None:
    """Lets firebird-driver use fbcrypt.

    firebird-driver creates the IProvider object inside connect(). The hook catches the
    place where the driver sets the crypt callback, and calls fbcrypt_callback(provider)
    for that IProvider. Checked with firebird-driver 2.0.3.
    """
    from firebird.driver.interfaces import iProvider

    if getattr(iProvider, "_fbcrypt_hook", False):
        return
    original = iProvider.set_dbcrypt_callback

    def set_dbcrypt_callback(self, callback):
        if isinstance(callback, UseFbCrypt):
            pointer = ctypes.cast(self._as_parameter_, ctypes.c_void_p)
            callback.fbcrypt.register_for_provider(pointer)
        else:
            original(self, callback)

    iProvider.set_dbcrypt_callback = set_dbcrypt_callback
    iProvider._fbcrypt_hook = True
