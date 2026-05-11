#!/usr/bin/env python3

import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
FORMAL_DIR = ROOT / "formal"
JOBS = [
    FORMAL_DIR / "id_stage.sby",
    FORMAL_DIR / "csr_unit.sby",
    FORMAL_DIR / "ex_stage.sby",
    FORMAL_DIR / "mem_stage.sby",
]


def run_job(job: Path) -> bool:
    proc = subprocess.run(
        ["sby", "-f", str(job)],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    print(proc.stdout, end="")
    if proc.returncode != 0:
        print(proc.stderr, end="")
        return False
    return True


def main() -> None:
    passed = 0
    failed = 0
    for job in JOBS:
        ok = run_job(job)
        if ok:
            passed += 1
            print(f"PASS {job.name}")
        else:
            failed += 1
            print(f"FAIL {job.name}")
    print(f"SUMMARY pass={passed} fail={failed} total={len(JOBS)}")


if __name__ == "__main__":
    main()
