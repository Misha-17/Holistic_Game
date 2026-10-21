"""Real headless ENet and synthetic PCM acceptance checks; no mic is opened."""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import subprocess
import time


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    output = root / ".tools" / f"voice-network-{time.time_ns()}"
    output.mkdir(parents=True)
    hidden = getattr(subprocess, "CREATE_NO_WINDOW", 0)
    failures = []

    def launch(label: str, script: str, extra: list[str]):
        env = os.environ.copy()
        env["APPDATA"] = str(output / label / "user")
        Path(env["APPDATA"]).mkdir(parents=True)
        log = (output / f"{label}.log").open("w", encoding="utf-8")
        cmd = [args.godot, "--headless", "--path", str(root), "--script", script, "--"] + extra
        return label, subprocess.Popen(cmd, cwd=root, env=env, stdout=log, stderr=subprocess.STDOUT, creationflags=hidden), log

    for label, script in [("audio", "voice_audio_test.gd"), ("sessions", "test_voice_sessions.gd")]:
        unit = launch(label, "res://tests/" + script, [])
        code = unit[1].wait(timeout=20)
        unit[2].close()
        if code: failures.append(unit[0])
    for mode, port in [("dedicated", 24781), ("desktop", 24782)]:
        common = [f"--port={port}"]
        if mode == "desktop": common.append("--desktop-host")
        processes = [launch(f"{mode}-server", "res://tests/voice_network_peer.gd", common + ["--voice-server", "--index=0"])]
        time.sleep(0.3)
        processes.append(launch(f"{mode}-legacy", "res://tests/voice_network_peer.gd", common + ["--legacy"]))
        time.sleep(0.7)
        indices = range(4) if mode == "dedicated" else range(1, 4)
        for index in indices:
            if index == 3: time.sleep(0.8)  # A genuinely late fourth participant.
            processes.append(launch(f"{mode}-client-{index}", "res://tests/voice_network_peer.gd", common + [f"--index={index}"]))
            time.sleep(0.15)
        for label, process, log in processes:
            try:
                code = process.wait(timeout=15)
            except subprocess.TimeoutExpired:
                process.kill()
                code = 1
            log.close()
            if code: failures.append(label)
    for path in sorted(output.glob("*.log")):
        content = path.read_text(encoding="utf-8", errors="replace")
        for line in content.splitlines():
            if "TEST:" in line or "REJECTION:" in line or "FAIL:" in line or "SCRIPT ERROR" in line:
                print(path.name, line)
    print("Voice logs:", output)
    print("VOICE SUITE:", "PASS" if not failures else "FAIL " + ", ".join(failures))
    return int(bool(failures))


if __name__ == "__main__":
    raise SystemExit(main())
