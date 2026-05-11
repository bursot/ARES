#!/usr/bin/env python3

import argparse
import re
import subprocess
from pathlib import Path
from typing import Optional

from run_emulator_tests import EMU_DIR, build_emulator
from run_rtl_elf_tests import ROOT, build_sim, elf_to_words, run_vvp


STATE_KIND_RE = re.compile(r"^STATE kind=(\w+)$")
STATE_REG_RE = re.compile(r"^STATE reg x(\d+)=(\w+)$")
STATE_CSR_RE = re.compile(r"^STATE csr ([a-z0-9_]+)=(\w+)$")
STATE_VALUE_RE = re.compile(r"^STATE (tohost|cycle)=(\w+)$")
DEFAULT_SIM_PATH = None


def parse_state(output: str) -> dict:
    state = {"kind": None, "regs": {}, "csrs": {}, "meta": {}}
    seen_end = False
    for raw_line in output.splitlines():
        line = raw_line.strip()
        if not line.startswith("STATE "):
            continue
        if line == "STATE end":
            seen_end = True
            continue
        if match := STATE_KIND_RE.match(line):
            state["kind"] = match.group(1)
            continue
        if match := STATE_REG_RE.match(line):
            state["regs"][int(match.group(1))] = int(match.group(2), 16)
            continue
        if match := STATE_CSR_RE.match(line):
            state["csrs"][match.group(1)] = int(match.group(2), 16)
            continue
        if match := STATE_VALUE_RE.match(line):
            state["meta"][match.group(1)] = int(match.group(2), 16)
            continue
    if state["kind"] is None or not seen_end:
        raise ValueError("missing complete STATE block")
    return state


def get_default_sim_path() -> Path:
    global DEFAULT_SIM_PATH
    if DEFAULT_SIM_PATH is None or not DEFAULT_SIM_PATH.exists():
        DEFAULT_SIM_PATH = build_sim()
    return DEFAULT_SIM_PATH


def run_rtl_state(elf_path: Path, sim_path: Optional[Path] = None) -> dict:
    words, tohost_idx = elf_to_words(elf_path)
    plusargs = ["+state_dump"]
    if tohost_idx is not None:
        plusargs.append(f"+tohost_idx={tohost_idx}")
    proc = run_vvp(sim_path or get_default_sim_path(), words, plusargs)
    if proc.returncode != 0:
        raise RuntimeError(f"rtl sim failed for {elf_path.name}: {proc.stderr.strip()}")
    return parse_state(proc.stdout)


def run_emu_state(elf_path: Path) -> dict:
    proc = subprocess.run(
        [str(EMU_DIR / "ares"), "--state-dump", str(elf_path)],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    if proc.returncode != 0:
        raise RuntimeError(f"emulator failed for {elf_path.name}: {proc.stderr.strip()}")
    return parse_state(proc.stdout)


def compare_states(rtl_state: dict, emu_state: dict) -> list[str]:
    mismatches = []
    for reg_idx in range(32):
        rtl_val = rtl_state["regs"].get(reg_idx)
        emu_val = emu_state["regs"].get(reg_idx)
        if rtl_val != emu_val:
            mismatches.append(
                f"reg x{reg_idx}: rtl=0x{rtl_val:016x} emu=0x{emu_val:016x}"
            )

    csr_names = sorted(set(rtl_state["csrs"]) | set(emu_state["csrs"]))
    for name in csr_names:
        rtl_val = rtl_state["csrs"].get(name)
        emu_val = emu_state["csrs"].get(name)
        if rtl_val != emu_val:
            mismatches.append(
                f"csr {name}: rtl=0x{rtl_val:016x} emu=0x{emu_val:016x}"
            )

    for name in ("tohost",):
        rtl_val = rtl_state["meta"].get(name)
        emu_val = emu_state["meta"].get(name)
        if rtl_val != emu_val:
            mismatches.append(
                f"{name}: rtl=0x{rtl_val:016x} emu=0x{emu_val:016x}"
            )

    return mismatches


def main() -> None:
    parser = argparse.ArgumentParser(description="Compare final architectural state between RTL and emulator.")
    parser.add_argument(
        "--pattern",
        action="append",
        dest="patterns",
        help="Glob under repo root. Can be given multiple times.",
    )
    parser.add_argument(
        "--limit",
        type=int,
        help="Only run the first N matched tests.",
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
    if args.limit is not None:
        tests = tests[: args.limit]
    if not tests:
        raise SystemExit("no differential tests matched")

    sim_path = build_sim()
    build_emulator()

    passed = 0
    failed = 0
    for test in tests:
        try:
            rtl_state = run_rtl_state(test, sim_path)
            emu_state = run_emu_state(test)
            mismatches = compare_states(rtl_state, emu_state)
        except Exception as exc:
            failed += 1
            print(f"ERROR {test.relative_to(ROOT)} {exc}")
            continue

        if mismatches:
            failed += 1
            print(f"FAIL {test.relative_to(ROOT)}")
            for mismatch in mismatches[:10]:
                print(f"  {mismatch}")
        else:
            passed += 1
            print(f"PASS {test.relative_to(ROOT)}")

    print(f"SUMMARY pass={passed} fail={failed} total={len(tests)}")


if __name__ == "__main__":
    main()
