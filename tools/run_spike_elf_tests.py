#!/usr/bin/env python3

import argparse
import re
import subprocess
from pathlib import Path
from typing import Optional

from run_rtl_elf_tests import ROOT, read_elf


SPIKE_TOHOST_RE = re.compile(r"mem 0x([0-9a-fA-F]+) 0x([0-9a-fA-F]+)")


def get_tohost_addr(elf_path: Path) -> Optional[int]:
    _, sections = read_elf(elf_path)
    for section in sections:
        if section["name"] == ".tohost":
            return section["addr"]
    return None


def run_spike(elf_path: Path, instr_limit: int) -> Optional[int]:
    tohost_addr = get_tohost_addr(elf_path)
    if tohost_addr is None:
        raise ValueError(f"missing .tohost in {elf_path}")

    cmd = [
        "spike",
        "-l",
        "--log-commits",
        f"--instructions={instr_limit}",
    ]
    # riscv-tests expects Spike's default ISA set, which includes zicntr,
    # and misaligned data tests need the explicit support switch.
    if "ma_data" in elf_path.name:
        cmd.append("--misaligned")
    cmd.append(str(elf_path))

    proc = subprocess.run(
        cmd,
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )

    log_text = proc.stdout + "\n" + proc.stderr
    first_tohost = None
    for line in log_text.splitlines():
        match = SPIKE_TOHOST_RE.search(line)
        if not match:
            continue
        addr = int(match.group(1), 16)
        value = int(match.group(2), 16)
        if addr == tohost_addr:
            first_tohost = value
            break
    return first_tohost


def main() -> None:
    parser = argparse.ArgumentParser(description="Run Spike smoke regression on ELF ISA tests.")
    parser.add_argument(
        "--pattern",
        action="append",
        dest="patterns",
        help="Glob under repo root. Can be given multiple times.",
    )
    parser.add_argument(
        "--instructions",
        type=int,
        default=200000,
        help="Spike instruction limit per test (default: 200000).",
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
        raise SystemExit("no Spike tests matched")

    passed = 0
    failed = 0
    for test in tests:
        try:
            tohost = run_spike(test, args.instructions)
        except Exception as exc:
            failed += 1
            print(f"ERROR {test.relative_to(ROOT)} {exc}")
            continue

        if tohost == 1:
            passed += 1
            print(f"PASS [tohost=1] {test.relative_to(ROOT)}")
        elif tohost is None:
            failed += 1
            print(f"ERROR [no-tohost] {test.relative_to(ROOT)}")
        else:
            failed += 1
            print(f"FAIL [tohost={tohost}] {test.relative_to(ROOT)}")

    print(f"SUMMARY pass={passed} fail={failed} total={len(tests)}")


if __name__ == "__main__":
    main()
