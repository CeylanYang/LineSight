"""Observe normal-entrypoint cold launches on a disposable Android device.

Optionally reinstall an APK while retaining app data. Capture each am result,
late Android display events, opt-in Dart startup timings and the final image.
An am timeout remains a failed observation even if a later frame appears.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--adb", required=True)
    parser.add_argument("--serial", default="emulator-5554")
    parser.add_argument("--apk", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--runs", type=int, default=3)
    parser.add_argument("--settle-seconds", type=float, default=0)
    parser.add_argument("--renderer", choices=["default", "impeller", "skia"], default="default")
    args = parser.parse_args()
    if args.runs < 1 or not 0 <= args.settle_seconds <= 60:
        parser.error("runs must be positive and settle-seconds must be 0–60")
    if args.apk is not None and not args.apk.is_file():
        parser.error("APK does not exist")
    args.output.mkdir(parents=True, exist_ok=False)
    adb = [args.adb, "-s", args.serial]
    package = "com.example.linesight_flutter"
    report = {"serial": args.serial, "settleSeconds": args.settle_seconds, "rendererRequest": args.renderer, "launches": []}
    renderer_args = [] if args.renderer == "default" else [
        "--ez", "enable-impeller", "true" if args.renderer == "impeller" else "false"
    ]

    def run(name, command):
        started = time.monotonic()
        result = subprocess.run(adb + command, capture_output=True)
        text = (result.stdout + result.stderr).decode("utf-8", errors="replace")
        (args.output / name).write_text(text, encoding="utf-8")
        return result, text, time.monotonic() - started

    log_path = args.output / "logcat.txt"
    with log_path.open("wb") as stream:
        logger = subprocess.Popen(
            adb + ["logcat", "-v", "threadtime", "-T", "1"],
            stdout=stream,
            stderr=subprocess.STDOUT,
            creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0,
        )
        try:
            if args.apk is not None:
                report["apk"] = str(args.apk.resolve())
                report["apkSha256"] = hashlib.sha256(args.apk.read_bytes()).hexdigest()
                result, _, seconds = run("install.txt", ["install", "-r", str(args.apk.resolve())])
                report["installSeconds"] = seconds
                result.check_returncode()
                time.sleep(args.settle_seconds)
            for index in range(1, args.runs + 1):
                result, _, _ = run(f"stop-{index}.txt", ["shell", "am", "force-stop", package])
                result.check_returncode()
                log_offset = log_path.stat().st_size
                result, text, seconds = run(
                    f"launch-{index}.txt", ["shell", "am", "start", "-W", "-n", f"{package}/.MainActivity", *renderer_args]
                )
                passed = result.returncode == 0 and "Status: ok" in text and "LaunchState: COLD" in text
                observation = {"run": index, "seconds": seconds, "exitCode": result.returncode, "coldWaitPassed": passed}
                report["launches"].append(observation)
                print(f"Run {index}: cold wait passed={passed}; {seconds:.3f} s", flush=True)
                # A wait timeout is not process completion. Let the same live app
                # draw before any next cold-start sample; never restart on timeout.
                deadline = time.monotonic() + 45
                displayed = False
                while time.monotonic() < deadline:
                    recent = log_path.read_bytes()[log_offset:].decode("utf-8", errors="replace")
                    if f"Displayed {package}/.MainActivity" in recent:
                        displayed = True
                        break
                    time.sleep(0.5)
                observation["androidDisplayObserved"] = displayed
                time.sleep(5)
                image = subprocess.check_output(adb + ["exec-out", "screencap", "-p"])
                (args.output / f"after-{index}.png").write_bytes(image)
                if not displayed:
                    print("No Displayed event observed; leaving the app running and ending sampling.", flush=True)
                    break
        finally:
            logger.terminate()
            logger.wait(timeout=10)
            text = log_path.read_text(encoding="utf-8", errors="replace")
            report["dartTimings"] = [json.loads(value) for value in re.findall(r"LINESIGHT_STARTUP (\{[^\r\n]+\})", text)]
            report["androidMilestones"] = [
                line for line in text.splitlines()
                if re.search(r"Using the Impeller|Start proc.*com.example.linesight|Displayed com.example.linesight|START u0.*com.example.linesight|Fully drawn com.example.linesight", line)
            ]
            (args.output / "observations.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    if len(report["launches"]) != args.runs or not all(
        row["coldWaitPassed"] and row["androidDisplayObserved"] for row in report["launches"]
    ):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
