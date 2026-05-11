#!/usr/bin/env python3

import argparse
import random
import re
import subprocess
import tempfile
from pathlib import Path
from typing import Dict, List, Optional, Tuple

from run_state_diff import run_emu_state, run_rtl_state


ROOT = Path(__file__).resolve().parents[1]
LINKER = ROOT / "riscv-tests" / "env" / "p" / "link.ld"
SPIKE_REG_RE = re.compile(r"\bx(\d+)\s+0x([0-9a-fA-F]+)")
SPIKE_MEM_RE = re.compile(r"\bmem 0x([0-9a-fA-F]+) 0x([0-9a-fA-F]+)")

GENERAL_REGS = [idx for idx in range(1, 32) if idx not in (8, 9, 24, 25)]
BYTE_OFFSETS = list(range(0, 64))
HALF_OFFSETS = list(range(0, 64, 2))
WORD_OFFSETS = list(range(0, 64, 4))
DWORD_OFFSETS = list(range(0, 64, 8))
AMO_WORD_OPS = ["amoadd.w", "amoxor.w", "amoor.w", "amoand.w", "amomin.w", "amomax.w", "amominu.w", "amomaxu.w", "amoswap.w"]
AMO_DWORD_OPS = ["amoadd.d", "amoxor.d", "amoor.d", "amoand.d", "amomin.d", "amomax.d", "amominu.d", "amomaxu.d", "amoswap.d"]


def reg_name(idx: int) -> str:
    return f"x{idx}"


def signed_12(rng: random.Random) -> int:
    return rng.randint(-2048, 2047)


def random_u64(rng: random.Random) -> int:
    return rng.getrandbits(64)


def emit_li(reg_idx: int, value: int) -> str:
    value &= 0xFFFFFFFFFFFFFFFF
    return f"    li {reg_name(reg_idx)}, 0x{value:016x}"


def init_registers(seed: int) -> List[str]:
    rng = random.Random(seed)
    lines = []
    for reg_idx in range(1, 32):
        if reg_idx in (8, 9):
            continue
        lines.append(emit_li(reg_idx, random_u64(rng)))
    lines.append("    la x8, scratch")
    lines.append("    la x9, tohost")
    return lines


def random_op(rng: random.Random) -> List[str]:
    rd = reg_name(rng.choice(GENERAL_REGS))
    rs1 = reg_name(rng.choice(GENERAL_REGS))
    rs2 = reg_name(rng.choice(GENERAL_REGS))
    kind = rng.choice(
        [
            "rr",
            "ri",
            "rw",
            "iw",
            "mem_load",
            "mem_store",
            "muldiv",
            "muldivw",
            "amo",
            "lrsc",
        ]
    )

    if kind == "rr":
        op = rng.choice(["add", "sub", "xor", "or", "and", "slt", "sltu", "sll", "srl", "sra"])
        return [f"    {op} {rd}, {rs1}, {rs2}"]

    if kind == "ri":
        op = rng.choice(["addi", "xori", "ori", "andi", "slti", "sltiu"])
        return [f"    {op} {rd}, {rs1}, {signed_12(rng)}"]

    if kind == "rw":
        op = rng.choice(["addw", "subw", "sllw", "srlw", "sraw"])
        return [f"    {op} {rd}, {rs1}, {rs2}"]

    if kind == "iw":
        op = rng.choice(["addiw", "slliw", "srliw", "sraiw"])
        imm = rng.randint(0, 31) if op != "addiw" else signed_12(rng)
        return [f"    {op} {rd}, {rs1}, {imm}"]

    if kind == "mem_load":
        op, offsets = rng.choice(
            [
                ("lb", BYTE_OFFSETS),
                ("lbu", BYTE_OFFSETS),
                ("lh", HALF_OFFSETS),
                ("lhu", HALF_OFFSETS),
                ("lw", WORD_OFFSETS),
                ("lwu", WORD_OFFSETS),
                ("ld", DWORD_OFFSETS),
            ]
        )
        return [f"    {op} {rd}, {rng.choice(offsets)}(x8)"]

    if kind == "mem_store":
        src = reg_name(rng.choice(GENERAL_REGS))
        op, offsets = rng.choice(
            [
                ("sb", BYTE_OFFSETS),
                ("sh", HALF_OFFSETS),
                ("sw", WORD_OFFSETS),
                ("sd", DWORD_OFFSETS),
            ]
        )
        return [f"    {op} {src}, {rng.choice(offsets)}(x8)"]

    if kind == "muldiv":
        op = rng.choice(["mul", "mulh", "mulhsu", "mulhu", "div", "divu", "rem", "remu"])
        return [f"    {op} {rd}, {rs1}, {rs2}"]

    if kind == "muldivw":
        op = rng.choice(["mulw", "divw", "divuw", "remw", "remuw"])
        return [f"    {op} {rd}, {rs1}, {rs2}"]

    if kind == "amo":
        src = reg_name(rng.choice(GENERAL_REGS))
        if rng.choice([False, True]):
            op = rng.choice(AMO_DWORD_OPS)
            offset = rng.choice(DWORD_OFFSETS)
        else:
            op = rng.choice(AMO_WORD_OPS)
            offset = rng.choice(WORD_OFFSETS)
        return [
            f"    addi x25, x8, {offset}",
            f"    {op} {rd}, {src}, (x25)",
        ]

    rd_idx = int(rd[1:])
    status_idx = rng.choice([idx for idx in GENERAL_REGS if idx != rd_idx])
    status = reg_name(status_idx)
    addr = rng.choice(DWORD_OFFSETS)
    return [
        f"    addi x25, x8, {addr}",
        f"    lr.d {rd}, (x25)",
        f"    sc.d {status}, {rs2}, (x25)",
    ]


def final_fold() -> List[str]:
    lines = [
        "    li x20, 0",
        "    li x21, 0",
        "    li x22, 0",
        "    li x23, 0",
    ]
    for offset in DWORD_OFFSETS:
        lines.extend(
            [
                f"    ld x24, {offset}(x8)",
                "    xor x20, x20, x24",
                "    add x21, x21, x24",
                "    sub x22, x22, x24",
                "    or  x23, x23, x24",
            ]
        )
    return lines


def build_asm(seed: int, ops: int) -> str:
    rng = random.Random(seed)
    scratch_words = [random_u64(rng) for _ in range(8)]
    lines = [
        ".option norvc",
        ".section .text.init",
        ".globl _start",
        "_start:",
        *init_registers(seed ^ 0xACE55EED),
    ]
    for _ in range(ops):
        lines.extend(random_op(rng))
    lines.extend(
        [
            *final_fold(),
            "    li x3, 1",
            "    sw x3, 0(x9)",
            "1:  j 1b",
            "",
            ".section .tohost,\"aw\",@progbits",
            ".align 3",
            ".globl tohost",
            "tohost:",
            "    .dword 0",
            "",
            ".section .data",
            ".align 3",
            "scratch:",
        ]
    )
    for value in scratch_words:
        lines.append(f"    .dword 0x{value:016x}")
    return "\n".join(lines) + "\n"


def compile_test(src_path: Path, elf_path: Path) -> None:
    subprocess.run(
        [
            "riscv64-unknown-elf-gcc",
            "-nostdlib",
            "-nostartfiles",
            "-static",
            "-march=rv64ima",
            "-mabi=lp64",
            "-Wl,--build-id=none",
            "-Wl,--no-relax",
            f"-T{LINKER}",
            "-o",
            str(elf_path),
            str(src_path),
        ],
        cwd=ROOT,
        check=True,
    )


def parse_spike_final_regs(log_text: str, tohost_addr: int) -> Tuple[Dict[int, int], Optional[int]]:
    regs = {idx: 0 for idx in range(32)}
    first_tohost = None
    for line in log_text.splitlines():
        for reg_match in SPIKE_REG_RE.finditer(line):
            regs[int(reg_match.group(1))] = int(reg_match.group(2), 16)
        mem_match = SPIKE_MEM_RE.search(line)
        if mem_match:
            addr = int(mem_match.group(1), 16)
            value = int(mem_match.group(2), 16)
            if addr == tohost_addr and first_tohost is None:
                first_tohost = value
    regs[0] = 0
    return regs, first_tohost


def run_spike_regs(elf_path: Path, instr_limit: int) -> Tuple[Dict[int, int], Optional[int]]:
    proc = subprocess.run(
        [
            "spike",
            "-l",
            "--log-commits",
            f"--instructions={instr_limit}",
            "--isa=rv64ima",
            str(elf_path),
        ],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    log_text = proc.stdout + "\n" + proc.stderr
    tohost_addr = 0x80001000
    return parse_spike_final_regs(log_text, tohost_addr)


def compare_reg_sets(spike_regs: Dict[int, int], model_regs: Dict[int, int], name: str) -> List[str]:
    mismatches = []
    for idx in range(32):
        spike_val = spike_regs.get(idx, 0)
        model_val = model_regs.get(idx, 0)
        if spike_val != model_val:
            mismatches.append(
                f"{name} reg x{idx}: spike=0x{spike_val:016x} model=0x{model_val:016x}"
            )
    return mismatches


def main() -> None:
    parser = argparse.ArgumentParser(description="Run random RV64IMA differential tests across Spike, emulator, and RTL.")
    parser.add_argument("--count", type=int, default=10, help="Number of generated programs (default: 10).")
    parser.add_argument("--ops", type=int, default=80, help="Random operations per program (default: 80).")
    parser.add_argument("--seed", type=int, default=1, help="Base random seed (default: 1).")
    parser.add_argument("--instructions", type=int, default=5000, help="Spike instruction limit per program (default: 5000).")
    args = parser.parse_args()

    passed = 0
    failed = 0
    with tempfile.TemporaryDirectory(prefix="ares-randdiff-") as tmpdir_name:
        tmpdir = Path(tmpdir_name)
        for index in range(args.count):
            seed = args.seed + index
            src_path = tmpdir / f"rand_{seed}.S"
            elf_path = tmpdir / f"rand_{seed}.elf"
            src_path.write_text(build_asm(seed, args.ops))
            compile_test(src_path, elf_path)

            try:
                spike_regs, spike_tohost = run_spike_regs(elf_path, args.instructions)
                emu_state = run_emu_state(elf_path)
                rtl_state = run_rtl_state(elf_path)
            except Exception as exc:
                failed += 1
                print(f"ERROR seed={seed} {exc}")
                continue

            mismatches = []
            mismatches.extend(compare_reg_sets(spike_regs, emu_state["regs"], "emu"))
            mismatches.extend(compare_reg_sets(spike_regs, rtl_state["regs"], "rtl"))
            if spike_tohost != emu_state["meta"].get("tohost"):
                mismatches.append(
                    f"emu tohost: spike=0x{(spike_tohost or 0):016x} model=0x{emu_state['meta'].get('tohost', 0):016x}"
                )
            if spike_tohost != rtl_state["meta"].get("tohost"):
                mismatches.append(
                    f"rtl tohost: spike=0x{(spike_tohost or 0):016x} model=0x{rtl_state['meta'].get('tohost', 0):016x}"
                )

            if mismatches:
                failed += 1
                print(f"FAIL seed={seed}")
                for mismatch in mismatches[:12]:
                    print(f"  {mismatch}")
            else:
                passed += 1
                print(f"PASS seed={seed}")

    print(f"SUMMARY pass={passed} fail={failed} total={args.count}")


if __name__ == "__main__":
    main()
