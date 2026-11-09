"""Two real players on a dedicated server: the second player drops out and
rejoins mid-level without anyone's departments changing (playtest 2.11), and
each player stores their own study files locally in a date_time_name folder
with descriptive names (playtest 07.11).

Run: python tests/run_coop_storage_tests.py --godot /path/to/godot
No microphone is opened. Temporary files are isolated per run under .tools/.
"""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import subprocess
import time


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True)
    parser.add_argument("--port", type=int, default=25927)
    args = parser.parse_args()
    if not 1024 <= args.port <= 65535:
        parser.error("port must be between 1024 and 65535")
    root = Path(__file__).resolve().parents[1]
    output = root / ".tools" / f"coop-storage-{time.time_ns()}"
    output.mkdir(parents=True)
    hidden = getattr(subprocess, "CREATE_NO_WINDOW", 0)
    processes = []
    failures = []

    def launch(label: str, extra: list[str]) -> None:
        env = os.environ.copy()
        local_user = output / label / "user"
        local_user.mkdir(parents=True)
        env["APPDATA"] = str(local_user)
        env["XDG_DATA_HOME"] = str(local_user)
        log = (output / f"{label}.log").open("w", encoding="utf-8")
        command = [args.godot, "--headless", "--path", str(root), "--script",
                   "res://tests/test_coop_storage_peer.gd", "--",
                   f"--port={args.port}", f"--qa-dir={output}", *extra]
        process = subprocess.Popen(command, cwd=root, env=env, stdout=log,
                                   stderr=subprocess.STDOUT, creationflags=hidden)
        processes.append((label, process, log))

    try:
        launch("server", ["--server"])
        time.sleep(0.3)
        launch("leader", ["--leader"])
        launch("guest", ["--guest"])
        for label, process, _ in reversed(processes):
            try:
                if process.wait(timeout=75):
                    failures.append(label)
            except subprocess.TimeoutExpired:
                failures.append(label + " timeout")
    finally:
        for _, process, log in processes:
            if process.poll() is None:
                process.kill()
                process.wait(timeout=5)
            log.close()
    for path in sorted(output.glob("*.log")):
        content = path.read_text(encoding="utf-8", errors="replace")
        if "PASS:" not in content:
            failures.append(path.stem + " missing PASS")
        for line in content.splitlines():
            if "ERROR:" in line and "Failed to read the root certificate store" not in line:
                failures.append(path.stem + " engine error")
            if any(token in line for token in ["PASS:", "FAIL:", "SCRIPT ERROR", "ERROR:"]):
                print(path.name, line)
    print("Co-op storage logs:", output)
    print("COOP STORAGE SUITE:", "PASS" if not failures else "FAIL: " + ", ".join(failures))
    return int(bool(failures))


if __name__ == "__main__":
    raise SystemExit(main())
