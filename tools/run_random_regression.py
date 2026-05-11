#!/usr/bin/env python3

import argparse
import subprocess
import sys
from pathlib import Path
from typing import List, Tuple


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CAMPAIGNS: List[Tuple[int, int, int, int]] = [
    (10, 100, 200, 12000),
    (16, 140, 1000, 18000),
    (16, 180, 4000, 24000),
]


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Run an extended randomized Spike/emulator/RTL differential regression."
    )
    parser.add_argument(
        "--campaign",
        action="append",
        nargs=4,
        metavar=("COUNT", "OPS", "SEED", "INSTR"),
        type=int,
        help="Override default campaigns. May be provided multiple times.",
    )
    args = parser.parse_args()

    campaigns = [tuple(entry) for entry in args.campaign] if args.campaign else DEFAULT_CAMPAIGNS
    passed = 0
    failed = 0

    for index, (count, ops, seed, instructions) in enumerate(campaigns, start=1):
        print(
            f"CAMPAIGN {index}: count={count} ops={ops} seed={seed} instructions={instructions}",
            flush=True,
        )
        proc = subprocess.run(
            [
                sys.executable,
                str(ROOT / "tools" / "run_random_spike_diff.py"),
                "--count",
                str(count),
                "--ops",
                str(ops),
                "--seed",
                str(seed),
                "--instructions",
                str(instructions),
            ],
            cwd=ROOT,
        )
        if proc.returncode == 0:
            passed += 1
        else:
            failed += 1

    print(f"REGRESSION SUMMARY pass={passed} fail={failed} total={len(campaigns)}")
    if failed:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
