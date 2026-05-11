#!/usr/bin/env python3

import argparse
import re
from pathlib import Path
from typing import List

from run_rtl_elf_tests import ROOT, RTL_DIR, build_sim, run_vvp


TESTS_DIR = ROOT / "tests"
SUMMARY_RE = re.compile(r"^(PASS after .*|FAIL .*|TIMEOUT .*)$")
DEFAULT_TOHOST_IDX = 0x400

def bin_to_words(bin_path: Path) -> List[str]:
    src = bin_path.read_bytes()
    words = []
    for i in range(0, len(src), 4):
        chunk = src[i : i + 4]
        chunk += b"\x00" * (4 - len(chunk))
        words.append(chunk[::-1].hex())
    words.extend(["00000000"] * (65536 - len(words)))
    return words


def run_one(bin_path: Path, sim_path: Path) -> str:
    proc = run_vvp(sim_path, bin_to_words(bin_path), [f"+tohost_idx={DEFAULT_TOHOST_IDX}"])
    summary = None
    for line in proc.stdout.splitlines():
        match = SUMMARY_RE.match(line.strip())
        if match:
            summary = match.group(1)
            if not summary.startswith("TIMEOUT"):
                break
    if summary is None:
        return f"ERROR no-summary {bin_path.name}"
    return summary


def main() -> None:
    parser = argparse.ArgumentParser(description="Run RTL regression on rv64ui test binaries.")
    parser.add_argument(
        "--pattern",
        default="rv64ui-p-*.bin",
        help="Glob under tests/ to select binaries (default: rv64ui-p-*.bin)",
    )
    args = parser.parse_args()

    bins = sorted(TESTS_DIR.glob(args.pattern))
    if not bins:
        raise SystemExit(f"no test binaries matched {args.pattern}")

    sim_path = build_sim()

    passed = 0
    failed = 0
    for bin_path in bins:
        summary = run_one(bin_path, sim_path)
        if summary.startswith("PASS"):
            passed += 1
        else:
            failed += 1
        print(f"{summary} {bin_path.stem}")

    print(f"SUMMARY pass={passed} fail={failed} total={len(bins)}")


if __name__ == "__main__":
    main()
