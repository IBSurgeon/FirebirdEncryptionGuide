"""Opens many connections through a workstation folder and reports time, errors and memory.

The script loads fbclient.dll from the given folder. The KeySource library of this folder
gives the key. Use it to check a KeySource library under load.

Example:
    python connect_loop.py --client D:\\work\\fb5\\remote --dsn localhost/30055:crypt_employee
                           --count 1000 --threads 8
"""
import argparse
import ctypes
import ctypes.wintypes as wt
import os
import threading
import time


class ProcessMemoryCounters(ctypes.Structure):
    _fields_ = [("cb", wt.DWORD), ("PageFaultCount", wt.DWORD),
                ("PeakWorkingSetSize", ctypes.c_size_t), ("WorkingSetSize", ctypes.c_size_t),
                ("QuotaPeakPagedPoolUsage", ctypes.c_size_t), ("QuotaPagedPoolUsage", ctypes.c_size_t),
                ("QuotaPeakNonPagedPoolUsage", ctypes.c_size_t), ("QuotaNonPagedPoolUsage", ctypes.c_size_t),
                ("PagefileUsage", ctypes.c_size_t), ("PeakPagefileUsage", ctypes.c_size_t)]


def private_bytes() -> int:
    counters = ProcessMemoryCounters()
    counters.cb = ctypes.sizeof(counters)
    get_process = ctypes.windll.kernel32.GetCurrentProcess
    get_process.restype = wt.HANDLE
    get_info = ctypes.windll.psapi.GetProcessMemoryInfo
    get_info.argtypes = [wt.HANDLE, ctypes.POINTER(ProcessMemoryCounters), wt.DWORD]
    get_info(get_process(), ctypes.byref(counters), counters.cb)
    return counters.PagefileUsage


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--client", required=True, help="folder with fbclient.dll and KeySource.dll")
    parser.add_argument("--dsn", required=True)
    parser.add_argument("--user", default="SYSDBA")
    parser.add_argument("--password", default="masterkey")
    parser.add_argument("--count", type=int, default=100, help="connections of each thread")
    parser.add_argument("--threads", type=int, default=1)
    parser.add_argument("--sql", default="select count(*) from customer")
    args = parser.parse_args()

    os.environ.pop("FIREBIRD", None)
    from firebird.driver import connect, driver_config
    driver_config.fb_client_library.value = os.path.join(args.client, "fbclient.dll")

    errors: list[str] = []
    lock = threading.Lock()

    def one() -> None:
        con = connect(args.dsn, user=args.user, password=args.password)
        try:
            cur = con.cursor()
            cur.execute(args.sql)
            cur.fetchall()
        finally:
            con.close()

    def worker() -> None:
        for _ in range(args.count):
            try:
                one()
            except Exception as ex:  # the first line of the message is enough for the report
                with lock:
                    errors.append(str(ex).splitlines()[0])

    one()  # the first connection loads the libraries; do not count its memory
    memory_before = private_bytes()
    started = time.perf_counter()
    threads = [threading.Thread(target=worker) for _ in range(args.threads)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    seconds = time.perf_counter() - started
    memory_after = private_bytes()

    total = args.count * args.threads
    print(f"connections: {total}, threads: {args.threads}, errors: {len(errors)}, "
          f"time: {seconds:.1f} s, {seconds / total * 1000:.1f} ms per connection")
    print(f"private memory: {memory_before // 1024} KB -> {memory_after // 1024} KB "
          f"({(memory_after - memory_before) // 1024:+d} KB)")
    for text in sorted(set(errors))[:5]:
        print(f"error: {text}")
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
