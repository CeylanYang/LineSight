"""Summarize alternating storage comparisons without dropping first runs."""

import argparse
import json
import re
import statistics
from pathlib import Path


def summarize(path):
    rows = [
        json.loads(match.group(1))
        for match in re.finditer(r"STORAGE_COMPARE (\{[^\r\n]+\})", path.read_text(encoding="utf-8-sig"))
    ]
    if len(rows) != 24 or len({(r["phase"], r["run"]) for r in rows}) != 24:
        raise ValueError(f"Expected 24 unique observations in {path}")
    output = {}
    for phase in ("prepare", "write", "read"):
        group = {}
        for label in ("baseline", "worker"):
            values = sorted(
                (r for r in rows if r["phase"] == f"{phase}-{label}"),
                key=lambda r: r["run"],
            )
            if [r["run"] for r in values] != [1, 2, 3, 4]:
                raise ValueError(f"Incomplete {phase}-{label}")
            group[label] = {
                "runs": values,
                "medianElapsedMs": statistics.median(r["elapsedUs"] for r in values) / 1000,
                "medianMaxGapMs": statistics.median(r["maxGapUs"] for r in values) / 1000,
                "runs2To4MedianElapsedMs": statistics.median(r["elapsedUs"] for r in values[1:]) / 1000,
            }
        group["elapsedMedianChangePercent"] = (
            group["worker"]["medianElapsedMs"] / group["baseline"]["medianElapsedMs"] - 1
        ) * 100
        group["gapMedianChangePercent"] = (
            group["worker"]["medianMaxGapMs"] / group["baseline"]["medianMaxGapMs"] - 1
        ) * 100
        output[phase] = group
    return {
        "log": str(path),
        "method": "4 alternating AOT emulator rounds; all runs retained; 16 ms scheduling heartbeat, not frame time",
        "phases": output,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("logs", type=Path, nargs="+")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = [summarize(path) for path in args.logs]
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    for report in result:
        print(report["log"])
        for phase, values in report["phases"].items():
            print(
                f"  {phase}: elapsed {values['baseline']['medianElapsedMs']:.1f} -> "
                f"{values['worker']['medianElapsedMs']:.1f} ms; longest gap "
                f"{values['baseline']['medianMaxGapMs']:.1f} -> {values['worker']['medianMaxGapMs']:.1f} ms"
            )


if __name__ == "__main__":
    main()
