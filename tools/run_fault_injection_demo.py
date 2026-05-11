#!/usr/bin/env python3

import argparse
from pathlib import Path
from typing import Optional

from run_rtl_elf_tests import ROOT, build_sim, elf_to_words, run_vvp


def run_one(elf_path: Path, fault_kind: int, fault_addr: Optional[int], fault_mask: int):
    words, tohost_idx = elf_to_words(elf_path)
    sim_path = build_sim()
    plusargs = [f"+fault_kind={fault_kind}", f"+fault_mask={fault_mask:x}"]
    if tohost_idx is not None:
        plusargs.append(f"+tohost_idx={tohost_idx}")
    if fault_addr is not None:
        plusargs.append(f"+fault_addr={fault_addr:x}")
    proc = run_vvp(sim_path, words, plusargs)
    lines = proc.stdout.splitlines()

    fault_line = next((line for line in lines if line.startswith("ARES_FAULT ")), "ARES_FAULT missing")
    summary = next(
        (line for line in lines if line.startswith("PASS after") or line.startswith("FAIL ") or line.startswith("TIMEOUT")),
        "ERROR no-summary",
    )
    return fault_line, summary, proc.returncode


def main():
    parser = argparse.ArgumentParser(description="Run one RTL ELF with deterministic fault injection.")
    parser.add_argument("--elf", required=True, help="ELF path under repo root or absolute path")
    parser.add_argument(
        "--kind",
        choices=["imem", "dmem", "rf", "imem_parity", "dmem_parity"],
        required=True,
        help="Fault target",
    )
    parser.add_argument("--addr", help="Hex address to corrupt on first matching access")
    parser.add_argument("--mask", default="1", help="Hex XOR mask (default: 1)")
    parser.add_argument("--reg", type=int, default=1, help="Register index for rf parity corruption")
    parser.add_argument("--cycle", type=int, default=20, help="Cycle to inject rf parity corruption")
    args = parser.parse_args()

    elf_path = Path(args.elf)
    if not elf_path.is_absolute():
        elf_path = ROOT / elf_path
    if not elf_path.is_file():
        raise SystemExit(f"ELF not found: {elf_path}")

    fault_kind = (
        1 if args.kind == "imem" else
        2 if args.kind == "dmem" else
        3 if args.kind == "rf" else
        4 if args.kind == "imem_parity" else
        5
    )
    fault_addr = int(args.addr, 16) if args.addr else None
    fault_mask = int(args.mask, 16)

    words, tohost_idx = elf_to_words(elf_path)
    sim_path = build_sim()
    plusargs = [f"+fault_kind={fault_kind}", f"+fault_mask={fault_mask:x}"]
    if tohost_idx is not None:
        plusargs.append(f"+tohost_idx={tohost_idx}")
    if fault_addr is not None:
        plusargs.append(f"+fault_addr={fault_addr:x}")
    if args.kind == "rf":
        plusargs.append(f"+fault_reg={args.reg}")
        plusargs.append(f"+fault_cycle={args.cycle}")
    proc = run_vvp(sim_path, words, plusargs)
    lines = proc.stdout.splitlines()
    fault_line = next((line for line in lines if line.startswith("ARES_FAULT ")), "ARES_FAULT missing")
    summary = next(
        (line for line in lines if line.startswith("PASS after") or line.startswith("FAIL ") or line.startswith("TIMEOUT")),
        "ERROR no-summary",
    )
    returncode = proc.returncode
    print(fault_line)
    print(summary)
    raise SystemExit(returncode)


if __name__ == "__main__":
    main()
