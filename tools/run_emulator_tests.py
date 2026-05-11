#!/usr/bin/env python3

import argparse
import re
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
EMU_DIR = ROOT / "emulator"
SUMMARY_RE = re.compile(r"^(PASS|FAIL) \[tohost=(\d+)\] ([^\s]+)$")


def build_emulator() -> None:
    subprocess.run(["make"], cwd=EMU_DIR, check=True)


def run_one(path: Path) -> str:
    proc = subprocess.run(
        [str(EMU_DIR / "ares-test"), str(path)],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    for line in proc.stdout.splitlines():
        match = SUMMARY_RE.match(line.strip())
        if match:
            return line.strip()
    return f"FAIL [tohost=0] {path.name}"


def main() -> None:
    parser = argparse.ArgumentParser(description="Run emulator regression on ELF tests.")
    parser.add_argument(
        "--pattern",
        action="append",
        dest="patterns",
        help="Glob under repo root. Can be given multiple times.",
    )
    args = parser.parse_args()

    patterns = args.patterns or [
        "riscv-tests/isa/rv64ui-p-*",
        "riscv-tests/isa/rv64mi-p-*",
        "riscv-tests/isa/rv64um-p-*",
        "riscv-tests/isa/rv64ua-p-*",
    ]

    tests = []
    for pattern in patterns:
        tests.extend(path for path in ROOT.glob(pattern) if path.is_file() and not path.name.endswith(".dump"))
    tests = sorted(set(tests))
    if not tests:
        raise SystemExit("no emulator tests matched")

    build_emulator()

    passed = 0
    failed = 0
    for test in tests:
        summary = run_one(test)
        if summary.startswith("PASS"):
            passed += 1
        else:
            failed += 1
        print(summary)

    print(f"SUMMARY pass={passed} fail={failed} total={len(tests)}")


if __name__ == "__main__":
    main()
