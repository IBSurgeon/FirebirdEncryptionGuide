"""Scenario S6: encrypted backup and restore from a program.

Firebird 4.0 and 5.0: gbak -KeyHolder KeyHolderStdin, the key goes to the standard input of gbak.
Firebird 3.0: gbak has no -KeyHolder switch. The program writes the key to a temporary file
that only the current user can read, and runs gbak -KEYFILE.

The key is never put on the command line: other users can see the command line.
"""
import os
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import fbcrypt_common as common

KEY_NAME = "Red"
MARKER = b"Hello from crypt_red"


def gbak_exe() -> str:
    return str(common.client_dir() / ("gbak.exe" if os.name == "nt" else "bin/gbak"))


def run_gbak(args: list[str], key_line: str | None) -> subprocess.CompletedProcess:
    """Runs gbak. The line with the key goes to the standard input of the process."""
    cmd = [gbak_exe(), "-user", common.env("FBCRYPT_USER"), "-password", common.env("FBCRYPT_PASSWORD")] + args
    return subprocess.run(cmd, input=(key_line or "").encode("ascii"), capture_output=True)


def gbak_with_key(args: list[str], key: bytes, fb_major: int) -> subprocess.CompletedProcess:
    key_line = f"Key={KEY_NAME} {common.key_text(key)}"
    if fb_major >= 4:
        return run_gbak(args + ["-keyholder", "KeyHolderStdin"], key_line)

    # Firebird 3.0: a temporary key file. mkstemp creates it for the current user only.
    fd, key_file = tempfile.mkstemp(prefix="fbkey-", suffix=".conf")
    try:
        with os.fdopen(fd, "w", encoding="ascii") as f:
            f.write(key_line + "\n")
        return run_gbak(args + ["-keyfile", key_file, "-keyname", KEY_NAME], None)
    finally:
        os.remove(key_file)


def report(title: str, result: subprocess.CompletedProcess, must_fail: bool = False) -> bool:
    failed = result.returncode != 0
    if failed == must_fail:
        print(f"{title}: {'error, as expected' if must_fail else 'OK'}")
    else:
        print(f"{title}: {'NO ERROR - this is wrong' if must_fail else 'FAILED'}")
    if failed:
        print(f"--- {title}\n{result.stderr.decode(errors='replace')}", file=sys.stderr)
    return failed == must_fail


def main() -> None:
    fb_major = int(os.environ.get("FBCRYPT_FB_MAJOR", "5"))
    key = common.read_keys()[KEY_NAME]
    work = Path(common.env("FBCRYPT_WORK"))
    backup_file = work / "tmp" / "python-crypt_red.fbk"
    restored_db = work / "db" / "python-restored.fdb"
    server = f"{common.env('FBCRYPT_HOST')}/{common.env('FBCRYPT_PORT')}:"

    try:
        # 1. Backup without a key must fail: the database is encrypted.
        report("Backup without a key", run_gbak(["-b", server + "crypt_red", str(backup_file)], None),
               must_fail=True)

        # 2. Backup with the key. The backup file is encrypted too.
        ok = report("Backup with the key", gbak_with_key(["-b", server + "crypt_red", str(backup_file)], key, fb_major))
        if not ok:
            sys.exit(1)
        encrypted = MARKER not in backup_file.read_bytes()
        print("Backup file is encrypted:", "yes" if encrypted else "NO - this is wrong")

        # 3. Restore without a key must fail: gbak cannot read the encrypted backup file.
        report("Restore without a key", run_gbak(["-rep", str(backup_file), server + str(restored_db)], None),
               must_fail=True)

        # 4. Restore with the key. gbak encrypts the new database with the same key.
        report("Restore with the key", gbak_with_key(["-rep", str(backup_file), server + str(restored_db)], key, fb_major))
    finally:
        backup_file.unlink(missing_ok=True)
        restored_db.unlink(missing_ok=True)


if __name__ == "__main__":
    main()
